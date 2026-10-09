import Foundation
import CloudKit
import CryptoKit
import Testing
import SkriptumCore
@testable import SkriptumWorkspaceModel

@Test @MainActor func ownerShareRetryKeepsExactOperationAcrossRestartAndConfirmation() throws {
    let directory = URL(fileURLWithPath: "/private/tmp/ScriptumOwnerShareReceipt-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let scope = try ICloudSyncScope(accountID: "Owner", libraryID: UUID())
    let (snapshot, page) = ownerReceiptLibrary()
    let plan = try ICloudShareRecordPlan(scope: .page(page.id), snapshot: snapshot)
    let store = try ICloudOwnerShareReceipts(directory: directory, scope: scope)
    let operation = try store.begin(plan: plan, shareName: "cloudkit.share." + UUID().uuidString)
    #expect(!operation.confirmed)
    let restarted = try ICloudOwnerShareReceipts(directory: directory, scope: scope)
    #expect(try restarted.operation(for: plan) == operation)
    #expect(try restarted.begin(plan: plan, shareName: operation.shareName) == operation)
    #expect(throws: (any Error).self) { try restarted.begin(plan: plan, shareName: "different-share") }
    try restarted.confirm(operation)
    let persisted = try ICloudOwnerShareReceipts(directory: directory, scope: scope).operation(for: plan)
    let confirmed = try #require(persisted)
    #expect(confirmed.id == operation.id && confirmed.confirmed)
    var changed = snapshot
    changed.pages.append(Page(spaceID: page.spaceID, parentID: page.id, title: "Added later"))
    let changedPlan = try ICloudShareRecordPlan(scope: .page(page.id), snapshot: changed)
    #expect(throws: (any Error).self) { try restarted.operation(for: changedPlan) }
    #expect(try restarted.operation(for: plan) == confirmed)
}

@Test @MainActor func ownerShareReceiptIsAccountAndLibraryScopedAndCorruptionCannotBeReplaced() throws {
    let directory = URL(fileURLWithPath: "/private/tmp/ScriptumOwnerShareScopes-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let (snapshot, page) = ownerReceiptLibrary()
    let plan = try ICloudShareRecordPlan(scope: .page(page.id), snapshot: snapshot)
    let scope = try ICloudSyncScope(accountID: "e\u{301}", libraryID: UUID())
    let store = try ICloudOwnerShareReceipts(directory: directory, scope: scope)
    _ = try store.begin(plan: plan, shareName: "saved-share")
    #expect(try ICloudOwnerShareReceipts(directory: directory, scope: ICloudSyncScope(accountID: "é", libraryID: scope.libraryID)).operation(for: plan) == nil)
    #expect(try ICloudOwnerShareReceipts(directory: directory, scope: ICloudSyncScope(accountID: scope.accountID, libraryID: UUID())).operation(for: plan) == nil)
    let file = try #require(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first)
    let broken = Data("not-json".utf8)
    try broken.write(to: file)
    #expect(throws: (any Error).self) { try store.begin(plan: plan, shareName: "replacement") }
    #expect(try Data(contentsOf: file) == broken)
}

@Test @MainActor func ownerSharePreparationReusesPersistedIDAndRecoveryRejectsExtraDescendants() throws {
    let (snapshot, page) = ownerReceiptLibrary()
    let plan = try ICloudShareRecordPlan(scope: .page(page.id), snapshot: snapshot)
    let library = UUID(), zone = CKRecordZone.ID(zoneName: "Owner", ownerName: CKCurrentUserDefaultName)
    let source = ownerReceiptRecord(page: page, library: library, zone: zone)
    let shareID = CKRecord.ID(recordName: "cloudkit.share." + UUID().uuidString, zoneID: zone)
    let prepared = try ICloudShareRecordBuilder.prepare(plan: plan, zoneID: zone, libraryID: library,
        zoneRecords: [source], title: page.title, shareID: shareID)
    #expect(prepared.share.recordID == shareID && prepared.share.publicPermission == .none)
    #expect(source.parent == nil && source.share == nil)
    try ICloudShareRecordBuilder.validateSavedHierarchy(plan: plan, zoneID: zone, libraryID: library,
        zoneRecords: prepared.records, shareID: shareID, rootShareID: shareID)
    #expect(throws: (any Error).self) {
        try ICloudShareRecordBuilder.validateSavedHierarchy(plan: plan, zoneID: zone, libraryID: library,
            zoneRecords: prepared.records, shareID: shareID, rootShareID: nil)
    }
    let extra = ownerReceiptRecord(page: Page(spaceID: page.spaceID, title: "Private"), library: library, zone: zone)
    extra.parent = .init(recordID: source.recordID, action: .none)
    #expect(throws: (any Error).self) {
        try ICloudShareRecordBuilder.validateSavedHierarchy(plan: plan, zoneID: zone, libraryID: library,
            zoneRecords: prepared.records + [extra], shareID: shareID, rootShareID: shareID)
    }
    #expect(throws: (any Error).self) {
        try ICloudShareRecordBuilder.prepare(plan: plan, zoneID: zone, libraryID: library,
            zoneRecords: [source], title: page.title, shareID: .init(recordName: shareID.recordName, zoneID: .init(zoneName: "wrong", ownerName: CKCurrentUserDefaultName)))
    }
}

@MainActor private func ownerReceiptLibrary() -> (LibrarySnapshot, Page) {
    var snapshot = LibrarySnapshot(); let space = Space(title: "Writing")
    let page = Page(spaceID: space.id, title: "Shared")
    snapshot.spaces = [space]; snapshot.pages = [page]; return (snapshot, page)
}

@Test @MainActor func ownerShareMetadataCannotBlessDifferentContentOrAlteredPayload() throws {
    let directory = URL(fileURLWithPath: "/private/tmp/ScriptumOwnerMetadata-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let (snapshot, page) = ownerReceiptLibrary()
    let plan = try ICloudShareRecordPlan(scope: .page(page.id), snapshot: snapshot)
    let record = ownerReceiptRecord(page: page, library: UUID(), zone: .init(zoneName: "Owner", ownerName: CKCurrentUserDefaultName))
    let bytes = try ICloudPagePayload(page: page, baseRevision: nil).encoded()
    let asset = directory.appendingPathComponent("page.bin"); try bytes.write(to: asset)
    record["payload"] = CKAsset(fileURL: asset)
    record["sha256"] = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined() as CKRecordValue
    record["revision"] = page.revision.uuidString.lowercased() as CKRecordValue
    #expect(try ICloudShareRecordBuilder.confirmedMetadata(plan: plan, records: [record], snapshot: snapshot).count == 1)
    var changed = snapshot; changed.pages[0].title += " Changed"
    #expect(throws: (any Error).self) { try ICloudShareRecordBuilder.confirmedMetadata(plan: plan, records: [record], snapshot: changed) }
    record["sha256"] = String(repeating: "0", count: 64) as CKRecordValue
    #expect(throws: (any Error).self) { try ICloudShareRecordBuilder.confirmedMetadata(plan: plan, records: [record], snapshot: snapshot) }
    #expect(throws: (any Error).self) { try ICloudShareRecordBuilder.confirmedMetadata(plan: plan, records: [], snapshot: snapshot) }
}
private func ownerReceiptRecord(page: Page, library: UUID, zone: CKRecordZone.ID) -> CKRecord {
    let record = CKRecord(recordType: "ScriptumItemV1", recordID: .init(recordName: "page:" + page.id.uuidString.lowercased(), zoneID: zone))
    record["libraryID"] = library.uuidString.lowercased() as CKRecordValue
    record["kind"] = "page" as CKRecordValue; record["uuid"] = page.id.uuidString.lowercased() as CKRecordValue
    record["operation"] = "upsert" as CKRecordValue; return record
}
