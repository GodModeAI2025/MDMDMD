import Foundation
import Observation
import CloudKit
#if canImport(SkriptumCore)
import SkriptumCore
#endif

enum ICloudSharedSessionError: Error { case unavailable }

@MainActor @Observable final class ICloudSharedSession: ICloudChangeHintTarget {
    enum Status { case notConfigured, inactive, accepting, synchronizing, ready, failed, accountChanged }
    private(set) var status: Status
    private(set) var context: ICloudSharedDocumentContext?
    private(set) var pendingCount = 0
    private(set) var catalogWarning: String?
    private(set) var identity: ICloudSharedStoreIdentity?
    private(set) var recoveredDrafts: [ICloudSharedDraft] = []
    @ObservationIgnored private var draftStore: ICloudSharedDraftStore?
    @ObservationIgnored private var knownPages = Set<UUID>()
    @ObservationIgnored private var store: ICloudSharedDocumentStore?
    @ObservationIgnored private var transport: ICloudShareParticipantTransport?
    @ObservationIgnored private var accepted: ICloudShareParticipantTransport.Accepted?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var accountGeneration: UUID
    @ObservationIgnored private let accountFence: SharedAccountFence
    @ObservationIgnored private var accountObservation: SharedAccountObservation?
    @ObservationIgnored private let accountLookup: @MainActor () async throws -> String
    private let directory: URL
    @ObservationIgnored private var foregroundRefresh: ICloudForegroundRefresh?
    @ObservationIgnored private var hintToken: UUID?
    @ObservationIgnored private var cloudHintPending = false
    @ObservationIgnored private var subscriptionConfirmed = false
    private let provisioned: Bool
    private let containerIdentifier = "iCloud.com.mobilebox.Skriptum"

    convenience init(directory: URL) {
        self.init(directory: directory,
            provisioned: Bundle.main.object(forInfoDictionaryKey: "ScriptumICloudProvisioned") as? Bool == true,
            notificationCenter: .default, accountLookup: {
                let container = CKContainer(identifier: "iCloud.com.mobilebox.Skriptum")
                guard try await container.accountStatus() == .available else { throw ICloudSharedSessionError.unavailable }
                return try await container.userRecordID().recordName
            })
    }
    init(directory: URL, provisioned: Bool, notificationCenter: NotificationCenter,
         accountLookup: @escaping @MainActor () async throws -> String) {
        self.directory = directory
        self.provisioned = provisioned
        self.accountLookup = accountLookup
        let fence = SharedAccountFence()
        accountFence = fence; accountGeneration = fence.current
        status = provisioned ? .inactive : .notConfigured
        foregroundRefresh = ICloudForegroundRefresh { [weak self] in await self?.synchronize() }
        accountObservation = SharedAccountObservation(center: notificationCenter, fence: fence) { [weak self] in
            Task { @MainActor [weak self] in self?.accountChanged() }
        }
    }
    /// Called only by the person's invitation-acceptance action.
    func accept(_ metadata: CKShare.Metadata) async {
        guard provisioned, status == .inactive || status == .failed || status == .accountChanged else { return }
        accountGeneration = accountFence.current
        let attempt = UUID(); generation = attempt; status = .accepting
        do {
            let account = try await accountID()
            guard isCurrent(attempt) else { return }
            let participant = ICloudShareParticipantTransport(containerIdentifier: containerIdentifier, accountID: account)
            let grant = try await participant.accept(metadata) { self.isCurrent(attempt) }
            try await install(grant, participant: participant, account: account, attempt: attempt)
        } catch { if isCurrent(attempt) { fail(error) } }
    }
    /// Restore descriptors contain no cached access grant. Loading always asks
    /// Apple's shared database for the current participant status first.
    func restore(_ identity: ICloudSharedStoreIdentity) async {
        guard provisioned, status == .inactive || status == .failed || status == .accountChanged else { return }
        accountGeneration = accountFence.current
        let attempt = UUID(); generation = attempt; status = .accepting
        do {
            let account = try await accountID()
            guard account.utf8.elementsEqual(identity.accountID.utf8), isCurrent(attempt) else { throw ICloudSharedSessionError.unavailable }
            let participant = ICloudShareParticipantTransport(containerIdentifier: containerIdentifier, accountID: account)
            let zone = CKRecordZone.ID(zoneName: identity.zoneName, ownerName: identity.ownerID)
            let root = CKRecord.ID(recordName: identity.root.kind.rawValue + ":" + identity.root.id.uuidString.lowercased(), zoneID: zone)
            let grant = try await participant.load(shareID: .init(recordName: identity.shareName, zoneID: zone), rootID: root) { self.isCurrent(attempt) }
            try await install(grant, participant: participant, account: account, attempt: attempt)
        } catch { if isCurrent(attempt) { fail(error) } }
    }
    private func install(_ grant: ICloudShareParticipantTransport.Accepted, participant: ICloudShareParticipantTransport,
                         account: String, attempt: UUID) async throws {
        guard isCurrent(attempt) else { throw ICloudSharedSessionError.unavailable }
        let root = grant.root.recordID, parts = root.recordName.split(separator: ":")
        guard parts.count == 2, let kind = ICloudSyncRecordKind(rawValue: String(parts[0])),
              let id = UUID(uuidString: String(parts[1])) else { throw ICloudSharedSessionError.unavailable }
        let identity = try ICloudSharedStoreIdentity(accountID: account, ownerID: root.zoneID.ownerName,
            zoneName: root.zoneID.zoneName, shareName: grant.share.recordID.recordName, root: .init(kind: kind, id: id))
        let checkpoint = try ICloudSharedDocumentStore(directory: directory, identity: identity)
        self.identity = identity; store = checkpoint; transport = participant; accepted = grant
        let recovery = try ICloudSharedDraftStore(directory: directory.appendingPathComponent("Drafts"), identity: identity)
        draftStore = recovery; recoveredDrafts = try recovery.drafts()
        context = try checkpoint.context(permission: grant.canWrite ? .readWrite : .readOnly)
        knownPages = Set(context?.canonical.pages.map(\.id) ?? [])
        // Pending local changes are sent before a full snapshot can replace the
        // checkpoint, including after a process restart.
        try await participant.send(accepted: grant, store: checkpoint, stagingDirectory: assetDirectory(checkpoint)) { self.isCurrent(attempt) }
        let received = try await participant.receive(accepted: grant, store: checkpoint,
            imageDirectory: imageDirectory(checkpoint)) { self.isCurrent(attempt) }
        guard isCurrent(attempt) else { throw ICloudSharedSessionError.unavailable }
        try await participant.ensureChangeSubscription { self.isCurrent(attempt) }
        guard isCurrent(attempt) else { throw ICloudSharedSessionError.unavailable }
        subscriptionConfirmed = true
        context = received; knownPages.formUnion(received.canonical.pages.map(\.id)); pendingCount = try checkpoint.pendingChanges().count; status = .ready
        ICloudChangeHints.shared.remove(hintToken)
        hintToken = ICloudChangeHints.shared.register(self, scope: .shared)
        if pendingCount > 0 { foregroundRefresh?.request() }
        do {
            let title = identity.root.kind == .page ? received.canonical.pages.first(where: { $0.id == identity.root.id })?.title : received.canonical.spaces.first(where: { $0.id == identity.root.id })?.title
            try ICloudSharedCatalog(directory: directory).record(identity, title: title ?? "Geteiltes Dokument")
            catalogWarning = nil
        } catch { catalogWarning = "Die Freigabe ist geöffnet, konnte aber noch nicht in der Übersicht gespeichert werden." }
    }
    func setForegroundActive(_ active: Bool) {
        foregroundRefresh?.setActive(active && provisioned)
    }
    func receiveCloudChangeHint() async {
        guard provisioned else { return }
        if status == .synchronizing { cloudHintPending = true; return }
        await synchronize()
    }
    func synchronize() async {
        guard accountFence.current == accountGeneration, status == .ready || status == .failed, let store, let transport, let accepted else { return }
        let wasReady = status == .ready
        let attempt = generation; status = .synchronizing
        defer {
            if generation == attempt, status == .ready, pendingCount > 0 {
                foregroundRefresh?.request()
            }
            if generation == attempt, cloudHintPending, status == .ready {
                cloudHintPending = false
                Task { @MainActor [weak self] in
                    guard let self, self.generation == attempt else { return }
                    await self.receiveCloudChangeHint()
                }
            }
        }
        do {
            if !subscriptionConfirmed {
                try await transport.ensureChangeSubscription { self.isCurrent(attempt) }
                guard isCurrent(attempt) else { return }
                subscriptionConfirmed = true
                ICloudChangeHints.shared.remove(hintToken)
                hintToken = ICloudChangeHints.shared.register(self, scope: .shared)
            }
            try await transport.send(accepted: accepted, store: store, stagingDirectory: assetDirectory(store)) { self.isCurrent(attempt) }
            let received = try await transport.receive(accepted: accepted, store: store,
                imageDirectory: imageDirectory(store)) { self.isCurrent(attempt) }
            guard isCurrent(attempt) else { return }
            context = received; knownPages.formUnion(received.canonical.pages.map(\.id)); pendingCount = try store.pendingChanges().count; status = .ready
        } catch {
            guard isCurrent(attempt) else { return }
            pendingCount = (try? store.pendingChanges().count) ?? pendingCount
            if ICloudRefreshCancellation.isExpectedPause(error, callerCancelled: Task.isCancelled,
                transportCurrent: wasReady && context != nil && subscriptionConfirmed) {
                status = .ready
            } else { fail(error) }
        }
    }
    @discardableResult func edit(pageID: UUID, revision: UUID, markdown: String) throws -> UUID {
        guard accountFence.current == accountGeneration, let store, let context, status == .ready || status == .synchronizing || status == .failed else { throw ICloudSharedSessionError.unavailable }
        let result = try store.editMarkdown(pageID: pageID, expectedPageRevision: revision, markdown: markdown, permission: context.permission)
        try reloadLocal(store, permission: context.permission)
        return result
    }
    func addComment(pageID: UUID, blockID: UUID?, quotation: String, body: String) throws {
        guard accountFence.current == accountGeneration, let store, let context, status == .ready || status == .synchronizing || status == .failed else { throw ICloudSharedSessionError.unavailable }
        _ = try store.addComment(pageID: pageID, blockID: blockID, quotedText: quotation, body: body, permission: context.permission)
        try reloadLocal(store, permission: context.permission)
    }
    func reply(commentID: UUID, body: String) throws {
        guard accountFence.current == accountGeneration, let store, let context, status == .ready || status == .synchronizing || status == .failed else { throw ICloudSharedSessionError.unavailable }
        _ = try store.replyToComment(commentID, body: body, permission: context.permission)
        try reloadLocal(store, permission: context.permission)
    }
    func resolve(commentID: UUID, resolved: Bool) throws {
        guard accountFence.current == accountGeneration, let store, let context, status == .ready || status == .synchronizing || status == .failed else { throw ICloudSharedSessionError.unavailable }
        try store.setCommentResolved(commentID, resolved: resolved, permission: context.permission)
        try reloadLocal(store, permission: context.permission)
    }
    func preserveDraft(_ draft: ICloudSharedDraft) throws {
        guard let draftStore, knownPages.contains(draft.pageID) else { throw ICloudSharedSessionError.unavailable }
        try draftStore.save(draft)
        if let index = recoveredDrafts.firstIndex(where: { $0.id == draft.id }) { recoveredDrafts[index] = draft }
        else { recoveredDrafts.insert(draft, at: 0) }
    }
    func clearDraft(_ id: UUID, matching text: String) throws {
        guard let draftStore else { throw ICloudSharedSessionError.unavailable }
        if try draftStore.remove(id, matching: text) { recoveredDrafts.removeAll { $0.id == id } }
        else if let actual = try draftStore.draft(id), let index = recoveredDrafts.firstIndex(where: { $0.id == id }) { recoveredDrafts[index] = actual }
    }
    func recoveryDraft(_ id: UUID) throws -> ICloudSharedDraft? {
        guard let draftStore else { throw ICloudSharedSessionError.unavailable }
        return try draftStore.draft(id)
    }
    func stop() {
        foregroundRefresh?.setActive(false)
        ICloudChangeHints.shared.remove(hintToken); hintToken = nil
        cloudHintPending = false; subscriptionConfirmed = false
        generation = UUID(); context = nil; accepted = nil; transport = nil; store = nil; identity = nil; pendingCount = 0
        draftStore = nil; recoveredDrafts = []; knownPages = []; catalogWarning = nil
        status = provisioned ? .inactive : .notConfigured
    }
    private func accountChanged() {
        guard accountFence.current != accountGeneration else { return }
        stop()
        if provisioned { status = .accountChanged }
    }
    private func isCurrent(_ attempt: UUID) -> Bool {
        generation == attempt && accountFence.current == accountGeneration
    }
    private func fail(_ error: any Error) {
        // A network failure does not erase an active session's last confirmed
        // grant or local draft. Writeback still revalidates the grant every time.
        if error is ICloudShareParticipantError || error as? ICloudSharedSendError == .permissionDenied ||
           error is ICloudSharedSessionError {
            context = nil
        } else if let cloud = error as? CKError,
                  [.notAuthenticated, .permissionFailure, .zoneNotFound, .unknownItem].contains(cloud.code) {
            context = nil
        }
        status = .failed
    }
    private func reloadLocal(_ store: ICloudSharedDocumentStore, permission: ICloudSharedPermission) throws {
        context = try store.context(permission: permission); knownPages.formUnion(context?.canonical.pages.map(\.id) ?? []); pendingCount = try store.pendingChanges().count
        if pendingCount > 0 { foregroundRefresh?.request() }
    }
    private func assetDirectory(_ store: ICloudSharedDocumentStore) -> URL {
        directory.appendingPathComponent(store.fileURL.deletingPathExtension().lastPathComponent + "-outgoing")
    }
    private func imageDirectory(_ store: ICloudSharedDocumentStore) -> URL {
        directory.appendingPathComponent(store.fileURL.deletingPathExtension().lastPathComponent + "-media")
    }
    private func accountID() async throws -> String {
        try await accountLookup()
    }
}

/// CloudKit account notifications may arrive on any queue. Invalidate admission
/// synchronously, before the main-actor presentation cleanup is scheduled.
private final class SharedAccountFence: @unchecked Sendable {
    private let lock = NSLock()
    private var value = UUID()
    var current: UUID { lock.withLock { value } }
    func invalidate() { lock.withLock { value = UUID() } }
}
/// Immutable token ownership; removal also occurs when a window/session closes.
private final class SharedAccountObservation: @unchecked Sendable {
    private let center: NotificationCenter
    private let token: any NSObjectProtocol
    init(center: NotificationCenter, fence: SharedAccountFence, changed: @escaping @Sendable () -> Void) {
        self.center = center
        token = center.addObserver(forName: .CKAccountChanged, object: nil, queue: nil) { _ in
            fence.invalidate(); changed()
        }
    }
    deinit { center.removeObserver(token) }
}
