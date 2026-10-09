import Foundation
import CloudKit
import CryptoKit
import Darwin
#if canImport(SkriptumCore)
import SkriptumCore
#endif

enum ICloudSharedReceiveError: Error { case invalidRecord, incomplete, capacity, storage }

/// Full shared hierarchy receive. Incremental CKSyncEngine state and local edits
/// are integrated separately; no token is advanced by this full-snapshot path.
@MainActor enum ICloudSharedSnapshotReceiver {
    static func receive(container: CKContainer, accepted: ICloudShareParticipantTransport.Accepted,
                        store: ICloudSharedDocumentStore, imageDirectory: URL,
                        revalidate: () async throws -> ICloudShareParticipantTransport.Accepted) async throws -> ICloudSharedDocumentContext {
        let expected = try store.checkpointRevision()
        let rootID = accepted.root.recordID
        guard rootID.recordName == store.identity.root.kind.rawValue + ":" + store.identity.root.id.uuidString.lowercased(),
              rootID.zoneID.zoneName == store.identity.zoneName,
              rootID.zoneID.ownerName == store.identity.ownerID,
              accepted.share.recordID.recordName == store.identity.shareName else { throw ICloudSharedReceiveError.invalidRecord }
        var records: [CKRecord.ID: CKRecord] = [:], token: CKServerChangeToken?
        var more = true
        while more {
            try Task.checkCancellation()
            let result = try await container.sharedCloudDatabase.recordZoneChanges(inZoneWith: rootID.zoneID, since: token,
                desiredKeys: ["libraryID", "kind", "uuid", "revision", "operation", "sha256", "sourceRecordName"], resultsLimit: 200)
            for (id, change) in result.modificationResultsByID { records[id] = try change.get().record }
            for deletion in result.deletions { records.removeValue(forKey: deletion.recordID) }
            guard records.count <= 4096 else { throw ICloudSharedReceiveError.capacity }
            token = result.changeToken; more = result.moreComing
        }
        guard records[rootID] != nil else { throw ICloudSharedReceiveError.incomplete }
        func included(_ record: CKRecord) -> Bool {
            var cursor: CKRecord? = record, visited = Set<CKRecord.ID>()
            while let current = cursor {
                if current.recordID == rootID { return true }
                guard visited.insert(current.recordID).inserted, let parent = current.parent?.recordID,
                      parent.zoneID == rootID.zoneID else { return false }
                cursor = records[parent]
            }
            return false
        }
        var snapshot = LibrarySnapshot(), documentBytes = 0
        let media = try LibraryStore(directory: imageDirectory)
        let libraryID = try requiredString(accepted.root, "libraryID")
        guard UUID(uuidString: libraryID)?.uuidString.lowercased() == libraryID else { throw ICloudSharedReceiveError.invalidRecord }
        for metadata in records.values.filter(included) {
            try Task.checkCancellation()
            let record = try await container.sharedCloudDatabase.record(for: metadata.recordID)
            // A moved/reparented record no longer belongs to this fetched graph.
            guard record.parent?.recordID == metadata.parent?.recordID,
                  record["libraryID"] as? String == libraryID,
                  record["operation"] as? String == "upsert",
                  let id = UUID(uuidString: try requiredString(record, "uuid")),
                  let revision = UUID(uuidString: try requiredString(record, "revision")),
                  let kind = ICloudSyncRecordKind(rawValue: try requiredString(record, "kind")),
                  let assetURL = (record["payload"] as? CKAsset)?.fileURL else { throw ICloudSharedReceiveError.invalidRecord }
            let bytes = try readAsset(assetURL, maximum: kind == .image ? ICloudImagePayload.maximumEncodedBytes : 8 * 1024 * 1024)
            let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
            guard record["sha256"] as? String == digest else { throw ICloudSharedReceiveError.invalidRecord }
            if kind == .image {
                let expectedName = "shared-image:" + rootID.recordName + ":" + id.uuidString.lowercased()
                guard record.recordType == "ScriptumSharedImageV1", record.recordID.recordName == expectedName,
                      record["sourceRecordName"] as? String == "image:" + id.uuidString.lowercased() else { throw ICloudSharedReceiveError.invalidRecord }
                try media.importICloudImage(ICloudImagePayload.decode(bytes, expectedImageID: id, expectedRevision: revision))
                continue
            }
            guard bytes.count <= 64 * 1024 * 1024 - documentBytes else { throw ICloudSharedReceiveError.capacity }
            documentBytes += bytes.count
            guard record.recordType == "ScriptumItemV1", record.recordID.recordName == kind.rawValue + ":" + id.uuidString.lowercased() else { throw ICloudSharedReceiveError.invalidRecord }
            switch kind {
            case .page: snapshot.pages.append(try ICloudPagePayload.decode(bytes, expectedPageID: id, expectedRevision: revision).page)
            case .space: snapshot.spaces.append(try metadataValue(bytes, id: id, revision: revision, as: Space.self))
            case .comment: snapshot.comments.append(try metadataValue(bytes, id: id, revision: revision, as: Comment.self))
            case .revision: snapshot.revisions.append(try metadataValue(bytes, id: id, revision: revision, as: Revision.self))
            case .image: break
            }
        }
        snapshot.spaces.sort { $0.id.uuidString < $1.id.uuidString }
        snapshot.pages.sort { $0.id.uuidString < $1.id.uuidString }
        snapshot.comments.sort { $0.id.uuidString < $1.id.uuidString }
        snapshot.revisions.sort { $0.id.uuidString < $1.id.uuidString }
        let grant = try await revalidate()
        guard grant.share.recordID == accepted.share.recordID, grant.root.recordID == rootID else { throw ICloudSharedReceiveError.invalidRecord }
        let permission: ICloudSharedPermission = grant.canWrite ? .readWrite : .readOnly
        let context = try ICloudSharedDocumentContext(root: store.identity.root, canonical: snapshot, permission: permission)
        for page in snapshot.pages + snapshot.revisions.map(\.page) {
            for attachment in page.attachments ?? [] { _ = try media.attachmentData(attachment) }
        }
        _ = try store.replace(snapshot, expectedRevision: expected)
        return context
    }
    private static func requiredString(_ record: CKRecord, _ key: String) throws -> String {
        guard let value = record[key] as? String else { throw ICloudSharedReceiveError.invalidRecord }; return value
    }
    private static func metadataValue<T: Codable & Sendable & Identifiable>(_ bytes: Data, id: UUID, revision: UUID, as type: T.Type) throws -> T where T.ID == UUID {
        let payload = try ICloudMetadataPayload<T>.decode(bytes)
        guard payload.value.id == id, try payload.revisionID() == revision else { throw ICloudSharedReceiveError.invalidRecord }
        return payload.value
    }
    private static func readAsset(_ url: URL, maximum: Int) throws -> Data {
        guard url.isFileURL else { throw ICloudSharedReceiveError.storage }
        let fd = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { throw ICloudSharedReceiveError.storage }
        defer { Darwin.close(fd) }
        var info = stat()
        guard Darwin.fstat(fd, &info) == 0, info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG), info.st_size >= 0,
              info.st_size <= maximum else { throw ICloudSharedReceiveError.capacity }
        var data = Data(), buffer = [UInt8](repeating: 0, count: 8192)
        while true {
            let count = Darwin.read(fd, &buffer, buffer.count)
            if count < 0, errno == EINTR { continue }
            guard count >= 0, count <= maximum - data.count else { throw ICloudSharedReceiveError.storage }
            if count == 0 { return data }; data.append(contentsOf: buffer.prefix(count))
        }
    }
}
