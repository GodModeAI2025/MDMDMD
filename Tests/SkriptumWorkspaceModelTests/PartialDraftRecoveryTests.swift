import Foundation
import Testing
import SkriptumCore
@testable import SkriptumWorkspaceModel

@MainActor struct PartialDraftRecoveryTests {
    private func fixture() throws -> (URL, LibraryStore, WritingLibrary, WritingPage, MediaAttachment) {
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
        let store = try LibraryStore(directory: root.appending(path: "Documents/Skriptum"))
        let space = try store.createSpace(title: "Book")
        let page = try store.createPage(spaceID: space.id, title: "Page", markdown: "Baseline")
        let png = try #require(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII="))
        let attachment = try store.addAttachment(pageID: page.id, data: png, mediaType: "image/png", filename: "pixel.png", baseRevision: page.revision)
        let library = try WritingLibrary(store: store, documentRoot: root.appending(path: "Documents"), supportRoot: root.appending(path: "Support"), preferences: UserDefaults(suiteName: UUID().uuidString)!)
        return (root, store, library, library.pages[0], attachment)
    }
    @Test func missingImageDoesNotPreventTextRecoveryAndRawExport() throws {
        let (root, store, library, baseline, attachment) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.removeItem(at: store.directory.appendingPathComponent(attachment.relativePath))
        var draft = baseline; draft.markdown = "Unsaved 🦊 e\u{301}\r\n![Image](\(attachment.relativePath))\r\n"
        #expect(!library.preserveConflictedDraft(draft))
        let record = try #require(library.recoveries.first)
        #expect(record.page.markdown.utf8.elementsEqual(draft.markdown.utf8))
        let share = try #require(library.exportMarkdown(record.page))
        defer { try? FileManager.default.removeItem(at: share.url.deletingLastPathComponent()) }
        #expect(try Data(contentsOf: share.url) == Data(draft.markdown.utf8))
        #expect(library.recoverAsCopy(record) == nil)
        #expect(library.recoveries.count == 1)
    }
}

extension PartialDraftRecoveryTests {
    @Test func repairedMediaCompletesTheSameRecordAndRestoresExactText() throws {
        let (root, store, library, baseline, attachment) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let media = store.directory.appendingPathComponent(attachment.relativePath), bytes = try Data(contentsOf: media)
        try FileManager.default.removeItem(at: media)
        var draft = baseline; draft.markdown = "New text 🦊\r\n"
        #expect(!library.preserveConflictedDraft(draft))
        let partial = try #require(library.recoveries.first)
        #expect(!partial.isComplete)
        try bytes.write(to: media)
        #expect(library.preserveConflictedDraft(draft))
        let complete = try #require(library.recoveries.first)
        #expect(complete.id == partial.id && complete.isComplete)
        #expect(library.recoveries.count == 1)
        let id = try #require(library.recoverAsCopy(complete))
        #expect(store.snapshot.pages.first(where: { $0.id == id })?.markdown.utf8.elementsEqual(draft.markdown.utf8) == true)
        #expect(library.recoveries.isEmpty)
    }
    @Test func unreadableNeighborDoesNotHideOrBlockNewTextRecovery() throws {
        let (root, store, library, baseline, _) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let directory = store.directory.appending(path: "Recoveries")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let bad = directory.appending(path: UUID().uuidString + ".json"), bytes = Data("broken".utf8)
        try bytes.write(to: bad)
        var draft = baseline; draft.markdown = "Healthy source e\u{301}\r\n"
        #expect(library.preserveConflictedDraft(draft))
        #expect(library.recoveries.count == 1 && library.unreadableRecoveryCount == 1)
        #expect(try Data(contentsOf: bad) == bytes)
    }
}

extension PartialDraftRecoveryTests {
    @Test func oneMissingImageDoesNotPreventArchivingOtherGoodImages() throws {
        let (root, store, library, _, good) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let bytes = try store.attachmentData(good), page = try #require(store.snapshot.pages.first)
        let missing = try store.addAttachment(pageID: page.id, data: bytes, mediaType: "image/png", filename: "missing.png", baseRevision: page.revision)
        library.reload()
        var draft = library.pages[0]; draft.markdown = "Preserve all possible source 🦊"
        try FileManager.default.removeItem(at: store.directory.appendingPathComponent(missing.relativePath))
        #expect(!library.preserveConflictedDraft(draft))
        let record = try #require(library.recoveries.first)
        #expect(!record.isComplete)
        let archived = store.directory.appending(path: "Recoveries").appendingPathComponent(good.relativePath)
        #expect(try Data(contentsOf: archived) == bytes)
        try FileManager.default.removeItem(at: store.directory.appendingPathComponent(good.relativePath))
        #expect(try Data(contentsOf: archived) == bytes)
        #expect(library.saveError?.contains("missing.png") == true)
    }
}

extension PartialDraftRecoveryTests {
    @Test func textCopyKeepsExactSourceMetadataAndOriginalRecoveryUntilFullRestore() throws {
        let (root, store, library, baseline, attachment) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let media = store.directory.appendingPathComponent(attachment.relativePath), bytes = try Data(contentsOf: media)
        try FileManager.default.removeItem(at: media)
        var draft = baseline
        draft.markdown = "# Cafe\u{301} 🦊\r\n![Photo](\(attachment.relativePath))\r\n"
        draft.tags = ["Research"]; draft.favorite = true; draft.wordGoal = 1200
        draft.assistantRules = "Use my voice"; draft.purpose = .material
        draft.blockDraft = MarkdownReconciler.reconcile(draft.markdown, previous: [])
        #expect(!library.preserveConflictedDraft(draft))
        let recovery = try #require(library.recoveries.first)
        let copyID = try #require(library.recoverTextAsCopy(recovery))
        let copy = try #require(store.snapshot.pages.first(where: { $0.id == copyID }))
        #expect(copy.markdown.utf8.elementsEqual(draft.markdown.utf8))
        #expect(copy.attachments == nil)
        #expect(copy.blocks.map(\.id) == draft.blockDraft?.map(\.id))
        #expect(copy.tags == draft.tags && copy.isFavorite && copy.wordGoal == 1200)
        #expect(copy.assistantRules == draft.assistantRules && copy.purpose == .material)
        #expect(library.saveError == nil)
        #expect(library.recoveries.count == 1 && library.recoveries.first?.id == recovery.id)
        #expect(library.recoveries.first?.isComplete == false)
        let reopened = try LibraryStore(directory: store.directory)
        #expect(reopened.snapshot.pages.first(where: { $0.id == copyID })?.markdown.utf8.elementsEqual(draft.markdown.utf8) == true)
        try bytes.write(to: media)
        let restoredID = try #require(library.recoverAsCopy(recovery))
        #expect(restoredID != copyID)
        #expect(try store.attachmentData(attachment) == bytes)
        #expect(library.recoveries.isEmpty)
        #expect(store.snapshot.pages.contains(where: { $0.id == copyID }))
    }
    @Test func staleLibraryCannotCreateTextCopyOrConsumeRecovery() throws {
        let (root, store, library, baseline, attachment) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.removeItem(at: store.directory.appendingPathComponent(attachment.relativePath))
        var draft = baseline; draft.markdown = "Unsaved text"
        #expect(!library.preserveConflictedDraft(draft))
        let recovery = try #require(library.recoveries.first)
        let external = try LibraryStore(directory: store.directory)
        _ = try external.createSpace(title: "Another writer")
        #expect(library.recoverTextAsCopy(recovery) == nil)
        #expect(library.saveError != nil)
        #expect(library.recoveries.first?.id == recovery.id)
        let reopened = try LibraryStore(directory: store.directory)
        #expect(reopened.snapshot.pages.count == 1)
        #expect(reopened.snapshot.spaces.contains(where: { $0.title == "Another writer" }))
    }
}
