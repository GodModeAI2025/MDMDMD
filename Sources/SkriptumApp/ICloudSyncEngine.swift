import Foundation
import CloudKit
import CryptoKit
import Darwin
#if canImport(SkriptumCore)
import SkriptumCore
#endif

enum ICloudSyncEngineError: Error { case invalidConfiguration, accountUnavailable, accountChanged, invalidRecord, capacity, storage, stopped }
enum ICloudSyncEngineStatus: Sendable, Equatable { case inactive, active, accountChanged, storageUnavailable, cloudUnavailable }

/// A cached native hierarchy is only a hint. The owner transport must confirm
/// these same links and the current owner role before adding new metadata.
enum ICloudOwnerMetadataParent {
    struct Link: Sendable, Equatable {
        let id: CKRecord.ID
        let parent: CKRecord.ID?
        let share: CKRecord.ID?
        init(id: CKRecord.ID, parent: CKRecord.ID? = nil, share: CKRecord.ID? = nil) {
            self.id = id; self.parent = parent; self.share = share
        }
        init(_ record: CKRecord) throws {
            guard record.recordType == "ScriptumItemV1" else { throw ICloudSyncEngineError.invalidRecord }
            self.init(id: record.recordID, parent: record.parent?.recordID, share: record.share?.recordID)
        }
    }
    struct Request: Sendable, Equatable {
        let page: CKRecord.ID
        let root: CKRecord.ID
        let share: CKRecord.ID
        var ancestors: [CKRecord.ID] = []
    }

    static func pageID(for change: ICloudSyncChange) throws -> UUID? {
        guard change.operation == .upsert else { return nil }
        switch change.recordID.kind {
        case .comment:
            let payload = try ICloudMetadataPayload<Comment>.decode(change.payload)
            guard payload.value.id == change.recordID.id, try payload.revisionID() == change.revisionID else {
                throw ICloudSyncEngineError.invalidRecord
            }
            return payload.value.pageID
        case .revision:
            let payload = try ICloudMetadataPayload<Revision>.decode(change.payload)
            guard payload.value.id == change.recordID.id, payload.baseDigest == nil,
                  try payload.revisionID() == change.revisionID else { throw ICloudSyncEngineError.invalidRecord }
            return payload.value.page.id
        default: return nil
        }
    }

    static func request(pageID: UUID, zone: CKRecordZone.ID,
                        cached: (CKRecord.ID) throws -> Link?) throws -> Request? {
        let id = CKRecord.ID(recordName: "page:" + pageID.uuidString.lowercased(), zoneID: zone)
        guard let page = try cached(id) else { return nil }
        guard page.id == id else { throw ICloudSyncEngineError.invalidRecord }
        if page.parent == nil, page.share == nil { return nil }
        var chain = [page], visited: Set<CKRecord.ID> = [id]
        while let parent = chain.last?.parent {
            try validateRoot(parent, zone: zone)
            guard chain.count < 4096, visited.insert(parent).inserted,
                  let link = try cached(parent), link.id == parent else { throw ICloudSyncEngineError.invalidRecord }
            chain.append(link)
        }
        guard let root = chain.last, let share = root.share, share.zoneID == zone,
              chain.allSatisfy({ $0.share == nil || $0.share == share }) else { throw ICloudSyncEngineError.invalidRecord }
        return Request(page: id, root: root.id, share: share, ancestors: Array(chain.dropFirst().dropLast().map(\.id)))
    }

    /// Native read-only fields are passed explicitly so negative tests do not
    /// forge CKRecord.share or CKShare.currentUserParticipant with private APIs.
    static func validate(_ request: Request, page: Link, root: Link, ancestors: [Link] = [],
                         shareID: CKRecord.ID, isOwner: Bool, isPrivate: Bool) throws {
        try validateRoot(request.root, zone: request.page.zoneID)
        guard isOwner, isPrivate, request.share == shareID, shareID.zoneID == request.page.zoneID,
              page.id == request.page, root.id == request.root, root.parent == nil,
              root.share == request.share, ancestors.map(\.id) == request.ancestors else { throw ICloudSyncEngineError.invalidRecord }
        let chain = request.page == request.root ? [page] : [page] + ancestors + [root]
        guard chain.count <= 4096, Set(chain.map(\.id)).count == chain.count else { throw ICloudSyncEngineError.invalidRecord }
        for (index, link) in chain.enumerated() {
            try validateRoot(link.id, zone: request.page.zoneID)
            let parent = index + 1 < chain.count ? chain[index + 1].id : nil
            guard link.parent == parent, link.share == nil || link.share == request.share else { throw ICloudSyncEngineError.invalidRecord }
        }
    }

    static func validateRoot(_ id: CKRecord.ID, zone: CKRecordZone.ID) throws {
        let parts = id.recordName.split(separator: ":", omittingEmptySubsequences: false)
        guard id.zoneID == zone, parts.count == 2, parts[0] == "page" || parts[0] == "space",
              let uuid = UUID(uuidString: String(parts[1])), uuid.uuidString.lowercased() == parts[1] else {
            throw ICloudSyncEngineError.invalidRecord
        }
    }
}

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
    private var inFlightParents: [CKRecord.ID: CKRecord.ID] = [:]
    private var assetFiles: [CKRecord.ID: String] = [:]
    private(set) var status = ICloudSyncEngineStatus.inactive
    private(set) var lastFailure: ICloudFailureDiagnostic?
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
        files = try Files(directory: directory, name: "icloud-engine-" + Self.digest(identity) + ".json", maximumFileBytes: 128 * 1024 * 1024)
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
        try ICloudAccountAvailability.require(try await container.accountStatus())
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
        lastFailure = nil
        if status == .cloudUnavailable { status = .active }
        try queuePending(active)
        do { try await active.sendChanges() }
        catch {
            if let lastFailure { throw ICloudTransportFailure(diagnostic: lastFailure) }
            throw error
        }
        if let lastFailure { throw ICloudTransportFailure(diagnostic: lastFailure) }
        guard generation == captured, engine === active else { throw ICloudSyncEngineError.stopped }
        do { try await active.fetchChanges(.init(scope: .zoneIDs([zoneID]))) }
        catch {
            if let lastFailure { throw ICloudTransportFailure(diagnostic: lastFailure) }
            throw error
        }
        if let lastFailure { throw ICloudTransportFailure(diagnostic: lastFailure) }
        guard status == .active else { throw ICloudSyncEngineError.storage }
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
    func latestPageConflictChanges() -> [ICloudSyncChange] {
        var latest: [String: Incoming] = [:]
        for input in snapshot.inbox { latest[input.recordName] = input }
        return latest.values.compactMap { input in
            guard !input.physicalDeletion, let change = input.change, change.recordID.kind == .page, change.operation == .upsert else { return nil }
            return change
        }
    }
    func refreshForConflictReview() async throws {
        guard status == .active, let active = engine else { throw ICloudSyncEngineError.stopped }
        let attempt = generation
        try await active.fetchChanges(.init(scope: .zoneIDs([zoneID])))
        guard generation == attempt, engine === active, status == .active else { throw ICloudSyncEngineError.stopped }
    }
    func completePageConflictResolution(scope: ICloudSyncScope, expected: ICloudSyncChange, resolvedRevision: UUID) throws {
        guard scope == journal.scope, status == .active, engine != nil, inFlight.isEmpty else { throw ICloudPageConflictError.unavailable }
        let name = recordID(expected.recordID).recordName
        let latest = snapshot.inbox.last { $0.recordName == name }
        try ICloudPageConflict.admitCompletion(scope: scope, expectedScope: journal.scope, expected: expected, latest: latest?.physicalDeletion == false ? latest?.change : nil,
            queued: journal.pendingChange(recordID: expected.recordID), resolvedRevision: resolvedRevision)
        var next = snapshot
        next.inbox.removeAll { $0.recordName == name }; next.conflicts.remove(name)
        try persist(next)
    }
    func unresolvedConflictCount() -> Int { snapshot.conflicts.count }
    /// Serialized owner creation has validated exact local/server document
    /// contents. Replace only optimistic metadata, never document payloads.
    func registerOwnedShareMetadata(_ metadata: [String: Data]) throws {
        guard engine != nil, status == .active, inFlight.isEmpty,
              try journal.pendingCount() == 0, snapshot.inbox.isEmpty, snapshot.conflicts.isEmpty else { throw ICloudSyncEngineError.stopped }
        var next = snapshot
        for (name, data) in metadata {
            let decoder = try NSKeyedUnarchiver(forReadingFrom: data); decoder.requiresSecureCoding = true
            guard let record = CKRecord(coder: decoder), record.recordID.zoneID == zoneID, record.recordID.recordName == name,
                  record.recordType == "ScriptumItemV1" || record.recordType == "ScriptumSharedImageV1" else { throw ICloudSyncEngineError.invalidRecord }
            decoder.finishDecoding(); next.systemFields[name] = data
        }
        try persist(next)
    }
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
    func verificationFailCallback(_ error: any Error) async { await storageFailed(error) }
    func verificationOutgoingRecord(_ change: ICloudSyncChange,
        parentLookup: @Sendable (UUID) async throws -> CKRecord.ID?) async throws -> CKRecord {
        try await makeOutgoingRecord(change, parentLookup: parentLookup)
    }
    func verificationOwnerLookupFailure(_ error: any Error) async {
        await preparationFailed(OwnerParentLookupFailure(underlying: error))
    }
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
        let attempt = generation
        var records: [CKRecord] = []
        do {
            let changes = try journal.pendingBatch(limit: 64, maximumPayloadBytes: 64 * 1024 * 1024)
            for change in changes {
                try requireCurrentEngine(syncEngine, generation: attempt)
                let id = recordID(change.recordID)
                guard context.options.scope.contains(.saveRecord(id)), inFlight[id] == nil, !snapshot.conflicts.contains(id.recordName) else { continue }
                records.append(try await makeOutgoingRecord(change) { [self] pageID in
                    do { return try await ownerMetadataParent(pageID: pageID, active: syncEngine, attempt: attempt) }
                    catch { throw OwnerParentLookupFailure(underlying: error) }
                })
                try requireCurrentEngine(syncEngine, generation: attempt)
            }
            try requireCurrentEngine(syncEngine, generation: attempt)
            // An earlier record may have changed while a later record awaited
            // its share lookup. Do not return that stale batch to CloudKit.
            for record in records {
                guard let sent = inFlight[record.recordID], try journal.pendingChange(recordID: sent.recordID) == sent,
                      !snapshot.conflicts.contains(record.recordID.recordName) else { throw ICloudSyncEngineError.stopped }
            }
            return records.isEmpty ? nil : CKSyncEngine.RecordZoneChangeBatch(recordsToSave: records)
        } catch {
            guard generation == attempt, engine === syncEngine else { return nil }
            for record in records { releaseAsset(record.recordID) }
            await preparationFailed(error)
            return nil
        }
    }

    private func makeOutgoingRecord(_ change: ICloudSyncChange,
        parentLookup: @Sendable (UUID) async throws -> CKRecord.ID?) async throws -> CKRecord {
        let id = recordID(change.recordID)
        let attempt = generation
        guard !stopping, inFlight[id] == nil, !snapshot.conflicts.contains(id.recordName),
              try journal.pendingChange(recordID: change.recordID) == change else { throw ICloudSyncEngineError.stopped }
        let record: CKRecord
        let parent: CKRecord.ID?
        if let restored = try cachedRecord(id) { record = restored; parent = nil }
        else {
            record = CKRecord(recordType: "ScriptumItemV1", recordID: id)
            if let pageID = try ICloudOwnerMetadataParent.pageID(for: change) {
                parent = try await parentLookup(pageID)
                guard generation == attempt, !stopping, inFlight[id] == nil,
                      !snapshot.conflicts.contains(id.recordName), snapshot.systemFields[id.recordName] == nil,
                      try journal.pendingChange(recordID: change.recordID) == change else { throw ICloudSyncEngineError.stopped }
                try Task.checkCancellation()
                if let parent {
                    try ICloudOwnerMetadataParent.validateRoot(parent, zone: zoneID)
                    record.parent = CKRecord.Reference(recordID: parent, action: .none)
                }
            } else { parent = nil }
        }
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
        inFlight[id] = change
        if let parent { inFlightParents[id] = parent }
        return record
    }

    private struct OwnerParentLookupFailure: Error { let underlying: any Error }

    private func preparationFailed(_ error: any Error) async {
        let underlying = (error as? OwnerParentLookupFailure)?.underlying ?? error
        if case ICloudSyncEngineError.stopped = underlying { return }
        if underlying is CancellationError || (underlying as? CKError)?.code == .operationCancelled { return }
        if error is OwnerParentLookupFailure {
            lastFailure = ICloudFailureDiagnostic.describe(underlying)
            status = .cloudUnavailable
        } else { await storageFailed(error) }
    }

    private func cachedRecord(_ id: CKRecord.ID) throws -> CKRecord? {
        guard let data = snapshot.systemFields[id.recordName] else { return nil }
        let decoder = try NSKeyedUnarchiver(forReadingFrom: data); decoder.requiresSecureCoding = true
        defer { decoder.finishDecoding() }
        guard let record = CKRecord(coder: decoder), record.recordID == id,
              record.recordType == "ScriptumItemV1" else { throw ICloudSyncEngineError.invalidRecord }
        return record
    }
    private func ownerMetadataRequest(pageID: UUID) throws -> ICloudOwnerMetadataParent.Request? {
        try ICloudOwnerMetadataParent.request(pageID: pageID, zone: zoneID) { id in
            try cachedRecord(id).map(ICloudOwnerMetadataParent.Link.init)
        }
    }
    private func requireCurrentEngine(_ active: CKSyncEngine, generation attempt: UUID) throws {
        try Task.checkCancellation()
        guard generation == attempt, engine === active, !stopping, status == .active else { throw ICloudSyncEngineError.stopped }
    }
    private func ownerMetadataParent(pageID: UUID, active: CKSyncEngine, attempt: UUID) async throws -> CKRecord.ID? {
        try requireCurrentEngine(active, generation: attempt)
        guard let request = try ownerMetadataRequest(pageID: pageID) else { return nil }
        let container = CKContainer(identifier: containerIdentifier)
        let account = try await container.accountStatus()
        try requireCurrentEngine(active, generation: attempt)
        try ICloudAccountAvailability.require(account)
        let user = try await container.userRecordID()
        try requireCurrentEngine(active, generation: attempt)
        guard user.recordName.utf8.elementsEqual(journal.scope.accountID.utf8) else { throw ICloudSyncEngineError.accountChanged }
        let database = container.privateCloudDatabase
        let page = try await database.record(for: request.page)
        try requireCurrentEngine(active, generation: attempt)
        let root: CKRecord
        if request.root == request.page { root = page }
        else {
            root = try await database.record(for: request.root)
            try requireCurrentEngine(active, generation: attempt)
        }
        var ancestors: [CKRecord] = []
        for id in request.ancestors {
            ancestors.append(try await database.record(for: id))
            try requireCurrentEngine(active, generation: attempt)
        }
        let fetchedShare = try await database.record(for: request.share)
        try requireCurrentEngine(active, generation: attempt)
        guard let share = fetchedShare as? CKShare else { throw ICloudSyncEngineError.invalidRecord }
        for (record, expected) in [(page, request.page), (root, request.root)] + Array(zip(ancestors, request.ancestors)) {
            let source = try parseID(expected)
            guard record.recordID == expected, record.recordType == "ScriptumItemV1",
                  record["libraryID"] as? String == journal.scope.libraryID.uuidString.lowercased(),
                  record["kind"] as? String == source.kind.rawValue,
                  record["uuid"] as? String == source.id.uuidString.lowercased(),
                  record["operation"] as? String == "upsert" else { throw ICloudSyncEngineError.invalidRecord }
        }
        try ICloudOwnerMetadataParent.validate(request, page: .init(page), root: .init(root), ancestors: try ancestors.map(ICloudOwnerMetadataParent.Link.init),
            shareID: share.recordID, isOwner: share.currentUserParticipant?.role == .owner,
            isPrivate: share.publicPermission == .none)
        let confirmedUser = try await container.userRecordID()
        try requireCurrentEngine(active, generation: attempt)
        guard confirmedUser.recordName.utf8.elementsEqual(journal.scope.accountID.utf8) else { throw ICloudSyncEngineError.accountChanged }
        guard try ownerMetadataRequest(pageID: pageID) == request else { throw ICloudSyncEngineError.stopped }
        return request.page
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
                    if failure.error.code != .serverRecordChanged {
                        lastFailure = ICloudFailureDiagnostic.describe(failure.error)
                    }
                    // Preserve the local queue. Retain a server conflict revision
                    // in inbox so merge can resolve it without overwrite.
                    if let server = failure.error.serverRecord {
                        try retainIncoming([server], deletions: [])
                        var next = snapshot; next.conflicts.insert(server.recordID.recordName)
                        try persist(next)
                    }
                    releaseAsset(failure.record.recordID)
                }
                if let error = changes.failedRecordDeletes.values.first { lastFailure = ICloudFailureDiagnostic.describe(error) }
                // Failed saves remain in the durable outbox. Retry on the next
                // explicit/foreground synchronization, not in the same send loop.
                if changes.failedRecordSaves.isEmpty && changes.failedRecordDeletes.isEmpty { try queuePending(syncEngine) }
            case .fetchedDatabaseChanges(let changes):
                if changes.deletions.contains(where: { $0.zoneID == zoneID }) { throw ICloudSyncEngineError.invalidRecord }
            case .sentDatabaseChanges(let changes):
                if let error = changes.failedZoneSaves.first?.error ?? changes.failedZoneDeletes.values.first {
                    lastFailure = ICloudFailureDiagnostic.describe(error); status = .cloudUnavailable
                }
            default: break
            }
        } catch { await storageFailed(error) }
    }

    private func handleSaved(_ records: [CKRecord]) throws {
        guard !records.isEmpty else { return }
        var next = snapshot
        var confirmed: [ICloudSyncRecordID: UUID] = [:]
        for record in records {
            let id = try parseID(record.recordID)
            guard confirmed[id] == nil, let change = inFlight[record.recordID], change.recordID == id,
                  record.recordType == "ScriptumItemV1",
                  record["libraryID"] as? String == journal.scope.libraryID.uuidString.lowercased(),
                  record["kind"] as? String == id.kind.rawValue,
                  record["uuid"] as? String == id.id.uuidString.lowercased(),
                  record["revision"] as? String == change.revisionID.uuidString.lowercased(),
                  record["operation"] as? String == change.operation.rawValue,
                  record["sha256"] as? String == Self.digest(change.payload) else {
                throw ICloudSyncEngineError.invalidRecord
            }
            if let parent = inFlightParents[record.recordID] {
                guard record.parent?.recordID == parent, record.parent?.action == CKRecord.ReferenceAction.none else {
                    throw ICloudSyncEngineError.invalidRecord
                }
            }
            // CloudKit may return only saved metadata; the immutable sent bytes
            // remain owned locally. Incoming decode still requires its asset.
            next.systemFields[record.recordID.recordName] = try systemFields(record)
            if change.recordID.kind == .image, change.operation == .upsert {
                var receipts = next.confirmedImages ?? [:]
                receipts[record.recordID.recordName] = Self.digest(change.payload)
                next.confirmedImages = receipts
            }
            confirmed[id] = change.revisionID
        }
        try persist(next)
        _ = try journal.acknowledge(confirmed)
        for record in records { releaseAsset(record.recordID) }
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
                next.inbox.removeAll { $0.recordName == entry.recordName && $0.change?.revisionID == change.revisionID }
            }
            next.inbox.append(entry)
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
            next.inbox.removeAll { $0.recordName == deletion.recordID.recordName && $0.physicalDeletion }
            next.inbox.append(Incoming(recordName: deletion.recordID.recordName, change: nil, physicalDeletion: true))
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
    private func storageFailed(_ error: any Error) async {
        lastFailure = ICloudFailureDiagnostic.describe(error)
        generation = UUID(); status = .storageUnavailable
        let previous = engine; engine = nil
        await previous?.cancelOperations(); clearAssets()
    }
    private func releaseAsset(_ id: CKRecord.ID) {
        inFlight.removeValue(forKey: id)
        inFlightParents.removeValue(forKey: id)
        if let name = assetFiles.removeValue(forKey: id) { files.removeAsset(name) }
    }
    private func clearAssets() { for id in Array(inFlight.keys) { releaseAsset(id) } }
    private static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    /// Private owned-directory descriptor; no enumeration or user-selected paths.
    final class Files: @unchecked Sendable {
        let directory: URL
        let descriptor: Int32
        let name: String
        // Inbox payloads are base64 JSON, unlike the raw network batch. This
        // includes encoding overhead for supported document checkpoints.
        static let maximumBytes = 128 * 1024 * 1024
        private let maximumFileBytes: Int
        init(directory: URL, name: String, createParents: Bool = false, maximumFileBytes: Int = 64 * 1024 * 1024) throws {
            guard (1...Self.maximumBytes).contains(maximumFileBytes) else { throw ICloudSyncEngineError.capacity }
            self.directory = directory; self.name = name; self.maximumFileBytes = maximumFileBytes
            var current = Darwin.open("/", O_SEARCH | O_CLOEXEC)
            guard current >= 0 else { throw ICloudSyncEngineError.storage }
            let parts = directory.path.split(separator: "/").map(String.init)
            guard directory.isFileURL, !parts.isEmpty, parts.allSatisfy({ $0 != "." && $0 != ".." }) else { Darwin.close(current); throw ICloudSyncEngineError.storage }
            for (index, part) in parts.enumerated() {
                // Ancestors need traversal, not directory-read permission in the app sandbox.
                let access = index == parts.count - 1 ? O_RDONLY | O_DIRECTORY : O_SEARCH
                var next = Darwin.openat(current, part, access | O_NOFOLLOW | O_CLOEXEC)
                if next < 0, errno == ENOENT, createParents || index == parts.count - 1 {
                    if Darwin.mkdirat(current, part, 0o700) != 0, errno != EEXIST { Darwin.close(current); throw ICloudSyncEngineError.storage }
                    next = Darwin.openat(current, part, access | O_NOFOLLOW | O_CLOEXEC)
                }
                Darwin.close(current)
                guard next >= 0 else { throw ICloudSyncEngineError.storage }; current = next
            }
            var info = stat()
            guard Darwin.fstat(current, &info) == 0, info.st_uid == getuid(), info.st_mode & 0o077 == 0 else { Darwin.close(current); throw ICloudSyncEngineError.storage }
            descriptor = current
        }
        deinit { Darwin.close(descriptor) }
        func read(maximum: Int? = nil) throws -> Data? { try readSibling(name, maximum: maximum) }
        func readSibling(_ filename: String, maximum requestedMaximum: Int? = nil) throws -> Data? {
            let maximum = requestedMaximum ?? maximumFileBytes
            guard maximum > 0, maximum <= maximumFileBytes else { throw ICloudSyncEngineError.capacity }
            guard !filename.isEmpty, !filename.contains("/"), filename != ".", filename != ".." else { throw ICloudSyncEngineError.storage }
            let fd = Darwin.openat(descriptor, filename, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
            if fd < 0, errno == ENOENT { return nil }
            guard fd >= 0 else { throw ICloudSyncEngineError.storage }
            defer { Darwin.close(fd) }
            var info = stat()
            guard Darwin.fstat(fd, &info) == 0, info.st_uid == getuid(), info.st_nlink == 1,
                  info.st_mode & 0o077 == 0 else { throw ICloudSyncEngineError.storage }
            return try Self.read(fd, maximum: maximum)
        }
        func siblingNames(prefix: String) throws -> [String] {
            let duplicate = Darwin.dup(descriptor)
            guard duplicate >= 0 else { throw ICloudSyncEngineError.storage }
            guard let directory = Darwin.fdopendir(duplicate) else { Darwin.close(duplicate); throw ICloudSyncEngineError.storage }
            defer { Darwin.closedir(directory) }
            Darwin.rewinddir(directory)
            var names: [String] = []
            while true {
                errno = 0
                guard let entry = Darwin.readdir(directory) else {
                    guard errno == 0 else { throw ICloudSyncEngineError.storage }; break
                }
                let name = withUnsafePointer(to: &entry.pointee.d_name) {
                    $0.withMemoryRebound(to: CChar.self, capacity: Int(NAME_MAX) + 1) { String(cString: $0) }
                }
                if name.hasPrefix(prefix), name.hasSuffix(".json") { names.append(name) }
                guard names.count <= 4096 else { throw ICloudSyncEngineError.capacity }
            }
            return names
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
            guard data.count <= maximumFileBytes else { throw ICloudSyncEngineError.capacity }
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
