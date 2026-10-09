import Foundation
import Testing
@testable import SkriptumCore

@Test @MainActor func sharedCheckpointPreservesCanonicalPageAndDropsAccessGrantOnRestart() throws {
    let directory = URL(fileURLWithPath: "/private/tmp/ScriptumSharedStore-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let page = Page(spaceID: UUID(), parentID: UUID(), title: "Shared", markdown: "e\u{301}\r\n")
    var snapshot = LibrarySnapshot(); snapshot.pages = [page]
    let root = ICloudSyncRecordID(kind: .page, id: page.id)
    let identity = try ICloudSharedStoreIdentity(accountID: "participant", ownerID: "owner", zoneName: "zone", shareName: "share", root: root)
    let store = try ICloudSharedDocumentStore(directory: directory, identity: identity)
    let revision = try store.replace(snapshot, expectedRevision: nil)
    let restarted = try ICloudSharedDocumentStore(directory: directory, identity: identity)
    #expect(try restarted.checkpointRevision() == revision)
    #expect(try restarted.context()?.page(page.id) == nil)
    let loaded = try restarted.context(permission: .readOnly)
    let readable = try #require(loaded)
    #expect(readable.canonical.pages == [page])
    #expect(readable.page(page.id)?.markdown.utf8.elementsEqual(page.markdown.utf8) == true)
    #expect(try restarted.replace(snapshot, expectedRevision: revision) == revision)
    let before = try Data(contentsOf: store.fileURL)
    #expect(throws: ICloudSharedStoreError.staleCheckpoint) { try store.replace(snapshot, expectedRevision: nil) }
    #expect(try Data(contentsOf: store.fileURL) == before)
    let other = try ICloudSharedDocumentStore(directory: directory, identity: .init(accountID: "other", ownerID: "owner", zoneName: "zone", shareName: "share", root: root))
    #expect(other.fileURL != store.fileURL)
    #expect(try other.context() == nil)
}

@Test @MainActor func corruptSharedCheckpointCannotBeReplacedByAReceiveRetry() throws {
    let directory = URL(fileURLWithPath: "/private/tmp/ScriptumSharedCorrupt-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let page = Page(spaceID: UUID(), title: "Preserved")
    var snapshot = LibrarySnapshot(); snapshot.pages = [page]
    let identity = try ICloudSharedStoreIdentity(accountID: "participant", ownerID: "owner", zoneName: "zone", shareName: "share", root: .init(kind: .page, id: page.id))
    let store = try ICloudSharedDocumentStore(directory: directory, identity: identity)
    let revision = try store.replace(snapshot, expectedRevision: nil)
    let corrupt = Data("corrupt checkpoint retained for recovery".utf8)
    try corrupt.write(to: store.fileURL)
    #expect(throws: (any Error).self) { try store.context(permission: .readWrite) }
    #expect(throws: (any Error).self) { try store.replace(snapshot, expectedRevision: revision) }
    #expect(try Data(contentsOf: store.fileURL) == corrupt)
}

@Test @MainActor func linkedSharedCheckpointNeverReadsOrOverwritesItsTarget() throws {
    let directory = URL(fileURLWithPath: "/private/tmp/ScriptumSharedLinked-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let page = Page(spaceID: UUID(), title: "Preserved")
    var snapshot = LibrarySnapshot(); snapshot.pages = [page]
    let identity = try ICloudSharedStoreIdentity(accountID: "participant", ownerID: "owner", zoneName: "zone", shareName: "share", root: .init(kind: .page, id: page.id))
    let store = try ICloudSharedDocumentStore(directory: directory, identity: identity)
    let target = directory.appendingPathComponent("unrelated-private-file")
    let bytes = Data("Unrelated document must survive".utf8)
    try bytes.write(to: target)
    try FileManager.default.createSymbolicLink(at: store.fileURL, withDestinationURL: target)
    #expect(throws: ICloudSharedStoreError.unsafeFile) { try store.context(permission: .readWrite) }
    #expect(throws: ICloudSharedStoreError.unsafeFile) { try store.replace(snapshot, expectedRevision: nil) }
    #expect(try Data(contentsOf: target) == bytes)
    #expect(try FileManager.default.destinationOfSymbolicLink(atPath: store.fileURL.path) == target.path)
}

@Test @MainActor func sharedEditsPersistOrderedAncestryAndCannotBeOverwrittenByReceive() throws {
    let directory = URL(fileURLWithPath: "/private/tmp/ScriptumSharedEdit-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let page = Page(spaceID: UUID(), parentID: UUID(), title: "Shared", markdown: "Original")
    var snapshot = LibrarySnapshot(); snapshot.pages = [page]
    let identity = try ICloudSharedStoreIdentity(accountID: "participant", ownerID: "owner", zoneName: "zone", shareName: "share", root: .init(kind: .page, id: page.id))
    let store = try ICloudSharedDocumentStore(directory: directory, identity: identity)
    _ = try store.replace(snapshot, expectedRevision: nil)
    let before = try Data(contentsOf: store.fileURL)
    #expect(throws: ICloudSharedDocumentError.permissionDenied) {
        try store.editMarkdown(pageID: page.id, expectedPageRevision: page.revision, markdown: "Denied", permission: .readOnly)
    }
    #expect(try Data(contentsOf: store.fileURL) == before)
    let first = try store.editMarkdown(pageID: page.id, expectedPageRevision: page.revision, markdown: "First", permission: .readWrite)
    let second = try store.editMarkdown(pageID: page.id, expectedPageRevision: first, markdown: "e\u{301}\r\nSecond", permission: .readWrite)
    let reopened = try ICloudSharedDocumentStore(directory: directory, identity: identity)
    let changes = try reopened.pendingChanges().filter { $0.recordID.kind == .page }
    #expect(changes.map(\.revisionID) == [first, second])
    #expect(try ICloudPagePayload.decode(changes[0].payload, expectedPageID: page.id, expectedRevision: first).baseRevision == page.revision)
    #expect(try ICloudPagePayload.decode(changes[1].payload, expectedPageID: page.id, expectedRevision: second).baseRevision == first)
    #expect(try reopened.context(permission: .readWrite)?.canonical.pages.first?.parentID == page.parentID)
    let revision = try reopened.checkpointRevision()
    let saved = try Data(contentsOf: reopened.fileURL)
    #expect(throws: ICloudSharedStoreError.pendingLocalChanges) { try reopened.replace(snapshot, expectedRevision: revision) }
    #expect(try Data(contentsOf: reopened.fileURL) == saved)
    let recordID = ICloudSyncRecordID(kind: .page, id: page.id)
    #expect(try reopened.acknowledge(recordID: recordID, revisionID: second) == false)
    #expect(try reopened.acknowledge(recordID: recordID, revisionID: first))
    #expect(try reopened.acknowledge(recordID: recordID, revisionID: first) == false)
    #expect(try reopened.pendingChanges().filter { $0.recordID == recordID }.map(\.revisionID) == [second])
}
