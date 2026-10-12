import Foundation
import Testing
import SkriptumCore
@testable import SkriptumWorkspaceModel

@MainActor struct AssistantProposalAdmissionTests {
    private func fixture() throws -> (URL, LibraryStore, WritingLibrary, WritingPage) {
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
        let store = try LibraryStore(directory: root.appending(path: "Documents/Skriptum"))
        let space = try store.createSpace(title: "Book")
        let page = try store.createPage(spaceID: space.id, title: "Page", markdown: "Before 🦊\r\nSelected e\u{301}\r\nAfter\r\n")
        let library = try WritingLibrary(store: store, documentRoot: root.appending(path: "Documents"), supportRoot: root.appending(path: "Support"), preferences: UserDefaults(suiteName: UUID().uuidString)!)
        return (root, store, library, try #require(library.currentPage(page.id)))
    }
    @Test func selectedProposalCommitsBeforeReturningAndUndoRedoRetainExactBlocks() throws {
        let (root, store, library, page) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let range = (page.markdown as NSString).range(of: "Selected e\u{301}")
        let target = try AssistantTextTarget(page: page, selection: range)
        let before = store.snapshot.pages[0], admission = PageBlockWritingAdmission()
        let saved = try #require(admission.performToolMutation(library: library, pageID: page.id) { library.applyAssistantText(target, response: "Revised 名 🦊") })
        #expect(saved.markdown.utf8.elementsEqual("Before 🦊\r\nRevised 名 🦊\r\nAfter\r\n".utf8))
        #expect(try LibraryStore(directory: store.directory).snapshot.pages[0].markdown.utf8.elementsEqual(saved.markdown.utf8))
        #expect(admission.canUndoToolSource)
        let after = store.snapshot.pages[0]
        _ = try #require(admission.undoToolSource(library: library, pageID: page.id))
        #expect(store.snapshot.pages[0].blocks.map(\.id) == before.blocks.map(\.id))
        #expect(store.snapshot.pages[0].markdown.utf8.elementsEqual(before.markdown.utf8))
        _ = try #require(admission.redoToolSource(library: library, pageID: page.id))
        #expect(store.snapshot.pages[0].blocks.map(\.id) == after.blocks.map(\.id))
        #expect(store.snapshot.pages[0].markdown.utf8.elementsEqual(after.markdown.utf8))
    }
    @Test func proposalNeverRebasesOntoNewRevisionOrNormalizedSource() throws {
        let (root, store, library, page) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let target = try AssistantTextTarget(page: page)
        try store.renamePage(page.id, title: "Another writer")
        let before = store.snapshot
        #expect(library.applyAssistantText(target, response: "Stale answer") == nil)
        #expect(store.snapshot == before)
        // Even a fabricated same-revision target cannot treat canonically equal bytes as equal source.
        library.reload(); var altered = try #require(library.currentPage(page.id))
        altered.markdown = altered.markdown.precomposedStringWithCanonicalMapping
        let normalized = try AssistantTextTarget(page: altered)
        #expect(library.applyAssistantText(normalized, response: "Wrong baseline") == nil)
        #expect(store.snapshot == before)
        #expect(target.source.utf8.elementsEqual(page.markdown.utf8))
    }
    @Test func blockScopedAndInsertionProposalsFailOnRevisionMismatch() throws {
        let (root, store, library, page) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let block = (page.markdown as NSString).range(of: "Selected e\u{301}")
        let scoped = try AssistantTextTarget(page: page, selection: block)
        let insertion = try AssistantTextTarget(page: page, selection: NSRange(location: (page.markdown as NSString).length, length: 0))
        #expect(insertion.original.isEmpty)
        try store.renamePage(page.id, title: "Anderer Schreiber")
        let before = store.snapshot
        #expect(library.applyAssistantText(scoped, response: "Veraltet") == nil)
        #expect(library.applyAssistantText(insertion, response: "\r\nZusammenfassung") == nil)
        #expect(store.snapshot == before)
        library.reload()
        let fresh = try #require(library.currentPage(page.id))
        let end = NSRange(location: (fresh.markdown as NSString).length, length: 0)
        let saved = try #require(library.applyAssistantText(try AssistantTextTarget(page: fresh, selection: end), response: "\r\nZusammenfassung"))
        #expect(saved.markdown.utf8.elementsEqual((fresh.markdown + "\r\nZusammenfassung").utf8))
    }
    @Test func invalidUTF16SelectionCannotSplitSurrogatesOverflowOrWidenScope() throws {
        let (root, _, _, page) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let fox = (page.markdown as NSString).range(of: "🦊")
        for range in [NSRange(location: fox.location + 1, length: 1), NSRange(location: Int.max, length: 1), NSRange(location: 0, length: Int.max), NSRange(location: -1, length: 1)] {
            #expect(throws: AssistantTextTarget.TargetError.invalidSelection) { try AssistantTextTarget(page: page, selection: range) }
        }
        let target = try AssistantTextTarget(page: page, selection: fox)
        #expect(target.original == "🦊")
        #expect(target.replacing(with: "名").utf8.elementsEqual(page.markdown.replacingOccurrences(of: "🦊", with: "名").utf8))
    }
    @Test func failedDiskCommitOrTrashedPageCannotAcceptProposalOrCreateUndoStep() throws {
        let (root, store, library, page) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let target = try AssistantTextTarget(page: page), admission = PageBlockWritingAdmission()
        let external = try LibraryStore(directory: store.directory)
        _ = try external.createSpace(title: "External")
        let disk = try Data(contentsOf: store.directory.appending(path: "library.json"))
        #expect(admission.performToolMutation(library: library, pageID: page.id) { library.applyAssistantText(target, response: "Rejected") } == nil)
        #expect(!admission.canUndoToolSource)
        #expect(try Data(contentsOf: store.directory.appending(path: "library.json")) == disk)
        try external.trashPage(page.id)
        var trashed = page; trashed.revision = external.snapshot.pages[0].revision
        let refreshed = try WritingLibrary(store: external, documentRoot: root.appending(path: "Documents"), supportRoot: root.appending(path: "Support"), preferences: UserDefaults(suiteName: UUID().uuidString)!)
        #expect(refreshed.applyAssistantText(try AssistantTextTarget(page: trashed), response: "Cannot edit trash") == nil)
    }
    @Test func admittedMetadataChangesPreserveSourceUndoAndWrongPageIsRejected() throws {
        let (root, store, library, page) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let admission = PageBlockWritingAdmission(), target = try AssistantTextTarget(page: page)
        let first = try #require(admission.performToolMutation(library: library, pageID: page.id) { library.applyAssistantText(target, response: "New source") })
        _ = try #require(admission.performToolMutation(library: library, pageID: page.id) {
            library.savePageTools(pageID: page.id, baseRevision: first.revision, rules: "Keep this rule", prompts: [])
        })
        let other = try store.createPage(spaceID: page.spaceID, title: "Other")
        #expect(admission.undoToolSource(library: library, pageID: other.id) == nil)
        _ = try #require(admission.undoToolSource(library: library, pageID: page.id))
        #expect(store.snapshot.pages[0].markdown.utf8.elementsEqual(page.markdown.utf8))
        #expect(store.snapshot.pages[0].assistantRules == "Keep this rule")
        #expect(store.snapshot.pages.first(where: { $0.id == other.id })?.markdown == "")
    }
}

extension AssistantProposalAdmissionTests {
    @Test(arguments: ["table", "image", "history"])
    func actualToolsShareSourceUndoWithoutLosingMediaOrBlockIdentity(kind: String) throws {
        let (root, store, library, initial) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let admission = PageBlockWritingAdmission()
        var historical: Revision?
        if kind == "history" {
            try store.setMarkdown(initial.id, markdown: "Current before restoring history", baseRevision: initial.revision)
            library.reload(); historical = library.revisions.first(where: { $0.page.id == initial.id })
        }
        let before = store.snapshot.pages[0]
        let png = try #require(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII="))
        _ = try #require(admission.performToolMutation(library: library, pageID: initial.id) {
            if kind == "table" {
                return library.replaceBlock(pageID: initial.id, baseRevision: before.revision, blockID: before.blocks[0].id, expectedSource: before.blocks[0].markdown,
                    replacement: "| A | B |\r\n| --- | --- |\r\n| e\u{301} | 🦊 |\r\n")
            }
            if kind == "history", let historical { return library.restore(historical, baseRevision: before.revision) }
            do {
                _ = try store.addImageBlock(pageID: initial.id, data: png, mediaType: "image/png", filename: "photo.png", altText: "A fox", afterBlockID: before.blocks[0].id, baseRevision: before.revision)
                library.reload(); return library.currentPage(initial.id)
            } catch { Issue.record(error); return nil }
        })
        let after = store.snapshot.pages[0]
        #expect(admission.canUndoToolSource)
        _ = try #require(admission.undoToolSource(library: library, pageID: initial.id))
        #expect(store.snapshot.pages[0].blocks.map(\.id) == before.blocks.map(\.id))
        #expect(store.snapshot.pages[0].markdown.utf8.elementsEqual(before.markdown.utf8))
        _ = try #require(admission.redoToolSource(library: library, pageID: initial.id))
        #expect(store.snapshot.pages[0].blocks.map(\.id) == after.blocks.map(\.id))
        #expect(store.snapshot.pages[0].markdown.utf8.elementsEqual(after.markdown.utf8))
        if kind == "image" { #expect(try store.attachmentData(#require(after.attachments?.first)) == png) }
        #expect(try LibraryStore(directory: store.directory).snapshot == store.snapshot)
    }
}
