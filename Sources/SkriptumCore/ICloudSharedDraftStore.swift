import Foundation
import CryptoKit
import Darwin

public struct ICloudSharedDraft: Codable, Identifiable, Sendable {
    public let id: UUID
    public let pageID: UUID
    public let baseRevision: UUID
    public let text: String
    public let updatedAt: Date
    public init(id: UUID, pageID: UUID, baseRevision: UUID, text: String) {
        self.id = id; self.pageID = pageID; self.baseRevision = baseRevision; self.text = text; updatedAt = Date()
    }
}

/// Private recovery buffers, never sync records or persisted participant grants.
/// Separate files keep recovery available when the outgoing checkpoint is full.
@MainActor public final class ICloudSharedDraftStore {
    private let descriptor: Int32
    private let identity: ICloudSharedStoreIdentity
    private let prefix: String
    private let maximumBytes = 64 * 1024 * 1024
    private struct Envelope: Codable {
        var schemaVersion = 1
        let identity: ICloudSharedStoreIdentity
        let draft: ICloudSharedDraft
    }
    public init(directory: URL, identity: ICloudSharedStoreIdentity) throws {
        _ = try ICloudSharedStoreIdentity(accountID: identity.accountID, ownerID: identity.ownerID,
            zoneName: identity.zoneName, shareName: identity.shareName, root: identity.root)
        self.identity = identity
        prefix = "shared-draft-" + SHA256.hash(data: try Self.encode(identity)).map { String(format: "%02x", $0) }.joined() + "-"
        descriptor = try ICloudSharedDocumentStore.openDirectory(directory)
    }
    deinit { Darwin.close(descriptor) }
    public func save(_ draft: ICloudSharedDraft) throws {
        guard draft.text.utf8.count <= 8 * 1024 * 1024 else { throw ICloudSharedStoreError.capacity }
        let bytes = try Self.encode(Envelope(identity: identity, draft: draft))
        guard bytes.count <= maximumBytes else { throw ICloudSharedStoreError.capacity }
        // Validate an existing file before replacing it; retain corruption/links.
        _ = try load(draft.id)
        let temporary = ".shared-draft-" + UUID().uuidString
        let fd = Darwin.openat(descriptor, temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw ICloudSharedStoreError.persistence }
        defer { Darwin.close(fd); Darwin.unlinkat(descriptor, temporary, 0) }
        try bytes.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let count = Darwin.write(fd, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                if count < 0, errno == EINTR { continue }
                guard count > 0 else { throw ICloudSharedStoreError.persistence }; offset += count
            }
        }
        guard Darwin.fsync(fd) == 0, Darwin.renameat(descriptor, temporary, descriptor, filename(draft.id)) == 0,
              Darwin.fsync(descriptor) == 0 else { throw ICloudSharedStoreError.persistence }
    }
    public func draft(_ id: UUID) throws -> ICloudSharedDraft? { try load(id) }
    public func drafts() throws -> [ICloudSharedDraft] {
        let duplicate = Darwin.dup(descriptor)
        guard duplicate >= 0 else { throw ICloudSharedStoreError.persistence }
        guard let directory = Darwin.fdopendir(duplicate) else { Darwin.close(duplicate); throw ICloudSharedStoreError.persistence }
        defer { Darwin.closedir(directory) }
        Darwin.rewinddir(directory)
        var result: [ICloudSharedDraft] = []
        while true {
            errno = 0
            guard let entry = Darwin.readdir(directory) else {
                guard errno == 0 else { throw ICloudSharedStoreError.persistence }; break
            }
            let name = withUnsafePointer(to: &entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(NAME_MAX) + 1) { String(cString: $0) }
            }
            guard name.hasPrefix(prefix), name.hasSuffix(".json") else { continue }
            let value = String(name.dropFirst(prefix.count).dropLast(5))
            guard let id = UUID(uuidString: value), name == filename(id) else { throw ICloudSharedStoreError.invalidCheckpoint }
            if let draft = try load(id) { result.append(draft) }
        }
        return result.sorted { $0.updatedAt == $1.updatedAt ? $0.id.uuidString < $1.id.uuidString : $0.updatedAt > $1.updatedAt }
    }
    @discardableResult public func remove(_ id: UUID, matching text: String) throws -> Bool {
        guard let draft = try load(id), draft.text.utf8.elementsEqual(text.utf8) else { return false }
        guard Darwin.unlinkat(descriptor, filename(id), 0) == 0, Darwin.fsync(descriptor) == 0 else { throw ICloudSharedStoreError.persistence }
        return true
    }
    private func filename(_ id: UUID) -> String { prefix + id.uuidString + ".json" }
    private func load(_ id: UUID) throws -> ICloudSharedDraft? {
        let fd = Darwin.openat(descriptor, filename(id), O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        if fd < 0, errno == ENOENT { return nil }
        guard fd >= 0 else { throw ICloudSharedStoreError.unsafeFile }
        defer { Darwin.close(fd) }
        var info = stat()
        guard Darwin.fstat(fd, &info) == 0, info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG), info.st_nlink == 1,
              info.st_uid == getuid(), info.st_mode & 0o077 == 0 else { throw ICloudSharedStoreError.unsafeFile }
        guard info.st_size > 0, info.st_size <= maximumBytes else { throw ICloudSharedStoreError.capacity }
        var bytes = Data(), buffer = [UInt8](repeating: 0, count: 8192)
        while true {
            let count = Darwin.read(fd, &buffer, buffer.count)
            if count < 0, errno == EINTR { continue }
            guard count >= 0, count <= maximumBytes - bytes.count else { throw ICloudSharedStoreError.persistence }
            if count == 0 { break }; bytes.append(contentsOf: buffer.prefix(count))
        }
        let envelope = try JSONDecoder().decode(Envelope.self, from: bytes)
        guard envelope.schemaVersion == 1, envelope.identity == identity, envelope.draft.id == id,
              envelope.draft.text.utf8.count <= 8 * 1024 * 1024 else { throw ICloudSharedStoreError.invalidCheckpoint }
        return envelope.draft
    }
    private static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; return try encoder.encode(value)
    }
}
