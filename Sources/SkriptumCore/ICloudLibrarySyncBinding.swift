import Foundation
public enum ICloudLibrarySyncBindingError: Error { case inactive }

/// Explicit account-scoped attachment to a local library. Queue failures never
/// roll back successfully saved documents; the checkpoint makes retry possible.
@MainActor public final class ICloudLibrarySyncBinding {
    private weak var store: LibraryStore?
    private let bridge: ICloudLibraryJournalBridge
    private var observerID: UUID?
    public private(set) var needsRetry = false
    public var changesQueued: (@MainActor () -> Void)?

    public init(store: LibraryStore, journal: ICloudSyncJournal) throws {
        guard !store.hasActiveEdits else { throw LibraryError.editInProgress }
        self.store = store
        bridge = try ICloudLibraryJournalBridge(journal: journal)
        try reconcile(store.snapshot)
        observerID = store.installDurableObserver { [weak self] snapshot in
            guard let self else { return }
            do { try self.reconcile(snapshot); self.changesQueued?() }
            catch { self.needsRetry = true }
        }
    }
    public func retry() throws {
        guard let store, let observerID, store.isDurableObserverActive(observerID) else {
            throw ICloudLibrarySyncBindingError.inactive
        }
        // Reopen to obtain the disk baseline, not an in-memory open edit draft.
        let bytes = try Data(contentsOf: store.directory.appendingPathComponent("library.json"))
        let durable = try JSONDecoder().decode(LibrarySnapshot.self, from: bytes)
        try LibraryStore.validate(durable)
        try reconcile(durable)
        changesQueued?()
    }
    public func invalidate() {
        if let store, let observerID { store.removeDurableObserver(observerID) }
        observerID = nil; store = nil; changesQueued = nil
    }
    private func reconcile(_ snapshot: LibrarySnapshot) throws {
        if let previous = try bridge.lastProjectedSnapshot() {
            _ = try bridge.project(from: previous, to: snapshot)
        } else {
            try bridge.bootstrap(snapshot)
        }
        needsRetry = false
    }
}
