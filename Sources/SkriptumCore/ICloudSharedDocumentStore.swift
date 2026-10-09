import Foundation
import CryptoKit
import Darwin

public enum ICloudSharedStoreError: Error, Equatable { case invalidIdentity, invalidCheckpoint, unsafeFile, persistence, capacity, staleCheckpoint }
public struct ICloudSharedStoreIdentity: Codable, Sendable {
    public let accountID: String
    public let ownerID: String
    public let zoneName: String
    public let shareName: String
    public let root: ICloudSyncRecordID
    public init(accountID: String, ownerID: String, zoneName: String, shareName: String, root: ICloudSyncRecordID) throws {
        guard [.page, .space].contains(root.kind), [accountID, ownerID, zoneName, shareName].allSatisfy({
            !$0.isEmpty && $0.utf8.count <= 256 && $0.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) }
        }) else { throw ICloudSharedStoreError.invalidIdentity }
        self.accountID = accountID; self.ownerID = ownerID; self.zoneName = zoneName; self.shareName = shareName; self.root = root
    }
}

/// Separate share/account checkpoint; access grants are never persisted. Calls
/// serialize on MainActor. App extensions need a cross-process locking contract.
@MainActor public final class ICloudSharedDocumentStore {
    private static let maximumBytes = 64 * 1024 * 1024
    private let descriptor: Int32
    private let filename: String
    public let identity: ICloudSharedStoreIdentity
    public let fileURL: URL
    private struct Checkpoint: Codable {
        var schemaVersion = 1
        let identity: ICloudSharedStoreIdentity
        let revision: UUID
        let canonical: LibrarySnapshot
    }
    public init(directory: URL, identity: ICloudSharedStoreIdentity) throws {
        _ = try ICloudSharedStoreIdentity(accountID: identity.accountID, ownerID: identity.ownerID, zoneName: identity.zoneName, shareName: identity.shareName, root: identity.root)
        self.identity = identity
        let digest = SHA256.hash(data: try Self.encode(identity)).map { String(format: "%02x", $0) }.joined()
        filename = "icloud-shared-" + digest + ".json"
        fileURL = directory.appendingPathComponent(filename)
        descriptor = try Self.openDirectory(directory)
    }
    deinit { Darwin.close(descriptor) }
    public func checkpointRevision() throws -> UUID? { try load()?.revision }
    /// Offline/restored documents default to no grant. The runtime must obtain
    /// the current CKShare permission before requesting an accessible context.
    public func context(permission: ICloudSharedPermission = .revoked) throws -> ICloudSharedDocumentContext? {
        guard let checkpoint = try load() else { return nil }
        return try ICloudSharedDocumentContext(root: identity.root, canonical: checkpoint.canonical, permission: permission)
    }
    @discardableResult public func replace(_ canonical: LibrarySnapshot, expectedRevision: UUID?) throws -> UUID {
        _ = try ICloudSharedDocumentContext(root: identity.root, canonical: canonical, permission: .revoked)
        let old = try load()
        guard old?.revision == expectedRevision else { throw ICloudSharedStoreError.staleCheckpoint }
        if let old, try Self.encode(old.canonical) == Self.encode(canonical) { return old.revision }
        let next = Checkpoint(identity: identity, revision: UUID(), canonical: canonical)
        try persist(next)
        return next.revision
    }
    private static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }
    private func load() throws -> Checkpoint? {
        let fd = Darwin.openat(descriptor, filename, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        if fd < 0, errno == ENOENT { return nil }
        guard fd >= 0 else { throw ICloudSharedStoreError.unsafeFile }
        defer { Darwin.close(fd) }
        var info = stat()
        guard Darwin.fstat(fd, &info) == 0, info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              info.st_nlink == 1, info.st_uid == getuid(), info.st_mode & 0o077 == 0 else { throw ICloudSharedStoreError.unsafeFile }
        guard info.st_size > 0, info.st_size <= Self.maximumBytes else { throw ICloudSharedStoreError.capacity }
        var bytes = Data(), buffer = [UInt8](repeating: 0, count: 8192)
        while true {
            let count = Darwin.read(fd, &buffer, buffer.count)
            if count < 0, errno == EINTR { continue }
            guard count >= 0, count <= Self.maximumBytes - bytes.count else { throw ICloudSharedStoreError.persistence }
            if count == 0 { break }; bytes.append(contentsOf: buffer.prefix(count))
        }
        let value = try JSONDecoder().decode(Checkpoint.self, from: bytes)
        guard value.schemaVersion == 1, try Self.encode(value.identity) == Self.encode(identity) else { throw ICloudSharedStoreError.invalidCheckpoint }
        _ = try ICloudSharedDocumentContext(root: identity.root, canonical: value.canonical, permission: .revoked)
        return value
    }
    private func persist(_ checkpoint: Checkpoint) throws {
        let bytes = try Self.encode(checkpoint)
        guard bytes.count <= Self.maximumBytes else { throw ICloudSharedStoreError.capacity }
        let temporary = ".icloud-shared-" + UUID().uuidString
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
        guard Darwin.fsync(fd) == 0, Darwin.renameat(descriptor, temporary, descriptor, filename) == 0,
              Darwin.fsync(descriptor) == 0 else { throw ICloudSharedStoreError.persistence }
    }

    private static func openDirectory(_ directory: URL) throws -> Int32 {
        guard directory.isFileURL, directory.path.hasPrefix("/") else { throw ICloudSharedStoreError.unsafeFile }
        let components = directory.path.split(separator: "/").map(String.init)
        guard !components.isEmpty, components.allSatisfy({ $0 != "." && $0 != ".." }) else { throw ICloudSharedStoreError.unsafeFile }
        var fd = Darwin.open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard fd >= 0 else { throw ICloudSharedStoreError.persistence }
        for component in components {
            var next = Darwin.openat(fd, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            if next < 0, errno == ENOENT {
                if Darwin.mkdirat(fd, component, 0o700) != 0, errno != EEXIST { Darwin.close(fd); throw ICloudSharedStoreError.persistence }
                next = Darwin.openat(fd, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            }
            Darwin.close(fd)
            guard next >= 0 else { throw ICloudSharedStoreError.unsafeFile }; fd = next
        }
        var info = stat()
        guard Darwin.fstat(fd, &info) == 0, info.st_uid == getuid() else { Darwin.close(fd); throw ICloudSharedStoreError.unsafeFile }
        return fd
    }
}
