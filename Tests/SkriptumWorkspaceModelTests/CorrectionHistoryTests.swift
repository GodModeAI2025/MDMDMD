import Foundation
import Testing
import SkriptumCore
@testable import SkriptumWorkspaceModel

@MainActor struct CorrectionHistoryTests {
    private func fixture() throws -> (URL, LibraryStore, WritingLibrary, UUID, [Block]) {
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
        let store = try LibraryStore(directory: root.appending(path: "Documents/Skriptum"))
        let space = try store.createSpace(title: "Book")
        let page = try store.createPage(spaceID: space.id, title: "Page")
        let blocks = [Block(markdown: "Same e\u{301} 🦊\r\n\r\n"), Block(markdown: "Same e\u{301} 🦊\r\n\r\n"), Block(markdown: "End\r\n")]
        try store.setBlocks(pageID: page.id, blocks: blocks, baseRevision: page.revision)
        let library = try WritingLibrary(store: store, documentRoot: root.appending(path: "Documents"), supportRoot: root.appending(path: "Support"), preferences: UserDefaults(suiteName: UUID().uuidString)!)
        return (root, store, library, page.id, blocks)
    }
    @Test func undoAfterStructuralCorrectionRetainsExactOriginalBlockIDsAndComment() throws {
        let (root, store, library, id, blocks) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        try store.addComment(Comment(pageID: id, blockID: blocks[1].id, body: "Keep this paragraph", author: "Author"))
        let before = store.snapshot.pages[0]
        var corrected = try #require(library.currentPage(id)); corrected.markdown = "Merged source 🦊\r\n"
        _ = try #require(library.update(corrected))
        var history = WritingCorrectionHistory()
        let recorded = history.record(before: before, after: store.snapshot.pages[0]); #expect(recorded)
        let undone = history.undo(library: library); _ = try #require(undone)
        #expect(store.snapshot.pages[0].blocks.map(\.id) == blocks.map(\.id))
        #expect(store.snapshot.pages[0].markdown.utf8.elementsEqual(before.markdown.utf8))
        #expect(store.snapshot.comments.first?.blockID == blocks[1].id)
    }
}

extension CorrectionHistoryTests {
    private func correct(_ source: String, id: UUID, store: LibraryStore, library: WritingLibrary, history: inout WritingCorrectionHistory) throws -> Page {
        let before = store.snapshot.pages[0]
        var draft = try #require(library.currentPage(id)); draft.markdown = source
        _ = try #require(library.update(draft))
        let after = store.snapshot.pages[0]
        let recorded = history.record(before: before, after: after); #expect(recorded)
        return after
    }
    @Test func multipleUndoRedoStepsPreserveExactSourceBlocksAndDurableVersions() throws {
        let (root, store, library, id, _) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        var history = WritingCorrectionHistory()
        var states = [store.snapshot.pages[0]]
        for source in ["é\r\n\r\n![Photo](media/example.png)\r\n", "e\u{301}\r\n\r\n| A | B |\r\n| --- | --- |\r\n| 🦊 | 名 |\r\n", "Last\r\n"] {
            states.append(try correct(source, id: id, store: store, library: library, history: &history))
        }
        for state in states.dropLast().reversed() {
            let undone = history.undo(library: library); _ = try #require(undone)
            #expect(store.snapshot.pages[0].blocks.map(\.id) == state.blocks.map(\.id))
            #expect(store.snapshot.pages[0].markdown.utf8.elementsEqual(state.markdown.utf8))
        }
        #expect(!history.canUndo && history.canRedo)
        for state in states.dropFirst() {
            let redone = history.redo(library: library); _ = try #require(redone)
            #expect(store.snapshot.pages[0].blocks.map(\.id) == state.blocks.map(\.id))
            #expect(store.snapshot.pages[0].markdown.utf8.elementsEqual(state.markdown.utf8))
        }
        #expect(history.canUndo && !history.canRedo)
        #expect(try LibraryStore(directory: store.directory).snapshot == store.snapshot)
    }
    @Test func newCorrectionAfterUndoDiscardsOnlyRedoBranch() throws {
        let (root, store, library, id, blocks) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        var history = WritingCorrectionHistory()
        let first = try correct("First\r\n", id: id, store: store, library: library, history: &history)
        _ = try correct("Second\r\n", id: id, store: store, library: library, history: &history)
        let undone = history.undo(library: library); _ = try #require(undone)
        _ = try correct("Branch 🦊\r\n", id: id, store: store, library: library, history: &history)
        #expect(!history.canRedo)
        let branchUndo = history.undo(library: library); _ = try #require(branchUndo)
        #expect(store.snapshot.pages[0].blocks.map(\.id) == first.blocks.map(\.id))
        let firstUndo = history.undo(library: library); _ = try #require(firstUndo)
        #expect(store.snapshot.pages[0].blocks.map(\.id) == blocks.map(\.id))
    }
    @Test func unrelatedRevisionOrExternalDiskWriteCannotBeOverwrittenByUndo() throws {
        let (root, store, library, id, _) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        var history = WritingCorrectionHistory()
        _ = try correct("Correction", id: id, store: store, library: library, history: &history)
        try store.renamePage(id, title: "Another window")
        let changed = store.snapshot
        let rejected = history.undo(library: library)
        #expect(rejected == nil && history.canUndo && !history.canRedo)
        #expect(store.snapshot == changed)
        library.reload()
        _ = try correct("New correction", id: id, store: store, library: library, history: &history)
        let external = try LibraryStore(directory: store.directory)
        _ = try external.createSpace(title: "External")
        let disk = try Data(contentsOf: store.directory.appending(path: "library.json"))
        let diskRejected = history.undo(library: library)
        #expect(diskRejected == nil && history.canUndo && !history.canRedo)
        #expect(try Data(contentsOf: store.directory.appending(path: "library.json")) == disk)
        #expect(try LibraryStore(directory: store.directory).snapshot.spaces.contains(where: { $0.title == "External" }))
    }
    @Test func failedRedoDoesNotAdvanceStacksAndCanRetryAfterJournalFinishes() throws {
        let (root, store, library, id, _) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        var history = WritingCorrectionHistory()
        let corrected = try correct("Corrected 🦊", id: id, store: store, library: library, history: &history)
        let undone = history.undo(library: library); _ = try #require(undone)
        let current = store.snapshot.pages[0]
        let token = try store.beginEditing(pageID: id, baseRevision: current.revision)
        let rejected = history.redo(library: library)
        #expect(rejected == nil && history.canRedo && !history.canUndo)
        #expect(store.snapshot.pages[0] == current)
        try store.finishEditing(token)
        let redone = history.redo(library: library); _ = try #require(redone)
        #expect(store.snapshot.pages[0].markdown.utf8.elementsEqual(corrected.markdown.utf8))
        #expect(!history.canRedo && history.canUndo)
    }
    @Test func stepAndByteBoundsDoNotDiscardDurableVersions() throws {
        let (root, store, library, id, _) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        var history = WritingCorrectionHistory(maximumSteps: 2)
        let first = try correct("First", id: id, store: store, library: library, history: &history)
        _ = try correct("Second", id: id, store: store, library: library, history: &history)
        _ = try correct("Third", id: id, store: store, library: library, history: &history)
        #expect(history.isLimited)
        let one = history.undo(library: library); _ = try #require(one)
        let two = history.undo(library: library); _ = try #require(two)
        #expect(!history.canUndo && store.snapshot.pages[0].markdown == first.markdown)
        #expect(store.snapshot.revisions.count >= 5)
        var bounded = WritingCorrectionHistory(maximumBytes: 256)
        let before = store.snapshot.pages[0]
        var draft = try #require(library.currentPage(id)); draft.markdown = String(repeating: "🦊", count: 1000)
        _ = try #require(library.update(draft))
        let recorded = bounded.record(before: before, after: store.snapshot.pages[0])
        #expect(!recorded && bounded.isLimited && !bounded.canUndo && bounded.retainedBytes == 0)
        #expect(store.snapshot.revisions.contains(where: { $0.id == before.revision }))
    }
}
