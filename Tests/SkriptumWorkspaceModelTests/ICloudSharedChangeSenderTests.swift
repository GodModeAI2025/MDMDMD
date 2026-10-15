import Foundation
import CloudKit
import Testing
import SkriptumCore
@testable import SkriptumWorkspaceModel

@MainActor private final class SharedSenderDatabase: ICloudSharedRecordDatabase {
    var records: [CKRecord.ID: CKRecord] = [:]
    var saved: [CKRecord] = []
    var replacement: [CKRecord.ID: CKRecord] = [:]
    var savedPayloads: [CKRecord.ID: Data] = [:]
    var assetDirectory: URL?
    var transformReceipt: ((CKRecord) -> Void)?
    var failAfterSave: CKRecord.ID?
    func record(for id: CKRecord.ID) async throws -> CKRecord {
        guard let value = replacement[id] ?? records[id] else { throw CKError(.unknownItem) }
        return value.copy() as! CKRecord
    }
    func save(_ record: CKRecord) async throws -> CKRecord {
        let copy = record.copy() as! CKRecord
        if let url = (record["payload"] as? CKAsset)?.fileURL {
            let bytes = try Data(contentsOf: url); savedPayloads[record.recordID] = bytes
            if let assetDirectory {
                try FileManager.default.createDirectory(at: assetDirectory, withIntermediateDirectories: true)
                let persisted = assetDirectory.appendingPathComponent(UUID().uuidString)
                try bytes.write(to: persisted)
                copy["payload"] = CKAsset(fileURL: persisted)
            }
        }
        records[copy.recordID] = copy; saved.append(copy)
        if failAfterSave == record.recordID {
            failAfterSave = nil
            throw CKError(.networkFailure)
        }
        let receipt = copy.copy() as! CKRecord
        transformReceipt?(receipt)
        return receipt
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

@Test(arguments: [false, true], ["valid", "cycle", "outside", "wrong-zone", "wrong-id", "wrong-library", "tombstone", "unknown-parent"]) @MainActor
func sharedSenderEditsNestedPageWithinPageOrSpaceShare(spaceShare: Bool, scenario: String) async throws {
    let directory = URL(fileURLWithPath: "/private/tmp/ScriptumNestedSender-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let space = Space(title: "Manuskript")
    let parent = Page(spaceID: space.id, title: "Kapitel", markdown: "Original")
    var child = Page(spaceID: space.id, title: "Abschnitt", markdown: "Alt\r\n👩🏽‍💻")
    var middle = Page(spaceID: space.id, title: "Unterkapitel", markdown: "Mitte")
    middle.parentID = parent.id
    child.parentID = middle.id
    var snapshot = LibrarySnapshot(); snapshot.pages = [parent, middle, child]
    if spaceShare { snapshot.spaces = [space] }
    let identity = try ICloudSharedStoreIdentity(accountID: "participant", ownerID: "owner", zoneName: "zone", shareName: "share",
        root: .init(kind: spaceShare ? .space : .page, id: spaceShare ? space.id : parent.id))
    let store = try ICloudSharedDocumentStore(directory: directory, identity: identity)
    _ = try store.replace(snapshot, expectedRevision: nil)
    let comment = try store.addComment(pageID: child.id, body: "Kommentar zur Unterseite", permission: .readWrite)
    let revision = try store.editMarkdown(pageID: child.id, expectedPageRevision: child.revision,
        markdown: "Neu\r\ne\u{301} 👩🏽‍💻", permission: .readWrite)
    let zone = CKRecordZone.ID(zoneName: identity.zoneName, ownerName: identity.ownerID)
    let libraryID = UUID().uuidString.lowercased()
    func record(kind: String, id: UUID, revision: UUID, parentID: CKRecord.ID?) -> CKRecord {
        let value = CKRecord(recordType: "ScriptumItemV1", recordID: .init(recordName: kind + ":" + id.uuidString.lowercased(), zoneID: zone))
        value["libraryID"] = libraryID as CKRecordValue
        value["kind"] = kind as CKRecordValue; value["uuid"] = id.uuidString.lowercased() as CKRecordValue
        value["operation"] = "upsert" as CKRecordValue; value["revision"] = revision.uuidString.lowercased() as CKRecordValue
        value.parent = parentID.map { CKRecord.Reference(recordID: $0, action: .none) }
        return value
    }
    let root = record(kind: identity.root.kind.rawValue, id: identity.root.id, revision: UUID(), parentID: nil)
    let parentRecord = spaceShare ? record(kind: "page", id: parent.id, revision: parent.revision, parentID: root.recordID) : root
    let middleRecord = record(kind: "page", id: middle.id, revision: middle.revision, parentID: parentRecord.recordID)
    let childRecord = record(kind: "page", id: child.id, revision: child.revision, parentID: middleRecord.recordID)
    let share = CKShare(rootRecord: root, shareID: .init(recordName: identity.shareName, zoneID: zone))
    let grant = ICloudShareParticipantTransport.Accepted(share: share, root: root, canWrite: true,
        participantRecordID: .init(recordName: identity.accountID, zoneID: zone))
    let database = SharedSenderDatabase()
    database.assetDirectory = directory.appendingPathComponent("ServerAssets")
    for value in [root, parentRecord, middleRecord, childRecord] { database.records[value.recordID] = value }
    switch scenario {
    case "cycle": middleRecord.parent = .init(recordID: childRecord.recordID, action: .none)
    case "outside": middleRecord.parent = nil
    case "wrong-zone": database.replacement[middleRecord.recordID] = CKRecord(recordType: "ScriptumItemV1",
        recordID: .init(recordName: middleRecord.recordID.recordName, zoneID: .init(zoneName: "other", ownerName: identity.ownerID)))
    case "wrong-id": database.replacement[middleRecord.recordID] = parentRecord
    case "wrong-library": middleRecord["libraryID"] = UUID().uuidString.lowercased() as CKRecordValue
    case "tombstone": middleRecord["operation"] = "tombstone" as CKRecordValue
    case "unknown-parent": database.records.removeValue(forKey: middleRecord.recordID)
    default: break
    }
    let pending = try store.pendingChanges()
    if scenario != "valid" {
        await #expect(throws: (any Error).self) {
            try await ICloudSharedChangeSender.send(database: database, store: store,
                stagingDirectory: directory.appendingPathComponent("Assets")) { grant }
        }
        #expect(database.saved.isEmpty)
        #expect(try store.pendingChanges() == pending)
        #expect(try store.context(permission: .readOnly)?.page(child.id)?.markdown == "Neu\r\ne\u{301} 👩🏽‍💻")
        return
    }
    try await ICloudSharedChangeSender.send(database: database, store: store, stagingDirectory: directory.appendingPathComponent("Assets")) { grant }
    #expect(try store.pendingChanges().isEmpty)
    let saved = try #require(database.records[childRecord.recordID])
    #expect(saved["revision"] as? String == revision.uuidString.lowercased())
    #expect(saved.parent?.recordID == middleRecord.recordID)
    let sent = try ICloudPagePayload.decode(#require(database.savedPayloads[saved.recordID]), expectedPageID: child.id, expectedRevision: revision)
    #expect(sent.page.markdown.utf8.elementsEqual("Neu\r\ne\u{301} 👩🏽‍💻".utf8))
    #expect(database.saved.count == 3)
    let savedComment = try #require(database.saved.first { $0["kind"] as? String == "comment" })
    #expect(savedComment["uuid"] as? String == comment.id.uuidString.lowercased())
    #expect(savedComment.parent?.recordID == childRecord.recordID)
    let history = try #require(database.saved.first { $0["kind"] as? String == "revision" })
    #expect(history.parent?.recordID == childRecord.recordID)
    let original = try ICloudMetadataPayload<Revision>.decode(#require(database.savedPayloads[history.recordID]))
    #expect(original.value.page.markdown.utf8.elementsEqual(child.markdown.utf8))
    let reply = try store.replyToComment(comment.id, body: "Antwort e\u{301} 👩🏽‍💻", permission: .readWrite)
    try store.setCommentResolved(reply.id, resolved: true, permission: .readWrite)
    try await ICloudSharedChangeSender.send(database: database, store: store,
        stagingDirectory: directory.appendingPathComponent("Assets")) { grant }
    #expect(try store.pendingChanges().isEmpty)
    let replyID = CKRecord.ID(recordName: "comment:" + reply.id.uuidString.lowercased(), zoneID: zone)
    let sentReply = try ICloudMetadataPayload<SkriptumCore.Comment>.decode(#require(database.savedPayloads[replyID])).value
    #expect(sentReply.parentCommentID == comment.id)
    #expect(sentReply.body.utf8.elementsEqual(reply.body.utf8))
    #expect(database.records[replyID]?.parent?.recordID == childRecord.recordID)
    let commentID = savedComment.recordID
    let resolved = try ICloudMetadataPayload<SkriptumCore.Comment>.decode(#require(database.savedPayloads[commentID])).value
    #expect(resolved.resolvedAt != nil)
    try store.setCommentResolved(comment.id, resolved: false, permission: .readWrite)
    try await ICloudSharedChangeSender.send(database: database, store: store,
        stagingDirectory: directory.appendingPathComponent("Assets")) { grant }
    #expect(try store.pendingChanges().isEmpty)
    let reopened = try ICloudMetadataPayload<SkriptumCore.Comment>.decode(#require(database.savedPayloads[commentID])).value
    #expect(reopened.resolvedAt == nil)
    #expect(database.records[commentID]?.parent?.recordID == childRecord.recordID)
    #expect(database.saved.count == 6)
}


@Test(arguments: ["retry-exact", "retry-missing", "retry-different", "receipt-parent"]) @MainActor
func sharedSenderKeepsPendingUntilExactPayloadAndParentAreConfirmed(scenario: String) async throws {
    let directory = URL(fileURLWithPath: "/private/tmp/ScriptumSenderReceipt-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let page = Page(spaceID: UUID(), title: "Shared", markdown: "Original")
    var snapshot = LibrarySnapshot(); snapshot.pages = [page]
    let identity = try ICloudSharedStoreIdentity(accountID: "participant", ownerID: "owner", zoneName: "zone", shareName: "share", root: .init(kind: .page, id: page.id))
    let store = try ICloudSharedDocumentStore(directory: directory, identity: identity)
    _ = try store.replace(snapshot, expectedRevision: nil)
    _ = try store.editMarkdown(pageID: page.id, expectedPageRevision: page.revision,
        markdown: "Bleibt lokal\r\ne\u{301} 👩🏽‍💻", permission: .readWrite)
    let pending = try store.pendingChanges()
    let pageChange = try #require(pending.first { $0.recordID.kind == .page })
    let zone = CKRecordZone.ID(zoneName: identity.zoneName, ownerName: identity.ownerID)
    let root = CKRecord(recordType: "ScriptumItemV1", recordID: .init(recordName: "page:" + page.id.uuidString.lowercased(), zoneID: zone))
    let libraryID = UUID().uuidString.lowercased()
    root["libraryID"] = libraryID as CKRecordValue
    root["revision"] = page.revision.uuidString.lowercased() as CKRecordValue
    let share = CKShare(rootRecord: root, shareID: .init(recordName: identity.shareName, zoneID: zone))
    let grant = ICloudShareParticipantTransport.Accepted(share: share, root: root, canWrite: true,
        participantRecordID: .init(recordName: identity.accountID, zoneID: zone))
    let database = SharedSenderDatabase(); database.records[root.recordID] = root
    database.assetDirectory = directory.appendingPathComponent("ServerAssets")
    if scenario.hasPrefix("retry-") {
        database.failAfterSave = root.recordID
        await #expect(throws: CKError.self) {
            try await ICloudSharedChangeSender.send(database: database, store: store,
                stagingDirectory: directory.appendingPathComponent("Assets")) { grant }
        }
        let server = try #require(database.records[root.recordID])
        if scenario == "retry-missing" { server["payload"] = nil }
        if scenario == "retry-different" {
            let corrupt = directory.appendingPathComponent("Different")
            try Data("Andere Bytes".utf8).write(to: corrupt)
            server["payload"] = CKAsset(fileURL: corrupt)
        }
    } else {
        database.transformReceipt = { receipt in
            guard receipt.recordID == root.recordID else { return }
            receipt.parent = .init(recordID: .init(recordName: "page:" + UUID().uuidString.lowercased(), zoneID: zone),
                action: .none)
        }
    }
    let before = database.saved.count
    if scenario == "retry-exact" {
        try await ICloudSharedChangeSender.send(database: database, store: store,
            stagingDirectory: directory.appendingPathComponent("Assets")) { grant }
        #expect(try store.pendingChanges().isEmpty)
        #expect(database.saved.filter { $0.recordID == root.recordID }.count == 1)
    } else {
        await #expect(throws: (any Error).self) {
            try await ICloudSharedChangeSender.send(database: database, store: store,
                stagingDirectory: directory.appendingPathComponent("Assets")) { grant }
        }
        #expect(try store.pendingChanges().first { $0.recordID.kind == .page } == pageChange)
        if scenario.hasPrefix("retry-") { #expect(database.saved.count == before) }
    }
    #expect(try store.context(permission: .readOnly)?.page(page.id)?.markdown.utf8.elementsEqual("Bleibt lokal\r\ne\u{301} 👩🏽‍💻".utf8) == true)
}
