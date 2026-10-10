import Foundation
import Observation
import CloudKit
import CryptoKit
#if canImport(SkriptumCore)
import SkriptumCore
#endif

enum ICloudOwnerPresentationError: Error { case notReady }

@MainActor @Observable final class ICloudLibrarySession: ICloudChangeHintTarget {
    enum Status { case notConfigured, inactive, checking, ready, syncing, failed, accountChanged }
    private(set) var status: Status
    private(set) var pendingCount = 0
    private(set) var incomingCount = 0
    private(set) var conflictCount = 0
    private(set) var lastSynchronized: Date?
    @ObservationIgnored private weak var library: WritingLibrary?
    @ObservationIgnored private var binding: ICloudLibrarySyncBinding?
    @ObservationIgnored private var journal: ICloudSyncJournal?
    @ObservationIgnored private var engine: ICloudSyncEngine?
    @ObservationIgnored private var generation = UUID()
    private let containerID = "iCloud.com.mobilebox.Skriptum"
    @ObservationIgnored private var hintToken: UUID?
    @ObservationIgnored private var cloudHintPending = false
    private let provisioned: Bool

    init(library: WritingLibrary) {
        self.library = library
        provisioned = Bundle.main.object(forInfoDictionaryKey: "ScriptumICloudProvisioned") as? Bool == true
        status = provisioned ? .inactive : .notConfigured
    }
    func activate() async {
        guard provisioned, status == .inactive || status == .failed, let library, let store = library.store else { return }
        let attempt = UUID(); generation = attempt; status = .checking
        var startedTransport: ICloudSyncEngine?
        do {
            let container = CKContainer(identifier: containerID)
            guard try await container.accountStatus() == .available else { throw ICloudSyncEngineError.accountUnavailable }
            let account = try await container.userRecordID()
            guard generation == attempt else { return }
            let id: UUID
            switch try library.ownedWindowLocator() {
            case .primary: id = UUID(uuidString: "75BA73C5-4058-4F71-B810-CA49C7B17675")!
            case .imported(let value): id = value
            }
            let scope = try ICloudSyncScope(accountID: account.recordName, libraryID: id)
            let directory = library.iCloudStorageDirectory()
            let queue = try ICloudSyncJournal(directory: directory, scope: scope)
            let transport = try ICloudSyncEngine(containerIdentifier: containerID, journal: queue, directory: directory)
            startedTransport = transport
            try await transport.activate()
            guard generation == attempt else { await transport.stop(); return }
            let attachment = try ICloudLibrarySyncBinding(store: store, journal: queue)
            journal = queue; engine = transport; binding = attachment
            attachment.changesQueued = { [weak self] in
                guard let self else { return }
                self.pendingCount = (try? queue.pendingCount()) ?? self.pendingCount
            }
            pendingCount = try queue.pendingCount()
            status = .ready
            ICloudChangeHints.shared.remove(hintToken)
            hintToken = ICloudChangeHints.shared.register(self, scope: .owned)
        } catch {
            await startedTransport?.stop()
            if generation == attempt { status = .failed }
        }
    }
    func stop() async {
        ICloudChangeHints.shared.remove(hintToken); hintToken = nil; cloudHintPending = false
        generation = UUID(); binding?.invalidate(); binding = nil
        let previous = engine; engine = nil; journal = nil
        status = provisioned ? .inactive : .notConfigured
        pendingCount = 0; incomingCount = 0; conflictCount = 0; lastSynchronized = nil
        await previous?.stop()
    }
    func createShare(scope: ICloudShareScope) async throws -> CKShare {
        guard provisioned, status == .ready else { throw ICloudOwnerPresentationError.notReady }
        await synchronize()
        guard status == .ready, pendingCount == 0, incomingCount == 0, conflictCount == 0,
              let library, let store = library.store, !store.hasActiveEdits,
              let engine, let journal else { throw ICloudOwnerPresentationError.notReady }
        let attempt = generation; status = .syncing
        defer { drainCloudHint(attempt: attempt) }
        do {
            let plan = try ICloudShareRecordPlan(scope: scope, snapshot: store.snapshot)
            let title: String
            switch scope {
            case .page(let id): title = store.snapshot.pages.first(where: { $0.id == id })?.title ?? "Geteilte Seite"
            case .space(let id): title = store.snapshot.spaces.first(where: { $0.id == id })?.title ?? "Geteilter Space"
            }
            let receipts = try ICloudOwnerShareReceipts(directory: library.iCloudStorageDirectory(), scope: journal.scope)
            let transport = ICloudShareOwnerTransport(containerIdentifier: containerID, scope: journal.scope)
            let result = try await transport.create(plan: plan, title: title, receipts: receipts) { self.generation == attempt }
            guard generation == attempt, !store.hasActiveEdits else { throw ICloudOwnerPresentationError.notReady }
            let current = try ICloudShareRecordPlan(scope: scope, snapshot: store.snapshot)
            guard current.entries == plan.entries else { throw ICloudShareOwnerError.changedManifest }
            let metadata = try ICloudShareRecordBuilder.confirmedMetadata(plan: plan, records: result.records, snapshot: store.snapshot)
            try await engine.registerOwnedShareMetadata(metadata)
            guard generation == attempt else { throw ICloudOwnerPresentationError.notReady }
            status = .ready
            return result.share
        } catch {
            if generation == attempt { status = .failed }
            throw error
        }
    }
    func pageConflicts() async throws -> [ICloudPageConflict] {
        guard provisioned, let store = library?.store, let engine, let journal,
              status == .ready || status == .failed else { return [] }
        let attempt = generation
        let inputs = await engine.latestPageConflictChanges()
        guard generation == attempt else { throw ICloudPageConflictError.unavailable }
        var result: [ICloudPageConflict] = []
        for change in inputs {
            guard let local = store.snapshot.pages.first(where: { $0.id == change.recordID.id }),
                  local.revision != change.revisionID else { continue }
            result.append(try ICloudPageConflict(scope: journal.scope, local: local, change: change))
        }
        return result.sorted { $0.local.title.localizedStandardCompare($1.local.title) == .orderedAscending }
    }
    func reviewStore(for conflict: ICloudPageConflict) throws -> ICloudConflictReviewStore {
        guard provisioned, let journal, journal.scope == conflict.scope, let library else { throw ICloudPageConflictError.unavailable }
        return try ICloudConflictReviewStore(directory: library.iCloudStorageDirectory().appendingPathComponent("ConflictReviews"), identity: conflict.reviewIdentity)
    }
    func canResolve(_ conflict: ICloudPageConflict) -> Bool {
        provisioned && status == .ready && journal?.scope == conflict.scope &&
        library?.currentPage(conflict.id)?.revision == conflict.local.revision
    }
    func spaceTitle(_ id: UUID) -> String? { library?.spaces.first(where: { $0.id == id })?.title }
    func pageTitle(_ id: UUID) -> String? { library?.currentPage(id)?.title }
    func resolve(_ conflict: ICloudPageConflict, choice: ICloudPageResolutionChoice) async throws {
        guard provisioned, status == .ready, let library, let store = library.store,
              let engine, let journal, let binding, journal.scope == conflict.scope,
              !store.hasActiveEdits else { throw ICloudPageConflictError.unavailable }
        let attempt = generation; status = .syncing
        defer { drainCloudHint(attempt: attempt) }
        do {
            let container = CKContainer(identifier: containerID)
            guard try await container.accountStatus() == .available,
                  try await container.userRecordID().recordName.utf8.elementsEqual(journal.scope.accountID.utf8),
                  generation == attempt else { throw ICloudPageConflictError.unavailable }
            try await engine.refreshForConflictReview()
            guard generation == attempt, !store.hasActiveEdits,
                  let latest = await engine.latestPageConflictChanges().first(where: { $0.recordID == conflict.change.recordID }),
                  latest == conflict.change else { throw ICloudPageConflictError.stale }
            guard let current = store.snapshot.pages.first(where: { $0.id == conflict.id }),
                  try ICloudMetadataPayload<Page>.valueBytes(current) == ICloudMetadataPayload<Page>.valueBytes(conflict.local) else { throw ICloudPageConflictError.stale }
            try Task.checkCancellation()
            let resolution = try store.prepareICloudPageResolution(remote: conflict.remote,
                expectedLocalRevision: conflict.local.revision, choice: choice)
            try binding.applyPageResolution(resolution)
            library.reload()
            try await engine.completePageConflictResolution(scope: conflict.scope, expected: conflict.change,
                resolvedRevision: resolution.resolved.revision)
            guard generation == attempt else { throw ICloudPageConflictError.unavailable }
            pendingCount = try journal.pendingCount(); incomingCount = await engine.incomingSnapshot().count
            conflictCount = await engine.unresolvedConflictCount(); status = .ready
        } catch ICloudPageConflictError.stale {
            let incoming = await engine.incomingSnapshot().count
            let conflicts = await engine.unresolvedConflictCount()
            let active = await engine.status == .active
            if generation == attempt {
                library.reload(); pendingCount = (try? journal.pendingCount()) ?? pendingCount
                incomingCount = incoming; conflictCount = conflicts; status = active ? .ready : .failed
            }
            throw ICloudPageConflictError.stale
        } catch {
            if generation == attempt { library.reload(); status = .failed }
            throw error
        }
    }
    private func drainCloudHint(attempt: UUID) {
        guard generation == attempt, cloudHintPending, status == .ready else { return }
        cloudHintPending = false
        Task { @MainActor [weak self] in
            guard let self, self.generation == attempt else { return }
            await self.receiveCloudChangeHint()
        }
    }
    func receiveCloudChangeHint() async {
        guard provisioned else { return }
        if status == .syncing { cloudHintPending = true; return }
        await synchronize()
    }
    func synchronize() async {
        guard status == .ready, let engine, let binding, let journal,
              let library, let store = library.store else { return }
        let attempt = generation; status = .syncing
        defer { drainCloudHint(attempt: attempt) }
        do {
            try binding.retry()
            try await engine.synchronize()
            // Stream one immutable image at a time, keeping the bounded outbox
            // independent of the total size of a manuscript's attachments.
            let attachments = (store.snapshot.pages + store.snapshot.revisions.map(\.page))
                .flatMap { $0.attachments ?? [] }
            var seen = Set<UUID>()
            for attachment in attachments where seen.insert(attachment.id).inserted {
                guard generation == attempt else { return }
                let data = try store.attachmentData(attachment)
                var bytes = Array(SHA256.hash(data: data).prefix(16))
                bytes[6] = (bytes[6] & 0x0f) | 0x50; bytes[8] = (bytes[8] & 0x3f) | 0x80
                let revision = UUID(uuid: (bytes[0],bytes[1],bytes[2],bytes[3],bytes[4],bytes[5],bytes[6],bytes[7],bytes[8],bytes[9],bytes[10],bytes[11],bytes[12],bytes[13],bytes[14],bytes[15]))
                let payload = try ICloudImagePayload(attachment: attachment, revisionID: revision, data: data).encoded()
                let change = ICloudSyncChange(recordID: .init(kind: .image, id: attachment.id), revisionID: revision, operation: .upsert, payload: payload)
                if try await engine.enqueueImageIfNeeded(change) {
                    try await engine.synchronize()
                    guard generation == attempt else { return }
                    // Do not fill the queue with further large assets after an
                    // unconfirmed send; the next user sync retries this image.
                    if try journal.pendingChange(recordID: change.recordID) != nil { throw ICloudSyncEngineError.storage }
                }
            }
            guard generation == attempt else { return }
            guard await engine.status == .active else {
                binding.invalidate(); status = .accountChanged; return
            }
            var incoming = await engine.incomingSnapshot()
            var progress = true
            while progress {
                progress = false
                incoming.sort { priority($0.change?.recordID.kind) < priority($1.change?.recordID.kind) }
                for item in incoming {
                    guard generation == attempt else { return }
                    guard let change = item.change, !item.physicalDeletion, change.operation == .upsert,
                          try journal.pendingChange(recordID: change.recordID)?.operation != .tombstone else { continue }
                    do {
                        let accepted = try binding.performIncomingMutation {
                            switch change.recordID.kind {
                            case .page:
                                let payload = try ICloudPagePayload.decode(change.payload,
                                    expectedPageID: change.recordID.id, expectedRevision: change.revisionID)
                                let outcome = try store.mergeICloudPage(payload.page, basedOn: payload.baseRevision)
                                return outcome != .conflictPreserved && outcome != .historical
                            case .space, .comment, .revision:
                                let outcome = try ICloudMetadataMerge.apply(change, to: store)
                                return outcome != .conflict && outcome != .pendingTombstone
                            case .image:
                                let payload = try ICloudImagePayload.decode(change.payload,
                                    expectedImageID: change.recordID.id, expectedRevision: change.revisionID)
                                _ = try store.importICloudImage(payload)
                                return true
                            }
                        }
                        if accepted {
                            try await engine.acknowledgeIncoming(recordID: change.recordID, revisionID: change.revisionID)
                            progress = true
                        }
                    } catch { /* Durable inbox retains dependency failures and conflicts. */ }
                }
                incoming = await engine.incomingSnapshot()
            }
            let outgoing = try journal.pendingCount()
            let conflicts = await engine.unresolvedConflictCount()
            guard generation == attempt else { return }
            library.reload()
            pendingCount = outgoing
            incomingCount = incoming.count
            conflictCount = conflicts
            if pendingCount == 0 && incomingCount == 0 && conflictCount == 0 { lastSynchronized = Date() }
            if generation == attempt { status = .ready }
        } catch { if generation == attempt { status = .failed } }
    }
    private func priority(_ kind: ICloudSyncRecordKind?) -> Int {
        switch kind { case .space: 0; case .image: 1; case .page: 2; case .comment: 3; case .revision: 4; case nil: 5 }
    }
}
