import Foundation
import Observation
import CloudKit
#if canImport(SkriptumCore)
import SkriptumCore
#endif

@MainActor @Observable final class ICloudLibrarySession {
    enum Status { case notConfigured, inactive, checking, ready, syncing, failed, accountChanged }
    private(set) var status: Status
    private(set) var pendingCount = 0
    @ObservationIgnored private weak var library: WritingLibrary?
    @ObservationIgnored private var binding: ICloudLibrarySyncBinding?
    @ObservationIgnored private var journal: ICloudSyncJournal?
    @ObservationIgnored private var engine: ICloudSyncEngine?
    @ObservationIgnored private var generation = UUID()
    private let containerID = "iCloud.com.mobilebox.Skriptum"
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
                self.pendingCount = (try? queue.pendingBatch(limit: 128, maximumPayloadBytes: 64 * 1024 * 1024).count) ?? self.pendingCount
            }
            pendingCount = try queue.pendingBatch(limit: 128, maximumPayloadBytes: 64 * 1024 * 1024).count
            status = .ready
        } catch {
            await startedTransport?.stop()
            if generation == attempt { status = .failed }
        }
    }
    func stop() async {
        generation = UUID(); binding?.invalidate(); binding = nil
        let previous = engine; engine = nil; journal = nil
        status = provisioned ? .inactive : .notConfigured; pendingCount = 0
        await previous?.stop()
    }
    func synchronize() async {
        guard status == .ready, let engine, let binding, let journal,
              let library, let store = library.store else { return }
        let attempt = generation; status = .syncing
        do {
            try binding.retry()
            try await engine.synchronize()
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
                                _ = try store.mergeICloudPage(payload.page, basedOn: payload.baseRevision)
                                return true
                            case .space, .comment, .revision:
                                let outcome = try ICloudMetadataMerge.apply(change, to: store)
                                return outcome != .conflict && outcome != .pendingTombstone
                            case .image: return false
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
            library.reload()
            pendingCount = try journal.pendingBatch(limit: 128, maximumPayloadBytes: 64 * 1024 * 1024).count
            if generation == attempt { status = .ready }
        } catch { if generation == attempt { status = .failed } }
    }
    private func priority(_ kind: ICloudSyncRecordKind?) -> Int {
        switch kind { case .space: 0; case .page: 1; case .comment: 2; case .revision: 3; case .image: 4; case nil: 5 }
    }
}
