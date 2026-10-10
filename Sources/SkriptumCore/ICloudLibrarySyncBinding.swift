import Foundation
public enum ICloudLibrarySyncBindingError: Error { case inactive }

/// Explicit account-scoped attachment to a local library. Queue failures never
/// roll back successfully saved documents; the checkpoint makes retry possible.
@MainActor public final class ICloudLibrarySyncBinding {
    private weak var store: LibraryStore?
    private let bridge: ICloudLibraryJournalBridge
    private var observerID: UUID?
    private var applyingIncoming = false
    public private(set) var needsRetry = false
    public var changesQueued: (@MainActor () -> Void)?
    /// A network wake-up hint only for a newly enqueued durable projection.
    /// A no-op retry must not continuously schedule another synchronization.
    public var newChangesQueued: (@MainActor () -> Void)?

    public init(store: LibraryStore, journal: ICloudSyncJournal) throws {
        self.store = store
        bridge = try ICloudLibraryJournalBridge(journal: journal)
        let durable = try Self.durableSnapshot(store)
        _ = try reconcile(durable)
        observerID = store.installDurableObserver { [weak self] snapshot in
            guard let self else { return }
            guard !self.applyingIncoming else { return }
            do {
                let added = try self.reconcile(snapshot)
                self.changesQueued?()
                if added > 0 { self.newChangesQueued?() }
            }
            catch { self.needsRetry = true }
        }
    }
    public func retry() throws {
        guard let store, let observerID, store.isDurableObserverActive(observerID) else {
            throw ICloudLibrarySyncBindingError.inactive
        }
        // Reopen to obtain the disk baseline, not an in-memory open edit draft.
        let durable = try Self.durableSnapshot(store)
        let added = try reconcile(durable)
        changesQueued?()
        if added > 0 { newChangesQueued?() }
    }
    public func invalidate() {
        if let store, let observerID { store.removeDurableObserver(observerID) }
        observerID = nil; store = nil; changesQueued = nil; newChangesQueued = nil
    }
    /// Preparing the durable ancestry override precedes the local document
    /// commit. A failed enqueue/checkpoint is replayed by ordinary retry/startup.
    public func applyPageResolution(_ resolution: ICloudPageResolution) throws {
        guard let store, let observerID, store.isDurableObserverActive(observerID), !applyingIncoming,
              !store.hasActiveEdits else { throw ICloudLibrarySyncBindingError.inactive }
        try retry()
        try bridge.preparePageResolution(pageID: resolution.local.id, expectedLocalRevision: resolution.local.revision,
            resolvedRevision: resolution.resolved.revision, remoteRevision: resolution.remote.revision)
        applyingIncoming = true
        defer { applyingIncoming = false }
        do {
            try store.applyICloudPageResolution(resolution)
            let added = try reconcile(store.snapshot)
            changesQueued?()
            if added > 0 { newChangesQueued?() }
        }
        catch { needsRetry = true; throw error }
    }
    public func performIncomingMutation<T>(_ mutation: () throws -> T) throws -> T {
        guard let store, let observerID, store.isDurableObserverActive(observerID), !applyingIncoming,
              !store.hasActiveEdits, let previous = try bridge.lastProjectedSnapshot() else {
            throw ICloudLibrarySyncBindingError.inactive
        }
        applyingIncoming = true
        defer { applyingIncoming = false }
        let result = try mutation()
        try bridge.adoptIncoming(from: previous, to: store.snapshot)
        return result
    }
    private static func durableSnapshot(_ store: LibraryStore) throws -> LibrarySnapshot {
        let url = store.directory.appendingPathComponent("library.json")
        if !FileManager.default.fileExists(atPath: url.path), !store.hasActiveEdits,
           store.snapshot == LibrarySnapshot() { return LibrarySnapshot() }
        let value = try JSONDecoder().decode(LibrarySnapshot.self, from: Data(contentsOf: url))
        try LibraryStore.validate(value)
        return value
    }
    private func reconcile(_ snapshot: LibrarySnapshot) throws -> Int {
        let added: Int
        if let previous = try bridge.lastProjectedSnapshot() {
            added = try bridge.project(from: previous, to: snapshot)
        } else {
            added = try bridge.bootstrap(snapshot)
        }
        needsRetry = false
        return added
    }
}
