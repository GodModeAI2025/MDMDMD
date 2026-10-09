import Foundation
import Testing
@testable import SkriptumCore

@MainActor private struct PageResolutionFixture {
    let root: URL, store: LibraryStore, journal: ICloudSyncJournal
    let local: Page, remote: Page
    init() throws {
        root = URL(fileURLWithPath: "/private/tmp/ScriptumPageResolution-" + UUID().uuidString)
        store = try LibraryStore(directory: root.appendingPathComponent("Library"))
        let space = try store.createSpace(title: "Writing")
        local = try store.createPage(spaceID: space.id, title: "Local title", markdown: "Local e\u{301}\r\n🦊")
        var other = local; other.revision = UUID(); other.title = "Remote title"; other.blocks = [Block(markdown: "Remote 🦊\r\n")]
        remote = other
        journal = try ICloudSyncJournal(directory: root.appendingPathComponent("Outbox"), scope: ICloudSyncScope(accountID: "owned", libraryID: UUID()))
    }
    func clearInitial() throws {
        for change in try journal.pendingBatch() { try journal.acknowledge(recordID: change.recordID, revisionID: change.revisionID) }
    }
    func queuedPage() throws -> ICloudPagePayload {
        let change = try #require(try journal.pendingChange(recordID: .init(kind: .page, id: local.id)))
        return try ICloudPagePayload.decode(change.payload, expectedPageID: local.id, expectedRevision: change.revisionID)
    }
}

@Test @MainActor func pageResolutionKeepsBothVersionsAndQueuesChosenBytesBasedOnRemoteRevision() throws {
    let f = try PageResolutionFixture(); defer { try? FileManager.default.removeItem(at: f.root) }
    let binding = try ICloudLibrarySyncBinding(store: f.store, journal: f.journal); try f.clearInitial()
    let merged = "Local e\u{301}\r\nRemote 🦊\r\n"
    let resolution = try f.store.prepareICloudPageResolution(remote: f.remote, expectedLocalRevision: f.local.revision, choice: .mergedMarkdown(merged))
    try binding.applyPageResolution(resolution)
    let payload = try f.queuedPage()
    #expect(payload.baseRevision == f.remote.revision)
    #expect(payload.page.revision == resolution.resolved.revision)
    #expect(payload.page.markdown.utf8.elementsEqual(merged.utf8))
    #expect(f.store.snapshot.revisions.contains { $0.page == f.local })
    #expect(f.store.snapshot.revisions.contains { $0.page == f.remote })
    #expect(try LibraryStore(directory: f.store.directory).snapshot.pages == [resolution.resolved])
    let restart = try ICloudLibraryJournalBridge(journal: f.journal)
    #expect(try restart.project(from: f.store.snapshot, to: f.store.snapshot) == 0)
    #expect(try f.queuedPage().baseRevision == f.remote.revision)
}

@Test @MainActor func interruptedResolutionStartupReplaysRemoteAncestryBeforeOrdinaryProjection() throws {
    let f = try PageResolutionFixture(); defer { try? FileManager.default.removeItem(at: f.root) }
    let bridge = try ICloudLibraryJournalBridge(journal: f.journal)
    try bridge.bootstrap(f.store.snapshot); try f.clearInitial()
    let resolution = try f.store.prepareICloudPageResolution(remote: f.remote, expectedLocalRevision: f.local.revision, choice: .remote)
    try bridge.preparePageResolution(pageID: f.local.id, expectedLocalRevision: f.local.revision,
        resolvedRevision: resolution.resolved.revision, remoteRevision: f.remote.revision)
    try f.store.applyICloudPageResolution(resolution)
    // Simulate process loss before the outbox/baseline projection. Constructor
    // startup must discover the reservation before creating the queued payload.
    let reopened = try LibraryStore(directory: f.store.directory)
    let binding = try ICloudLibrarySyncBinding(store: reopened, journal: f.journal)
    #expect(try f.queuedPage().baseRevision == f.remote.revision)
    #expect(try f.queuedPage().page.title == f.remote.title)
    try binding.retry()
    #expect(try f.queuedPage().page.revision == resolution.resolved.revision)
}

@Test @MainActor func laterLocalEditAfterInterruptedResolutionRetainsServerBaseAndAllHistory() throws {
    let f = try PageResolutionFixture(); defer { try? FileManager.default.removeItem(at: f.root) }
    let bridge = try ICloudLibraryJournalBridge(journal: f.journal)
    try bridge.bootstrap(f.store.snapshot); try f.clearInitial()
    let resolution = try f.store.prepareICloudPageResolution(remote: f.remote, expectedLocalRevision: f.local.revision, choice: .local)
    try bridge.preparePageResolution(pageID: f.local.id, expectedLocalRevision: f.local.revision,
        resolvedRevision: resolution.resolved.revision, remoteRevision: f.remote.revision)
    try f.store.applyICloudPageResolution(resolution)
    try f.store.setMarkdown(f.local.id, markdown: "Later exact e\u{301}\r\n🦊", baseRevision: resolution.resolved.revision)
    let reopened = try LibraryStore(directory: f.store.directory)
    let binding = try ICloudLibrarySyncBinding(store: reopened, journal: f.journal)
    #expect(try f.queuedPage().baseRevision == f.remote.revision)
    #expect(try f.queuedPage().page.markdown.utf8.elementsEqual("Later exact e\u{301}\r\n🦊".utf8))
    #expect(reopened.snapshot.revisions.contains { $0.id == resolution.resolved.revision })
    try binding.retry()
    #expect(try f.queuedPage().baseRevision == f.remote.revision)
}

@Test @MainActor func staleResolutionAndIncomingAdoptionCannotErasePendingAncestry() throws {
    let f = try PageResolutionFixture(); defer { try? FileManager.default.removeItem(at: f.root) }
    let binding = try ICloudLibrarySyncBinding(store: f.store, journal: f.journal); try f.clearInitial()
    let resolution = try f.store.prepareICloudPageResolution(remote: f.remote, expectedLocalRevision: f.local.revision, choice: .remote)
    try f.store.setMarkdown(f.local.id, markdown: "New user text", baseRevision: f.local.revision)
    let bytes = try Data(contentsOf: f.store.directory.appendingPathComponent("library.json"))
    #expect(throws: (any Error).self) { try binding.applyPageResolution(resolution) }
    #expect(try Data(contentsOf: f.store.directory.appendingPathComponent("library.json")) == bytes)
    let bridge = try ICloudLibraryJournalBridge(journal: f.journal)
    let previous = try #require(try bridge.lastProjectedSnapshot())
    try bridge.preparePageResolution(pageID: f.local.id, expectedLocalRevision: previous.pages[0].revision,
        resolvedRevision: UUID(), remoteRevision: f.remote.revision)
    var unrelatedIncoming = previous; unrelatedIncoming.spaces[0].title = "Incoming title"
    #expect(throws: (any Error).self) { try bridge.adoptIncoming(from: previous, to: unrelatedIncoming) }
    #expect(try bridge.lastProjectedSnapshot() == previous)
}

@Test @MainActor func failedResolutionOutboxCommitPreservesChosenTextAndReplayableRemoteBase() throws {
    let f = try PageResolutionFixture(); defer { try? FileManager.default.removeItem(at: f.root) }
    let binding = try ICloudLibrarySyncBinding(store: f.store, journal: f.journal); try f.clearInitial()
    let originalQueue = try Data(contentsOf: f.journal.fileURL)
    let foreign = f.root.appendingPathComponent("unrelated.txt"), foreignBytes = Data("Unrelated preserved bytes".utf8)
    try foreignBytes.write(to: foreign)
    try FileManager.default.removeItem(at: f.journal.fileURL)
    try FileManager.default.createSymbolicLink(at: f.journal.fileURL, withDestinationURL: foreign)
    let resolution = try f.store.prepareICloudPageResolution(remote: f.remote, expectedLocalRevision: f.local.revision, choice: .mergedMarkdown("Chosen e\u{301}\r\n🦊"))
    #expect(throws: (any Error).self) { try binding.applyPageResolution(resolution) }
    #expect(binding.needsRetry)
    #expect(try LibraryStore(directory: f.store.directory).snapshot.pages == [resolution.resolved])
    #expect(try Data(contentsOf: foreign) == foreignBytes)
    try FileManager.default.removeItem(at: f.journal.fileURL)
    try originalQueue.write(to: f.journal.fileURL)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: f.journal.fileURL.path)
    try binding.retry()
    #expect(!binding.needsRetry)
    #expect(try f.queuedPage().baseRevision == f.remote.revision)
    #expect(try f.queuedPage().page.markdown.utf8.elementsEqual("Chosen e\u{301}\r\n🦊".utf8))
    #expect(try Data(contentsOf: foreign) == foreignBytes)
}

@Test @MainActor func unappliedResolutionReservationIsRetiredBeforeUnrelatedIncomingMutation() throws {
    let f = try PageResolutionFixture(); defer { try? FileManager.default.removeItem(at: f.root) }
    let bridge = try ICloudLibraryJournalBridge(journal: f.journal)
    try bridge.bootstrap(f.store.snapshot); try f.clearInitial()
    try bridge.preparePageResolution(pageID: f.local.id, expectedLocalRevision: f.local.revision,
        resolvedRevision: UUID(), remoteRevision: f.remote.revision)
    #expect(try bridge.project(from: f.store.snapshot, to: f.store.snapshot) == 0)
    var incoming = f.store.snapshot; incoming.spaces[0].title = "Remote metadata"
    try bridge.adoptIncoming(from: f.store.snapshot, to: incoming)
    #expect(try bridge.lastProjectedSnapshot() == incoming)
    #expect(try f.journal.pendingCount() == 0)
}

@Test @MainActor func mergedOlderReviewRestoresOnlyReferencedImagesFromSamePageHistory() throws {
    let f = try PageResolutionFixture(); defer { try? FileManager.default.removeItem(at: f.root) }
    let png = try #require(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII="))
    let image = try f.store.addAttachment(pageID: f.local.id, data: png, mediaType: "image/png", filename: "Historical.png", baseRevision: f.local.revision)
    let withImage = try #require(f.store.snapshot.pages.first { $0.id == f.local.id })
    try f.store.removeAttachment(pageID: f.local.id, attachmentID: image.id, baseRevision: withImage.revision)
    let local = try #require(f.store.snapshot.pages.first { $0.id == f.local.id })
    #expect(local.attachments?.isEmpty ?? true)
    var remote = local; remote.revision = UUID()
    let body = "Older restored text e\u{301}\r\n![Historical](media/\(image.id))\r\n"
    let resolution = try f.store.prepareICloudPageResolution(remote: remote, expectedLocalRevision: local.revision, choice: .mergedMarkdown(body))
    #expect(resolution.resolved.attachments == [image])
    #expect(resolution.resolved.markdown.utf8.elementsEqual(body.utf8))
    try f.store.applyICloudPageResolution(resolution)
    let reopened = try LibraryStore(directory: f.store.directory)
    #expect(reopened.snapshot.pages.first?.attachments == [image])
    #expect(try reopened.attachmentData(image) == png)
    #expect(reopened.snapshot.revisions.contains { $0.page.revision == withImage.revision && $0.page.attachments == [image] })
}

@Test @MainActor func mergeDoesNotBorrowOtherPagesImagesAndCodeExamplesDoNotRestoreAssets() throws {
    let f = try PageResolutionFixture(); defer { try? FileManager.default.removeItem(at: f.root) }
    let other = try f.store.createPage(spaceID: f.local.spaceID, title: "Private other page")
    let png = try #require(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII="))
    let privateImage = try f.store.addAttachment(pageID: other.id, data: png, mediaType: "image/png", filename: "Private.png", baseRevision: other.revision)
    let before = try Data(contentsOf: f.store.directory.appendingPathComponent("library.json"))
    #expect(throws: LibraryError.missingAttachment) {
        try f.store.prepareICloudPageResolution(remote: f.remote, expectedLocalRevision: f.local.revision,
            choice: .mergedMarkdown("![Not associated](media/\(privateImage.id))"))
    }
    let body = "`![Example](media/\(privateImage.id))`\n\n```markdown\n![Example](media/\(privateImage.id))\n```\n"
    let resolution = try f.store.prepareICloudPageResolution(remote: f.remote, expectedLocalRevision: f.local.revision, choice: .mergedMarkdown(body))
    #expect(resolution.resolved.attachments?.isEmpty ?? true)
    #expect(try Data(contentsOf: f.store.directory.appendingPathComponent("library.json")) == before)
    #expect(try f.store.attachmentData(privateImage) == png)
}

@Test @MainActor func unavailableHistoricalImageStopsMergeWithoutChangingEitherVersion() throws {
    let f = try PageResolutionFixture(); defer { try? FileManager.default.removeItem(at: f.root) }
    let png = try #require(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII="))
    let image = try f.store.addAttachment(pageID: f.local.id, data: png, mediaType: "image/png", filename: "Retained.png", baseRevision: f.local.revision)
    let version = try #require(f.store.snapshot.pages.first { $0.id == f.local.id })
    try f.store.removeAttachment(pageID: f.local.id, attachmentID: image.id, baseRevision: version.revision)
    let current = try #require(f.store.snapshot.pages.first { $0.id == f.local.id })
    var remote = current; remote.revision = UUID()
    let before = try Data(contentsOf: f.store.directory.appendingPathComponent("library.json"))
    // Controlled fixture removal only; source images from the app are never deleted.
    try FileManager.default.removeItem(at: f.store.directory.appendingPathComponent(image.relativePath))
    #expect(throws: (any Error).self) {
        try f.store.prepareICloudPageResolution(remote: remote, expectedLocalRevision: current.revision,
            choice: .mergedMarkdown("![Retained](media/\(image.id))"))
    }
    #expect(try Data(contentsOf: f.store.directory.appendingPathComponent("library.json")) == before)
}

@Test @MainActor func missingCurrentReferencedImageAlsoStopsMergedResolution() throws {
    let f = try PageResolutionFixture(); defer { try? FileManager.default.removeItem(at: f.root) }
    let png = try #require(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII="))
    let image = try f.store.addAttachment(pageID: f.local.id, data: png, mediaType: "image/png", filename: "Current.png", baseRevision: f.local.revision)
    let current = try #require(f.store.snapshot.pages.first { $0.id == f.local.id })
    var remote = current; remote.revision = UUID(); remote.attachments = nil
    let before = try Data(contentsOf: f.store.directory.appendingPathComponent("library.json"))
    try FileManager.default.removeItem(at: f.store.directory.appendingPathComponent(image.relativePath))
    #expect(throws: (any Error).self) {
        try f.store.prepareICloudPageResolution(remote: remote, expectedLocalRevision: current.revision,
            choice: .mergedMarkdown("![Current](media/\(image.id))"))
    }
    #expect(try Data(contentsOf: f.store.directory.appendingPathComponent("library.json")) == before)
}

@Test @MainActor func mergingRejectsByteDifferentImageDescriptorsDespiteEquivalentUnicodeNames() throws {
    let f = try PageResolutionFixture(); defer { try? FileManager.default.removeItem(at: f.root) }
    let png = try #require(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII="))
    let image = try f.store.addAttachment(pageID: f.local.id, data: png, mediaType: "image/png", filename: "é.png", baseRevision: f.local.revision)
    let current = try #require(f.store.snapshot.pages.first { $0.id == f.local.id })
    var remote = current; remote.revision = UUID()
    remote.attachments = [MediaAttachment(id: image.id, filename: "e\u{301}.png", mediaType: image.mediaType,
        byteCount: image.byteCount, sha256: image.sha256)]
    let before = try Data(contentsOf: f.store.directory.appendingPathComponent("library.json"))
    #expect(throws: LibraryError.invalidAttachment) {
        try f.store.prepareICloudPageResolution(remote: remote, expectedLocalRevision: current.revision,
            choice: .mergedMarkdown("![Same ID](media/\(image.id))"))
    }
    #expect(try Data(contentsOf: f.store.directory.appendingPathComponent("library.json")) == before)
    #expect(try f.store.attachmentData(image) == png)
}
