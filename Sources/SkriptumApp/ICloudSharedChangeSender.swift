import Foundation
import CloudKit
import CryptoKit
#if canImport(SkriptumCore)
import SkriptumCore
#endif

enum ICloudSharedSendError: Error { case permissionDenied, conflict, invalidRecord, unconfirmedSave }

@MainActor protocol ICloudSharedRecordDatabase {
    func record(for id: CKRecord.ID) async throws -> CKRecord
    func save(_ record: CKRecord) async throws -> CKRecord
}
@MainActor private struct NativeSharedRecordDatabase: ICloudSharedRecordDatabase {
    let database: CKDatabase
    func record(for id: CKRecord.ID) async throws -> CKRecord { try await database.record(for: id) }
    func save(_ record: CKRecord) async throws -> CKRecord {
        let result = try await database.modifyRecords(saving: [record], deleting: [], savePolicy: .ifServerRecordUnchanged, atomically: true)
        guard let saved = try result.saveResults[record.recordID]?.get() else { throw ICloudSharedSendError.unconfirmedSave }
        return saved
    }
}

@MainActor enum ICloudSharedChangeSender {
    static func send(container: CKContainer, store: ICloudSharedDocumentStore,
                     stagingDirectory: URL,
                     revalidate: () async throws -> ICloudShareParticipantTransport.Accepted) async throws {
        try await send(database: NativeSharedRecordDatabase(database: container.sharedCloudDatabase), store: store,
            stagingDirectory: stagingDirectory, revalidate: revalidate)
    }
    static func send(database: any ICloudSharedRecordDatabase, store: ICloudSharedDocumentStore,
                     stagingDirectory: URL,
                     revalidate: () async throws -> ICloudShareParticipantTransport.Accepted) async throws {
        let files = try ICloudSyncEngine.Files(directory: stagingDirectory, name: "shared-asset-staging")
        for change in try store.pendingChanges() {
            try Task.checkCancellation()
            let grant = try await revalidate()
            guard grant.canWrite else { throw ICloudSharedSendError.permissionDenied }
            let root = grant.root.recordID
            guard root.recordName == store.identity.root.kind.rawValue + ":" + store.identity.root.id.uuidString.lowercased(),
                  root.zoneID.zoneName == store.identity.zoneName, root.zoneID.ownerName == store.identity.ownerID,
                  grant.share.recordID.recordName == store.identity.shareName,
                  let libraryID = grant.root["libraryID"] as? String,
                  UUID(uuidString: libraryID)?.uuidString.lowercased() == libraryID else { throw ICloudSharedSendError.invalidRecord }
            let id = CKRecord.ID(recordName: change.recordID.kind.rawValue + ":" + change.recordID.id.uuidString.lowercased(), zoneID: root.zoneID)
            let digest = SHA256.hash(data: change.payload).map { String(format: "%02x", $0) }.joined()
            let record: CKRecord
            let isNew: Bool
            do { record = try await database.record(for: id); isNew = false }
            catch let error as CKError where error.code == .unknownItem && [.revision, .comment].contains(change.recordID.kind) {
                isNew = true
                record = CKRecord(recordType: "ScriptumItemV1", recordID: id)
                let pageID: UUID
                if change.recordID.kind == .comment {
                    pageID = try ICloudMetadataPayload<Comment>.decode(change.payload).value.pageID
                } else {
                    pageID = try ICloudMetadataPayload<Revision>.decode(change.payload).value.page.id
                }
                guard let context = try store.context(permission: .readWrite) else { throw ICloudSharedSendError.invalidRecord }
                try context.requireWrite(to: pageID)
                record.parent = CKRecord.Reference(recordID: .init(recordName: "page:" + pageID.uuidString.lowercased(), zoneID: root.zoneID), action: .none)
            }
            guard record.recordID == id, record.recordType == "ScriptumItemV1" else {
                throw ICloudSharedSendError.invalidRecord
            }
            try await validateHierarchy(record, root: root, libraryID: libraryID, database: database)
            // An uncertain earlier save can be acknowledged only if its exact
            // immutable identity and digest are already confirmed on the server.
            if matches(record, change: change, libraryID: libraryID, digest: digest) {
                try confirmPayload(record, change: change)
                _ = try await revalidate()
                _ = try store.acknowledge(recordID: change.recordID, revisionID: change.revisionID)
                continue
            }
            switch change.recordID.kind {
            case .page:
                let payload = try ICloudPagePayload.decode(change.payload, expectedPageID: change.recordID.id, expectedRevision: change.revisionID)
                guard let base = payload.baseRevision, record["revision"] as? String == base.uuidString.lowercased(),
                      record["libraryID"] as? String == libraryID else { throw ICloudSharedSendError.conflict }
            case .comment:
                let incoming = try ICloudMetadataPayload<Comment>.decode(change.payload)
                guard incoming.value.id == change.recordID.id, try incoming.revisionID() == change.revisionID else { throw ICloudSharedSendError.invalidRecord }
                if isNew {
                    guard incoming.baseDigest == nil else { throw ICloudSharedSendError.conflict }
                } else {
                    guard let url = (record["payload"] as? CKAsset)?.fileURL else { throw ICloudSharedSendError.invalidRecord }
                    let bytes = try ICloudSharedSnapshotReceiver.readAsset(url, maximum: 8 * 1024 * 1024)
                    let currentDigest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
                    guard record["sha256"] as? String == currentDigest else { throw ICloudSharedSendError.invalidRecord }
                    let current = try ICloudMetadataPayload<Comment>.decode(bytes)
                    guard current.value.id == incoming.value.id,
                          record["libraryID"] as? String == libraryID, record["kind"] as? String == "comment",
                          record["revision"] as? String == (try current.revisionID()).uuidString.lowercased(),
                          try ICloudMetadataPayload<Comment>.digest(of: current.value) == incoming.baseDigest else { throw ICloudSharedSendError.conflict }
                }
            case .revision:
                let payload = try ICloudMetadataPayload<Revision>.decode(change.payload)
                guard payload.value.id == change.recordID.id, try payload.revisionID() == change.revisionID,
                      isNew else { throw ICloudSharedSendError.conflict }
            default: throw ICloudSharedSendError.invalidRecord
            }
            let filename = "shared-asset-" + UUID().uuidString
            try files.writeAsset(change.payload, name: filename)
            defer { files.removeAsset(filename) }
            record["libraryID"] = libraryID as CKRecordValue
            record["kind"] = change.recordID.kind.rawValue as CKRecordValue
            record["uuid"] = change.recordID.id.uuidString.lowercased() as CKRecordValue
            record["revision"] = change.revisionID.uuidString.lowercased() as CKRecordValue
            record["operation"] = change.operation.rawValue as CKRecordValue
            record["sha256"] = digest as CKRecordValue
            record["payload"] = CKAsset(fileURL: stagingDirectory.appendingPathComponent(filename))
            let latest = try await revalidate()
            guard latest.canWrite, latest.share.recordID == grant.share.recordID else { throw ICloudSharedSendError.permissionDenied }
            let expectedParent = record.parent
            let saved = try await database.save(record)
            guard saved.recordID == id, matches(saved, change: change, libraryID: libraryID, digest: digest),
                  saved.parent?.recordID == expectedParent?.recordID, saved.parent?.action == expectedParent?.action else {
                throw ICloudSharedSendError.unconfirmedSave
            }
            try confirmPayload(saved, change: change)
            _ = try await revalidate()
            _ = try store.acknowledge(recordID: change.recordID, revisionID: change.revisionID)
        }
    }
    private static func validateHierarchy(_ record: CKRecord, root: CKRecord.ID, libraryID: String,
                                          database: any ICloudSharedRecordDatabase) async throws {
        var current = record
        var visited: Set<CKRecord.ID> = []
        while current.recordID != root {
            try Task.checkCancellation()
            guard visited.insert(current.recordID).inserted, visited.count <= 4096,
                  let parent = current.parent?.recordID, parent.zoneID == root.zoneID else {
                throw ICloudSharedSendError.invalidRecord
            }
            if parent == root { return }
            let ancestor = try await database.record(for: parent)
            let parts = parent.recordName.split(separator: ":", omittingEmptySubsequences: false)
            guard ancestor.recordID == parent, ancestor.recordType == "ScriptumItemV1",
                  parts.count == 2, parts[0] == "page" || parts[0] == "space",
                  let id = UUID(uuidString: String(parts[1])), id.uuidString.lowercased() == parts[1],
                  ancestor["libraryID"] as? String == libraryID,
                  ancestor["kind"] as? String == String(parts[0]), ancestor["uuid"] as? String == String(parts[1]),
                  ancestor["operation"] as? String == "upsert" else {
                throw ICloudSharedSendError.invalidRecord
            }
            current = ancestor
        }
        guard current.parent == nil else { throw ICloudSharedSendError.invalidRecord }
    }
    private static func confirmPayload(_ record: CKRecord, change: ICloudSyncChange) throws {
        guard let url = (record["payload"] as? CKAsset)?.fileURL,
              try ICloudSharedSnapshotReceiver.readAsset(url, maximum: 8 * 1024 * 1024) == change.payload else {
            throw ICloudSharedSendError.unconfirmedSave
        }
    }
    private static func matches(_ record: CKRecord, change: ICloudSyncChange, libraryID: String, digest: String) -> Bool {
        record.recordType == "ScriptumItemV1" && record["libraryID"] as? String == libraryID && record["kind"] as? String == change.recordID.kind.rawValue &&
        record["uuid"] as? String == change.recordID.id.uuidString.lowercased() &&
        record["revision"] as? String == change.revisionID.uuidString.lowercased() &&
        record["operation"] as? String == change.operation.rawValue && record["sha256"] as? String == digest
    }
}
