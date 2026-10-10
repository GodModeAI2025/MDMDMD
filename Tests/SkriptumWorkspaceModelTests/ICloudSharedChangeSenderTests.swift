import Foundation
import CloudKit
import Testing
import SkriptumCore
@testable import SkriptumWorkspaceModel

@MainActor private final class SharedSenderDatabase: ICloudSharedRecordDatabase {
    var records: [CKRecord.ID: CKRecord] = [:]
    var saved: [CKRecord] = []
    func record(for id: CKRecord.ID) async throws -> CKRecord {
        guard let value = records[id] else { throw CKError(.unknownItem) }
        return value.copy() as! CKRecord
    }
    func save(_ record: CKRecord) async throws -> CKRecord {
        let copy = record.copy() as! CKRecord
        records[copy.recordID] = copy; saved.append(copy)
        return copy
    }
}

@Test @MainActor func sharedSenderConfirmsExactPageAndPreservesDivergentLocalQueue() async throws {
    let directory = URL(fileURLWithPath: "/private/tmp/ScriptumSharedSender-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let page = Page(spaceID: UUID(), title: "Shared", markdown: "Original")
    var snapshot = LibrarySnapshot(); snapshot.pages = [page]
    let identity = try ICloudSharedStoreIdentity(accountID: "participant", ownerID: "owner", zoneName: "zone", shareName: "share", root: .init(kind: .page, id: page.id))
    let store = try ICloudSharedDocumentStore(directory: directory, identity: identity)
    _ = try store.replace(snapshot, expectedRevision: nil)
    let first = try store.editMarkdown(pageID: page.id, expectedPageRevision: page.revision, markdown: "First", permission: .readWrite)
    let zone = CKRecordZone.ID(zoneName: identity.zoneName, ownerName: identity.ownerID)
    let root = CKRecord(recordType: "ScriptumItemV1", recordID: .init(recordName: "page:" + page.id.uuidString.lowercased(), zoneID: zone))
    let libraryID = UUID().uuidString.lowercased()
    root["libraryID"] = libraryID as CKRecordValue
    root["revision"] = page.revision.uuidString.lowercased() as CKRecordValue
    let share = CKShare(rootRecord: root, shareID: .init(recordName: identity.shareName, zoneID: zone))
    let grant = ICloudShareParticipantTransport.Accepted(share: share, root: root, canWrite: true, participantRecordID: .init(recordName: identity.accountID, zoneID: zone))
    let database = SharedSenderDatabase(); database.records[root.recordID] = root
    try await ICloudSharedChangeSender.send(database: database, store: store, stagingDirectory: directory.appendingPathComponent("Assets")) { grant }
    #expect(try store.pendingChanges().isEmpty)
    #expect(database.records[root.recordID]?["revision"] as? String == first.uuidString.lowercased())
    #expect(database.saved.count == 2)
    _ = try store.editMarkdown(pageID: page.id, expectedPageRevision: first, markdown: "Local preserved", permission: .readWrite)
    database.records[root.recordID]?["revision"] = UUID().uuidString.lowercased() as CKRecordValue
    let pending = try store.pendingChanges().filter { $0.recordID.kind == .page }
    do {
        try await ICloudSharedChangeSender.send(database: database, store: store, stagingDirectory: directory.appendingPathComponent("Assets")) { grant }
        Issue.record("Divergent server revision overwritten")
    } catch { #expect(error as? ICloudSharedSendError == .conflict) }
    #expect(try store.pendingChanges().filter { $0.recordID.kind == .page } == pending)
    #expect(try store.context(permission: .readOnly)?.canonical.pages.first?.markdown == "Local preserved")
}
