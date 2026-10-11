import Foundation
import Testing
import SkriptumCore
@testable import SkriptumWorkspaceModel

@MainActor struct DiskConflictRecoveryTests {
    private func fixture() throws -> (URL, LibraryStore, WritingLibrary, WritingPage) {
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
        let store = try LibraryStore(directory: root.appending(path: "Documents/Skriptum"))
        let space = try store.createSpace(title: "Book")
        _ = try store.createPage(spaceID: space.id, title: "Page", markdown: "Baseline\r\n")
        let library = try WritingLibrary(store: store, documentRoot: root.appending(path: "Documents"), supportRoot: root.appending(path: "Support"), preferences: UserDefaults(suiteName: UUID().uuidString)!)
        return (root, store, library, library.pages[0])
    }
    @Test func staleTextWriteArchivesVisibleSourceWithoutReplacingWinner() throws {
        let (root, store, library, baseline) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let other = try LibraryStore(directory: store.directory)
        try other.setMarkdown(baseline.id, markdown: "Other writer", baseRevision: baseline.revision)
        var draft = baseline; draft.markdown = "My unsaved 🦊 e\u{301}\r\n"
        #expect(library.updateText(draft, token: nil) == nil)
        #expect(library.recoveries.count == 1)
        #expect(library.recoveries.first?.page.markdown.utf8.elementsEqual(draft.markdown.utf8) == true)
        #expect(try LibraryStore(directory: store.directory).snapshot.pages.first?.markdown == "Other writer")
    }
    @Test func failedFinalizationArchivesEvenMatchingInMemoryJournal() throws {
        let (root, store, library, baseline) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        var draft = baseline; draft.markdown = "Accepted draft 🦊\r\n"
        let saved = try #require(library.updateText(draft, token: nil))
        let other = try LibraryStore(directory: store.directory)
        try other.renameSpace(baseline.spaceID, title: "Other metadata")
        #expect(!library.finishTyping(saved.token))
        #expect(library.recoveries.count == 1)
        #expect(library.recoveries.first?.page.markdown.utf8.elementsEqual(draft.markdown.utf8) == true)
        #expect(library.recoveries.first?.page.blockDraft != nil)
    }
}

extension DiskConflictRecoveryTests {
    @Test func staleBlockWriteKeepsExactIdentityAndOrderInRecovery() throws {
        let (root, store, library, baseline) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let other = try LibraryStore(directory: store.directory)
        try other.renameSpace(baseline.spaceID, title: "Changed elsewhere")
        let blocks = [Block(markdown: "same\r\n"), Block(markdown: "same\r\n"), Block(markdown: "e\u{301} 🦊")]
        #expect(library.updateBlocks(baseline, blocks: blocks, token: nil) == nil)
        let record = try #require(library.recoveries.first)
        #expect(record.page.blockDraft?.map(\.id) == blocks.map(\.id))
        #expect(record.page.markdown.utf8.elementsEqual(blocks.map(\.markdown).joined().utf8))
        #expect(library.updateBlocks(baseline, blocks: blocks, token: nil) == nil)
        #expect(library.recoveries.count == 1)
    }
    @Test func archiveFailureDoesNotClaimSuccessfulRecovery() throws {
        let (root, store, library, baseline) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let other = try LibraryStore(directory: store.directory)
        try other.renameSpace(baseline.spaceID, title: "Changed elsewhere")
        try Data("blocked archive".utf8).write(to: store.directory.appending(path: "Recoveries"))
        var draft = baseline; draft.markdown = "Keep visible source 🦊\r\n"
        #expect(library.updateText(draft, token: nil) == nil)
        #expect(library.recoveries.isEmpty)
        #expect(library.saveError?.contains("konnte nicht gesichert") == true)
        #expect(library.saveError?.contains("Exportieren") == true)
        #expect(store.snapshot.pages.first?.markdown == baseline.markdown)
    }
}

extension DiskConflictRecoveryTests {
    @Test func emergencyMarkdownExportUsesVisibleDraftDespiteFailedFinalization() throws {
        let (root, store, library, baseline) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        var accepted = baseline; accepted.markdown = "Accepted journal"
        let saved = try #require(library.updateText(accepted, token: nil))
        let other = try LibraryStore(directory: store.directory)
        try other.renameSpace(baseline.spaceID, title: "Changed elsewhere")
        #expect(!library.finishTyping(saved.token))
        var visible = accepted; visible.markdown = "Newest visible 🦊 e\u{301}\r\n\r\n"
        let share = try #require(library.exportMarkdown(visible))
        defer { try? FileManager.default.removeItem(at: share.url.deletingLastPathComponent()) }
        #expect(try Data(contentsOf: share.url) == Data(visible.markdown.utf8))
        #expect(library.saveError != nil)
        #expect(try LibraryStore(directory: store.directory).snapshot.pages.first?.markdown == "Accepted journal")
    }
}
