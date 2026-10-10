import Foundation
import Darwin

public enum ICloudLibraryJournalBridgeError: Error, Equatable, Sendable {
    case baselineConflict, invalidCheckpoint, unsafeFile, capacityExceeded, persistence
    case invalidResolution
}

/// Only committed document snapshots enter the durable outbox. The checkpoint
/// stays old until every enqueue succeeds; replay retains exact revision ancestry.
/// Lock order: bridge transaction → journal transaction. Neither calls user code.
@MainActor public final class ICloudLibraryJournalBridge {
    private static let transactionLock = NSLock()
    private static let maximumBytes = 64 * 1024 * 1024
    private let journal: ICloudSyncJournal
    private let directory: OwnedDirectory
    private let filename: String
    public let checkpointURL: URL
    public var scope: ICloudSyncScope { journal.scope }

    private struct Checkpoint: Codable {
        var schemaVersion = 1
        let scope: ICloudSyncScope
        let snapshot: LibrarySnapshot
        var resolutions: [ResolutionBase]?
    }
    private struct ResolutionBase: Codable {
        let pageID: UUID, expectedLocalRevision: UUID, resolvedRevision: UUID, remoteRevision: UUID
    }
    private final class OwnedDirectory: @unchecked Sendable {
        let fd: Int32
        init(_ url: URL) throws {
            guard url.isFileURL, url.path.hasPrefix("/") else { throw ICloudLibraryJournalBridgeError.unsafeFile }
            let components = url.path.split(separator: "/").map(String.init)
            guard !components.isEmpty, components.allSatisfy({ $0 != "." && $0 != ".." }) else { throw ICloudLibraryJournalBridgeError.unsafeFile }
            var current = Darwin.open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
            guard current >= 0 else { throw ICloudLibraryJournalBridgeError.persistence }
            for component in components {
                let next = Darwin.openat(current, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                Darwin.close(current)
                guard next >= 0 else { throw ICloudLibraryJournalBridgeError.unsafeFile }
                current = next
            }
            var info = stat()
            guard Darwin.fstat(current, &info) == 0, info.st_uid == getuid() else {
                Darwin.close(current); throw ICloudLibraryJournalBridgeError.unsafeFile
            }
            fd = current
        }
        deinit { Darwin.close(fd) }
    }

    public init(journal: ICloudSyncJournal) throws {
        self.journal = journal
        filename = journal.fileURL.deletingPathExtension().lastPathComponent + ".baseline.json"
        checkpointURL = journal.fileURL.deletingLastPathComponent().appendingPathComponent(filename)
        directory = try OwnedDirectory(journal.fileURL.deletingLastPathComponent())
        _ = try Self.transactionLock.withLock { try load() }
    }

    public func lastProjectedSnapshot() throws -> LibrarySnapshot? {
        try Self.transactionLock.withLock { try load()?.snapshot }
    }

    /// Reserve the chosen server ancestry before committing the local resolution.
    /// Crash replay of normal projection then uses that exact base, rather than
    /// silently treating the old divergent local revision as the server parent.
    public func preparePageResolution(pageID: UUID, expectedLocalRevision: UUID,
                                      resolvedRevision: UUID, remoteRevision: UUID) throws {
        try Self.transactionLock.withLock {
            guard var stored = try load(), let local = stored.snapshot.pages.first(where: { $0.id == pageID }),
                  local.revision == expectedLocalRevision, resolvedRevision != expectedLocalRevision,
                  resolvedRevision != remoteRevision,
                  !stored.snapshot.pages.contains(where: { $0.revision == resolvedRevision }),
                  !stored.snapshot.revisions.contains(where: { $0.id == resolvedRevision }) else { throw ICloudLibraryJournalBridgeError.invalidResolution }
            var pending = stored.resolutions ?? []
            if let index = pending.firstIndex(where: { $0.pageID == pageID }) {
                // Binding retry reconciles the durable document first. A failed
                // commit's reservation absent from that baseline may be replaced.
                let old = pending[index]
                guard !stored.snapshot.revisions.contains(where: { $0.id == old.resolvedRevision }),
                      local.revision != old.resolvedRevision else { throw ICloudLibraryJournalBridgeError.invalidResolution }
                pending.remove(at: index)
            }
            pending.append(ResolutionBase(pageID: pageID, expectedLocalRevision: expectedLocalRevision,
                resolvedRevision: resolvedRevision, remoteRevision: remoteRevision))
            guard pending.count <= 4096, Set(pending.map(\.resolvedRevision)).count == pending.count else { throw ICloudLibraryJournalBridgeError.invalidResolution }
            stored.resolutions = pending; try persist(stored)
        }
    }

    /// Explicit account activation calls this once; absence of a checkpoint means
    /// all current document records need their initial upload, not an empty queue.
    @discardableResult public func bootstrap(_ current: LibrarySnapshot) throws -> Int {
        let currentBytes = try Self.snapshotBytes(current)
        return try Self.transactionLock.withLock {
            if let stored = try load() {
                guard try Self.snapshotBytes(stored.snapshot) == currentBytes else { throw ICloudLibraryJournalBridgeError.baselineConflict }
                return 0
            }
            return try commit(previous: LibrarySnapshot(), current: current)
        }
    }

    /// Expected previous bytes fence late callers from another bridge instance.
    /// An already committed exact transition is idempotent, including crash replay.
    @discardableResult public func project(from previous: LibrarySnapshot, to current: LibrarySnapshot) throws -> Int {
        let expected = try Self.snapshotBytes(previous), desired = try Self.snapshotBytes(current)
        return try Self.transactionLock.withLock {
            guard let stored = try load() else { throw ICloudLibraryJournalBridgeError.baselineConflict }
            let actual = try Self.snapshotBytes(stored.snapshot)
            if actual == desired {
                // No local resolution reached the durable document. Retire its
                // unused reservation so a failed commit cannot block receiving.
                if !(stored.resolutions?.isEmpty ?? true) { try persist(Checkpoint(scope: scope, snapshot: current)) }
                return 0
            }
            guard actual == expected else { throw ICloudLibraryJournalBridgeError.baselineConflict }
            return try commit(previous: previous, current: current)
        }
    }

    /// A validated incoming mutation changes the local baseline without creating
    /// an outbound echo. Existing locally queued revisions are retained.
    public func adoptIncoming(from previous: LibrarySnapshot, to current: LibrarySnapshot) throws {
        let expected = try Self.snapshotBytes(previous), desired = try Self.snapshotBytes(current)
        try Self.transactionLock.withLock {
            guard let stored = try load() else { throw ICloudLibraryJournalBridgeError.baselineConflict }
            let actual = try Self.snapshotBytes(stored.snapshot)
            if actual == desired { return }
            guard actual == expected else { throw ICloudLibraryJournalBridgeError.baselineConflict }
            guard stored.resolutions?.isEmpty ?? true else { throw ICloudLibraryJournalBridgeError.invalidResolution }
            try persist(Checkpoint(scope: scope, snapshot: current))
        }
    }
    private func commit(previous: LibrarySnapshot, current: LibrarySnapshot) throws -> Int {
        let reservations = try load()?.resolutions ?? []
        var changes = try ICloudLibraryProjection.changes(from: previous, to: current)
        for reservation in reservations {
            guard previous.pages.first(where: { $0.id == reservation.pageID })?.revision == reservation.expectedLocalRevision else { throw ICloudLibraryJournalBridgeError.invalidResolution }
            guard let page = current.pages.first(where: { $0.id == reservation.pageID }) else { throw ICloudLibraryJournalBridgeError.invalidResolution }
            let applied = page.revision == reservation.resolvedRevision || current.revisions.contains {
                $0.id == reservation.resolvedRevision && $0.page.id == reservation.pageID
            }
            if applied {
                guard let index = changes.firstIndex(where: { $0.recordID == ICloudSyncRecordID(kind: .page, id: reservation.pageID) }) else { throw ICloudLibraryJournalBridgeError.invalidResolution }
                changes[index] = ICloudSyncChange(recordID: .init(kind: .page, id: page.id), revisionID: page.revision,
                    operation: .upsert, payload: try ICloudPagePayload(page: page, baseRevision: reservation.remoteRevision).encoded())
            }
        }
        for change in changes { try journal.enqueue(change) }
        // A partial enqueue or failed checkpoint never pretends the baseline moved.
        try persist(Checkpoint(scope: scope, snapshot: current))
        return changes.count
    }
    private static func snapshotBytes(_ snapshot: LibrarySnapshot) throws -> Data {
        try LibraryStore.validate(snapshot)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(snapshot)
        guard data.count <= maximumBytes else { throw ICloudLibraryJournalBridgeError.capacityExceeded }
        return data
    }

    private func load() throws -> Checkpoint? {
        let fd = Darwin.openat(directory.fd, filename, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        if fd < 0, errno == ENOENT { return nil }
        guard fd >= 0 else { throw ICloudLibraryJournalBridgeError.unsafeFile }
        defer { Darwin.close(fd) }
        var info = stat()
        guard Darwin.fstat(fd, &info) == 0, info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG), info.st_nlink == 1,
              info.st_uid == getuid(), info.st_mode & 0o077 == 0 else { throw ICloudLibraryJournalBridgeError.unsafeFile }
        guard info.st_size > 0, info.st_size <= Self.maximumBytes else { throw ICloudLibraryJournalBridgeError.invalidCheckpoint }
        var bytes = Data(), buffer = [UInt8](repeating: 0, count: 8192)
        while true {
            let count = Darwin.read(fd, &buffer, buffer.count)
            if count < 0, errno == EINTR { continue }
            guard count >= 0, count <= Self.maximumBytes - bytes.count else { throw ICloudLibraryJournalBridgeError.invalidCheckpoint }
            if count == 0 { break }; bytes.append(contentsOf: buffer.prefix(count))
        }
        do {
            let checkpoint = try JSONDecoder().decode(Checkpoint.self, from: bytes)
            guard checkpoint.schemaVersion == 1, checkpoint.scope == scope else { throw ICloudLibraryJournalBridgeError.invalidCheckpoint }
            _ = try Self.snapshotBytes(checkpoint.snapshot)
            let reservations = checkpoint.resolutions ?? []
            guard reservations.count <= 4096, Set(reservations.map(\.pageID)).count == reservations.count,
                  Set(reservations.map(\.resolvedRevision)).count == reservations.count,
                  reservations.allSatisfy({ reservation in
                      checkpoint.snapshot.pages.contains { $0.id == reservation.pageID && $0.revision == reservation.expectedLocalRevision } &&
                      !checkpoint.snapshot.pages.contains { $0.revision == reservation.resolvedRevision } &&
                      !checkpoint.snapshot.revisions.contains { $0.id == reservation.resolvedRevision } &&
                      reservation.resolvedRevision != reservation.expectedLocalRevision && reservation.resolvedRevision != reservation.remoteRevision
                  }) else { throw ICloudLibraryJournalBridgeError.invalidCheckpoint }
            return checkpoint
        } catch { throw ICloudLibraryJournalBridgeError.invalidCheckpoint }
    }

    private func persist(_ checkpoint: Checkpoint) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(checkpoint)
        guard bytes.count <= Self.maximumBytes else { throw ICloudLibraryJournalBridgeError.capacityExceeded }
        let temporary = ".icloud-baseline-" + UUID().uuidString
        let fd = Darwin.openat(directory.fd, temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw ICloudLibraryJournalBridgeError.persistence }
        defer { Darwin.close(fd); Darwin.unlinkat(directory.fd, temporary, 0) }
        try bytes.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let count = Darwin.write(fd, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                if count < 0, errno == EINTR { continue }
                guard count > 0 else { throw ICloudLibraryJournalBridgeError.persistence }; offset += count
            }
        }
        guard Darwin.fsync(fd) == 0, Darwin.renameat(directory.fd, temporary, directory.fd, filename) == 0,
              Darwin.fsync(directory.fd) == 0 else { throw ICloudLibraryJournalBridgeError.persistence }
    }
}
