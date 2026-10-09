import Foundation
#if canImport(SkriptumWorkspaceClient)
import SkriptumWorkspaceClient
#endif

protocol WorkspaceAccountAdmissionTicket: Sendable {}

struct WorkspaceAccountLoadedCredential {
    let credential: WorkspaceCredential
    let ticket: any WorkspaceAccountAdmissionTicket
}

enum WorkspaceAccountDenialReason { case localLogout, logoutAll, accountDeletion, unauthorized }
enum WorkspaceAccountDeletionResult: Equatable, Sendable {
    case cancelled, superseded, wrongAccount, authenticationUnavailable, localPersistenceUnavailable
    case confirmedAccountTombstone, remoteDeletionUnknown
}

enum WorkspaceAccountAdmissionFailure: Error { case staleTicket, unavailable }

@MainActor protocol WorkspaceAccountAdmission: AnyObject {
    func capture(scope: WorkspaceAccountScope) throws -> any WorkspaceAccountAdmissionTicket
    func beginEnrollment(expected: any WorkspaceAccountAdmissionTicket) throws -> any WorkspaceAccountAdmissionTicket
    func deny(expected: any WorkspaceAccountAdmissionTicket, reason: WorkspaceAccountDenialReason) throws -> any WorkspaceAccountAdmissionTicket
    func load(expected: any WorkspaceAccountAdmissionTicket) async throws -> WorkspaceAccountLoadedCredential?
    func remove(expected: any WorkspaceAccountAdmissionTicket) async throws
}

struct WorkspaceAccountVerifiedSession: Equatable, Sendable {
    let accountID: UUID
    let sessionID: UUID
    let expiresAt: Date
}

/// Production driver retains the real enrollment privately for gated persistence.
/// Proof acquisition and server verification are never inferred from presentation state.
@MainActor protocol WorkspaceAccountIdentityDriver: AnyObject {
    func restore() async throws -> WorkspaceAccountVerifiedSession
    func enroll() async throws -> WorkspaceAccountVerifiedSession
    func save(expected: any WorkspaceAccountAdmissionTicket) async throws -> any WorkspaceAccountAdmissionTicket
    func discardEnrollment() async -> WorkspaceLogoutOutcome
    func logout(allSessions: Bool) async -> WorkspaceLogoutOutcome
    func deleteFreshEnrollment() async throws -> WorkspaceAccountDeletionOutcome
    func invalidate() async
    func cancelProof()
}

enum WorkspaceAccountCoordinatorError: Error { case capacity, wrongDeployment }

/// One process-shared instance is injected by app composition. No default endpoint,
/// account, Keychain enumeration, document mutation or library upload exists here.
@MainActor final class WorkspaceAccountCoordinator {
    @MainActor private final class Slot {
        var changed: (() -> Void)?
        var generation = UUID()
        var state: WorkspaceAccountState = .signedOut { didSet { changed?() } }
        var driver: (any WorkspaceAccountIdentityDriver)?
        var retryDriver: (any WorkspaceAccountIdentityDriver)?
        var retryTicket: (any WorkspaceAccountAdmissionTicket)?
        var pending = 0
        var deletionID: UUID? { didSet { changed?() } }
        var deletionCleanup: DeletionCleanup? { didSet { changed?() } }
        var freshSessionCleanupOutcome: WorkspaceLogoutOutcome? { didSet { changed?() } }
    }
    private struct Attempt {
        let id: UUID
        let epoch: UUID
        let driver: any WorkspaceAccountIdentityDriver
        var resolvedScope: WorkspaceAccountScope?
        var resolvedGeneration: UUID?
    }
    private final class DeletionAttempt {
        let id = UUID()
        let scope: WorkspaceAccountScope
        let driver: any WorkspaceAccountIdentityDriver
        var generation: UUID
        var cancelled = false
        init(scope: WorkspaceAccountScope, generation: UUID, driver: any WorkspaceAccountIdentityDriver) {
            self.scope = scope; self.generation = generation; self.driver = driver
        }
    }
    private struct DeletionCleanup {
        let id = UUID()
        let reservationID: UUID
        let generation: UUID
        let fresh: any WorkspaceAccountIdentityDriver
        let original: (any WorkspaceAccountIdentityDriver)?
        var ticket: (any WorkspaceAccountAdmissionTicket)?
        var outcome: WorkspaceAccountRemoteOutcome
        var freshCleanup: WorkspaceLogoutOutcome?
    }
    private var deletions: [UUID: DeletionAttempt] = [:] { didSet { publishPresentations() } }
    private var deletionReportIDs: [UUID: UUID] = [:]
    private var liveDeletions = 0

    let deployment: WorkspaceDeploymentConfiguration
    private let admission: any WorkspaceAccountAdmission
    private let makeIdentity: (WorkspaceCredential?, UUID) throws -> any WorkspaceAccountIdentityDriver
    private let invalidateConnections: (WorkspaceAccountScope) -> Void
    private let capacity: Int
    private var slots: [WorkspaceAccountScope: Slot] = [:]
    private var windows: [UUID: WorkspaceAccountScope] = [:] { didSet { publishPresentations() } }
    private var attempts: [UUID: Attempt] = [:] { didSet { publishPresentations() } }
    private var localStates: [UUID: WorkspaceAccountState] = [:] { didSet { publishPresentations() } }
    private var epoch = UUID()

    private final class WeakPresentation {
        weak var value: WorkspaceAccountPresentation?
        init(_ value: WorkspaceAccountPresentation) { self.value = value }
    }
    private var presentations: [UUID: WeakPresentation] = [:]
    private var operationOutcomes: [UUID: WorkspaceAccountOperationOutcome] = [:]
    private struct DiscoverySignature: Equatable {
        let scope: WorkspaceAccountScope
        let generation: UUID
        let driverID: ObjectIdentifier
    }
    private final class DiscoveryObserver {
        weak var owner: AnyObject?
        let notify: @MainActor (UUID) -> Void
        init(owner: AnyObject, notify: @escaping @MainActor (UUID) -> Void) {
            self.owner = owner; self.notify = notify
        }
    }
    private var discoveryObservers: [UUID: DiscoveryObserver] = [:]
    private var discoverySignatures: [UUID: DiscoverySignature] = [:]

    func addDiscoveryInvalidationObserver(owner: AnyObject,
        _ observer: @escaping @MainActor (UUID) -> Void) throws -> UUID {
        discoveryObservers = discoveryObservers.filter { $0.value.owner != nil }
        guard discoveryObservers.count < capacity else { throw WorkspaceAccountCoordinatorError.capacity }
        let token = UUID()
        discoveryObservers[token] = DiscoveryObserver(owner: owner, notify: observer)
        return token
    }
    func removeDiscoveryInvalidationObserver(_ token: UUID) {
        discoveryObservers.removeValue(forKey: token)
    }
    private func discoverySignature(windowID: UUID) -> DiscoverySignature? {
        guard let scope = windows[windowID], let slot = slots[scope],
              case .active(let activeScope, _, let expiry) = state(windowID: windowID),
              activeScope == scope, expiry > Date(),
              let driver = slot.driver as? any WorkspaceLibraryDiscoveryDriver else { return nil }
        return DiscoverySignature(scope: scope, generation: slot.generation, driverID: ObjectIdentifier(driver))
    }
    func discoveryAccess(windowID: UUID) throws -> WorkspaceLibraryDiscoveryAccess {
        guard let signature = discoverySignature(windowID: windowID),
              let driver = slots[signature.scope]?.driver as? any WorkspaceLibraryDiscoveryDriver else {
            throw WorkspaceAccountAdmissionFailure.unavailable
        }
        return WorkspaceLibraryDiscoveryAccess(scope: signature.scope, driver: driver) { [weak self] requestedWindow in
            guard requestedWindow == windowID,
                  self?.discoverySignature(windowID: windowID) == signature else {
                throw WorkspaceAccountAdmissionFailure.staleTicket
            }
        }
    }
    private func publishDiscoveryInvalidations() {
        discoveryObservers = discoveryObservers.filter { $0.value.owner != nil }
        var current: [UUID: DiscoverySignature] = [:]
        for window in windows.keys { if let signature = discoverySignature(windowID: window) { current[window] = signature } }
        let changed = Set(discoverySignatures.keys).union(current.keys).filter { discoverySignatures[$0] != current[$0] }
        discoverySignatures = current
        let observers = Array(discoveryObservers.values)
        for window in changed { for observer in observers where observer.owner != nil { observer.notify(window) } }
    }

    func observe(windowID: UUID) throws -> WorkspaceAccountPresentation {
        presentations = presentations.filter { $0.value.value != nil }
        if let existing = presentations[windowID]?.value { publishPresentation(existing); return existing }
        guard presentations.count < capacity else { throw WorkspaceAccountCoordinatorError.capacity }
        let model = WorkspaceAccountPresentation(windowID: windowID)
        presentations[windowID] = WeakPresentation(model)
        publishPresentation(model)
        return model
    }

    func unsubscribe(windowID: UUID) {
        let old = presentations.removeValue(forKey: windowID)?.value
        operationOutcomes.removeValue(forKey: windowID)
        old?.publish(state: .signedOut, outcome: nil, cleanup: nil)
    }

    private func publishPresentations() {
        publishDiscoveryInvalidations()
        presentations = presentations.filter { $0.value.value != nil }
        for item in presentations.values { if let model = item.value { publishPresentation(model) } }
    }

    private func publishPresentation(_ model: WorkspaceAccountPresentation) {
        let state = state(windowID: model.windowID)
        let inferred: WorkspaceAccountOperationOutcome?
        switch state {
        case .active: inferred = .signedIn
        case .unavailable(let reason): inferred = .unavailable(reason)
        case .localDenied(_, .confirmedAccountTombstone): inferred = .deletion(.confirmedAccountTombstone)
        case .localDenied(_, .deletionUnknown): inferred = .deletion(.remoteDeletionUnknown)
        case .localDenied(_, let outcome): inferred = .logout(outcome)
        default: inferred = nil
        }
        let scope = windows[model.windowID]
        model.publish(state: state, outcome: operationOutcomes[model.windowID] ?? inferred,
            cleanup: scope.flatMap { slots[$0]?.freshSessionCleanupOutcome },
            canRetryDeletionLocalCleanup: deletionCleanupScope(windowID: model.windowID) != nil)
    }

    init(deployment: WorkspaceDeploymentConfiguration, admission: any WorkspaceAccountAdmission,
         capacity: Int = 64, invalidateConnections: @escaping (WorkspaceAccountScope) -> Void = { _ in },
         makeIdentity: @escaping (WorkspaceCredential?, UUID) throws -> any WorkspaceAccountIdentityDriver) throws {
        guard (1...64).contains(capacity) else { throw WorkspaceAccountCoordinatorError.capacity }
        self.deployment = deployment
        self.admission = admission
        self.capacity = capacity
        self.invalidateConnections = invalidateConnections
        self.makeIdentity = makeIdentity
    }

    func attach(windowID: UUID, scope: WorkspaceAccountScope) throws {
        try validate(scope)
        guard windows[windowID] != nil || windows.count < capacity else { throw WorkspaceAccountCoordinatorError.capacity }
        _ = try slot(scope)
        windows[windowID] = scope
    }

    func state(windowID: UUID) -> WorkspaceAccountState {
        if let deletion = deletions[windowID], !deletion.cancelled {
            if slots[deletion.scope]?.deletionID == deletion.id { return .deleting(scope: deletion.scope) }
            return .reauthenticatingForDeletion(scope: deletion.scope, attemptID: deletion.id)
        }
        if let attempt = attempts[windowID] { return .signingIn(attemptID: attempt.id) }
        guard let scope = windows[windowID], let slot = slots[scope] else { return localStates[windowID] ?? .signedOut }
        return slot.state
    }

    func detach(windowID: UUID) {
        cancelSignIn(windowID: windowID)
        cancelAccountDeletion(windowID: windowID)
        windows.removeValue(forKey: windowID)
        localStates.removeValue(forKey: windowID)
        deletionReportIDs.removeValue(forKey: windowID)
        unsubscribe(windowID: windowID)
        prune()
    }

    func cancelSignIn(windowID: UUID) {
        guard let attempt = attempts.removeValue(forKey: windowID) else { return }
        attempt.driver.cancelProof()
        operationOutcomes[windowID] = .cancelled
        publishPresentations()
        Task { await attempt.driver.invalidate() }
    }

    func restore(windowID: UUID) async {
        guard let scope = windows[windowID], let slot = slots[scope], slot.deletionID == nil else { return }
        operationOutcomes.removeValue(forKey: windowID)
        slot.generation = UUID()
        let generation = slot.generation
        slot.pending += 1
        defer { slot.pending -= 1; prune() }
        var loadedTicket: (any WorkspaceAccountAdmissionTicket)?
        slot.state = .restoring(scope: scope)
        do {
            let ticket = try admission.capture(scope: scope)
            guard let loaded = try await admission.load(expected: ticket) else {
                if current(scope, generation) { slot.state = .signedOut }
                return
            }
            let credential = loaded.credential
            loadedTicket = loaded.ticket
            guard current(scope, generation), windows[windowID] == scope else { return }
            guard credential.origin == scope.origin, credential.profileID == scope.profileID,
                  credential.accountID == scope.accountID else { throw WorkspaceClientError.invalidCredential }
            let driver = try makeIdentity(credential, windowID)
            if let discovery = driver as? any WorkspaceLibraryDiscoveryDriver { try discovery.adopt(loaded) }
            let session = try await driver.restore()
            guard current(scope, generation), windows[windowID] == scope else {
                await driver.invalidate()
                return
            }
            try validate(session, scope: scope)
            slot.driver = driver
            slot.state = .active(scope: scope, sessionID: session.sessionID, expiresAt: session.expiresAt)
        } catch {
            if current(scope, generation) {
                slot.state = .unavailable(.credentialUnavailable)
                if let loadedTicket, (error as? WorkspaceClientError) == .unauthenticated {
                    do {
                        let denial = try admission.deny(expected: loadedTicket, reason: .unauthorized)
                        try await admission.remove(expected: denial)
                    } catch { /* Exact captured-ticket CAS protects a newer login. */ }
                }
            }
        }
    }

    func signIn(windowID: UUID) async {
        guard attempts[windowID] == nil, attempts.count + liveDeletions < min(8, capacity),
              windows[windowID] != nil || localStates[windowID] != nil || windows.count + localStates.count < capacity else { return }
        let driver: any WorkspaceAccountIdentityDriver
        do { driver = try makeIdentity(nil, windowID) }
        catch { return }
        operationOutcomes.removeValue(forKey: windowID)
        let attempt = Attempt(id: UUID(), epoch: epoch, driver: driver)
        attempts[windowID] = attempt
        localStates[windowID] = .signedOut
        defer {
            // Terminal cleanup belongs to this attempt, independent of account
            // generation. A replacement attempt in the same window survives.
            if attempts[windowID]?.id == attempt.id { attempts.removeValue(forKey: windowID) }
            prune()
        }
        do {
            let session = try await driver.enroll()
            guard valid(attempt, windowID: windowID) else {
                _ = await driver.discardEnrollment()
                return
            }
            let scope = try WorkspaceAccountScope(origin: deployment.origin, profileID: deployment.profileID, accountID: session.accountID)
            try validate(session, scope: scope)
            let slot = try slot(scope)
            guard slot.deletionID == nil else { _ = await driver.discardEnrollment(); return }
            slot.pending += 1
            defer { slot.pending -= 1 }
            slot.generation = UUID()
            let generation = slot.generation
            let ticket = try admission.beginEnrollment(expected: admission.capture(scope: scope))
            var resolved = attempt
            resolved.resolvedScope = scope
            resolved.resolvedGeneration = generation
            attempts[windowID] = resolved
            let saved = try await driver.save(expected: ticket)
            guard valid(attempt, windowID: windowID), current(scope, generation) else {
                await cleanupSaved(saved, scope: scope, slot: slot, generation: generation, driver: driver, windowID: windowID)
                _ = await driver.discardEnrollment()
                return
            }
            slot.driver = driver
            slot.retryDriver = nil
            slot.retryTicket = nil
            slot.state = .active(scope: scope, sessionID: session.sessionID, expiresAt: session.expiresAt)
            windows[windowID] = scope
            localStates.removeValue(forKey: windowID)
            attempts.removeValue(forKey: windowID)
        } catch {
            _ = await driver.discardEnrollment()
            if valid(attempt, windowID: windowID) {
                operationOutcomes[windowID] = .authenticationUnavailable
                attempts.removeValue(forKey: windowID)
            }
        }
    }

    func logout(scope: WorkspaceAccountScope, allSessions: Bool) async {
        guard (try? validate(scope)) != nil, let slot = slots[scope] else { return }
        let initiating = slot.driver ?? slot.retryDriver
        slot.pending += 1
        defer { slot.pending -= 1; prune() }
        // All local subscribers see fencing before the first suspension.
        slot.generation = UUID()
        let generation = slot.generation
        for (window, scopeValue) in windows where scopeValue == scope { operationOutcomes.removeValue(forKey: window) }
        slot.state = .signingOut(scope: scope)
        slot.driver = nil
        epoch = UUID()
        for (window, attempt) in Array(attempts) {
            if attempt.resolvedScope == nil || attempt.resolvedScope == scope {
                cancelSignIn(windowID: window)
            }
        }
        for (window, attempt) in Array(deletions) where attempt.scope == scope { cancelAccountDeletion(windowID: window) }
        invalidateConnections(scope)
        let denied: any WorkspaceAccountAdmissionTicket
        do {
            denied = try admission.deny(expected: admission.capture(scope: scope), reason: allSessions ? .logoutAll : .localLogout)
        } catch {
            slot.state = .unavailable(.localSignOutPersistenceUnavailable)
            slot.retryDriver = initiating
            slot.retryTicket = try? admission.capture(scope: scope)
            return
        }
        let outcome = await initiating?.logout(allSessions: allSessions) ?? .remoteRevocationUnknown
        do { try await admission.remove(expected: denied) }
        catch {
            if current(scope, generation) { slot.state = .unavailable(.credentialUnavailable) }
            return
        }
        guard current(scope, generation) else { return }
        slot.retryDriver = nil
        slot.retryTicket = nil
        slot.state = .localDenied(scope: scope, remoteOutcome: outcome == .confirmedRemoteRevocation ? .confirmedRevocation : .revocationUnknown)
    }

    /// Separate targeted-session cleanup metadata; never implies account deletion.
    func deletionSessionCleanupOutcome(scope: WorkspaceAccountScope) -> WorkspaceLogoutOutcome? {
        slots[scope]?.freshSessionCleanupOutcome
    }

    /// Operational cleanup discovery, not authentication or presentation authority.
    func deletionCleanupScope(windowID: UUID) -> WorkspaceAccountScope? {
        guard let scope = windows[windowID], slots[scope]?.deletionCleanup != nil else { return nil }
        return scope
    }

    func cancelAccountDeletion(windowID: UUID) {
        guard let attempt = deletions.removeValue(forKey: windowID) else { return }
        attempt.cancelled = true
        attempt.driver.cancelProof()
        publishPresentations()
    }

    func deleteAccount(windowID: UUID, scope: WorkspaceAccountScope) async -> WorkspaceAccountDeletionResult {
        guard windows[windowID] == scope, let slot = slots[scope], slot.deletionID == nil,
              deletions[windowID] == nil, attempts[windowID] == nil,
              attempts.count + liveDeletions < min(8, capacity) else { return .superseded }
        let fresh: any WorkspaceAccountIdentityDriver
        do { try validate(scope); fresh = try makeIdentity(nil, windowID) }
        catch { return .authenticationUnavailable }
        operationOutcomes.removeValue(forKey: windowID)
        slot.freshSessionCleanupOutcome = nil
        let attempt = DeletionAttempt(scope: scope, generation: slot.generation, driver: fresh)
        deletions[windowID] = attempt
        deletionReportIDs[windowID] = attempt.id
        slot.pending += 1; liveDeletions += 1
        defer {
            if deletions[windowID]?.id == attempt.id { deletions.removeValue(forKey: windowID) }
            slot.pending -= 1; liveDeletions -= 1
            if slot.deletionID == attempt.id && slot.deletionCleanup == nil { slot.deletionID = nil }
            publishPresentations()
            prune()
        }
        do {
            let session = try await fresh.enroll()
            guard deletionValid(attempt, windowID: windowID) else {
                _ = await discardDeletionFresh(attempt, windowID: windowID, slot: slot)
                return completeDeletion(attempt.cancelled || Task.isCancelled ? .cancelled : .superseded, attempt: attempt, windowID: windowID)
            }
            guard session.accountID == scope.accountID else { _ = await discardDeletionFresh(attempt, windowID: windowID, slot: slot); return completeDeletion(.wrongAccount, attempt: attempt, windowID: windowID) }
            try validate(session, scope: scope)
        } catch {
            _ = await discardDeletionFresh(attempt, windowID: windowID, slot: slot)
            return completeDeletion(attempt.cancelled || Task.isCancelled ? .cancelled : .authenticationUnavailable, attempt: attempt, windowID: windowID)
        }
        // No suspension between exact fresh-account validation, reservation,
        // local fencing and durable denial. No fresh credential is saved.
        let original = slot.driver
        slot.deletionID = attempt.id
        slot.generation = UUID(); attempt.generation = slot.generation
        slot.driver = nil; slot.state = .deleting(scope: scope)
        invalidateConnections(scope)
        epoch = UUID()
        for (window, login) in Array(attempts) where login.resolvedScope == nil || login.resolvedScope == scope { cancelSignIn(windowID: window) }
        let denied: any WorkspaceAccountAdmissionTicket
        do { denied = try admission.deny(expected: admission.capture(scope: scope), reason: .accountDeletion) }
        catch {
            slot.state = .unavailable(.localSignOutPersistenceUnavailable)
            slot.deletionCleanup = DeletionCleanup(reservationID: attempt.id, generation: attempt.generation, fresh: fresh, original: original,
                ticket: nil, outcome: .deletionUnknown, freshCleanup: nil)
            return completeDeletion(.localPersistenceUnavailable, attempt: attempt, windowID: windowID)
        }
        if let original { Task { await original.invalidate() } }
        let outcome: WorkspaceAccountDeletionOutcome
        do {
            guard deletionValid(attempt, windowID: windowID) else { throw CancellationError() }
            outcome = try await fresh.deleteFreshEnrollment()
        } catch { outcome = .remoteDeletionUnknown }
        let cleanup = await fresh.discardEnrollment()
        slot.freshSessionCleanupOutcome = cleanup
        let remote: WorkspaceAccountRemoteOutcome = outcome == .confirmedAccountTombstone ? .confirmedAccountTombstone : .deletionUnknown
        slot.deletionCleanup = DeletionCleanup(reservationID: attempt.id, generation: attempt.generation, fresh: fresh, original: nil,
            ticket: denied, outcome: remote, freshCleanup: cleanup)
        await retryDeletionLocalCleanup(scope: scope)
        return completeDeletion(outcome == .confirmedAccountTombstone ? .confirmedAccountTombstone : .remoteDeletionUnknown, attempt: attempt, windowID: windowID)
    }

    private func completeDeletion(_ result: WorkspaceAccountDeletionResult, attempt: DeletionAttempt, windowID: UUID) -> WorkspaceAccountDeletionResult {
        if deletionReportIDs[windowID] == attempt.id, windows[windowID] == attempt.scope,
           current(attempt.scope, attempt.generation) {
            operationOutcomes[windowID] = .deletion(result)
            publishPresentations()
        }
        return result
    }

    func retryDeletionLocalCleanup(scope: WorkspaceAccountScope) async {
        guard let slot = slots[scope], var cleanup = slot.deletionCleanup else { return }
        slot.pending += 1
        defer { slot.pending -= 1; prune() }
        guard current(scope, cleanup.generation) else {
            await retireStaleCleanup(cleanup, slot: slot)
            return
        }
        do {
            if cleanup.ticket == nil {
                cleanup.ticket = try admission.deny(expected: admission.capture(scope: scope), reason: .accountDeletion)
                guard ownsCleanup(slot, cleanup) else { return }
                slot.deletionCleanup = cleanup
            }
            guard let ticket = cleanup.ticket else { return }
            try await admission.remove(expected: ticket)
            guard ownsCleanup(slot, cleanup) else { return }
            guard current(scope, cleanup.generation) else { await retireStaleCleanup(cleanup, slot: slot); return }
            if cleanup.freshCleanup == nil {
                cleanup.freshCleanup = await cleanup.fresh.discardEnrollment()
                guard ownsCleanup(slot, cleanup) else { return }
                guard current(scope, cleanup.generation) else { await retireStaleCleanup(cleanup, slot: slot); return }
                slot.deletionCleanup = cleanup
            }
            if let original = cleanup.original {
                await original.invalidate()
                guard ownsCleanup(slot, cleanup), current(scope, cleanup.generation) else { return }
            }
            for (window, scopeValue) in windows where scopeValue == scope { operationOutcomes.removeValue(forKey: window) }
            slot.freshSessionCleanupOutcome = cleanup.freshCleanup
            slot.state = .localDenied(scope: scope, remoteOutcome: cleanup.outcome)
            slot.deletionCleanup = nil
            slot.deletionID = nil
        } catch {
            if ownsCleanup(slot, cleanup), current(scope, cleanup.generation) {
                slot.state = .unavailable(.localSignOutPersistenceUnavailable)
            }
        }
    }

    private func ownsCleanup(_ slot: Slot, _ cleanup: DeletionCleanup) -> Bool {
        slot.deletionCleanup?.id == cleanup.id && slot.deletionID == cleanup.reservationID
    }

    private func retireStaleCleanup(_ cleanup: DeletionCleanup, slot: Slot) async {
        _ = await cleanup.fresh.discardEnrollment()
        // Targeted remote cleanup may suspend; never clear a newer reservation.
        guard ownsCleanup(slot, cleanup) else { return }
        slot.deletionCleanup = nil
        slot.deletionID = nil
    }

    private func discardDeletionFresh(_ attempt: DeletionAttempt, windowID: UUID, slot: Slot) async -> WorkspaceLogoutOutcome {
        let outcome = await attempt.driver.discardEnrollment()
        if deletionReportIDs[windowID] == attempt.id, windows[windowID] == attempt.scope,
           current(attempt.scope, attempt.generation) {
            slot.freshSessionCleanupOutcome = outcome
        }
        return outcome
    }

    private func deletionValid(_ attempt: DeletionAttempt, windowID: UUID) -> Bool {
        !attempt.cancelled && !Task.isCancelled && deletions[windowID]?.id == attempt.id
            && windows[windowID] == attempt.scope && current(attempt.scope, attempt.generation)
    }

    private func cleanupSaved(_ saved: any WorkspaceAccountAdmissionTicket, scope: WorkspaceAccountScope,
                              slot: Slot, generation: UUID, driver: any WorkspaceAccountIdentityDriver, windowID: UUID) async {
        do {
            let denied = try admission.deny(expected: saved, reason: .localLogout)
            if current(scope, generation) {
                let previous = slot.driver
                slot.driver = nil
                slot.state = .signingOut(scope: scope)
                invalidateConnections(scope)
                if localStates[windowID] != nil { localStates[windowID] = .signingOut(scope: scope) }
                if let previous { Task { await previous.invalidate() } }
            }
            try await admission.remove(expected: denied)
            if current(scope, generation) {
                slot.retryDriver = nil
                slot.retryTicket = nil
                slot.state = .localDenied(scope: scope, remoteOutcome: .revocationUnknown)
                if localStates[windowID] != nil { localStates[windowID] = slot.state }
            }
        } catch WorkspaceAccountAdmissionFailure.staleTicket {
            // A newer admission owns the scope; this cleanup cannot touch it.
        } catch {
            if current(scope, generation) {
                slot.retryDriver = driver
                slot.retryTicket = saved
                slot.state = .unavailable(.localSignOutPersistenceUnavailable)
            }
        }
    }

    private func prune() {
        let retained = Set(windows.values)
        // Pending operations retain their incarnation; recreated slots always
        // receive a fresh UUID and cannot admit an older operation's result.
        slots = slots.filter { scope, slot in
            retained.contains(scope) || slot.pending > 0 || slot.retryDriver != nil || slot.retryTicket != nil
                || slot.driver != nil || slot.deletionCleanup != nil || slot.deletionID != nil || !attempts.isEmpty
        }
    }

    private func valid(_ attempt: Attempt, windowID: UUID) -> Bool {
        guard let currentAttempt = attempts[windowID], currentAttempt.id == attempt.id, !Task.isCancelled else { return false }
        if let scope = currentAttempt.resolvedScope, let generation = currentAttempt.resolvedGeneration {
            return current(scope, generation)
        }
        return currentAttempt.epoch == epoch
    }
    private func current(_ scope: WorkspaceAccountScope, _ generation: UUID) -> Bool {
        slots[scope]?.generation == generation
    }
    private func validate(_ scope: WorkspaceAccountScope) throws {
        guard scope.origin == deployment.origin, scope.profileID.utf8.elementsEqual(deployment.profileID.utf8) else {
            throw WorkspaceAccountCoordinatorError.wrongDeployment
        }
    }
    private func validate(_ session: WorkspaceAccountVerifiedSession, scope: WorkspaceAccountScope) throws {
        guard session.accountID == scope.accountID, session.expiresAt.timeIntervalSinceReferenceDate.isFinite,
              session.expiresAt > Date(), session.expiresAt.timeIntervalSinceNow <= 8 * 3600 else {
            throw WorkspaceClientError.invalidResponse
        }
    }
    private func slot(_ scope: WorkspaceAccountScope) throws -> Slot {
        if let existing = slots[scope] { return existing }
        prune()
        guard slots.count < capacity else { throw WorkspaceAccountCoordinatorError.capacity }
        let value = Slot()
        value.changed = { [weak self] in self?.publishPresentations() }
        slots[scope] = value
        return value
    }
}

/// Per-requesting-window proof acquisition. The app supplies the real
/// WorkspaceAppleAuthorization adapter bound to that window's current scene.
@MainActor struct WorkspaceAccountProofAcquisition {
    let authorize: (WorkspaceIdentityChallenge) async throws -> WorkspaceIdentityProof
    let cancel: () -> Void
}

extension WorkspaceCredentialAdmissionTicket: WorkspaceAccountAdmissionTicket {}

@MainActor private final class ProductionWorkspaceAccountAdmission: WorkspaceAccountAdmission {
    let context: WorkspaceCredentialAdmissionContext
    let store: WorkspaceCredentialAdmissionStore
    init(context: WorkspaceCredentialAdmissionContext) {
        self.context = context
        store = WorkspaceCredentialAdmissionStore(context: context)
    }
    func capture(scope: WorkspaceAccountScope) throws -> any WorkspaceAccountAdmissionTicket {
        try context.capture(scope: WorkspaceCredentialScope(origin: scope.origin, profileID: scope.profileID, accountID: scope.accountID))
    }
    func beginEnrollment(expected: any WorkspaceAccountAdmissionTicket) throws -> any WorkspaceAccountAdmissionTicket {
        try translate { try context.beginExplicitEnrollment(expected: ticket(expected)) }
    }
    func deny(expected: any WorkspaceAccountAdmissionTicket, reason: WorkspaceAccountDenialReason) throws -> any WorkspaceAccountAdmissionTicket {
        try translate { try context.commitDenial(expected: ticket(expected), reason: moduleReason(reason)) }
    }
    private func moduleReason(_ reason: WorkspaceAccountDenialReason) -> WorkspaceCredentialDenialReason {
        switch reason {
        case .localLogout: .localLogout
        case .logoutAll: .logoutAll
        case .accountDeletion: .accountDeletion
        case .unauthorized: .unauthorized
        }
    }
    func load(expected: any WorkspaceAccountAdmissionTicket) async throws -> WorkspaceAccountLoadedCredential? {
        do {
            guard let loaded = try await store.loadIfAdmitted(expected: ticket(expected)) else { return nil }
            return WorkspaceAccountLoadedCredential(credential: loaded.credential, ticket: loaded.ticket)
        } catch { throw mapped(error) }
    }
    func remove(expected: any WorkspaceAccountAdmissionTicket) async throws {
        do { try await store.removeIfDenied(expected: ticket(expected)) }
        catch { throw mapped(error) }
    }
    func ticket(_ value: any WorkspaceAccountAdmissionTicket) throws -> WorkspaceCredentialAdmissionTicket {
        guard let actual = value as? WorkspaceCredentialAdmissionTicket else { throw WorkspaceAccountAdmissionFailure.staleTicket }
        return actual
    }
    private func translate<T>(_ operation: () throws -> T) throws -> T {
        do { return try operation() }
        catch { throw mapped(error) }
    }
    private func mapped(_ error: any Error) -> any Error {
        if (error as? WorkspaceCredentialAdmissionError) == .staleTicket { return WorkspaceAccountAdmissionFailure.staleTicket }
        return WorkspaceAccountAdmissionFailure.unavailable
    }
}

/// Extracted production proof-admission boundary. Task cancellation alone cannot
/// represent an explicit coordinator/scene cancellation while a request awaits.
@MainActor final class WorkspaceAccountProofGate {
    private var cancelled = false
    func cancel() { cancelled = true }
    func check() throws {
        guard !cancelled else { throw CancellationError() }
        try Task.checkCancellation()
    }
}

@MainActor private final class ProductionWorkspaceAccountIdentityDriver: WorkspaceAccountIdentityDriver, WorkspaceLibraryDiscoveryDriver {
    private let client: WorkspaceIdentityClient
    private let admission: ProductionWorkspaceAccountAdmission
    private let acquireProof: () throws -> WorkspaceAccountProofAcquisition
    private var proof: WorkspaceAccountProofAcquisition?
    private let proofGate = WorkspaceAccountProofGate()
    private let deletionStartControl = WorkspaceIdentityDeletionStartControl()
    private var enrollment: WorkspaceIdentityEnrollment?
    private var savedTicket: WorkspaceCredentialAdmissionTicket?
    private var boundCredential: WorkspaceCredential?

    init(deployment: WorkspaceDeploymentConfiguration, credential: WorkspaceCredential?,
         admission: ProductionWorkspaceAccountAdmission,
         acquireProof: @escaping () throws -> WorkspaceAccountProofAcquisition) throws {
        client = try WorkspaceIdentityClient(origin: deployment.origin, profileID: deployment.profileID,
            consentVersion: deployment.consentVersion, credential: credential)
        self.admission = admission
        self.acquireProof = acquireProof
        boundCredential = credential
    }
    func adopt(_ loaded: WorkspaceAccountLoadedCredential) throws {
        guard let boundCredential else { throw WorkspaceAccountAdmissionFailure.unavailable }
        let ticket = try admission.ticket(loaded.ticket)
        try admission.context.validateIfAdmitted(expected: ticket, matching: boundCredential)
        savedTicket = ticket
    }
    func validateAdmission() throws {
        guard let savedTicket, let boundCredential else { throw WorkspaceAccountAdmissionFailure.unavailable }
        try admission.context.validateIfAdmitted(expected: savedTicket, matching: boundCredential)
    }
    func withAdmittedCredential<T>(_ body: () throws -> T) throws -> T {
        guard let savedTicket, let boundCredential else { throw WorkspaceAccountAdmissionFailure.unavailable }
        return try admission.context.withAdmittedCredential(expected: savedTicket, matching: boundCredential, body)
    }
    func listLibraries(after: UUID?) async throws -> WorkspaceLibraryMetadataPage {
        try validateAdmission()
        let page = try await client.listLibraries(after: after)
        try validateAdmission()
        return page
    }
    func libraryMetadata(id: UUID) async throws -> WorkspaceLibraryMetadata {
        try validateAdmission()
        let metadata = try await client.libraryMetadata(id: id)
        try validateAdmission()
        return metadata
    }
    func restore() async throws -> WorkspaceAccountVerifiedSession {
        let session = try await client.currentSession()
        return presentation(session)
    }
    func enroll() async throws -> WorkspaceAccountVerifiedSession {
        try proofGate.check()
        let proof = try acquireProof()
        self.proof = proof
        defer { self.proof = nil }
        try proofGate.check()
        let challenge = try await client.challenge()
        try proofGate.check()
        let acquired = try await proof.authorize(challenge)
        try proofGate.check()
        let result = try await client.enroll(challenge: challenge, proof: acquired)
        // Keep the actual credential/receipt opaque and in memory. Persist only
        // through the verified-enrollment admission store, never a synthetic DTO.
        enrollment = result
        try proofGate.check()
        return presentation(result.session)
    }
    func save(expected: any WorkspaceAccountAdmissionTicket) async throws -> any WorkspaceAccountAdmissionTicket {
        guard let enrollment else { throw WorkspaceAccountAdmissionFailure.unavailable }
        do {
            let saved = try await admission.store.saveIfAdmitted(enrollment, expected: admission.ticket(expected))
            savedTicket = saved
            boundCredential = enrollment.credential
            return saved
        } catch {
            if (error as? WorkspaceCredentialAdmissionError) == .staleTicket { throw WorkspaceAccountAdmissionFailure.staleTicket }
            throw WorkspaceAccountAdmissionFailure.unavailable
        }
    }
    func discardEnrollment() async -> WorkspaceLogoutOutcome {
        guard let enrollment else { return .remoteRevocationUnknown }
        let result = (try? await client.discardIssuedSession(enrollment.credential)) ?? .remoteRevocationUnknown
        self.enrollment = nil
        savedTicket = nil
        return result
    }
    func logout(allSessions: Bool) async -> WorkspaceLogoutOutcome {
        let result = allSessions ? await client.logoutAll() : await client.logoutCurrentSession()
        enrollment = nil
        savedTicket = nil
        return result
    }
    func deleteFreshEnrollment() async throws -> WorkspaceAccountDeletionOutcome {
        try proofGate.check()
        guard let enrollment else { throw WorkspaceAccountAdmissionFailure.unavailable }
        return try await client.deleteAccount(using: enrollment.reauthenticationReceipt, startControl: deletionStartControl)
    }
    func invalidate() async { await client.invalidateLocally() }
    func cancelProof() { deletionStartControl.cancel(); proofGate.cancel(); proof?.cancel() }
    private func presentation(_ session: WorkspaceIdentitySession) -> WorkspaceAccountVerifiedSession {
        WorkspaceAccountVerifiedSession(accountID: session.accountID, sessionID: session.sessionID, expiresAt: session.expiresAt)
    }
}

extension WorkspaceAccountCoordinator {
    /// Composition must supply a provisioned deployment and owned shared context.
    /// This factory provides real adapters; it does not expose UI or sign anyone in.
    static func configured(deployment: WorkspaceDeploymentConfiguration,
                           context: WorkspaceCredentialAdmissionContext,
                           connectionRegistry: CloudConnectionRegistry,
                           proofForWindow: @escaping (UUID) throws -> WorkspaceAccountProofAcquisition) throws -> WorkspaceAccountCoordinator {
        let admission = ProductionWorkspaceAccountAdmission(context: context)
        return try WorkspaceAccountCoordinator(deployment: deployment, admission: admission,
            invalidateConnections: { scope in
                connectionRegistry.invalidateAll(origin: scope.origin.url.absoluteString,
                    profileID: scope.profileID, accountID: scope.accountID)
            }, makeIdentity: { credential, windowID in
                try ProductionWorkspaceAccountIdentityDriver(deployment: deployment, credential: credential,
                    admission: admission, acquireProof: { try proofForWindow(windowID) })
            })
    }
}
