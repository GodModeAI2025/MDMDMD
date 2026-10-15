import Foundation
import Observation
import CloudKit
import CryptoKit
#if canImport(SkriptumCore)
import SkriptumCore
#endif

enum ICloudOwnerPresentationError: Error { case notReady, pendingChanges, unresolvedConflicts, activeEdits }

enum ICloudAccountAvailability: Error {
    case noAccount, restricted, temporarilyUnavailable, undetermined
    static func require(_ status: CKAccountStatus) throws {
        switch status {
        case .available: return
        case .noAccount: throw Self.noAccount
        case .restricted: throw Self.restricted
        case .temporarilyUnavailable: throw Self.temporarilyUnavailable
        case .couldNotDetermine: throw Self.undetermined
        @unknown default: throw Self.undetermined
        }
    }
}

struct ICloudTransportFailure: Error { let diagnostic: ICloudFailureDiagnostic }

/// Only Foundation's explicit user-cancelled error is a silent native dialog
/// dismissal. A CloudKit operation or URL task cancellation can be a real error.
enum ICloudSharePresentationFailure {
    static func message(_ error: any Error) -> String? {
        let value = error as NSError
        if value.domain == NSCocoaErrorDomain, value.code == NSUserCancelledError { return nil }
        if error is CKError || error is ICloudTransportFailure || error is ICloudOwnerPresentationError ||
            error is ICloudAccountAvailability || error is ICloudShareOwnerError {
            return ICloudFailureDiagnostic.describe(error).message
        }
        return "Die iCloud-Freigabe konnte nicht abgeschlossen werden. Versuche es erneut; deine Texte bleiben erhalten."
    }
}

/// Safe actionable explanations: never display CloudKit userInfo, record names,
/// account identities, document contents or filesystem paths.
struct ICloudFailureDiagnostic: Sendable, Equatable {
    let message: String
    var code = "unknown"
    static func describe(_ error: any Error) -> Self {
        if let failure = error as? ICloudTransportFailure { return failure.diagnostic }
        var result = describeMessage(error)
        result.code = identifier(error)
        return result
    }
    /// Only fixed framework codes and payload-free local enums enter diagnostics.
    /// Never use NSError descriptions, userInfo, record names or arbitrary types.
    private static func identifier(_ error: any Error) -> String {
        if let cloud = error as? CKError {
            if cloud.code == .partialFailure {
                let codes = cloudFailureCodes(cloud).map(\.rawValue).sorted().prefix(8)
                return "CloudKit.\(cloud.code.rawValue)[\(codes.map(String.init).joined(separator: ","))]"
            }
            return "CloudKit.\(cloud.code.rawValue)"
        }
        if let value = error as? ICloudAccountAvailability { return "Account.\(value)" }
        if let value = error as? ICloudSyncJournalError { return "Outbox.\(value)" }
        if let value = error as? ICloudLibraryJournalBridgeError { return "Projection.\(value)" }
        if let value = error as? ICloudSyncEngineError { return "Transport.\(value)" }
        if let value = error as? ICloudOwnerConnectionChoiceError { return "Connection.\(value)" }
        if let value = error as? ICloudShareOwnerError { return "ShareOwner.\(value)" }
        if let value = error as? ICloudSharedStoreError { return "SharedStore.\(value)" }
        if error is CancellationError { return "Cancelled" }
        let value = error as NSError
        if value.domain == NSCocoaErrorDomain || value.domain == NSPOSIXErrorDomain {
            return "\(value.domain).\(value.code)"
        }
        return "unknown"
    }
    private static func cloudFailureCodes(_ error: CKError, depth: Int = 0) -> Set<CKError.Code> {
        guard error.code == .partialFailure, depth < 8,
              let failures = error.partialErrorsByItemID else { return [error.code] }
        return failures.values.reduce(into: Set<CKError.Code>()) { codes, value in
            guard let cloud = value as? CKError else { return }
            codes.formUnion(cloudFailureCodes(cloud, depth: depth + 1))
        }
    }
    private static func describeMessage(_ error: any Error) -> Self {
        if let account = error as? ICloudAccountAvailability {
            switch account {
            case .noAccount: return .init(message: "Apple stellt Scriptum derzeit keinen iCloud-Kontozugriff bereit. Das kann auch bei bestehender iCloud-Anmeldung auftreten. Versuche es erneut; deine Texte bleiben lokal erhalten.")
            case .restricted: return .init(message: "Der iCloud-Zugriff ist auf diesem Gerät eingeschränkt. Prüfe die Einschränkungen für Scriptum in den Systemeinstellungen.")
            case .temporarilyUnavailable, .undetermined: return .init(message: "Apple konnte den iCloud-Zugang gerade nicht bestätigen. Versuche es später erneut. Du musst dich dafür nicht abmelden.")
            }
        }
        if let cloud = error as? CKError {
            switch cloud.code {
            case .notAuthenticated: return .init(message: "Die iCloud-Anmeldung für Scriptum konnte gerade nicht bestätigt werden. Versuche es erneut; deine Texte bleiben lokal erhalten.")
            case .networkUnavailable, .networkFailure: return .init(message: "Die Verbindung zu iCloud ist unterbrochen. Prüfe die Internetverbindung und versuche es erneut.")
            case .quotaExceeded: return .init(message: "Der iCloud-Speicher ist voll. Schaffe freien Speicher und starte die Synchronisation erneut.")
            case .invalidArguments:
                return .init(message: "iCloud hat die Anfrage von Scriptum abgewiesen (CloudKit 12). Die App bzw. ihre iCloud-Konfiguration muss korrigiert werden. Deine Texte bleiben erhalten.")
            case .badContainer, .badDatabase, .missingEntitlement, .permissionFailure, .serverRejectedRequest:
                return .init(message: "iCloud hat den Zugriff dieser App abgewiesen (CloudKit \(cloud.code.rawValue)). Das ist ein Problem der App-Einrichtung; eine erneute iCloud-Anmeldung hilft hier nicht.")
            case .serviceUnavailable, .requestRateLimited, .zoneBusy:
                return .init(message: "iCloud ist vorübergehend ausgelastet. Versuche es später erneut; ausstehende Änderungen bleiben gespeichert.")
            case .partialFailure:
                // Deterministic code only, including nested partial failures;
                // record identifiers and server descriptions stay private.
                let codes = cloudFailureCodes(cloud).filter { $0 != .batchRequestFailed && $0 != .partialFailure }.sorted { $0.rawValue < $1.rawValue }
                if let code = codes.first { return describe(CKError(code)) }
                return .init(message: "iCloud konnte einige Änderungen noch nicht übertragen. Starte die Synchronisation erneut; deine Texte bleiben erhalten.")
            default: return .init(message: "iCloud konnte den Vorgang nicht abschließen (CloudKit \(cloud.code.rawValue)). Versuche es erneut; deine Texte bleiben erhalten.")
            }
        }
        if let presentation = error as? ICloudOwnerPresentationError {
            switch presentation {
            case .activeEdits: return .init(message: "Schließe die aktuelle Bearbeitung ab, bevor du den Inhalt teilst.")
            case .pendingChanges: return .init(message: "Für die Freigabe müssen alle Änderungen übertragen sein. Synchronisiere erneut und versuche es danach noch einmal.")
            case .unresolvedConflicts: return .init(message: "Kläre zuerst die Seitenkonflikte unter Dateien → iCloud → Seitenkonflikte prüfen.")
            case .notReady: return .init(message: "Die iCloud-Verbindung von Scriptum ist noch nicht bereit. Öffne Dateien → iCloud und starte die Verbindung erneut.")
            }
        }
        if let sharing = error as? ICloudShareOwnerError {
            switch sharing {
            case .accountChanged:
                return .init(message: "Der iCloud-Zugang oder der gewählte Inhalt hat sich während des Öffnens geändert. Öffne die Freigabe erneut.")
            case .invalidReceipt, .unconfirmedSave:
                return .init(message: "Die bestehende iCloud-Freigabe konnte nicht bestätigt werden. Synchronisiere erneut und öffne sie danach noch einmal. Es wurde keine neue Freigabe erstellt.")
            case .changedManifest:
                return .init(message: "Die Inhalte der noch nicht bestätigten Freigabe haben sich geändert. Sie kann nicht unverändert erneut angelegt werden. Vorhandene Freigaben und lokale Texte bleiben erhalten.")
            case .capacity:
                return .init(message: "Dieser Inhalt überschreitet die aktuelle Freigabegrenze. Teile eine kleinere Seite oder einen kleineren Space.")
            }
        }
        if error as? ICloudSyncJournalError == .capacityExceeded || error as? ICloudLibraryJournalBridgeError == .capacityExceeded || error as? ICloudSyncEngineError == .capacity {
            return .init(message: "Bei der Übertragung wurde eine Synchronisationsgrenze von Scriptum erreicht. Deine Texte und ausstehenden Änderungen bleiben erhalten. Teile die Diagnose, damit die App dafür korrigiert werden kann.")
        }
        if error as? ICloudSyncEngineError == .invalidRecord {
            return .init(message: "Scriptum konnte eine iCloud-Änderung nicht sicher verarbeiten. Die vorhandenen Texte werden nicht ersetzt. Teile die Diagnose; eine erneute iCloud-Anmeldung behebt diesen Fehler nicht.")
        }
        if error is ICloudSyncJournalError || error is ICloudLibraryJournalBridgeError || error is ICloudSharedStoreError || error is ICloudOwnerConnectionChoiceError || error as? ICloudSyncEngineError == .storage {
            return .init(message: "Scriptum konnte den lokalen Synchronisationsspeicher nicht öffnen oder sichern. Deine Texte bleiben erhalten. Aktualisiere die App und versuche es erneut.")
        }
        if error as? ICloudSyncEngineError == .accountUnavailable { return describe(ICloudAccountAvailability.undetermined) }
        return .init(message: "Die Synchronisation konnte nicht abgeschlossen werden. Versuche es erneut; deine lokalen Texte und ausstehenden Änderungen bleiben erhalten.")
    }
}

@MainActor @Observable final class ICloudLibrarySession: ICloudChangeHintTarget {
    enum Status { case notConfigured, inactive, checking, ready, syncing, failed, accountChanged }
    private(set) var status: Status
    private(set) var pendingCount = 0
    private(set) var incomingCount = 0
    private(set) var conflictCount = 0
    private(set) var lastSynchronized: Date?
    private(set) var connectionError: String?
    private(set) var failureCode: String?
    var diagnosticReport: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        let os = ProcessInfo.processInfo.operatingSystemVersion
        #if os(macOS)
        let platform = "macOS"
        #else
        let platform = "iOS/iPadOS"
        #endif
        return "Scriptum iCloud\nVersion: \(version) (\(build))\nSystem: \(platform) \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)\nStatus: \(status)\nLetzte erfasste Zähler:\nAusstehend: \(pendingCount)\nEmpfangen: \(incomingCount)\nKonflikte: \(conflictCount)\nFehler: \(failureCode ?? "none")"
    }
    @ObservationIgnored private weak var library: WritingLibrary?
    @ObservationIgnored private var binding: ICloudLibrarySyncBinding?
    @ObservationIgnored private var journal: ICloudSyncJournal?
    @ObservationIgnored private var engine: ICloudSyncEngine?
    @ObservationIgnored private var generation = UUID()
    /// Native dialog callbacks must belong to this exact connection, even when
    /// stop/activate reuses the same session object.
    var connectionRevision: UUID { generation }
    private let containerID = "iCloud.com.mobilebox.Skriptum"
    @ObservationIgnored private var foregroundRefresh: ICloudForegroundRefresh?
    @ObservationIgnored private var foregroundSyncPending = false
    @ObservationIgnored private var hintToken: UUID?
    @ObservationIgnored private var cloudHintPending = false
    private let provisioned: Bool
    @ObservationIgnored private let accountLookup: @MainActor () async throws -> String

    convenience init(library: WritingLibrary) {
        self.init(library: library,
            provisioned: Bundle.main.object(forInfoDictionaryKey: "ScriptumICloudProvisioned") as? Bool == true,
            accountLookup: {
                let container = CKContainer(identifier: "iCloud.com.mobilebox.Skriptum")
                try ICloudAccountAvailability.require(try await container.accountStatus())
                return try await container.userRecordID().recordName
            })
    }
    init(library: WritingLibrary, provisioned: Bool, accountLookup: @escaping @MainActor () async throws -> String) {
        self.library = library; self.provisioned = provisioned; self.accountLookup = accountLookup
        status = provisioned ? .inactive : .notConfigured
        foregroundRefresh = ICloudForegroundRefresh { [weak self] in await self?.synchronizeForeground() }
        setForegroundActive(library.iCloudForegroundScenes.isActive)
    }
    func activate(allowAccountChange: Bool = false) async {
        if status == .failed, engine != nil { await stop(rememberDisconnect: false) }
        await connect(restoring: nil, allowAccountChange: allowAccountChange)
    }
    func resumeSavedConnection() async {
        guard provisioned, status == .inactive || (status == .failed && engine == nil), let library else { return }
        do {
            let choice = try library.iCloudConnectionChoice()
            guard !choice.isRuntimeDisconnected, let selected = try choice.load(), selected.enabled else { return }
            await connect(restoring: selected, allowAccountChange: false)
        } catch {
            failureCode = ICloudFailureDiagnostic.describe(error).code
            status = .failed; connectionError = "Die gespeicherte iCloud-Auswahl konnte nicht gelesen werden. Es wurden keine Texte übertragen."
        }
    }
    private func connect(restoring selected: ICloudOwnerConnectionChoice.Selection?, allowAccountChange: Bool) async {
        guard provisioned, status == .inactive || status == .failed, let library, let store = library.store else { return }
        let attempt = UUID(); generation = attempt; status = .checking; connectionError = nil; failureCode = nil
        var startedTransport: ICloudSyncEngine?
        do {
            let choice = try library.iCloudConnectionChoice()
            let expected = try choice.load()
            let intent = choice.runtimeRevision
            if let selected {
                guard !choice.isRuntimeDisconnected, selected.enabled, selected == expected else { throw ICloudOwnerConnectionChoiceError.superseded }
            }
            let account = try await accountLookup()
            try Task.checkCancellation()
            guard generation == attempt else { return }
            try choice.confirm(expected, intent: intent)
            let scope = try choice.admit(accountID: account, selection: expected, allowAccountChange: allowAccountChange)
            let directory = library.iCloudStorageDirectory()
            let queue = try ICloudSyncJournal(directory: directory, scope: scope)
            let transport = try ICloudSyncEngine(containerIdentifier: containerID, journal: queue, directory: directory)
            startedTransport = transport
            try await transport.activate()
            guard generation == attempt else { await transport.stop(); return }
            try Task.checkCancellation()
            try choice.confirm(expected, intent: intent)
            if selected == nil { _ = try choice.enable(scope: scope, replacing: expected, intent: intent) }
            let attachment = try ICloudLibrarySyncBinding(store: store, journal: queue)
            journal = queue; engine = transport; binding = attachment
            attachment.changesQueued = { [weak self] in
                guard let self else { return }
                self.pendingCount = (try? queue.pendingCount()) ?? self.pendingCount
            }
            attachment.newChangesQueued = { [weak self] in
                guard let self else { return }
                self.setForegroundActive(self.library?.iCloudForegroundScenes.isActive == true)
                self.foregroundRefresh?.request()
            }
            pendingCount = try queue.pendingCount()
            status = .ready
            setForegroundActive(library.iCloudForegroundScenes.isActive)
            foregroundRefresh?.request()
            ICloudChangeHints.shared.remove(hintToken)
            hintToken = ICloudChangeHints.shared.register(self, scope: .owned)
        } catch {
            await startedTransport?.stop()
            guard generation == attempt else { return }
            if error as? ICloudOwnerConnectionChoiceError == .accountChanged { status = .accountChanged }
            else if error is CancellationError, Task.isCancelled { status = .inactive }
            else { status = .failed; recordFailure(error) }
        }
    }
    func stop(rememberDisconnect: Bool = true) async {
        foregroundRefresh?.setActive(false); foregroundSyncPending = false
        ICloudChangeHints.shared.remove(hintToken); hintToken = nil; cloudHintPending = false
        generation = UUID(); binding?.invalidate(); binding = nil
        let previous = engine, oldScope = journal?.scope; engine = nil; journal = nil
        connectionError = nil; failureCode = nil
        if provisioned, rememberDisconnect, let library {
            do { try library.iCloudConnectionChoice().disable(lastKnownScope: oldScope) }
            catch {
                failureCode = ICloudFailureDiagnostic.describe(error).code
                connectionError = "Die Verbindung ist für diese Sitzung getrennt. Die Auswahl für den nächsten App-Start konnte nicht gespeichert werden."
            }
        }
        status = provisioned ? (connectionError == nil ? .inactive : .failed) : .notConfigured
        pendingCount = 0; incomingCount = 0; conflictCount = 0; lastSynchronized = nil
        await previous?.stop()
    }
    func createShare(scope: ICloudShareScope) async throws -> CKShare {
        guard provisioned, status == .ready else {
            if let connectionError { throw ICloudTransportFailure(diagnostic: .init(message: connectionError, code: failureCode ?? "unknown")) }
            throw ICloudOwnerPresentationError.notReady
        }
        await synchronize()
        guard status == .ready else {
            if let connectionError { throw ICloudTransportFailure(diagnostic: .init(message: connectionError, code: failureCode ?? "unknown")) }
            throw ICloudOwnerPresentationError.notReady
        }
        guard conflictCount == 0 else { throw ICloudOwnerPresentationError.unresolvedConflicts }
        guard pendingCount == 0, incomingCount == 0 else { throw ICloudOwnerPresentationError.pendingChanges }
        guard library?.store?.hasActiveEdits != true else { throw ICloudOwnerPresentationError.activeEdits }
        guard let library, let store = library.store,
              let engine, let journal else { throw ICloudOwnerPresentationError.notReady }
        let connection = try ICloudOwnerShareConnection(choice: library.iCloudConnectionChoice(), scope: journal.scope)
        let attempt = generation; status = .syncing
        defer { drainCloudHint(attempt: attempt) }
        do {
            let rootName = try ICloudOwnerShareReceipts.managementRoot(for: scope, snapshot: store.snapshot)
            let receipts = try ICloudOwnerShareReceipts(directory: library.iCloudStorageDirectory(), scope: journal.scope)
            let transport = ICloudShareOwnerTransport(containerIdentifier: containerID, scope: journal.scope)
            let isCurrent = {
                self.generation == attempt && self.library === library && library.store === store &&
                self.engine === engine && self.journal === journal && !store.hasActiveEdits &&
                !library.isReadOnlyRecovery && connection.isCurrent &&
                (try? ICloudOwnerShareReceipts.managementRoot(for: scope, snapshot: store.snapshot)) == rootName
            }
            // The management dialog is read-only here. Normal synchronization
            // reconciles membership before presenting the existing share.
            if let operation = try receipts.managementOperation(for: scope, snapshot: store.snapshot) {
                let share = try await transport.reopen(operation, isCurrent: isCurrent)
                try await ICloudOwnerShareManagementReader.confirmPresentation(transportIsActive: {
                    await engine.status == .active
                }, isCurrent: {
                    try isCurrent() && receipts.managementOperation(for: scope, snapshot: store.snapshot) == operation
                })
                status = .ready
                return share
            }
            let plan = try ICloudShareRecordPlan(scope: scope, snapshot: store.snapshot)
            let title: String
            switch scope {
            case .page(let id): title = store.snapshot.pages.first(where: { $0.id == id })?.title ?? "Geteilte Seite"
            case .space(let id): title = store.snapshot.spaces.first(where: { $0.id == id })?.title ?? "Geteilter Space"
            }
            let result = try await transport.create(plan: plan, title: title, receipts: receipts, isCurrent: isCurrent)
            try Task.checkCancellation()
            guard isCurrent() else { throw ICloudOwnerPresentationError.notReady }
            let current = try ICloudShareRecordPlan(scope: scope, snapshot: store.snapshot)
            guard current.entries == plan.entries else { throw ICloudShareOwnerError.changedManifest }
            let metadata = try ICloudShareRecordBuilder.confirmedMetadata(plan: plan, records: result.records, snapshot: store.snapshot)
            try await engine.registerOwnedShareMetadata(metadata)
            try Task.checkCancellation()
            guard isCurrent() else { throw ICloudOwnerPresentationError.notReady }
            status = .ready
            return result.share
        } catch {
            let transportActive = await engine.status == .active
            if generation == attempt {
                let current = transportActive && self.library === library && library.store === store &&
                    self.engine === engine && self.journal === journal && connection.isCurrent
                status = ICloudRefreshCancellation.isExpectedPause(error,
                    callerCancelled: Task.isCancelled, transportCurrent: current) ? .ready : .failed
                if status == .failed { recordFailure(error) }
            }
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
            if generation == attempt { library.reload(); status = .failed; recordFailure(error) }
            throw error
        }
    }
    func setForegroundActive(_ active: Bool) {
        foregroundRefresh?.setActive(active && provisioned)
    }
    private func synchronizeForeground() async {
        guard library?.iCloudForegroundScenes.isActive == true else {
            setForegroundActive(false); return
        }
        if status == .syncing || status == .checking { foregroundSyncPending = true; return }
        if status == .inactive || (status == .failed && engine == nil) { await resumeSavedConnection() }
        else { await synchronize() }
    }
    private func drainCloudHint(attempt: UUID) {
        guard generation == attempt, status == .ready else { return }
        if foregroundSyncPending {
            foregroundSyncPending = false
            foregroundRefresh?.request()
        }
        guard cloudHintPending else { return }
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
        let attempt = generation; status = .syncing; connectionError = nil; failureCode = nil
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
            var progress = true, sharesReconciled = false
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
                                library.mediaPreviewGeneration = UUID()
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
                if !progress, !sharesReconciled {
                    sharesReconciled = true
                    if incoming.isEmpty, try journal.pendingCount() == 0,
                       await engine.unresolvedConflictCount() == 0, !store.hasActiveEdits,
                       try await reconcileOwnedShares(library: library, store: store, engine: engine, journal: journal, attempt: attempt) {
                        try await engine.refreshForConflictReview()
                        incoming = await engine.incomingSnapshot()
                        progress = !incoming.isEmpty
                    }
                }
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
        } catch {
            guard generation == attempt else { return }
            let transportCurrent = await engine.status == .active
            guard generation == attempt else { return }
            status = ICloudRefreshCancellation.isExpectedPause(error,
                callerCancelled: Task.isCancelled, transportCurrent: transportCurrent) ? .ready : .failed
            if status == .failed { recordFailure(error) }
        }
    }
    private func reconcileOwnedShares(library: WritingLibrary, store: LibraryStore, engine: ICloudSyncEngine,
                                      journal: ICloudSyncJournal, attempt: UUID) async throws -> Bool {
        let receipts = try ICloudOwnerShareReceipts(directory: library.iCloudStorageDirectory(), scope: journal.scope)
        let operations = try receipts.confirmedOperations()
        guard !operations.isEmpty else { return false }
        let connection = try ICloudOwnerShareConnection(choice: library.iCloudConnectionChoice(), scope: journal.scope)
        let transport = ICloudShareOwnerTransport(containerIdentifier: containerID, scope: journal.scope)
        var changed = false
        for operation in operations {
            let parts = operation.rootName.split(separator: ":")
            guard parts.count == 2, let id = UUID(uuidString: String(parts[1])) else { throw ICloudShareOwnerError.invalidReceipt }
            let scope: ICloudShareScope = parts[0] == "page" ? .page(id) : .space(id)
            guard (try? ICloudOwnerShareReceipts.managementRoot(for: scope, snapshot: store.snapshot)) == operation.rootName else { continue }
            let snapshot = store.snapshot, revision = store.durableRevision
            let plan = try ICloudShareRecordPlan(scope: scope, snapshot: snapshot)
            guard try receipts.needsExpansion(plan, operation: operation) else { continue }
            let isCurrent = {
                self.generation == attempt && self.library === library && library.store === store &&
                self.engine === engine && self.journal === journal && !store.hasActiveEdits &&
                !library.isReadOnlyRecovery && connection.isCurrent && store.durableRevision == revision &&
                (try? receipts.confirmedOperations().contains(operation)) == true
            }
            do {
                guard let result = try await transport.expand(plan: plan, snapshot: snapshot, operation: operation, isCurrent: isCurrent) else { continue }
                guard isCurrent() else { throw ICloudSyncEngineError.stopped }
                if !result.records.isEmpty {
                    let metadata = try ICloudShareRecordBuilder.confirmedMetadata(plan: plan, records: result.records, snapshot: snapshot)
                    try await engine.registerOwnedShareMetadata(metadata)
                    changed = true
                }
                guard isCurrent() else { throw ICloudSyncEngineError.stopped }
                try receipts.confirmExpansion(plan, operation: operation)
            } catch {
                // An editor can commit while the network is saving. Keep that
                // new durable outbox and fetch the server result before retry.
                if generation == attempt, connection.isCurrent, store.durableRevision != revision || store.hasActiveEdits { return true }
                throw error
            }
        }
        return changed
    }
    private func priority(_ kind: ICloudSyncRecordKind?) -> Int {
        switch kind { case .space: 0; case .image: 1; case .page: 2; case .comment: 3; case .revision: 4; case nil: 5 }
    }
    private func recordFailure(_ error: any Error) {
        let diagnostic = ICloudFailureDiagnostic.describe(error)
        connectionError = diagnostic.message; failureCode = diagnostic.code
    }
}
