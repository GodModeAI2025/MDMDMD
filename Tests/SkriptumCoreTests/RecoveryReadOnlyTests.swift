import Foundation
import Testing
@testable import SkriptumCore

@MainActor struct RecoveryReadOnlyTests {
    private func fixture() throws -> (LibraryStore, Page, UUID, URL) {
        let store = try LibraryStore(directory: URL.temporaryDirectory.appending(path: UUID().uuidString))
        let space = try store.createSpace(title: "Book")
        let page = try store.createPage(spaceID: space.id, title: "Chapter", markdown: "Durable 🦊 e\u{301}\r\n")
        let token = try store.beginEditing(pageID: page.id, baseRevision: page.revision)
        try store.updateEditing(token, markdown: "Pending 🦊 e\u{301}\r\n")
        let bad = store.directory.appending(path: "edits/" + UUID().uuidString + ".json")
        try Data("broken".utf8).write(to: bad)
        return (store, page, token, bad)
    }
    @Test func damagedNeighborStillAllowsReadingTheDurableLibrary() throws {
        let (store, page, _, _) = try fixture(); defer { try? FileManager.default.removeItem(at: store.directory) }
        let reopened = try LibraryStore(directory: store.directory, recoveryPolicy: .readOnlyOnFailure)
        #expect(reopened.snapshot.pages[0].markdown.utf8.elementsEqual(page.markdown.utf8))
    }
}

extension RecoveryReadOnlyTests {
    @Test func readOnlyOpenPreservesAllFilesAndExposesOnlyReadableDrafts() throws {
        let (store, page, token, bad) = try fixture(); defer { try? FileManager.default.removeItem(at: store.directory) }
        let json = store.directory.appending(path: "library.json"), good = store.directory.appending(path: "edits/" + token.uuidString + ".json")
        let original = try Data(contentsOf: json), goodBytes = try Data(contentsOf: good), badBytes = try Data(contentsOf: bad)
        let reopened = try LibraryStore(directory: store.directory, recoveryPolicy: .readOnlyOnFailure)
        #expect(reopened.isReadOnly && reopened.hasActiveEdits && reopened.recoveryFailure != nil)
        #expect(reopened.unreadableJournalFiles == [bad.lastPathComponent])
        #expect(reopened.snapshot.pages[0].revision == page.revision)
        let pending = try #require(reopened.pendingRecoveryDrafts.first)
        #expect(pending.id == token && pending.page.markdown.utf8.elementsEqual("Pending 🦊 e\u{301}\r\n".utf8))
        #expect(try Data(contentsOf: json) == original)
        #expect(try Data(contentsOf: good) == goodBytes)
        #expect(try Data(contentsOf: bad) == badBytes)
        var notifications = 0; reopened.onDurableChange = { _ in notifications += 1 }
        #expect(throws: LibraryError.recoveryRequired) { try reopened.createSpace(title: "No write") }
        #expect(throws: LibraryError.recoveryRequired) { try reopened.setMarkdown(page.id, markdown: "No write", baseRevision: page.revision) }
        #expect(throws: LibraryError.recoveryRequired) { try reopened.beginEditing(pageID: page.id, baseRevision: page.revision) }
        #expect(throws: LibraryError.recoveryRequired) { try reopened.updateEditing(token, markdown: "No journal write") }
        #expect(throws: LibraryError.recoveryRequired) { try reopened.finishEditing(token) }
        #expect(throws: LibraryError.editInProgress) { try reopened.exportPackage(to: store.directory.appending(path: "Rescue.scriptum")) }
        #expect(notifications == 0)
        #expect(try Data(contentsOf: json) == original)
        #expect(try Data(contentsOf: good) == goodBytes)
        #expect(try Data(contentsOf: bad) == badBytes)
    }
    @Test func mediaAndRecoveryCreationRejectBeforeCreatingFiles() throws {
        let (store, page, _, _) = try fixture(); defer { try? FileManager.default.removeItem(at: store.directory) }
        let reopened = try LibraryStore(directory: store.directory, recoveryPolicy: .readOnlyOnFailure)
        let png = try #require(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII="))
        #expect(throws: LibraryError.recoveryRequired) { try reopened.addAttachment(pageID: page.id, data: png, mediaType: "image/png", filename: "photo.png", baseRevision: page.revision) }
        #expect(throws: LibraryError.recoveryRequired) { try reopened.addImageBlock(pageID: page.id, data: png, mediaType: "image/png", filename: "photo.png", altText: "Photo", afterBlockID: nil, baseRevision: page.revision) }
        #expect(throws: LibraryError.recoveryRequired) { try reopened.createRecoveredPage(from: page, spaceID: page.spaceID, mediaRoot: store.directory) }
        let attachment = MediaAttachment(filename: "photo.png", mediaType: "image/png", byteCount: png.count, sha256: MediaValidation.digest(png))
        let payload = try ICloudImagePayload(attachment: attachment, revisionID: page.revision, data: png)
        #expect(throws: LibraryError.recoveryRequired) { try reopened.importICloudImage(payload) }
        #expect(!FileManager.default.fileExists(atPath: store.directory.appending(path: "media").path))
        #expect(reopened.snapshot.pages.count == 1)
    }
    @Test func repairedFixtureRequiresFreshOpenAndRecoversWithoutLosingSource() throws {
        let (store, page, _, bad) = try fixture(); defer { try? FileManager.default.removeItem(at: store.directory) }
        let protected = try LibraryStore(directory: store.directory, recoveryPolicy: .readOnlyOnFailure)
        try FileManager.default.removeItem(at: bad) // Only this test's deliberately broken fixture.
        let repaired = try LibraryStore(directory: store.directory)
        #expect(!repaired.isReadOnly && !repaired.hasActiveEdits && repaired.pendingRecoveryDrafts.isEmpty)
        #expect(repaired.snapshot.pages[0].markdown.utf8.elementsEqual("Pending 🦊 e\u{301}\r\n".utf8))
        #expect(repaired.snapshot.revisions.contains(where: { $0.id == page.revision }))
        #expect(protected.isReadOnly)
        #expect(throws: LibraryError.recoveryRequired) { try protected.renamePage(page.id, title: "Old rescue view") }
        try repaired.renamePage(page.id, title: "Writable after explicit reopen")
    }
    @Test func invalidLibraryCannotBeReplacedByAnEmptyRescueSnapshot() throws {
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString); defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appending(path: "library.json"), data = Data("not a library".utf8)
        try data.write(to: file)
        #expect(throws: (any Error).self) { try LibraryStore(directory: root, recoveryPolicy: .readOnlyOnFailure) }
        #expect(try Data(contentsOf: file) == data)
    }
}
