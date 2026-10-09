import Foundation
import CryptoKit
import Darwin

public enum ICloudSyncJournalError: Error, Equatable, Sendable {
    case invalidScope, invalidChange, invalidJournal, unsafeFile, persistence
    case capacityExceeded, revisionPayloadMismatch, invalidBatch, batchLimitTooSmall
}

/// Stable private-database identity, not a credential or account activation.
public struct ICloudSyncScope: Codable, Hashable, Sendable, CustomStringConvertible {
    public let accountID: String
    public let libraryID: UUID
    public init(accountID: String, libraryID: UUID) throws {
        guard (1...256).contains(accountID.utf8.count), !accountID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              accountID.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
            throw ICloudSyncJournalError.invalidScope
        }
        self.accountID = accountID; self.libraryID = libraryID
    }
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.libraryID == rhs.libraryID && lhs.accountID.utf8.elementsEqual(rhs.accountID.utf8)
    }
    public func hash(into hasher: inout Hasher) { hasher.combine(libraryID); for byte in accountID.utf8 { hasher.combine(byte) } }
    public var description: String { "ICloudSyncScope(<private>)" }
}

/// Only document-domain records belong in this queue. Credentials and private
/// provider history have no record kind; serialization remains the adapter's job.
public enum ICloudSyncRecordKind: String, Codable, Sendable { case space, page, comment, revision, image }
public struct ICloudSyncRecordID: Codable, Hashable, Sendable {
    public let kind: ICloudSyncRecordKind
    public let id: UUID
    public init(kind: ICloudSyncRecordKind, id: UUID) { self.kind = kind; self.id = id }
    fileprivate var order: String { kind.rawValue + ":" + id.uuidString }
}
public enum ICloudSyncOperation: String, Codable, Sendable { case upsert, tombstone }
public struct ICloudSyncChange: Codable, Equatable, Sendable, CustomStringConvertible, CustomReflectable {
    public let recordID: ICloudSyncRecordID
    public let revisionID: UUID
    public let operation: ICloudSyncOperation
    public let payload: Data
    public init(recordID: ICloudSyncRecordID, revisionID: UUID, operation: ICloudSyncOperation, payload: Data) {
        self.recordID = recordID; self.revisionID = revisionID; self.operation = operation; self.payload = payload
    }
    public var description: String { "ICloudSyncChange(<private revision payload>)" }
    public var customMirror: Mirror { Mirror(self, children: ["change": "<private>"]) }
    fileprivate func validate() throws {
        guard payload.count <= 8 * 1024 * 1024, operation != .tombstone || payload.isEmpty else {
            throw ICloudSyncJournalError.invalidChange
        }
    }
}

/// Durable local outbox only: it never uploads or applies changes to live editing.
/// All instances serialize read/modify/write in this process. Cross-process
/// writers/app extensions require a separate locking contract before activation.
public final class ICloudSyncJournal: @unchecked Sendable {
    private static let transactionLock = NSLock()
    private static let maximumFileBytes = 64 * 1024 * 1024
    private static let maximumRecords = 4096
    public let scope: ICloudSyncScope
    public let fileURL: URL
    private var descriptor: Int32
    private let filename: String
    private struct Snapshot: Codable {
        var schemaVersion = 1
        let scope: ICloudSyncScope
        var pending: [ICloudSyncChange]
    }

    public init(directory: URL, scope: ICloudSyncScope) throws {
        _ = try ICloudSyncScope(accountID: scope.accountID, libraryID: scope.libraryID)
        self.scope = scope
        var identity = Data(scope.accountID.utf8); identity.append(0); identity.append(contentsOf: scope.libraryID.uuidString.utf8)
        filename = "icloud-outbox-" + SHA256.hash(data: identity).map { String(format: "%02x", $0) }.joined() + ".json"
        fileURL = directory.appendingPathComponent(filename)
        descriptor = try Self.openDirectory(directory)
        do { _ = try Self.transactionLock.withLock { try load() } }
        catch {
            // A fully initialized throwing class initializer may run deinit.
            // Invalidate ownership first so it cannot close a reused descriptor.
            let owned = descriptor; descriptor = -1; Darwin.close(owned); throw error
        }
    }
    deinit { Darwin.close(descriptor) }

    public func enqueue(_ change: ICloudSyncChange) throws {
        try change.validate()
        try Self.transactionLock.withLock {
            var snapshot = try load()
            if let index = snapshot.pending.firstIndex(where: { $0.recordID == change.recordID }) {
                let previous = snapshot.pending[index]
                if previous.revisionID == change.revisionID {
                    guard previous == change else { throw ICloudSyncJournalError.revisionPayloadMismatch }
                    return
                }
                snapshot.pending[index] = change
            } else {
                guard snapshot.pending.count < Self.maximumRecords else { throw ICloudSyncJournalError.capacityExceeded }
                snapshot.pending.append(change)
            }
            try persist(snapshot)
        }
    }

    /// A send snapshots immutable revisions. Only a confirmed exact revision may
    /// be acknowledged; failed/unknown remote results leave pending data intact.
    @discardableResult public func acknowledge(recordID: ICloudSyncRecordID, revisionID: UUID) throws -> Bool {
        try Self.transactionLock.withLock {
            var snapshot = try load()
            guard let index = snapshot.pending.firstIndex(where: { $0.recordID == recordID && $0.revisionID == revisionID }) else { return false }
            snapshot.pending.remove(at: index)
            try persist(snapshot)
            return true
        }
    }

    public func pendingBatch(limit: Int = 64, maximumPayloadBytes: Int = 8 * 1024 * 1024) throws -> [ICloudSyncChange] {
        guard (1...128).contains(limit), (1...Self.maximumFileBytes).contains(maximumPayloadBytes) else { throw ICloudSyncJournalError.invalidBatch }
        return try Self.transactionLock.withLock {
            let ordered = try load().pending.sorted { $0.recordID.order < $1.recordID.order }
            var result: [ICloudSyncChange] = [], bytes = 0
            for change in ordered.prefix(limit) {
                guard change.payload.count <= maximumPayloadBytes - bytes else {
                    if result.isEmpty { throw ICloudSyncJournalError.batchLimitTooSmall }
                    break
                }
                result.append(change); bytes += change.payload.count
            }
            return result
        }
    }

    private func load() throws -> Snapshot {
        let fd = Darwin.openat(descriptor, filename, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        if fd < 0, errno == ENOENT { return Snapshot(scope: scope, pending: []) }
        guard fd >= 0 else { throw ICloudSyncJournalError.unsafeFile }
        defer { Darwin.close(fd) }
        var info = stat()
        guard Darwin.fstat(fd, &info) == 0, info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG), info.st_nlink == 1,
              info.st_uid == getuid(), info.st_mode & 0o077 == 0 else { throw ICloudSyncJournalError.unsafeFile }
        guard info.st_size > 0, info.st_size <= Self.maximumFileBytes else { throw ICloudSyncJournalError.invalidJournal }
        var bytes = Data(), buffer = [UInt8](repeating: 0, count: 8192)
        while true {
            let count = Darwin.read(fd, &buffer, buffer.count)
            if count < 0, errno == EINTR { continue }
            guard count >= 0, count <= Self.maximumFileBytes - bytes.count else { throw ICloudSyncJournalError.invalidJournal }
            if count == 0 { break }; bytes.append(contentsOf: buffer.prefix(count))
        }
        do {
            let snapshot = try JSONDecoder().decode(Snapshot.self, from: bytes)
            guard snapshot.schemaVersion == 1, snapshot.scope == scope, snapshot.pending.count <= Self.maximumRecords else { throw ICloudSyncJournalError.invalidJournal }
            var records: Set<ICloudSyncRecordID> = []
            for change in snapshot.pending { try change.validate(); guard records.insert(change.recordID).inserted else { throw ICloudSyncJournalError.invalidJournal } }
            return snapshot
        } catch { throw ICloudSyncJournalError.invalidJournal }
    }

    private func persist(_ value: Snapshot) throws {
        var snapshot = value; snapshot.pending.sort { $0.recordID.order < $1.recordID.order }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(snapshot)
        guard bytes.count <= Self.maximumFileBytes else { throw ICloudSyncJournalError.capacityExceeded }
        let temporary = ".icloud-pending-" + UUID().uuidString
        let fd = Darwin.openat(descriptor, temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw ICloudSyncJournalError.persistence }
        defer { Darwin.close(fd); Darwin.unlinkat(descriptor, temporary, 0) }
        try bytes.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let count = Darwin.write(fd, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                if count < 0, errno == EINTR { continue }
                guard count > 0 else { throw ICloudSyncJournalError.persistence }; offset += count
            }
        }
        guard Darwin.fsync(fd) == 0, Darwin.renameat(descriptor, temporary, descriptor, filename) == 0,
              Darwin.fsync(descriptor) == 0 else { throw ICloudSyncJournalError.persistence }
    }

    private static func openDirectory(_ directory: URL) throws -> Int32 {
        guard directory.isFileURL, directory.path.hasPrefix("/") else { throw ICloudSyncJournalError.unsafeFile }
        let components = directory.path.split(separator: "/").map(String.init)
        guard !components.isEmpty, components.allSatisfy({ $0 != "." && $0 != ".." }) else { throw ICloudSyncJournalError.unsafeFile }
        var fd = Darwin.open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard fd >= 0 else { throw ICloudSyncJournalError.persistence }
        for component in components {
            var next = Darwin.openat(fd, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            if next < 0, errno == ENOENT {
                if Darwin.mkdirat(fd, component, 0o700) != 0, errno != EEXIST { Darwin.close(fd); throw ICloudSyncJournalError.persistence }
                next = Darwin.openat(fd, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            }
            Darwin.close(fd)
            guard next >= 0 else { throw ICloudSyncJournalError.unsafeFile }; fd = next
        }
        var info = stat()
        guard Darwin.fstat(fd, &info) == 0, info.st_uid == getuid() else { Darwin.close(fd); throw ICloudSyncJournalError.unsafeFile }
        return fd
    }
}
