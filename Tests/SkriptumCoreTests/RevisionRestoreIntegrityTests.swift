import Foundation
import Testing
@testable import SkriptumCore

@MainActor struct RevisionRestoreIntegrityTests {
    private func fixture() throws -> (LibraryStore, Page, MediaAttachment, Data) {
        let store = try LibraryStore(directory: URL.temporaryDirectory.appending(path: UUID().uuidString))
        let space = try store.createSpace(title: "Book")
        let page = try store.createPage(spaceID: space.id, title: "Chapter", markdown: "Original e\u{301} 🦊\r\n")
        let png = try #require(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII="))
        let attachment = try store.addAttachment(pageID: page.id, data: png, mediaType: "image/png", filename: "photo.png", baseRevision: page.revision)
        return (store, try #require(store.snapshot.pages.first), attachment, png)
    }
    @Test func missingHistoricalImageRejectsRestoreWithoutPublishing() throws {
        let (store, historical, attachment, _) = try fixture(); defer { try? FileManager.default.removeItem(at: store.directory) }
        try store.removeAttachment(pageID: historical.id, attachmentID: attachment.id, baseRevision: historical.revision)
        let before = store.snapshot, disk = try Data(contentsOf: store.directory.appending(path: "library.json"))
        try FileManager.default.removeItem(at: store.directory.appendingPathComponent(attachment.relativePath))
        var notifications = 0; store.onDurableChange = { _ in notifications += 1 }
        #expect(throws: (any Error).self) { try store.restoreRevision(pageID: historical.id, revisionID: historical.revision, baseRevision: before.pages[0].revision) }
        #expect(store.snapshot == before)
        #expect(try Data(contentsOf: store.directory.appending(path: "library.json")) == disk)
        #expect(notifications == 0)
    }
    @Test func corruptHistoricalImageRejectsRestoreWithoutPublishing() throws {
        let (store, historical, attachment, _) = try fixture(); defer { try? FileManager.default.removeItem(at: store.directory) }
        try store.removeAttachment(pageID: historical.id, attachmentID: attachment.id, baseRevision: historical.revision)
        let before = store.snapshot
        try Data("corrupted".utf8).write(to: store.directory.appendingPathComponent(attachment.relativePath))
        #expect(throws: LibraryError.invalidAttachment) { try store.restoreRevision(pageID: historical.id, revisionID: historical.revision, baseRevision: before.pages[0].revision) }
        #expect(store.snapshot == before)
    }
    @Test func contentRestorationCannotSilentlyUntrashParentOrChildren() throws {
        let (store, historical, _, _) = try fixture(); defer { try? FileManager.default.removeItem(at: store.directory) }
        let child = try store.createPage(spaceID: historical.spaceID, parentID: historical.id, title: "Child")
        try store.setMarkdown(historical.id, markdown: "Current text", baseRevision: historical.revision)
        try store.trashPage(historical.id)
        let before = store.snapshot
        try store.restoreRevision(pageID: historical.id, revisionID: historical.revision, baseRevision: before.pages[0].revision)
        #expect(store.snapshot.pages[0].trashedAt == before.pages[0].trashedAt)
        #expect(store.snapshot.pages.first(where: { $0.id == child.id }) == before.pages.first(where: { $0.id == child.id }))
        #expect(store.snapshot.pages[0].markdown.utf8.elementsEqual(historical.markdown.utf8))
    }
    @Test func restoringTheSameContentIsNotAnotherHistoricalEdit() throws {
        let (store, historical, _, _) = try fixture(); defer { try? FileManager.default.removeItem(at: store.directory) }
        try store.setMarkdown(historical.id, markdown: "Changed", baseRevision: historical.revision)
        try store.restoreRevision(pageID: historical.id, revisionID: historical.revision, baseRevision: store.snapshot.pages[0].revision)
        let restored = store.snapshot
        var notifications = 0; store.onDurableChange = { _ in notifications += 1 }
        try store.restoreRevision(pageID: historical.id, revisionID: historical.revision, baseRevision: restored.pages[0].revision)
        #expect(store.snapshot == restored)
        #expect(notifications == 0)
    }
    @Test func restoreAndReturnPreserveBothExactVersionsAndMedia() throws {
        let (store, original, attachment, png) = try fixture(); defer { try? FileManager.default.removeItem(at: store.directory) }
        try store.setMarkdown(original.id, markdown: "# New 🦊\r\nCafe\u{301}\r\n", baseRevision: original.revision)
        let newer = store.snapshot.pages[0]
        var notifications = 0; store.onDurableChange = { _ in notifications += 1 }
        try store.restoreRevision(pageID: original.id, revisionID: original.revision, baseRevision: newer.revision)
        #expect(store.snapshot.pages[0].blocks == original.blocks)
        #expect(store.snapshot.revisions.contains(where: { $0.page.revision == newer.revision && $0.page.blocks == newer.blocks }))
        #expect(notifications == 1)
        try store.restoreRevision(pageID: original.id, revisionID: newer.revision, baseRevision: store.snapshot.pages[0].revision)
        #expect(store.snapshot.pages[0].markdown.utf8.elementsEqual(newer.markdown.utf8))
        #expect(store.snapshot.pages[0].blocks.map(\.id) == newer.blocks.map(\.id))
        #expect(try store.attachmentData(attachment) == png)
        #expect(notifications == 2)
        #expect(try LibraryStore(directory: store.directory).snapshot == store.snapshot)
    }
}
