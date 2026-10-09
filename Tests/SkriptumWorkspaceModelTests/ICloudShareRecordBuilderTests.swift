import Foundation
import CloudKit
import Testing
import SkriptumCore
@testable import SkriptumWorkspaceModel

@Test @MainActor func nativeSharePreparationKeepsOriginalRecordsAndPrivatePagesUnshared() throws {
    var snapshot = LibrarySnapshot(); let space = Space(title: "Writing")
    snapshot.spaces = [space]
    var page = Page(spaceID: space.id, title: "Shared")
    let other = Page(spaceID: space.id, title: "Private")
    let image = MediaAttachment(id: UUID(), filename: "image.png", mediaType: "image/png", byteCount: 100, sha256: String(repeating: "a", count: 64))
    page.attachments = [image]; snapshot.pages = [page, other]
    let plan = try ICloudShareRecordPlan(scope: .page(page.id), snapshot: snapshot)
    let libraryID = UUID(), zone = CKRecordZone.ID(zoneName: "Owned", ownerName: CKCurrentUserDefaultName)
    func record(_ kind: String, _ id: UUID) -> CKRecord {
        let record = CKRecord(recordType: "ScriptumItemV1", recordID: .init(recordName: kind + ":" + id.uuidString.lowercased(), zoneID: zone))
        record["libraryID"] = libraryID.uuidString.lowercased() as CKRecordValue
        record["kind"] = kind as CKRecordValue; record["uuid"] = id.uuidString.lowercased() as CKRecordValue
        record["operation"] = "upsert" as CKRecordValue
        return record
    }
    let source = record("page", page.id), privateRecord = record("page", other.id), asset = record("image", image.id)
    let prepared = try ICloudShareRecordBuilder.prepare(plan: plan, zoneID: zone, libraryID: libraryID,
        zoneRecords: [source, privateRecord, asset], title: page.title)
    #expect(prepared.share.publicPermission == .none)
    #expect(prepared.records.count == 2)
    #expect(!prepared.records.contains { $0.recordID == privateRecord.recordID })
    #expect(source.parent == nil && source.share == nil)
    #expect(privateRecord.parent == nil && privateRecord.share == nil)
    #expect(asset.parent == nil && asset.share == nil)
    let alias = try #require(prepared.records.first { $0.recordType == "ScriptumSharedImageV1" })
    #expect(alias.parent?.recordID == source.recordID)
    #expect(alias.recordID != asset.recordID)
    #expect(alias["sourceRecordName"] as? String == asset.recordID.recordName)
    privateRecord.parent = CKRecord.Reference(recordID: source.recordID, action: .none)
    #expect(throws: ICloudSharePreparationError.overlappingHierarchy) {
        try ICloudShareRecordBuilder.prepare(plan: plan, zoneID: zone, libraryID: libraryID,
            zoneRecords: [source, privateRecord, asset], title: page.title)
    }
}
