import Foundation
import CloudKit
import CryptoKit
import Testing
@testable import SkriptumCore
@testable import SkriptumWorkspaceModel

@MainActor private final class SharedReceiveFixture {
    let directory = URL(fileURLWithPath: "/private/tmp/ScriptumSharedReceive-" + UUID().uuidString)
    let page = Page(spaceID: UUID(), title: "Shared", markdown: "Original e\u{301}\r\n🦊")
    let libraryID = UUID().uuidString.lowercased()
    let zone = CKRecordZone.ID(zoneName: "shared-zone", ownerName: "owner")
    let store: ICloudSharedDocumentStore
    var records: [CKRecord.ID: CKRecord] = [:]
    let grant: ICloudShareParticipantTransport.Accepted
    var before: Data { get throws { try Data(contentsOf: store.fileURL) } }
    init() throws {
        let identity = try ICloudSharedStoreIdentity(accountID: "participant", ownerID: zone.ownerName,
            zoneName: zone.zoneName, shareName: "share", root: .init(kind: .page, id: page.id))
        store = try ICloudSharedDocumentStore(directory: directory, identity: identity)
        var snapshot = LibrarySnapshot(); snapshot.pages = [page]
        _ = try store.replace(snapshot, expectedRevision: nil)
        let root = CKRecord(recordType: "ScriptumItemV1", recordID: .init(recordName: "page:" + page.id.uuidString.lowercased(), zoneID: zone))
        let share = CKShare(rootRecord: root, shareID: .init(recordName: identity.shareName, zoneID: zone))
        grant = .init(share: share, root: root, canWrite: true, participantRecordID: .init(recordName: identity.accountID, zoneID: zone))
        let payload = try ICloudPagePayload(page: page, baseRevision: nil).encoded()
        root["libraryID"] = libraryID as CKRecordValue
        root["kind"] = "page" as CKRecordValue; root["uuid"] = page.id.uuidString.lowercased() as CKRecordValue
        root["revision"] = page.revision.uuidString.lowercased() as CKRecordValue; root["operation"] = "upsert" as CKRecordValue
        root["sha256"] = SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined() as CKRecordValue
        let file = directory.appendingPathComponent("root-payload"); try payload.write(to: file)
        root["payload"] = CKAsset(fileURL: file); records[root.recordID] = root
    }
    func close() { try? FileManager.default.removeItem(at: directory) }
    func add(_ change: ICloudSyncChange) -> CKRecord {
        let id = CKRecord.ID(recordName: change.recordID.kind.rawValue + ":" + change.recordID.id.uuidString.lowercased(), zoneID: zone)
        let record = CKRecord(recordType: "ScriptumItemV1", recordID: id)
        record.parent = .init(recordID: grant.root.recordID, action: .none)
        record["libraryID"] = libraryID as CKRecordValue
        record["kind"] = change.recordID.kind.rawValue as CKRecordValue
        record["uuid"] = change.recordID.id.uuidString.lowercased() as CKRecordValue
        record["revision"] = change.revisionID.uuidString.lowercased() as CKRecordValue
        record["operation"] = change.operation.rawValue as CKRecordValue
        record["sha256"] = SHA256.hash(data: change.payload).map { String(format: "%02x", $0) }.joined() as CKRecordValue
        records[id] = record; return record
    }
    func receive() async throws -> ICloudSharedDocumentContext {
        try await ICloudSharedSnapshotReceiver.receive(records: records, accepted: grant, store: store,
            expectedRevision: store.checkpointRevision(), imageDirectory: directory.appendingPathComponent("Images"),
            record: { try #require(self.records[$0]) }, revalidate: { self.grant })
    }
}

@Test @MainActor func sharedReceiveAcceptsActualOwnerDeletionProjectionWithoutBlockingRemainingPages() async throws {
    let fixture = try SharedReceiveFixture(); defer { fixture.close() }
    var child = Page(spaceID: fixture.page.spaceID, parentID: fixture.page.id, title: "Removed", markdown: "Old")
    child.trashedAt = Date()
    let comment = Comment(pageID: child.id, blockID: nil, body: "Old comment", author: "owner")
    let revision = Revision(page: child, author: "owner", capturedAt: Date())
    var old = LibrarySnapshot(); old.spaces = [Space(id: child.spaceID, title: "Space")]
    old.pages = [fixture.page, child]; old.comments = [comment]; old.revisions = [revision]
    var current = old; current.pages = [fixture.page]; current.comments = []; current.revisions = []
    let changes = try ICloudLibraryProjection.changes(from: old, to: current)
    #expect(changes.count == 3)
    #expect(changes.allSatisfy { $0.operation == .tombstone })
    for change in changes { _ = fixture.add(change) }
    var participant = old; participant.spaces = []
    _ = try fixture.store.replace(participant, expectedRevision: fixture.store.checkpointRevision())
    let result = try await fixture.receive()
    #expect(result.canonical.pages.map(\.id) == [fixture.page.id])
    #expect(result.canonical.comments.isEmpty)
    #expect(result.canonical.revisions.isEmpty)
    #expect(result.page(fixture.page.id)?.markdown.utf8.elementsEqual(fixture.page.markdown.utf8) == true)
    let restarted = try ICloudSharedDocumentStore(directory: fixture.directory, identity: fixture.store.identity)
    #expect(try restarted.context(permission: .readOnly)?.canonical.pages.map(\.id) == [fixture.page.id])
}

@Test(arguments: ["payload", "digest", "library", "uuid", "revision", "operation", "type", "root"])
@MainActor func sharedReceiveRejectsMalformedDeletionAndPreservesCheckpoint(_ mutation: String) async throws {
    let fixture = try SharedReceiveFixture(); defer { fixture.close() }
    let record = fixture.add(.init(recordID: .init(kind: .page, id: UUID()), revisionID: UUID(), operation: .tombstone, payload: Data()))
    switch mutation {
    case "payload": record["payload"] = CKAsset(fileURL: try #require((fixture.grant.root["payload"] as? CKAsset)?.fileURL))
    case "digest": record["sha256"] = String(repeating: "0", count: 64) as CKRecordValue
    case "library": record["libraryID"] = UUID().uuidString.lowercased() as CKRecordValue
    case "uuid": record["uuid"] = UUID().uuidString.lowercased() as CKRecordValue
    case "revision": record["revision"] = "invalid" as CKRecordValue
    case "operation": record["operation"] = "delete" as CKRecordValue
    case "type":
        let other = CKRecord(recordType: "Unrelated", recordID: record.recordID)
        for key in record.allKeys() { other[key] = record[key] }; other.parent = record.parent
        fixture.records[record.recordID] = other
    case "root":
        fixture.records.removeValue(forKey: record.recordID)
        fixture.grant.root["operation"] = "tombstone" as CKRecordValue
        fixture.grant.root["payload"] = nil
        fixture.grant.root["sha256"] = SHA256.hash(data: Data()).map { String(format: "%02x", $0) }.joined() as CKRecordValue
    default: Issue.record("Unknown fixture")
    }
    let before = try fixture.before
    do { _ = try await fixture.receive(); Issue.record("Malformed deletion accepted") }
    catch { #expect(error as? ICloudSharedReceiveError == .invalidRecord) }
    #expect(try fixture.before == before)
}

@Test @MainActor func sharedReceiveDeletionCannotOverwritePendingParticipantEdits() async throws {
    let fixture = try SharedReceiveFixture(); defer { fixture.close() }
    _ = fixture.add(.init(recordID: .init(kind: .comment, id: UUID()), revisionID: UUID(), operation: .tombstone, payload: Data()))
    _ = try fixture.store.editMarkdown(pageID: fixture.page.id, expectedPageRevision: fixture.page.revision,
        markdown: "Private pending e\u{301}\r\n🦊", permission: .readWrite)
    let before = try fixture.before, pending = try fixture.store.pendingChanges()
    do { _ = try await fixture.receive(); Issue.record("Pending participant text overwritten") }
    catch { #expect(error as? ICloudSharedStoreError == .pendingLocalChanges) }
    #expect(try fixture.before == before)
    #expect(try fixture.store.pendingChanges() == pending)
}

@Test @MainActor func sharedReceiveRevalidatesPermissionBeforeReplacingCheckpoint() async throws {
    let fixture = try SharedReceiveFixture(); defer { fixture.close() }
    _ = fixture.add(.init(recordID: .init(kind: .revision, id: UUID()), revisionID: UUID(), operation: .tombstone, payload: Data()))
    let before = try fixture.before
    do {
        _ = try await ICloudSharedSnapshotReceiver.receive(records: fixture.records, accepted: fixture.grant, store: fixture.store,
            expectedRevision: fixture.store.checkpointRevision(), imageDirectory: fixture.directory.appendingPathComponent("Images"),
            record: { try #require(fixture.records[$0]) }, revalidate: { throw ICloudShareParticipantError.permissionDenied })
        Issue.record("Revoked share replaced checkpoint")
    } catch { #expect(error as? ICloudShareParticipantError == .permissionDenied) }
    #expect(try fixture.before == before)
}

@Test @MainActor func sharedReceiveRejectsDifferentFetchedRecordIdentity() async throws {
    let fixture = try SharedReceiveFixture(); defer { fixture.close() }
    let metadata = fixture.add(.init(recordID: .init(kind: .comment, id: UUID()), revisionID: UUID(), operation: .tombstone, payload: Data()))
    let replacement = CKRecord(recordType: metadata.recordType, recordID: .init(recordName: metadata.recordID.recordName,
        zoneID: .init(zoneName: fixture.zone.zoneName, ownerName: "other-owner")))
    for key in metadata.allKeys() { replacement[key] = metadata[key] }; replacement.parent = metadata.parent
    let before = try fixture.before
    do {
        _ = try await ICloudSharedSnapshotReceiver.receive(records: fixture.records, accepted: fixture.grant, store: fixture.store,
            expectedRevision: fixture.store.checkpointRevision(), imageDirectory: fixture.directory.appendingPathComponent("Images"),
            record: { $0 == metadata.recordID ? replacement : try #require(fixture.records[$0]) }, revalidate: { fixture.grant })
        Issue.record("Wrong-zone record accepted")
    } catch { #expect(error as? ICloudSharedReceiveError == .invalidRecord) }
    #expect(try fixture.before == before)
}

@Test @MainActor func sharedReceiveDoesNotFetchUnrelatedDeletionOutsideSelectedShare() async throws {
    let fixture = try SharedReceiveFixture(); defer { fixture.close() }
    let other = fixture.add(.init(recordID: .init(kind: .comment, id: UUID()), revisionID: UUID(), operation: .tombstone, payload: Data()))
    other.parent = .init(recordID: .init(recordName: "page:" + UUID().uuidString.lowercased(), zoneID: fixture.zone), action: .none)
    other["operation"] = "invalid-and-unrelated" as CKRecordValue
    var fetched: [CKRecord.ID] = []
    let result = try await ICloudSharedSnapshotReceiver.receive(records: fixture.records, accepted: fixture.grant, store: fixture.store,
        expectedRevision: fixture.store.checkpointRevision(), imageDirectory: fixture.directory.appendingPathComponent("Images"),
        record: { fetched.append($0); return try #require(fixture.records[$0]) }, revalidate: { fixture.grant })
    #expect(fetched == [fixture.grant.root.recordID])
    #expect(result.canonical.pages.map(\.id) == [fixture.page.id])
}
