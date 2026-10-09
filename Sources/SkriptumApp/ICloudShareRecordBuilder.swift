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
                        libraryID: UUID, zoneRecords: [CKRecord], title: String) throws -> Prepared {
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
        let share = CKShare(rootRecord: root)
        share.publicPermission = .none
        share[CKShare.SystemFieldKey.title] = title as CKRecordValue
        return Prepared(share: share, records: prepared)
    }
}
