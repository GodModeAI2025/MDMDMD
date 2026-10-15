import Foundation
import CloudKit
import CryptoKit
import Testing
import SkriptumCore
@testable import SkriptumWorkspaceModel

@MainActor private struct ShareExpansionFixture {
    let directory = URL(fileURLWithPath: "/private/tmp/ScriptumShareExpansion-" + UUID().uuidString)
    let libraryID = UUID()
    let zone = CKRecordZone.ID(zoneName: "OwnerLibrary", ownerName: "owner")
    let space = Space(title: "Shared manuscript"), privateSpace = Space(title: "Private")
    let rootPage: Page, middle: Page, child: Page, privatePage: Page
    let attachment: MediaAttachment
    let imageBytes: Data
    let comment: SkriptumCore.Comment
    let spaceRoot: Bool
    init(spaceRoot: Bool) throws {
        self.spaceRoot = spaceRoot
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        imageBytes = try #require(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII="))
        attachment = MediaAttachment(filename: "e\u{301}.png", mediaType: "image/png", byteCount: imageBytes.count,
            sha256: SHA256.hash(data: imageBytes).map { String(format: "%02x", $0) }.joined())
        rootPage = Page(spaceID: space.id, title: "Root", markdown: "Root\r\n👩🏽‍💻")
        var middle = Page(spaceID: space.id, title: "Existing", markdown: "Existing")
        middle.parentID = rootPage.id; self.middle = middle
        var child = Page(spaceID: space.id, title: "New child", markdown: "New e\u{301}\r\n🦊")
        child.parentID = middle.id; child.attachments = [attachment]; self.child = child
        var privatePage = Page(spaceID: privateSpace.id, title: "Unrelated private page", markdown: "Private")
        privatePage.attachments = [attachment]; self.privatePage = privatePage
        comment = SkriptumCore.Comment(pageID: child.id, blockID: nil, body: "New comment", author: "Owner")
    }
    var scope: ICloudShareScope { spaceRoot ? .space(space.id) : .page(rootPage.id) }
    var snapshot: LibrarySnapshot {
        var value = LibrarySnapshot(); value.spaces = [space, privateSpace]
        value.pages = [rootPage, middle, child, privatePage]; value.comments = [comment]; return value
    }
    func id(_ kind: String, _ id: UUID) -> CKRecord.ID { .init(recordName: kind + ":" + id.uuidString.lowercased(), zoneID: zone) }
    var rootID: CKRecord.ID { spaceRoot ? id("space", space.id) : id("page", rootPage.id) }
    var shareID: CKRecord.ID { .init(recordName: "native-existing-share", zoneID: zone) }
    func install(_ bytes: Data, revision: UUID, record: CKRecord) throws {
        let path = directory.appendingPathComponent(UUID().uuidString)
        try bytes.write(to: path)
        record["payload"] = CKAsset(fileURL: path)
        record["revision"] = revision.uuidString.lowercased() as CKRecordValue
        record["sha256"] = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined() as CKRecordValue
    }
    func source(_ kind: String, _ uuid: UUID) -> CKRecord {
        let record = CKRecord(recordType: "ScriptumItemV1", recordID: id(kind, uuid))
        record["libraryID"] = libraryID.uuidString.lowercased() as CKRecordValue
        record["kind"] = kind as CKRecordValue; record["uuid"] = uuid.uuidString.lowercased() as CKRecordValue
        record["operation"] = "upsert" as CKRecordValue; return record
    }
    func records() throws -> [CKRecord.ID: CKRecord] {
        var values: [CKRecord] = []
        for page in snapshot.pages {
            let record = source("page", page.id)
            try install(ICloudPagePayload(page: page, baseRevision: nil).encoded(), revision: page.revision, record: record)
            if page.id == middle.id { record.parent = .init(recordID: rootID, action: .none) }
            if spaceRoot && page.id == rootPage.id { record.parent = .init(recordID: rootID, action: .none) }
            values.append(record)
        }
        for space in snapshot.spaces {
            let record = source("space", space.id), payload = try ICloudMetadataPayload(value: space, baseDigest: nil)
            try install(payload.encoded(), revision: payload.revisionID(), record: record); values.append(record)
        }
        let image = source("image", attachment.id), revision = UUID()
        try install(ICloudImagePayload(attachment: attachment, revisionID: revision, data: imageBytes).encoded(), revision: revision, record: image)
        values.append(image)
        let commentRecord = source("comment", comment.id), payload = try ICloudMetadataPayload(value: comment, baseDigest: nil)
        try install(payload.encoded(), revision: payload.revisionID(), record: commentRecord); values.append(commentRecord)
        return Dictionary(uniqueKeysWithValues: values.map { ($0.recordID, $0) })
    }
    func expansion(_ records: [CKRecord.ID: CKRecord], snapshot: LibrarySnapshot? = nil) throws -> ICloudShareRecordBuilder.Expansion? {
        let plan = try ICloudShareRecordPlan(scope: scope, snapshot: snapshot ?? self.snapshot)
        return try ICloudShareRecordBuilder.expansion(plan: plan, snapshot: snapshot ?? self.snapshot, zoneID: zone, libraryID: libraryID,
            zoneRecords: Array(records.values), shareID: shareID, rootShareID: shareID)
    }
}

@Test(arguments: [false, true]) @MainActor
func ownerShareExpansionReceivesNewPageCommentAndIsolatedImageThenRemovesMovedContent(spaceRoot: Bool) async throws {
    let fixture = try ShareExpansionFixture(spaceRoot: spaceRoot)
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    var records = try fixture.records()
    let before = records
    let expanded = try #require(try fixture.expansion(records))
    #expect(expanded.detached.isEmpty && expanded.deleting.isEmpty)
    let alias = try #require(expanded.records.first { $0.recordType == "ScriptumSharedImageV1" })
    #expect(alias.parent?.recordID == fixture.rootID)
    #expect(alias.recordID != fixture.id("image", fixture.attachment.id))
    #expect(alias["payload"] as? CKAsset !== before[fixture.id("image", fixture.attachment.id)]?["payload"] as? CKAsset)
    #expect(before[fixture.id("image", fixture.attachment.id)]?.parent == nil)
    #expect(before[fixture.id("page", fixture.privatePage.id)]?.parent == nil)
    #expect(before[fixture.id("page", fixture.child.id)]?.parent == nil)
    for record in expanded.records { records[record.recordID] = record }
    #expect(records[fixture.id("page", fixture.child.id)]?.parent?.recordID == fixture.id("page", fixture.middle.id))
    #expect(records[fixture.id("comment", fixture.comment.id)]?.parent?.recordID == fixture.id("page", fixture.child.id))
    #expect(try fixture.expansion(records) == nil)
    let plan = try ICloudShareRecordPlan(scope: fixture.scope, snapshot: fixture.snapshot)
    #expect(try ICloudShareRecordBuilder.confirmedMetadata(plan: plan, records: expanded.records, snapshot: fixture.snapshot).count == plan.entries.count)
    let identity = try ICloudSharedStoreIdentity(accountID: "participant", ownerID: fixture.zone.ownerName,
        zoneName: fixture.zone.zoneName, shareName: fixture.shareID.recordName,
        root: .init(kind: spaceRoot ? .space : .page, id: spaceRoot ? fixture.space.id : fixture.rootPage.id))
    let store = try ICloudSharedDocumentStore(directory: fixture.directory.appendingPathComponent("Participant"), identity: identity)
    let root = try #require(records[fixture.rootID]), share = CKShare(rootRecord: root, shareID: fixture.shareID)
    let grant = ICloudShareParticipantTransport.Accepted(share: share, root: root, canWrite: true,
        participantRecordID: .init(recordName: "participant", zoneID: fixture.zone))
    let media = fixture.directory.appendingPathComponent("ReceivedImages")
    let context = try await ICloudSharedSnapshotReceiver.receive(records: records, accepted: grant, store: store,
        expectedRevision: nil, imageDirectory: media, record: { try #require(records[$0]) }, revalidate: { grant })
    #expect(context.canonical.pages.contains { $0.id == fixture.child.id && $0.markdown == fixture.child.markdown })
    #expect(!context.canonical.pages.contains { $0.id == fixture.privatePage.id })
    #expect(context.canonical.comments.first?.body == fixture.comment.body)
    #expect(try LibraryStore(directory: media).attachmentData(fixture.attachment) == fixture.imageBytes)

    // The ordinary private sync has uploaded a move, retaining native ancestry
    // until this membership reconciliation removes the old grant.
    var moved = fixture.snapshot
    let index = try #require(moved.pages.firstIndex { $0.id == fixture.child.id })
    moved.pages[index].spaceID = fixture.privateSpace.id; moved.pages[index].parentID = nil
    moved.pages[index].revision = UUID()
    let movedRecord = try #require(records[fixture.id("page", fixture.child.id)])
    try fixture.install(ICloudPagePayload(page: moved.pages[index], baseRevision: nil).encoded(), revision: moved.pages[index].revision, record: movedRecord)
    let removal = try #require(try fixture.expansion(records, snapshot: moved))
    #expect(Set(removal.detached.map(\.recordID)) == [fixture.id("page", fixture.child.id), fixture.id("comment", fixture.comment.id)])
    #expect(removal.deleting == [alias.recordID])
    for record in removal.records + removal.detached { records[record.recordID] = record }
    for id in removal.deleting { records.removeValue(forKey: id) }
    let after = try await ICloudSharedSnapshotReceiver.receive(records: records, accepted: grant, store: store,
        expectedRevision: store.checkpointRevision(), imageDirectory: media, record: { try #require(records[$0]) }, revalidate: { grant })
    #expect(!after.canonical.pages.contains { $0.id == fixture.child.id })
    #expect(after.canonical.comments.isEmpty)
    #expect(try fixture.expansion(records, snapshot: moved) == nil)
    #expect(records[fixture.id("image", fixture.attachment.id)]?.parent == nil)
    #expect(records[fixture.id("page", fixture.privatePage.id)]?.parent == nil)
}

@Test(arguments: ["unplannedChild", "foreignRecord", "wrongLibrary", "wrongKind", "tombstone", "cycle", "parentedImage"])
@MainActor func ownerShareExpansionRejectsUnprovenOrOverlappingGraph(mismatch: String) throws {
    let fixture = try ShareExpansionFixture(spaceRoot: false)
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    var records = try fixture.records()
    let child = try #require(records[fixture.id("page", fixture.child.id)])
    switch mismatch {
    case "unplannedChild":
        let privateRecord = try #require(records[fixture.id("page", fixture.privatePage.id)])
        privateRecord.parent = .init(recordID: child.recordID, action: .none)
    case "foreignRecord":
        let foreign = CKRecord(recordType: "ScriptumItemV1", recordID: .init(recordName: "foreign", zoneID: .init(zoneName: "foreign", ownerName: "owner")))
        records[foreign.recordID] = foreign
    case "wrongLibrary": child["libraryID"] = UUID().uuidString.lowercased() as CKRecordValue
    case "wrongKind": child["kind"] = "image" as CKRecordValue
    case "tombstone": child["operation"] = "tombstone" as CKRecordValue
    case "cycle":
        child.parent = .init(recordID: fixture.id("page", fixture.middle.id), action: .none)
        records[fixture.id("page", fixture.middle.id)]?.parent = .init(recordID: child.recordID, action: .none)
    default: records[fixture.id("image", fixture.attachment.id)]?.parent = .init(recordID: fixture.rootID, action: .none)
    }
    #expect(throws: (any Error).self) { try fixture.expansion(records) }
    #expect(child["payload"] as? CKAsset != nil)
}

@Test @MainActor func ownerShareExpansionReceiptPersistsMembershipWithoutChangingCreationReceipt() throws {
    let fixture = try ShareExpansionFixture(spaceRoot: false)
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let scope = try ICloudSyncScope(accountID: "owner", libraryID: fixture.libraryID)
    let directory = fixture.directory.appendingPathComponent("Receipts")
    let receipts = try ICloudOwnerShareReceipts(directory: directory, scope: scope)
    var original = fixture.snapshot; original.pages.removeAll { $0.id == fixture.child.id }; original.comments = []
    let initial = try ICloudShareRecordPlan(scope: fixture.scope, snapshot: original)
    let changed = try ICloudShareRecordPlan(scope: fixture.scope, snapshot: fixture.snapshot)
    let pending = try receipts.begin(plan: initial, shareName: fixture.shareID.recordName)
    #expect(try receipts.confirmedOperations().isEmpty)
    #expect(throws: ICloudShareOwnerError.self) { try receipts.confirmExpansion(changed, operation: pending) }
    try receipts.confirm(pending)
    let operation = try #require(receipts.confirmedOperations().first)
    #expect(try receipts.needsExpansion(initial, operation: operation))
    #expect(try receipts.needsExpansion(changed, operation: operation))
    try receipts.confirmExpansion(changed, operation: operation)
    let restarted = try ICloudOwnerShareReceipts(directory: directory, scope: scope)
    let updated = try #require(restarted.confirmedOperations().first)
    #expect(updated.manifestDigest == operation.manifestDigest)
    #expect(!(try restarted.needsExpansion(changed, operation: updated)))
    var withReply = fixture.snapshot
    withReply.comments.append(SkriptumCore.Comment(pageID: fixture.child.id, blockID: nil, body: "Routine reply", author: "Owner"))
    let commentOnly = try ICloudShareRecordPlan(scope: fixture.scope, snapshot: withReply)
    #expect(!(try restarted.needsExpansion(commentOnly, operation: updated)))
    #expect(try restarted.needsExpansion(initial, operation: updated))
    #expect(throws: ICloudShareOwnerError.self) { try receipts.confirmExpansion(initial, operation: operation) }
}

@Test @MainActor func ownerShareExpansionFenceDetectsCanonicallyEqualUnicodeCommit() throws {
    let directory = URL(fileURLWithPath: "/private/tmp/ScriptumExpansionFence-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try LibraryStore(directory: directory)
    let space = try store.createSpace(title: "e\u{301}")
    let snapshot = store.snapshot, fence = store.durableRevision
    try store.renameSpace(space.id, title: "é")
    #expect(store.snapshot == snapshot)
    #expect(store.durableRevision != fence)
    let committed = store.durableRevision
    #expect(throws: LibraryError.self) { try store.renameSpace(UUID(), title: "Missing") }
    #expect(store.durableRevision == committed)
    try store.renameSpace(space.id, title: "é")
    #expect(store.durableRevision == committed)
}

@Test(arguments: [false, true]) @MainActor
func ownerShareExpansionReparentsRetainedChildBeforeDetachingFormerParent(spaceRoot: Bool) throws {
    let fixture = try ShareExpansionFixture(spaceRoot: spaceRoot)
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    var records = try fixture.records()
    let initial = try #require(try fixture.expansion(records))
    for record in initial.records { records[record.recordID] = record }
    var snapshot = fixture.snapshot
    let middle = try #require(snapshot.pages.firstIndex { $0.id == fixture.middle.id })
    snapshot.pages[middle].spaceID = fixture.privateSpace.id; snapshot.pages[middle].parentID = nil
    snapshot.pages[middle].revision = UUID()
    let child = try #require(snapshot.pages.firstIndex { $0.id == fixture.child.id })
    snapshot.pages[child].parentID = fixture.rootPage.id; snapshot.pages[child].revision = UUID()
    for index in [middle, child] {
        let page = snapshot.pages[index], record = try #require(records[fixture.id("page", page.id)])
        try fixture.install(ICloudPagePayload(page: page, baseRevision: nil).encoded(), revision: page.revision, record: record)
    }
    let change = try #require(try fixture.expansion(records, snapshot: snapshot))
    #expect(change.detached.map(\.recordID) == [fixture.id("page", fixture.middle.id)])
    #expect(change.deleting.isEmpty)
    #expect(change.records.first { $0.recordID == fixture.id("page", fixture.child.id) }?.parent?.recordID == fixture.id("page", fixture.rootPage.id))
    let plan = try ICloudShareRecordPlan(scope: fixture.scope, snapshot: snapshot)
    #expect(try ICloudShareRecordBuilder.confirmedMetadata(plan: plan, records: change.records, snapshot: snapshot).count == plan.entries.count)
    for record in change.records + change.detached { records[record.recordID] = record }
    #expect(try fixture.expansion(records, snapshot: snapshot) == nil)
}

@Test(arguments: ["page", "comment"]) @MainActor
func ownerShareExpansionNeverMistakesConcurrentRemoteAdditionForLocalRemoval(kind: String) throws {
    let fixture = try ShareExpansionFixture(spaceRoot: false)
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    var records = try fixture.records()
    let added = fixture.source(kind, UUID())
    added.parent = .init(recordID: fixture.rootID, action: .none)
    records[added.recordID] = added
    #expect(throws: ICloudShareOwnerError.changedManifest) { try fixture.expansion(records) }
    #expect(added.parent?.recordID == fixture.rootID)
}
