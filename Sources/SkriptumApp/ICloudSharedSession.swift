import Foundation
import Observation
import CloudKit
#if canImport(SkriptumCore)
import SkriptumCore
#endif

enum ICloudSharedSessionError: Error { case unavailable }

@MainActor @Observable final class ICloudSharedSession {
    enum Status { case notConfigured, inactive, accepting, synchronizing, ready, failed }
    private(set) var status: Status
    private(set) var context: ICloudSharedDocumentContext?
    private(set) var pendingCount = 0
    private(set) var identity: ICloudSharedStoreIdentity?
    private(set) var recoveredDrafts: [ICloudSharedDraft] = []
    @ObservationIgnored private var draftStore: ICloudSharedDraftStore?
    @ObservationIgnored private var knownPages = Set<UUID>()
    @ObservationIgnored private var store: ICloudSharedDocumentStore?
    @ObservationIgnored private var transport: ICloudShareParticipantTransport?
    @ObservationIgnored private var accepted: ICloudShareParticipantTransport.Accepted?
    @ObservationIgnored private var generation = UUID()
    private let directory: URL
    private let provisioned: Bool
    private let containerIdentifier = "iCloud.com.mobilebox.Skriptum"

    init(directory: URL) {
        self.directory = directory
        provisioned = Bundle.main.object(forInfoDictionaryKey: "ScriptumICloudProvisioned") as? Bool == true
        status = provisioned ? .inactive : .notConfigured
    }
    /// Called only by the person's invitation-acceptance action.
    func accept(_ metadata: CKShare.Metadata) async {
        guard provisioned, status == .inactive || status == .failed else { return }
        let attempt = UUID(); generation = attempt; status = .accepting
        do {
            let account = try await accountID()
            guard generation == attempt else { return }
            let participant = ICloudShareParticipantTransport(containerIdentifier: containerIdentifier, accountID: account)
            let grant = try await participant.accept(metadata) { self.generation == attempt }
            try await install(grant, participant: participant, account: account, attempt: attempt)
        } catch { if generation == attempt { fail(error) } }
    }
    /// Restore descriptors contain no cached access grant. Loading always asks
    /// Apple's shared database for the current participant status first.
    func restore(_ identity: ICloudSharedStoreIdentity) async {
        guard provisioned, status == .inactive || status == .failed else { return }
        let attempt = UUID(); generation = attempt; status = .accepting
        do {
            let account = try await accountID()
            guard account.utf8.elementsEqual(identity.accountID.utf8), generation == attempt else { throw ICloudSharedSessionError.unavailable }
            let participant = ICloudShareParticipantTransport(containerIdentifier: containerIdentifier, accountID: account)
            let zone = CKRecordZone.ID(zoneName: identity.zoneName, ownerName: identity.ownerID)
            let root = CKRecord.ID(recordName: identity.root.kind.rawValue + ":" + identity.root.id.uuidString.lowercased(), zoneID: zone)
            let grant = try await participant.load(shareID: .init(recordName: identity.shareName, zoneID: zone), rootID: root) { self.generation == attempt }
            try await install(grant, participant: participant, account: account, attempt: attempt)
        } catch { if generation == attempt { fail(error) } }
    }
    private func install(_ grant: ICloudShareParticipantTransport.Accepted, participant: ICloudShareParticipantTransport,
                         account: String, attempt: UUID) async throws {
        guard generation == attempt else { throw ICloudSharedSessionError.unavailable }
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
        try await participant.send(accepted: grant, store: checkpoint, stagingDirectory: assetDirectory(checkpoint)) { self.generation == attempt }
        let received = try await participant.receive(accepted: grant, store: checkpoint,
            imageDirectory: imageDirectory(checkpoint)) { self.generation == attempt }
        guard generation == attempt else { throw ICloudSharedSessionError.unavailable }
        context = received; knownPages.formUnion(received.canonical.pages.map(\.id)); pendingCount = try checkpoint.pendingChanges().count; status = .ready
    }
    func synchronize() async {
        guard status == .ready || status == .failed, let store, let transport, let accepted else { return }
        let attempt = generation; status = .synchronizing
        do {
            try await transport.send(accepted: accepted, store: store, stagingDirectory: assetDirectory(store)) { self.generation == attempt }
            let received = try await transport.receive(accepted: accepted, store: store,
                imageDirectory: imageDirectory(store)) { self.generation == attempt }
            guard generation == attempt else { return }
            context = received; knownPages.formUnion(received.canonical.pages.map(\.id)); pendingCount = try store.pendingChanges().count; status = .ready
        } catch {
            guard generation == attempt else { return }
            pendingCount = (try? store.pendingChanges().count) ?? pendingCount
            fail(error)
        }
    }
    @discardableResult func edit(pageID: UUID, revision: UUID, markdown: String) throws -> UUID {
        guard let store, let context, status == .ready || status == .synchronizing || status == .failed else { throw ICloudSharedSessionError.unavailable }
        let result = try store.editMarkdown(pageID: pageID, expectedPageRevision: revision, markdown: markdown, permission: context.permission)
        try reloadLocal(store, permission: context.permission)
        return result
    }
    func addComment(pageID: UUID, blockID: UUID?, quotation: String, body: String) throws {
        guard let store, let context, status == .ready || status == .synchronizing || status == .failed else { throw ICloudSharedSessionError.unavailable }
        _ = try store.addComment(pageID: pageID, blockID: blockID, quotedText: quotation, body: body, permission: context.permission)
        try reloadLocal(store, permission: context.permission)
    }
    func reply(commentID: UUID, body: String) throws {
        guard let store, let context, status == .ready || status == .synchronizing || status == .failed else { throw ICloudSharedSessionError.unavailable }
        _ = try store.replyToComment(commentID, body: body, permission: context.permission)
        try reloadLocal(store, permission: context.permission)
    }
    func resolve(commentID: UUID, resolved: Bool) throws {
        guard let store, let context, status == .ready || status == .synchronizing || status == .failed else { throw ICloudSharedSessionError.unavailable }
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
        generation = UUID(); context = nil; accepted = nil; transport = nil; store = nil; identity = nil; pendingCount = 0
        draftStore = nil; recoveredDrafts = []; knownPages = []
        status = provisioned ? .inactive : .notConfigured
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
    }
    private func assetDirectory(_ store: ICloudSharedDocumentStore) -> URL {
        directory.appendingPathComponent(store.fileURL.deletingPathExtension().lastPathComponent + "-outgoing")
    }
    private func imageDirectory(_ store: ICloudSharedDocumentStore) -> URL {
        directory.appendingPathComponent(store.fileURL.deletingPathExtension().lastPathComponent + "-media")
    }
    private func accountID() async throws -> String {
        let container = CKContainer(identifier: containerIdentifier)
        guard try await container.accountStatus() == .available else { throw ICloudSharedSessionError.unavailable }
        return try await container.userRecordID().recordName
    }
}
