import Foundation
import CryptoKit

/// Document-domain projection only. Provider credentials and conversation files
/// are outside LibrarySnapshot and cannot enter this serialization path.
@MainActor public enum ICloudLibraryProjection {
    public static func changes(from previous: LibrarySnapshot, to current: LibrarySnapshot) throws -> [ICloudSyncChange] {
        try LibraryStore.validate(previous)
        try LibraryStore.validate(current)
        var result: [ICloudSyncChange] = []
        try appendMetadata(previous.spaces, current.spaces, kind: .space, to: &result)
        try appendMetadata(previous.comments, current.comments, kind: .comment, to: &result)
        try appendMetadata(previous.revisions, current.revisions, kind: .revision, to: &result)
        let old = Dictionary(uniqueKeysWithValues: previous.pages.map { ($0.id, $0) })
        let new = Set(current.pages.map(\.id))
        for page in current.pages {
            if let previous = old[page.id], try exact(previous, page) { continue }
            if old[page.id]?.revision == page.revision { throw LibraryError.invalidLibrary }
            let payload = try ICloudPagePayload(page: page, baseRevision: old[page.id]?.revision).encoded()
            result.append(ICloudSyncChange(recordID: .init(kind: .page, id: page.id),
                revisionID: page.revision, operation: .upsert, payload: payload))
        }
        for page in previous.pages where !new.contains(page.id) {
            result.append(ICloudSyncChange(recordID: .init(kind: .page, id: page.id),
                revisionID: stableRevision(Data(("delete:page:" + page.id.uuidString + ":" + page.revision.uuidString).utf8)), operation: .tombstone, payload: Data()))
        }
        return result.sorted { ($0.recordID.kind.rawValue + $0.recordID.id.uuidString) < ($1.recordID.kind.rawValue + $1.recordID.id.uuidString) }
    }

    private static func appendMetadata<T: Codable & Equatable & Identifiable & Sendable>(_ previous: [T], _ current: [T],
        kind: ICloudSyncRecordKind, to result: inout [ICloudSyncChange]) throws where T.ID == UUID {
        let old = Dictionary(uniqueKeysWithValues: previous.map { ($0.id, $0) })
        let new = Set(current.map(\.id))
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        for item in current {
            if let previous = old[item.id], try exact(previous, item) { continue }
            if kind == .revision, old[item.id] != nil { throw LibraryError.invalidLibrary }
            let baseDigest = try old[item.id].map { try ICloudMetadataPayload<T>.digest(of: $0) }
            let wrapper = try ICloudMetadataPayload(value: item, baseDigest: baseDigest)
            let payload = try wrapper.encoded()
            let revision = try wrapper.revisionID()
            result.append(ICloudSyncChange(recordID: .init(kind: kind, id: item.id), revisionID: revision,
                operation: .upsert, payload: payload))
        }
        for item in previous where !new.contains(item.id) {
            var identity = Data(("delete:" + kind.rawValue + ":" + item.id.uuidString + ":").utf8)
            identity.append(try encoder.encode(item))
            result.append(ICloudSyncChange(recordID: .init(kind: kind, id: item.id), revisionID: stableRevision(identity),
                operation: .tombstone, payload: Data()))
        }
    }
    private static func stableRevision(_ data: Data) -> UUID {
        var bytes = Array(SHA256.hash(data: data).prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x50; bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (bytes[0],bytes[1],bytes[2],bytes[3],bytes[4],bytes[5],bytes[6],bytes[7],bytes[8],bytes[9],bytes[10],bytes[11],bytes[12],bytes[13],bytes[14],bytes[15]))
    }
    private static func exact<T: Encodable>(_ lhs: T, _ rhs: T) throws -> Bool {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(lhs) == encoder.encode(rhs)
    }
}
