import Foundation
import CloudKit
import CryptoKit
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
                for key in ["libraryID", "kind", "uuid", "revision", "operation", "sha256"] { record[key] = source[key] }
                // A CKAsset belongs to one record. Reusing the canonical
                // instance on an alias raises an Objective-C exception.
                guard let asset = source["payload"] as? CKAsset,
                      let file = asset.fileURL, file.isFileURL else {
                    throw ICloudSharePreparationError.invalidRecord
                }
                record["payload"] = CKAsset(fileURL: file)
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

    struct Expansion {
        let records: [CKRecord]
        let detached: [CKRecord]
        let deleting: [CKRecord.ID]
    }
    /// Adds only members of the current local hierarchy to an already owned
    /// share. Native ancestry follows the document; canonical images stay private.
    static func expansion(plan: ICloudShareRecordPlan, snapshot: LibrarySnapshot, zoneID: CKRecordZone.ID, libraryID: UUID,
                          zoneRecords: [CKRecord], shareID: CKRecord.ID, rootShareID: CKRecord.ID?) throws -> Expansion? {
        guard shareID.zoneID == zoneID, rootShareID == shareID else { throw ICloudShareOwnerError.invalidReceipt }
        var sources: [String: CKRecord] = [:]
        for record in zoneRecords {
            guard record.recordID.zoneID == zoneID, sources[record.recordID.recordName] == nil else { throw ICloudShareOwnerError.invalidReceipt }
            sources[record.recordID.recordName] = record
        }
        let names = Set(plan.entries.map(\.recordName))
        var result: [CKRecord] = [], additions = Set<String>(), changed = false
        for entry in plan.entries {
            let sourceName = entry.source.kind.rawValue + ":" + entry.source.id.uuidString.lowercased()
            guard let source = sources[sourceName], source.recordType == "ScriptumItemV1",
                  source["libraryID"] as? String == libraryID.uuidString.lowercased(),
                  source["kind"] as? String == entry.source.kind.rawValue,
                  source["uuid"] as? String == entry.source.id.uuidString.lowercased(),
                  source["operation"] as? String == "upsert" else { throw ICloudSharePreparationError.invalidRecord }
            if entry.isImageAlias {
                guard source.parent == nil, source.share == nil else { throw ICloudSharePreparationError.overlappingHierarchy }
                if let alias = sources[entry.recordName] {
                    guard alias.recordType == "ScriptumSharedImageV1", alias.parent?.recordID == CKRecord.ID(recordName: plan.rootRecordName, zoneID: zoneID),
                          alias["sourceRecordName"] as? String == sourceName, alias.share == nil || alias.share?.recordID == shareID,
                          ["libraryID", "kind", "uuid", "revision", "operation", "sha256"].allSatisfy({ alias[$0] as? String == source[$0] as? String }) else {
                        throw ICloudSharePreparationError.invalidRecord
                    }
                    result.append(alias)
                } else {
                    guard let url = (source["payload"] as? CKAsset)?.fileURL, url.isFileURL else { throw ICloudSharePreparationError.invalidRecord }
                    let alias = CKRecord(recordType: "ScriptumSharedImageV1", recordID: .init(recordName: entry.recordName, zoneID: zoneID))
                    for key in ["libraryID", "kind", "uuid", "revision", "operation", "sha256"] { alias[key] = source[key] }
                    alias["sourceRecordName"] = sourceName as CKRecordValue
                    alias["payload"] = CKAsset(fileURL: url)
                    alias.parent = CKRecord.Reference(recordID: .init(recordName: plan.rootRecordName, zoneID: zoneID), action: .none)
                    additions.insert(entry.recordName); changed = true; result.append(alias)
                }
            } else {
                guard let copy = source.copy() as? CKRecord else { throw ICloudSharePreparationError.invalidRecord }
                if entry.recordName == plan.rootRecordName {
                    guard copy.parent == nil else { throw ICloudSharePreparationError.overlappingHierarchy }
                } else if copy.parent == nil {
                    guard copy.share == nil, let parent = entry.parentRecordName, names.contains(parent) else { throw ICloudSharePreparationError.overlappingHierarchy }
                    copy.parent = CKRecord.Reference(recordID: .init(recordName: parent, zoneID: zoneID), action: .none)
                    additions.insert(entry.recordName); changed = true
                } else {
                    var cursor = source, visited = Set<String>()
                    while cursor.recordID.recordName != plan.rootRecordName {
                        guard visited.count < 4096, visited.insert(cursor.recordID.recordName).inserted,
                              cursor.share == nil || cursor.share?.recordID == shareID,
                              let parent = cursor.parent?.recordID, parent.zoneID == zoneID,
                              let next = sources[parent.recordName], next.recordType == "ScriptumItemV1",
                              next["libraryID"] as? String == libraryID.uuidString.lowercased(),
                              let kind = next["kind"] as? String, ["page", "space"].contains(kind),
                              let uuid = next["uuid"] as? String, UUID(uuidString: uuid)?.uuidString.lowercased() == uuid,
                              parent.recordName == kind + ":" + uuid else { throw ICloudSharePreparationError.overlappingHierarchy }
                        cursor = next
                    }
                    guard let parent = entry.parentRecordName, names.contains(parent) else { throw ICloudSharePreparationError.invalidRecord }
                    let expected = CKRecord.ID(recordName: parent, zoneID: zoneID)
                    if copy.parent?.recordID != expected {
                        copy.parent = CKRecord.Reference(recordID: expected, action: .none); changed = true
                    }
                }
                result.append(copy)
            }
        }
        // Granting a formerly private parent also grants its native descendants.
        // Reject an unplanned child rather than exposing it implicitly.
        for record in zoneRecords where !names.contains(record.recordID.recordName) {
            if let parent = record.parent, additions.contains(parent.recordID.recordName) { throw ICloudSharePreparationError.overlappingHierarchy }
        }
        var detached: [CKRecord] = [], deleting: [CKRecord.ID] = []
        for record in zoneRecords where !names.contains(record.recordID.recordName) {
            var cursor = record, visited = Set<CKRecord.ID>()
            while cursor.recordID.recordName != plan.rootRecordName {
                guard visited.insert(cursor.recordID).inserted, let parent = cursor.parent?.recordID,
                      parent.zoneID == zoneID, let next = sources[parent.recordName] else { break }
                cursor = next
            }
            guard cursor.recordID.recordName == plan.rootRecordName else { continue }
            guard record["libraryID"] as? String == libraryID.uuidString.lowercased(),
                  record.share == nil || record.share?.recordID == shareID else { throw ICloudSharePreparationError.overlappingHierarchy }
            if record.recordType == "ScriptumSharedImageV1" {
                guard let image = record["uuid"] as? String, UUID(uuidString: image)?.uuidString.lowercased() == image,
                      record.recordID.recordName == "shared-image:" + plan.rootRecordName + ":" + image,
                      record["sourceRecordName"] as? String == "image:" + image,
                      record.parent?.recordID == CKRecord.ID(recordName: plan.rootRecordName, zoneID: zoneID) else { throw ICloudSharePreparationError.invalidRecord }
                deleting.append(record.recordID)
            } else {
                guard record.recordType == "ScriptumItemV1", let kind = record["kind"] as? String,
                      ["page", "comment", "revision"].contains(kind), let id = record["uuid"] as? String,
                      UUID(uuidString: id)?.uuidString.lowercased() == id,
                      record.recordID.recordName == kind + ":" + id,
                      let copy = record.copy() as? CKRecord else { throw ICloudSharePreparationError.invalidRecord }
                let known: Bool
                switch kind {
                case "page": known = snapshot.pages.contains { $0.id.uuidString.lowercased() == id }
                case "comment": known = snapshot.comments.contains { $0.id.uuidString.lowercased() == id }
                default: known = snapshot.revisions.contains { $0.id.uuidString.lowercased() == id }
                }
                // A concurrent participant/owner addition is not a local removal.
                // Fetch/merge it before deciding which hierarchy it belongs to.
                if !known {
                    guard record["operation"] as? String == "tombstone" else { throw ICloudShareOwnerError.changedManifest }
                    continue
                }
                copy.parent = nil; detached.append(copy)
            }
        }
        guard changed || !detached.isEmpty || !deleting.isEmpty else { return nil }
        return Expansion(records: result, detached: detached, deleting: deleting)
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
        // Recovering an unconfirmed creation never accepts extra descendants
        // added after this locally authorized manifest was recorded.
        for record in zoneRecords where !names.contains(record.recordID.recordName) {
            if let parent = record.parent, names.contains(parent.recordID.recordName) { throw ICloudShareOwnerError.changedManifest }
        }
    }

    /// Only install new optimistic server tags when each saved document value
    /// still equals the current local value. A remote/local difference requires
    /// normal receive/merge; metadata alone must never bless an overwrite.
    static func confirmedMetadata(plan: ICloudShareRecordPlan, records: [CKRecord], snapshot: LibrarySnapshot) throws -> [String: Data] {
        guard records.count == plan.entries.count, Set(records.map { $0.recordID.recordName }) == Set(plan.entries.map(\.recordName)) else { throw ICloudShareOwnerError.invalidReceipt }
        var metadata: [String: Data] = [:]
        for record in records {
            guard let entry = plan.entries.first(where: { $0.recordName == record.recordID.recordName }),
                  let revisionText = record["revision"] as? String, let revision = UUID(uuidString: revisionText),
                  revision.uuidString.lowercased() == revisionText,
                  let url = (record["payload"] as? CKAsset)?.fileURL else { throw ICloudShareOwnerError.invalidReceipt }
            let maximum = entry.source.kind == .image ? ICloudImagePayload.maximumEncodedBytes : 8 * 1024 * 1024
            let bytes = try ICloudSyncEngine.Files.readAsset(url, maximum: maximum)
            let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
            guard record["sha256"] as? String == digest else { throw ICloudShareOwnerError.invalidReceipt }
            switch entry.source.kind {
            case .page:
                let value = try ICloudPagePayload.decode(bytes, expectedPageID: entry.source.id, expectedRevision: revision).page
                guard let local = snapshot.pages.first(where: { $0.id == value.id }), try exact(local, value) else { throw ICloudShareOwnerError.changedManifest }
            case .space:
                try matchesMetadata(bytes, revision: revision, id: entry.source.id, values: snapshot.spaces)
            case .comment:
                try matchesMetadata(bytes, revision: revision, id: entry.source.id, values: snapshot.comments)
            case .revision:
                try matchesMetadata(bytes, revision: revision, id: entry.source.id, values: snapshot.revisions)
            case .image:
                let image = try ICloudImagePayload.decode(bytes, expectedImageID: entry.source.id, expectedRevision: revision)
                let attachments = (snapshot.pages + snapshot.revisions.map(\.page)).flatMap { $0.attachments ?? [] }
                guard attachments.contains(where: { $0.storageEquals(image.attachment) }) else { throw ICloudShareOwnerError.changedManifest }
            }
            let encoder = NSKeyedArchiver(requiringSecureCoding: true)
            record.encodeSystemFields(with: encoder); encoder.finishEncoding()
            metadata[record.recordID.recordName] = encoder.encodedData
        }
        return metadata
    }
    private static func matchesMetadata<Value: Codable & Sendable & Identifiable>(_ bytes: Data, revision: UUID,
        id: UUID, values: [Value]) throws where Value.ID == UUID {
        let payload = try ICloudMetadataPayload<Value>.decode(bytes)
        guard payload.value.id == id, try payload.revisionID() == revision,
              let local = values.first(where: { $0.id == id }), try exact(local, payload.value) else { throw ICloudShareOwnerError.changedManifest }
    }
    private static func exact<Value: Encodable>(_ left: Value, _ right: Value) throws -> Bool {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(left) == encoder.encode(right)
    }
}
