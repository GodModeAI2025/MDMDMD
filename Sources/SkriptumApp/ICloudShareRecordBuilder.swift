import Foundation
import CloudKit
#if canImport(SkriptumCore)
import SkriptumCore
#endif

enum ICloudSharePreparationError: Error { case missingRecord, invalidRecord, overlappingHierarchy }

/// Native records for an owner-side hierarchy save. This prepares local objects;
/// it neither invites participants nor claims the server has saved the share.
@MainActor enum ICloudShareRecordBuilder {
    struct Prepared {
        let share: CKShare
        let records: [CKRecord]
    }
    static func prepare(plan: ICloudShareRecordPlan, zoneID: CKRecordZone.ID,
                        libraryID: UUID, zoneRecords: [CKRecord], title: String,
                        shareID: CKRecord.ID? = nil) throws -> Prepared {
        var sources: [String: CKRecord] = [:]
        for record in zoneRecords {
            guard record.recordID.zoneID == zoneID, sources[record.recordID.recordName] == nil else {
                throw ICloudSharePreparationError.invalidRecord
            }
            sources[record.recordID.recordName] = record
        }
        let selected = Set(plan.entries.filter { !$0.isImageAlias }.map(\.recordName))
        // A previously parented record can implicitly share descendants not in
        // this manifest. Initial preparation rejects that graph for explicit
        // reuse/reconciliation rather than silently expanding a new share.
        for record in zoneRecords where selected.contains(record.recordID.recordName) || record.parent.map({ selected.contains($0.recordID.recordName) }) == true {
            guard record.parent == nil, record.share == nil else { throw ICloudSharePreparationError.overlappingHierarchy }
        }
        var prepared: [CKRecord] = []
        for entry in plan.entries {
            let sourceName = entry.source.kind.rawValue + ":" + entry.source.id.uuidString.lowercased()
            guard let source = sources[sourceName] else { throw ICloudSharePreparationError.missingRecord }
            guard source.recordType == "ScriptumItemV1",
                  source["libraryID"] as? String == libraryID.uuidString.lowercased(),
                  source["kind"] as? String == entry.source.kind.rawValue,
                  source["uuid"] as? String == entry.source.id.uuidString.lowercased(),
                  source["operation"] as? String == "upsert" else { throw ICloudSharePreparationError.invalidRecord }
            let record: CKRecord
            if entry.isImageAlias {
                let id = CKRecord.ID(recordName: entry.recordName, zoneID: zoneID)
                guard sources[entry.recordName] == nil else { throw ICloudSharePreparationError.overlappingHierarchy }
                record = CKRecord(recordType: "ScriptumSharedImageV1", recordID: id)
                for key in ["libraryID", "kind", "uuid", "revision", "operation", "sha256", "payload"] { record[key] = source[key] }
                record["sourceRecordName"] = sourceName as CKRecordValue
            } else {
                guard let copy = source.copy() as? CKRecord else { throw ICloudSharePreparationError.invalidRecord }
                record = copy
            }
            record.parent = entry.parentRecordName.map { CKRecord.Reference(recordID: .init(recordName: $0, zoneID: zoneID), action: .none) }
            prepared.append(record)
        }
        guard let root = prepared.first(where: { $0.recordID.recordName == plan.rootRecordName }) else {
            throw ICloudSharePreparationError.missingRecord
        }
        if let shareID, shareID.zoneID != zoneID { throw ICloudSharePreparationError.invalidRecord }
        let share = shareID.map { CKShare(rootRecord: root, shareID: $0) } ?? CKShare(rootRecord: root)
        share.publicPermission = .none
        share[CKShare.SystemFieldKey.title] = title as CKRecordValue
        return Prepared(share: share, records: prepared)
    }

    static func validateSaved(plan: ICloudShareRecordPlan, zoneID: CKRecordZone.ID, libraryID: UUID,
                              zoneRecords: [CKRecord], share: CKShare) throws {
        guard share.recordID.zoneID == zoneID, share.publicPermission == .none,
              share.currentUserParticipant?.role == .owner else { throw ICloudShareOwnerError.invalidReceipt }
        let root = zoneRecords.first { $0.recordID.recordName == plan.rootRecordName }
        try validateSavedHierarchy(plan: plan, zoneID: zoneID, libraryID: libraryID, zoneRecords: zoneRecords,
            shareID: share.recordID, rootShareID: root?.share?.recordID)
    }
    /// Separate graph validation keeps tests independent of read-only native
    /// server fields. Production obtains rootShareID only from the fetched root.
    static func validateSavedHierarchy(plan: ICloudShareRecordPlan, zoneID: CKRecordZone.ID, libraryID: UUID,
                                       zoneRecords: [CKRecord], shareID: CKRecord.ID, rootShareID: CKRecord.ID?) throws {
        guard shareID.zoneID == zoneID, rootShareID == shareID else { throw ICloudShareOwnerError.invalidReceipt }
        var records: [String: CKRecord] = [:]
        for record in zoneRecords {
            guard record.recordID.zoneID == zoneID, records[record.recordID.recordName] == nil else { throw ICloudShareOwnerError.invalidReceipt }
            records[record.recordID.recordName] = record
        }
        let names = Set(plan.entries.map(\.recordName))
        for entry in plan.entries {
            guard let record = records[entry.recordName],
                  record.recordType == (entry.isImageAlias ? "ScriptumSharedImageV1" : "ScriptumItemV1"),
                  record["libraryID"] as? String == libraryID.uuidString.lowercased(),
                  record["kind"] as? String == entry.source.kind.rawValue,
                  record["uuid"] as? String == entry.source.id.uuidString.lowercased(),
                  record["operation"] as? String == "upsert",
                  record.parent?.recordID == entry.parentRecordName.map({ CKRecord.ID(recordName: $0, zoneID: zoneID) }),
                  record.share == nil || record.share?.recordID == shareID else { throw ICloudShareOwnerError.invalidReceipt }
            if entry.isImageAlias {
                guard record["sourceRecordName"] as? String == entry.source.kind.rawValue + ":" + entry.source.id.uuidString.lowercased() else { throw ICloudShareOwnerError.invalidReceipt }
            }
        }
        // Reopening never silently accepts extra descendants introduced by a
        // different device after this locally authorized manifest was recorded.
        for record in zoneRecords where !names.contains(record.recordID.recordName) {
            if let parent = record.parent, names.contains(parent.recordID.recordName) { throw ICloudShareOwnerError.changedManifest }
        }
    }
}
