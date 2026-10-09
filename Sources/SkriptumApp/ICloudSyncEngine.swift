import Foundation
import CloudKit
import CryptoKit
import Darwin
#if canImport(SkriptumCore)
import SkriptumCore
#endif

enum ICloudSyncEngineError: Error { case invalidConfiguration, accountUnavailable, accountChanged, invalidRecord, capacity, storage, stopped }
enum ICloudSyncEngineStatus: Sendable, Equatable { case inactive, active, accountChanged, storageUnavailable, cloudUnavailable }

/// Explicitly activated private-database transport. It never applies inbox data
/// to LibraryStore, edits documents, or transfers provider credentials.
actor ICloudSyncEngine: CKSyncEngineDelegate {
    struct Incoming: Codable, Sendable {
        let recordName: String
        let change: ICloudSyncChange?
        // Physical CloudKit deletion lacks a revision; merge must not invent one.
        let physicalDeletion: Bool
    }
    private struct Snapshot: Codable {
        var schemaVersion = 1
        let scope: ICloudSyncScope
        let containerIdentifier: String
        var state: Data?
        var inbox: [Incoming] = []
        var systemFields: [String: Data] = [:]
        var conflicts: Set<String> = []
        var confirmedImages: [String: String]?
    }
    private let journal: ICloudSyncJournal
    private let containerIdentifier: String
    private let files: Files
    private var snapshot: Snapshot
    private var engine: CKSyncEngine?
    private var generation = UUID()
    private var stopping = false
    private var inFlight: [CKRecord.ID: ICloudSyncChange] = [:]
    private var assetFiles: [CKRecord.ID: String] = [:]
    private(set) var status = ICloudSyncEngineStatus.inactive
    private var zoneID: CKRecordZone.ID {
        CKRecordZone.ID(zoneName: "Scriptum-" + journal.scope.libraryID.uuidString.lowercased(), ownerName: CKCurrentUserDefaultName)
    }

    init(containerIdentifier: String, journal: ICloudSyncJournal, directory: URL) throws {
        guard containerIdentifier.hasPrefix("iCloud."), (8...256).contains(containerIdentifier.utf8.count),
              containerIdentifier.utf8.allSatisfy({ ($0 >= 48 && $0 <= 57) || ($0 >= 65 && $0 <= 90) || ($0 >= 97 && $0 <= 122) || $0 == 46 || $0 == 45 }) else {
            throw ICloudSyncEngineError.invalidConfiguration
        }
        self.containerIdentifier = containerIdentifier; self.journal = journal
        var identity = Data(journal.scope.accountID.utf8); identity.append(0); identity.append(contentsOf: journal.scope.libraryID.uuidString.utf8); identity.append(0); identity.append(contentsOf: containerIdentifier.utf8)
        files = try Files(directory: directory, name: "icloud-engine-" + Self.digest(identity) + ".json")
        if let data = try files.read() {
            let loaded = try JSONDecoder().decode(Snapshot.self, from: data)
            guard loaded.schemaVersion == 1, loaded.scope == journal.scope, loaded.containerIdentifier == containerIdentifier,
                  loaded.inbox.count <= 4096, loaded.systemFields.count <= 4096,
                  loaded.state.map({ $0.count <= 1024 * 1024 }) ?? true else { throw ICloudSyncEngineError.storage }
            snapshot = loaded
        } else { snapshot = Snapshot(scope: journal.scope, containerIdentifier: containerIdentifier) }
    }

    /// Caller must have provisioned the container and obtained explicit opt-in.
    /// A different iCloud account requires a new account-scoped journal/adapter.
    func activate() async throws {
        guard !stopping else { throw ICloudSyncEngineError.stopped }
        guard engine == nil else { return }
        let attempt = UUID(); generation = attempt
        let container = CKContainer(identifier: containerIdentifier)
        guard try await container.accountStatus() == .available else { throw ICloudSyncEngineError.accountUnavailable }
        let user = try await container.userRecordID()
        guard generation == attempt else { throw ICloudSyncEngineError.stopped }
        guard user.recordName.utf8.elementsEqual(journal.scope.accountID.utf8) else { throw ICloudSyncEngineError.accountChanged }
        let state = try snapshot.state.map { try JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: $0) }
        var configuration = CKSyncEngine.Configuration(database: container.privateCloudDatabase, stateSerialization: state, delegate: self)
        configuration.automaticallySync = false
        let created = CKSyncEngine(configuration)
        engine = created; status = .active
        created.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])
        try queuePending(created)
    }

    func synchronize() async throws {
        guard let active = engine else { throw ICloudSyncEngineError.stopped }
        let captured = generation
        try queuePending(active)
        try await active.sendChanges()
        guard generation == captured, engine === active else { throw ICloudSyncEngineError.stopped }
        try await active.fetchChanges(.init(scope: .zoneIDs([zoneID])))
    }

    func stop() async {
        guard !stopping else { return }
        generation = UUID(); status = .inactive
        let previous = engine; engine = nil; stopping = true
        await previous?.cancelOperations()
        clearAssets(); stopping = false
    }
    /// Receipts belong to this exact account/library/container namespace.
    func enqueueImageIfNeeded(_ change: ICloudSyncChange) throws -> Bool {
        guard change.recordID.kind == .image, change.operation == .upsert else { throw ICloudSyncEngineError.invalidRecord }
        let name = recordID(change.recordID).recordName
        if snapshot.confirmedImages?[name] == Self.digest(change.payload) { return false }
        try journal.enqueue(change)
        return true
    }
    func incomingSnapshot() -> [Incoming] { snapshot.inbox }
    func unresolvedConflictCount() -> Int { snapshot.conflicts.count }
    /// Root merge calls this only after its own durable revision-bound mutation.
    func acknowledgeIncoming(recordID: ICloudSyncRecordID, revisionID: UUID) throws {
        let name = self.recordID(recordID).recordName
        var next = snapshot
        next.inbox.removeAll { $0.recordName == name && $0.change?.revisionID == revisionID }
        try persist(next)
    }
    /// Explicit merge resolution, never automatic server-conflict overwrite.
    func resolveConflict(recordID: ICloudSyncRecordID) throws {
        var next = snapshot; next.conflicts.remove(self.recordID(recordID).recordName)
        try persist(next)
    }
    #if DEBUG && SWIFT_PACKAGE
    func verificationRetainIncoming(_ records: [CKRecord]) throws { try retainIncoming(records, deletions: []) }
    func verificationTrackSent(_ change: ICloudSyncChange) throws {
        guard try journal.pendingChange(recordID: change.recordID) == change else { throw ICloudSyncEngineError.invalidRecord }
        inFlight[recordID(change.recordID)] = change
    }
    func verificationHandleSaved(_ records: [CKRecord]) throws { try handleSaved(records) }
    #endif

    private func queuePending(_ active: CKSyncEngine) throws {
        let pending = try journal.pendingBatch(limit: 64, maximumPayloadBytes: 64 * 1024 * 1024)
        active.state.add(pendingRecordZoneChanges: pending.map { .saveRecord(recordID($0.recordID)) })
    }
    private func recordID(_ id: ICloudSyncRecordID) -> CKRecord.ID {
        CKRecord.ID(recordName: id.kind.rawValue + ":" + id.id.uuidString.lowercased(), zoneID: zoneID)
    }
    private func parseID(_ id: CKRecord.ID) throws -> ICloudSyncRecordID {
        let parts = id.recordName.split(separator: ":", omittingEmptySubsequences: false)
        guard id.zoneID == zoneID, parts.count == 2, let kind = ICloudSyncRecordKind(rawValue: String(parts[0])),
              let uuid = UUID(uuidString: String(parts[1])), uuid.uuidString.lowercased() == parts[1] else { throw ICloudSyncEngineError.invalidRecord }
        return ICloudSyncRecordID(kind: kind, id: uuid)
    }

    func nextRecordZoneChangeBatch(_ context: CKSyncEngine.SendChangesContext, syncEngine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
        guard engine === syncEngine else { return nil }
        do {
            let changes = try journal.pendingBatch(limit: 64, maximumPayloadBytes: 64 * 1024 * 1024)
            var records: [CKRecord] = []
            for change in changes {
                let id = recordID(change.recordID)
                guard context.options.scope.contains(.saveRecord(id)), inFlight[id] == nil, !snapshot.conflicts.contains(id.recordName) else { continue }
                let record: CKRecord
                if let data = snapshot.systemFields[id.recordName] {
                    let decoder = try NSKeyedUnarchiver(forReadingFrom: data); decoder.requiresSecureCoding = true
                    guard let restored = CKRecord(coder: decoder), restored.recordID == id else { throw ICloudSyncEngineError.invalidRecord }
                    decoder.finishDecoding(); record = restored
                } else { record = CKRecord(recordType: "ScriptumItemV1", recordID: id) }
                record["libraryID"] = journal.scope.libraryID.uuidString.lowercased() as CKRecordValue
                record["kind"] = change.recordID.kind.rawValue as CKRecordValue
                record["uuid"] = change.recordID.id.uuidString.lowercased() as CKRecordValue
                record["revision"] = change.revisionID.uuidString.lowercased() as CKRecordValue
                record["operation"] = change.operation.rawValue as CKRecordValue
                record["sha256"] = Self.digest(change.payload) as CKRecordValue
                if change.operation == .upsert {
                    let name = "asset-" + UUID().uuidString
                    try files.writeAsset(change.payload, name: name)
                    record["payload"] = CKAsset(fileURL: files.directory.appendingPathComponent(name))
                    assetFiles[id] = name
                } else { record["payload"] = nil }
                inFlight[id] = change; records.append(record)
            }
            return records.isEmpty ? nil : CKSyncEngine.RecordZoneChangeBatch(recordsToSave: records)
        } catch { await storageFailed(); return nil }
    }

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        guard engine === syncEngine else { return }
        do {
            switch event {
            case .stateUpdate(let update):
                // Fetched callbacks persist their inbox synchronously before return.
                var next = snapshot
                next.state = try JSONEncoder().encode(update.stateSerialization)
                guard next.state!.count <= 1024 * 1024 else { throw ICloudSyncEngineError.capacity }
                try persist(next)
            case .accountChange(let change):
                switch change.changeType {
                case .signIn(let user) where user.recordName.utf8.elementsEqual(journal.scope.accountID.utf8): break
                default:
                    generation = UUID(); engine = nil; status = .accountChanged; stopping = true
                    await syncEngine.cancelOperations(); clearAssets(); stopping = false
                }
            case .fetchedRecordZoneChanges(let changes):
                try retainIncoming(changes.modifications.map(\.record), deletions: changes.deletions)
            case .sentRecordZoneChanges(let changes):
                try handleSaved(changes.savedRecords)
                for failure in changes.failedRecordSaves {
                    // Preserve the local queue. Retain a server conflict revision
                    // in inbox so merge can resolve it without overwrite.
                    if let server = failure.error.serverRecord {
                        try retainIncoming([server], deletions: [])
                        var next = snapshot; next.conflicts.insert(server.recordID.recordName)
                        try persist(next)
                    }
                    releaseAsset(failure.record.recordID)
                }
                try queuePending(syncEngine)
            case .fetchedDatabaseChanges(let changes):
                if changes.deletions.contains(where: { $0.zoneID == zoneID }) { throw ICloudSyncEngineError.invalidRecord }
            case .sentDatabaseChanges(let changes):
                if !changes.failedZoneSaves.isEmpty || !changes.failedZoneDeletes.isEmpty { status = .cloudUnavailable }
            default: break
            }
        } catch { await storageFailed() }
    }

    private func handleSaved(_ records: [CKRecord]) throws {
        for record in records {
            let id = try parseID(record.recordID)
            guard let change = inFlight[record.recordID], change.recordID == id,
                  record.recordType == "ScriptumItemV1",
                  record["libraryID"] as? String == journal.scope.libraryID.uuidString.lowercased(),
                  record["kind"] as? String == id.kind.rawValue,
                  record["uuid"] as? String == id.id.uuidString.lowercased(),
                  record["revision"] as? String == change.revisionID.uuidString.lowercased(),
                  record["operation"] as? String == change.operation.rawValue,
                  record["sha256"] as? String == Self.digest(change.payload) else {
                throw ICloudSyncEngineError.invalidRecord
            }
            // CloudKit may return only saved metadata; the immutable sent bytes
            // remain owned locally. Incoming decode still requires its asset.
            var next = snapshot; next.systemFields[record.recordID.recordName] = try systemFields(record)
            if change.recordID.kind == .image, change.operation == .upsert {
                var receipts = next.confirmedImages ?? [:]
                receipts[record.recordID.recordName] = Self.digest(change.payload)
                next.confirmedImages = receipts
            }
            try persist(next)
            _ = try journal.acknowledge(recordID: change.recordID, revisionID: change.revisionID)
            releaseAsset(record.recordID)
        }
    }

    private func retainIncoming(_ records: [CKRecord], deletions: [CKDatabase.RecordZoneChange.Deletion]) throws {
        var next = snapshot
        for record in records {
            guard record.recordID.zoneID == zoneID else { throw ICloudSyncEngineError.invalidRecord }
            if record is CKShare {
                next.systemFields[record.recordID.recordName] = try systemFields(record)
                continue
            }
            if record.recordType == "ScriptumSharedImageV1" {
                try validateOwnedImageAlias(record)
                // Owners already receive the canonical image record. Aliases
                // belong to participant transport, not a second document inbox.
                next.systemFields[record.recordID.recordName] = try systemFields(record)
                continue
            }
            let change = try decode(record)
            let entry = Incoming(recordName: record.recordID.recordName, change: change, physicalDeletion: false)
            if let existing = next.inbox.first(where: { $0.recordName == entry.recordName && $0.change?.revisionID == change.revisionID }) {
                guard existing.change == change else { throw ICloudSyncEngineError.invalidRecord }
            } else { next.inbox.append(entry) }
            if let pending = try journal.pendingChange(recordID: change.recordID), pending.revisionID != change.revisionID { next.conflicts.insert(entry.recordName) }
            next.systemFields[entry.recordName] = try systemFields(record)
        }
        for deletion in deletions {
            guard deletion.recordID.zoneID == zoneID else { throw ICloudSyncEngineError.invalidRecord }
            if deletion.recordType == CKRecord.SystemType.share || deletion.recordType == "ScriptumSharedImageV1" {
                next.systemFields.removeValue(forKey: deletion.recordID.recordName)
                continue
            }
            _ = try parseID(deletion.recordID)
            guard deletion.recordType == "ScriptumItemV1" else { throw ICloudSyncEngineError.invalidRecord }
            if !next.inbox.contains(where: { $0.recordName == deletion.recordID.recordName && $0.physicalDeletion }) {
                next.inbox.append(Incoming(recordName: deletion.recordID.recordName, change: nil, physicalDeletion: true))
            }
            next.systemFields.removeValue(forKey: deletion.recordID.recordName)
            next.conflicts.insert(deletion.recordID.recordName)
        }
        // All borrowed assets are copied into owned durable payload bytes before
        // this delegate callback returns; later stateUpdate can now advance.
        try persist(next)
    }

    private func validateOwnedImageAlias(_ record: CKRecord) throws {
        let parts = record.recordID.recordName.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 4, parts[0] == "shared-image", parts[1] == "page" || parts[1] == "space",
              let root = UUID(uuidString: String(parts[2])), root.uuidString.lowercased() == parts[2],
              let image = UUID(uuidString: String(parts[3])), image.uuidString.lowercased() == parts[3],
              record["libraryID"] as? String == journal.scope.libraryID.uuidString.lowercased(),
              record["kind"] as? String == "image", record["uuid"] as? String == image.uuidString.lowercased(),
              record["sourceRecordName"] as? String == "image:" + image.uuidString.lowercased(),
              record.parent?.recordID == CKRecord.ID(recordName: String(parts[1]) + ":" + String(parts[2]), zoneID: zoneID) else {
            throw ICloudSyncEngineError.invalidRecord
        }
    }

    private func decode(_ record: CKRecord) throws -> ICloudSyncChange {
        let id = try parseID(record.recordID)
        guard record.recordType == "ScriptumItemV1", record["libraryID"] as? String == journal.scope.libraryID.uuidString.lowercased(),
              record["kind"] as? String == id.kind.rawValue, record["uuid"] as? String == id.id.uuidString.lowercased(),
              let revisionString = record["revision"] as? String, let revision = UUID(uuidString: revisionString),
              revision.uuidString.lowercased() == revisionString,
              let operationString = record["operation"] as? String, let operation = ICloudSyncOperation(rawValue: operationString) else { throw ICloudSyncEngineError.invalidRecord }
        let payload: Data
        if operation == .upsert {
            guard let asset = record["payload"] as? CKAsset, let url = asset.fileURL else { throw ICloudSyncEngineError.invalidRecord }
            payload = try Files.readAsset(url, maximum: id.kind == .image ? ICloudImagePayload.maximumEncodedBytes : 8 * 1024 * 1024)
        } else {
            guard record["payload"] == nil else { throw ICloudSyncEngineError.invalidRecord }
            payload = Data()
        }
        guard record["sha256"] as? String == Self.digest(payload) else { throw ICloudSyncEngineError.invalidRecord }
        return ICloudSyncChange(recordID: id, revisionID: revision, operation: operation, payload: payload)
    }
    private func systemFields(_ record: CKRecord) throws -> Data {
        let encoder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: encoder); encoder.finishEncoding()
        guard encoder.encodedData.count <= 131072 else { throw ICloudSyncEngineError.capacity }
        return encoder.encodedData
    }
    private func persist(_ next: Snapshot) throws {
        guard next.inbox.count <= 4096, next.systemFields.count <= 4096, next.conflicts.count <= 4096 else { throw ICloudSyncEngineError.capacity }
        let data = try JSONEncoder().encode(next)
        try files.write(data); snapshot = next
    }
    private func storageFailed() async {
        generation = UUID(); status = .storageUnavailable
        let previous = engine; engine = nil
        await previous?.cancelOperations(); clearAssets()
    }
    private func releaseAsset(_ id: CKRecord.ID) {
        inFlight.removeValue(forKey: id)
        if let name = assetFiles.removeValue(forKey: id) { files.removeAsset(name) }
    }
    private func clearAssets() { for id in Array(inFlight.keys) { releaseAsset(id) } }
    private static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    /// Private owned-directory descriptor; no enumeration or user-selected paths.
    final class Files: @unchecked Sendable {
        let directory: URL
        let descriptor: Int32
        let name: String
        static let maximumBytes = 64 * 1024 * 1024
        init(directory: URL, name: String) throws {
            self.directory = directory; self.name = name
            var current = Darwin.open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
            guard current >= 0 else { throw ICloudSyncEngineError.storage }
            let parts = directory.path.split(separator: "/").map(String.init)
            guard directory.isFileURL, !parts.isEmpty, parts.allSatisfy({ $0 != "." && $0 != ".." }) else { Darwin.close(current); throw ICloudSyncEngineError.storage }
            for (index, part) in parts.enumerated() {
                var next = Darwin.openat(current, part, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                if next < 0, errno == ENOENT, index == parts.count - 1 {
                    if Darwin.mkdirat(current, part, 0o700) != 0 { Darwin.close(current); throw ICloudSyncEngineError.storage }
                    next = Darwin.openat(current, part, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                }
                Darwin.close(current)
                guard next >= 0 else { throw ICloudSyncEngineError.storage }; current = next
            }
            var info = stat()
            guard Darwin.fstat(current, &info) == 0, info.st_uid == getuid(), info.st_mode & 0o077 == 0 else { Darwin.close(current); throw ICloudSyncEngineError.storage }
            descriptor = current
        }
        deinit { Darwin.close(descriptor) }
        func read() throws -> Data? {
            let fd = Darwin.openat(descriptor, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
            if fd < 0, errno == ENOENT { return nil }
            guard fd >= 0 else { throw ICloudSyncEngineError.storage }
            defer { Darwin.close(fd) }
            return try Self.read(fd, maximum: Self.maximumBytes)
        }
        static func readAsset(_ url: URL, maximum: Int) throws -> Data {
            guard url.isFileURL else { throw ICloudSyncEngineError.invalidRecord }
            let fd = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
            guard fd >= 0 else { throw ICloudSyncEngineError.storage }
            defer { Darwin.close(fd) }
            return try read(fd, maximum: maximum)
        }
        private static func read(_ fd: Int32, maximum: Int) throws -> Data {
            var info = stat()
            guard Darwin.fstat(fd, &info) == 0, info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG), info.st_size >= 0, info.st_size <= maximum else { throw ICloudSyncEngineError.storage }
            var data = Data(), buffer = [UInt8](repeating: 0, count: 65536)
            while true {
                let count = Darwin.read(fd, &buffer, buffer.count)
                if count < 0, errno == EINTR { continue }
                guard count >= 0, count <= maximum - data.count else { throw ICloudSyncEngineError.storage }
                if count == 0 { return data }; data.append(contentsOf: buffer.prefix(count))
            }
        }
        func write(_ data: Data) throws {
            guard data.count <= Self.maximumBytes else { throw ICloudSyncEngineError.capacity }
            let temporary = ".engine-" + UUID().uuidString
            try writeAsset(data, name: temporary)
            defer { Darwin.unlinkat(descriptor, temporary, 0) }
            guard Darwin.renameat(descriptor, temporary, descriptor, name) == 0, Darwin.fsync(descriptor) == 0 else { throw ICloudSyncEngineError.storage }
        }
        func writeAsset(_ data: Data, name: String) throws {
            let fd = Darwin.openat(descriptor, name, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
            guard fd >= 0 else { throw ICloudSyncEngineError.storage }
            var completed = false
            defer { Darwin.close(fd); if !completed { Darwin.unlinkat(descriptor, name, 0) } }
            try data.withUnsafeBytes { bytes in
                var offset = 0
                while offset < bytes.count {
                    let count = Darwin.write(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                    if count < 0, errno == EINTR { continue }
                    guard count > 0 else { throw ICloudSyncEngineError.storage }; offset += count
                }
            }
            guard Darwin.fsync(fd) == 0 else { throw ICloudSyncEngineError.storage }
            completed = true
        }
        func removeAsset(_ name: String) { Darwin.unlinkat(descriptor, name, 0) }
    }
}
