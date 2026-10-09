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
}
