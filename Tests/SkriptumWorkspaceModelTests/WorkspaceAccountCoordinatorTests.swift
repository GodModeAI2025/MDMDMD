import Foundation
import XCTest
@testable import SkriptumWorkspaceModel
import SkriptumWorkspaceClient

@MainActor final class WorkspaceAccountCoordinatorTests: XCTestCase {
    private let origin = try! WorkspaceOrigin("https://workspace.example")
    private func deployment() throws -> WorkspaceDeploymentConfiguration {
        try WorkspaceDeploymentConfiguration(origin: origin.url.absoluteString, profileID: "native", consentVersion: "v1", operatorName: "Owned test operator", privacyURL: "https://operator.example/privacy", serviceURL: "https://operator.example/service", consentDisclosure: "Sign-in does not upload documents.")
    }

    func testLogoutFencesBothWindowsBeforeRemoteSuspensionAndPreservesAccountB() async throws {
        let admission = FakeAdmission()
        let identity = FakeIdentity()
        let a = try WorkspaceAccountScope(origin: origin, profileID: "native", accountID: UUID())
        let b = try WorkspaceAccountScope(origin: origin, profileID: "native", accountID: UUID())
        let coordinator = try WorkspaceAccountCoordinator(deployment: deployment(), admission: admission, makeIdentity: { _, _ in identity })
        let a1 = UUID(), a2 = UUID(), b1 = UUID()
        try coordinator.attach(windowID: a1, scope: a)
        try coordinator.attach(windowID: a2, scope: a)
        try coordinator.attach(windowID: b1, scope: b)
        identity.session = .init(accountID: a.accountID, sessionID: UUID(), expiresAt: Date().addingTimeInterval(600))
        await coordinator.restore(windowID: a1)
        identity.session = .init(accountID: b.accountID, sessionID: UUID(), expiresAt: Date().addingTimeInterval(600))
        await coordinator.restore(windowID: b1)
        identity.logoutBarrier = Barrier()
        let task = Task { await coordinator.logout(scope: a, allSessions: true) }
        await identity.logoutBarrier!.waitUntilEntered()
        XCTAssertEqual(admission.denied, [a])
        XCTAssertEqual(coordinator.state(windowID: a1), .signingOut(scope: a))
        XCTAssertEqual(coordinator.state(windowID: a2), .signingOut(scope: a))
        guard case .active(let scope, _, _) = coordinator.state(windowID: b1) else { return XCTFail("B lost admission") }
        XCTAssertEqual(scope, b)
        identity.logoutBarrier!.release()
        await task.value
    }

    func testLateRestoreCannotPublishAfterLogout() async throws {
        let admission = FakeAdmission(), identity = FakeIdentity()
        let scope = try WorkspaceAccountScope(origin: origin, profileID: "native", accountID: UUID())
        identity.session = .init(accountID: scope.accountID, sessionID: UUID(), expiresAt: Date().addingTimeInterval(600))
        identity.restoreBarrier = Barrier()
        let coordinator = try WorkspaceAccountCoordinator(deployment: deployment(), admission: admission, makeIdentity: { _, _ in identity })
        let window = UUID()
        try coordinator.attach(windowID: window, scope: scope)
        let restore = Task { await coordinator.restore(windowID: window) }
        await identity.restoreBarrier!.waitUntilEntered()
        await coordinator.logout(scope: scope, allSessions: false)
        identity.restoreBarrier!.release()
        await restore.value
        XCTAssertEqual(coordinator.state(windowID: window), .localDenied(scope: scope, remoteOutcome: .revocationUnknown))
    }

    func testUnknownLoginCancelledByLogoutDiscardsLateEnrollmentWithoutSaving() async throws {
        let admission = FakeAdmission(), active = FakeIdentity(), provisional = FakeIdentity()
        let scope = try WorkspaceAccountScope(origin: origin, profileID: "native", accountID: UUID())
        provisional.session = .init(accountID: UUID(), sessionID: UUID(), expiresAt: Date().addingTimeInterval(600))
        provisional.loginBarrier = Barrier()
        var identities = [active, provisional]
        let coordinator = try WorkspaceAccountCoordinator(deployment: deployment(), admission: admission, makeIdentity: { _, _ in identities.removeFirst() })
        let known = UUID(), loginWindow = UUID()
        try coordinator.attach(windowID: known, scope: scope)
        active.session = .init(accountID: scope.accountID, sessionID: UUID(), expiresAt: Date().addingTimeInterval(600))
        await coordinator.restore(windowID: known)
        let login = Task { await coordinator.signIn(windowID: loginWindow) }
        await provisional.loginBarrier!.waitUntilEntered()
        await coordinator.logout(scope: scope, allSessions: true)
        provisional.loginBarrier!.release()
        await login.value
        XCTAssertEqual(provisional.discards, 1)
        XCTAssertEqual(provisional.saves, 0)
        XCTAssertEqual(coordinator.state(windowID: loginWindow), .signedOut)
    }

    func testOldLogoutCompletionCannotOverwriteNewSameAccountLogin() async throws {
        let admission = FakeAdmission(), old = FakeIdentity(), fresh = FakeIdentity()
        let scope = try WorkspaceAccountScope(origin: origin, profileID: "native", accountID: UUID())
        old.session = .init(accountID: scope.accountID, sessionID: UUID(), expiresAt: Date().addingTimeInterval(600))
        fresh.session = .init(accountID: scope.accountID, sessionID: UUID(), expiresAt: Date().addingTimeInterval(600))
        old.logoutBarrier = Barrier()
        var identities = [old, fresh]
        let coordinator = try WorkspaceAccountCoordinator(deployment: deployment(), admission: admission, makeIdentity: { _, _ in identities.removeFirst() })
        let window = UUID()
        try coordinator.attach(windowID: window, scope: scope)
        await coordinator.restore(windowID: window)
        let logout = Task { await coordinator.logout(scope: scope, allSessions: true) }
        await old.logoutBarrier!.waitUntilEntered()
        await coordinator.signIn(windowID: window)
        let admitted = coordinator.state(windowID: window)
        guard case .active = admitted else { return XCTFail("Fresh login was not admitted") }
        old.logoutBarrier!.release()
        await logout.value
        XCTAssertEqual(coordinator.state(windowID: window), admitted)
    }

    func testDenialPersistenceFailureNeverClaimsDurableLogout() async throws {
        let admission = FakeAdmission(), identity = FakeIdentity()
        admission.failDenial = true
        let coordinator = try WorkspaceAccountCoordinator(deployment: deployment(), admission: admission, makeIdentity: { _, _ in identity })
        let scope = try WorkspaceAccountScope(origin: origin, profileID: "native", accountID: UUID())
        let window = UUID()
        try coordinator.attach(windowID: window, scope: scope)
        await coordinator.logout(scope: scope, allSessions: true)
        XCTAssertEqual(coordinator.state(windowID: window), .unavailable(.localSignOutPersistenceUnavailable))
        XCTAssertEqual(identity.logouts, 0)
    }

    func testExplicitLoginSavesBeforePublishingAndDoesNotCreateLibraryBinding() async throws {
        let admission = FakeAdmission(), identity = FakeIdentity()
        identity.session = .init(accountID: UUID(), sessionID: UUID(), expiresAt: Date().addingTimeInterval(600))
        identity.saveBarrier = Barrier()
        let coordinator = try WorkspaceAccountCoordinator(deployment: deployment(), admission: admission, makeIdentity: { _, _ in identity })
        let window = UUID()
        let login = Task { await coordinator.signIn(windowID: window) }
        await identity.saveBarrier!.waitUntilEntered()
        guard case .signingIn = coordinator.state(windowID: window) else { return XCTFail("Published before save") }
        identity.saveBarrier!.release()
        await login.value
        guard case .active = coordinator.state(windowID: window) else { return XCTFail("Verified saved login not admitted") }
        XCTAssertEqual(identity.saves, 1)
        XCTAssertTrue(admission.denied.isEmpty)
    }
}

private struct FakeTicket: WorkspaceAccountAdmissionTicket { let scope: WorkspaceAccountScope }
@MainActor private final class FakeAdmission: WorkspaceAccountAdmission {
    var denied: [WorkspaceAccountScope] = []
    var failDenial = false
    var removals = 0
    var failRemoval = false
    var onDenial: (() -> Void)?
    func capture(scope: WorkspaceAccountScope) throws -> any WorkspaceAccountAdmissionTicket { FakeTicket(scope: scope) }
    func beginEnrollment(expected: any WorkspaceAccountAdmissionTicket) throws -> any WorkspaceAccountAdmissionTicket { expected }
    func deny(expected: any WorkspaceAccountAdmissionTicket, reason: WorkspaceAccountDenialReason) throws -> any WorkspaceAccountAdmissionTicket {
        if failDenial { throw WorkspaceClientError.unavailable }
        denied.append((expected as! FakeTicket).scope)
        onDenial?()
        return expected
    }
    func load(expected: any WorkspaceAccountAdmissionTicket) async throws -> WorkspaceAccountLoadedCredential? {
        let credential = try WorkspaceCredential(origin: (expected as! FakeTicket).scope.origin, accountID: (expected as! FakeTicket).scope.accountID, token: String(repeating: "a", count: 43), profileID: "native")
        return WorkspaceAccountLoadedCredential(credential: credential, ticket: expected)
    }
    func remove(expected: any WorkspaceAccountAdmissionTicket) async throws { if failRemoval { throw WorkspaceAccountAdmissionFailure.unavailable }; removals += 1 }
}
@MainActor private final class FakeIdentity: WorkspaceAccountIdentityDriver {
    var session: WorkspaceAccountVerifiedSession!
    var restoreBarrier: Barrier?, loginBarrier: Barrier?, saveBarrier: Barrier?, logoutBarrier: Barrier?
    var saves = 0, discards = 0, logouts = 0
    var failSave = false
    var deleteBarrier: Barrier?
    var deletes = 0
    var failDeleteReceipt = false
    var discardOutcome: WorkspaceLogoutOutcome = .confirmedRemoteRevocation
    var failEnrollAfterIssuing = false
    var discardBarriers: [Barrier] = []
    func restore() async throws -> WorkspaceAccountVerifiedSession { await restoreBarrier?.enter(); return session }
    func enroll() async throws -> WorkspaceAccountVerifiedSession { await loginBarrier?.enter(); if failEnrollAfterIssuing { throw WorkspaceClientError.cancelled }; return session }
    func save(expected: any WorkspaceAccountAdmissionTicket) async throws -> any WorkspaceAccountAdmissionTicket { await saveBarrier?.enter(); if failSave { throw WorkspaceAccountAdmissionFailure.staleTicket }; saves += 1; return expected }
    func discardEnrollment() async -> WorkspaceLogoutOutcome { discards += 1; if !discardBarriers.isEmpty { let barrier = discardBarriers.removeFirst(); await barrier.enter() }; return discardOutcome }
    func logout(allSessions: Bool) async -> WorkspaceLogoutOutcome { logouts += 1; await logoutBarrier?.enter(); return .remoteRevocationUnknown }
    func deleteFreshEnrollment() async throws -> WorkspaceAccountDeletionOutcome {
        await deleteBarrier?.enter()
        if failDeleteReceipt { throw WorkspaceIdentityClientError.expiredReceipt }
        deletes += 1
        return .confirmedAccountTombstone
    }
    func invalidate() async {}
    func cancelProof() {}
}
@MainActor private final class Barrier {
    private var entered = false
    private var observers: [CheckedContinuation<Void, Never>] = []
    private var pending: CheckedContinuation<Void, Never>?
    func enter() async {
        entered = true
        observers.forEach { $0.resume() }; observers.removeAll()
        await withCheckedContinuation { pending = $0 }
    }
    func waitUntilEntered() async {
        if entered { return }
        await withCheckedContinuation { observers.append($0) }
    }
    func release() { pending?.resume(); pending = nil }
}

extension WorkspaceAccountCoordinatorTests {
    func testLateGetCannotOverwriteFreshLogin() async throws {
        let admission = FakeAdmission(), old = FakeIdentity(), fresh = FakeIdentity()
        let scope = try WorkspaceAccountScope(origin: origin, profileID: "native", accountID: UUID())
        old.session = .init(accountID: scope.accountID, sessionID: UUID(), expiresAt: Date().addingTimeInterval(600))
        fresh.session = .init(accountID: scope.accountID, sessionID: UUID(), expiresAt: Date().addingTimeInterval(600))
        old.restoreBarrier = Barrier()
        var drivers = [old, fresh]
        let coordinator = try WorkspaceAccountCoordinator(deployment: deployment(), admission: admission, makeIdentity: { _, _ in drivers.removeFirst() })
        let window = UUID()
        try coordinator.attach(windowID: window, scope: scope)
        let restore = Task { await coordinator.restore(windowID: window) }
        await old.restoreBarrier!.waitUntilEntered()
        await coordinator.signIn(windowID: window)
        let admitted = coordinator.state(windowID: window)
        old.restoreBarrier!.release()
        await restore.value
        XCTAssertEqual(coordinator.state(windowID: window), admitted)
    }

    func testCancelAfterSaveDeniesLocalCredential() async throws {
        let admission = FakeAdmission(), identity = FakeIdentity()
        identity.session = .init(accountID: UUID(), sessionID: UUID(), expiresAt: Date().addingTimeInterval(600))
        identity.saveBarrier = Barrier()
        let coordinator = try WorkspaceAccountCoordinator(deployment: deployment(), admission: admission, makeIdentity: { _, _ in identity })
        let window = UUID()
        let login = Task { await coordinator.signIn(windowID: window) }
        await identity.saveBarrier!.waitUntilEntered()
        coordinator.detach(windowID: window)
        identity.saveBarrier!.release()
        await login.value
        XCTAssertEqual(admission.denied.map(\.accountID), [identity.session.accountID])
        XCTAssertEqual(admission.removals, 1)
        XCTAssertEqual(identity.discards, 1)
    }

    func testDetachedInactiveScopeDoesNotExhaustCapacity() throws {
        let coordinator = try WorkspaceAccountCoordinator(deployment: deployment(), admission: FakeAdmission(), capacity: 1, makeIdentity: { _, _ in FakeIdentity() })
        let window = UUID()
        try coordinator.attach(windowID: window, scope: WorkspaceAccountScope(origin: origin, profileID: "native", accountID: UUID()))
        coordinator.detach(windowID: window)
        XCTAssertNoThrow(try coordinator.attach(windowID: UUID(), scope: WorkspaceAccountScope(origin: origin, profileID: "native", accountID: UUID())))
    }

    func testFailedDenialRetainsInitiatorForRetry() async throws {
        let admission = FakeAdmission(), identity = FakeIdentity()
        let scope = try WorkspaceAccountScope(origin: origin, profileID: "native", accountID: UUID())
        identity.session = .init(accountID: scope.accountID, sessionID: UUID(), expiresAt: Date().addingTimeInterval(600))
        let coordinator = try WorkspaceAccountCoordinator(deployment: deployment(), admission: admission, makeIdentity: { _, _ in identity })
        let window = UUID()
        try coordinator.attach(windowID: window, scope: scope)
        await coordinator.restore(windowID: window)
        admission.failDenial = true
        await coordinator.logout(scope: scope, allSessions: true)
        admission.failDenial = false
        await coordinator.logout(scope: scope, allSessions: true)
        XCTAssertEqual(identity.logouts, 1)
        XCTAssertEqual(admission.removals, 1)
    }
}

extension WorkspaceAccountCoordinatorTests {
    func testCancelledSameAccountReauthenticationFencesPreviousActivePresentation() async throws {
        let admission = FakeAdmission(), old = FakeIdentity(), fresh = FakeIdentity()
        let scope = try WorkspaceAccountScope(origin: origin, profileID: "native", accountID: UUID())
        old.session = .init(accountID: scope.accountID, sessionID: UUID(), expiresAt: Date().addingTimeInterval(600))
        fresh.session = .init(accountID: scope.accountID, sessionID: UUID(), expiresAt: Date().addingTimeInterval(600))
        fresh.saveBarrier = Barrier()
        var drivers = [old, fresh]
        var fenced: [WorkspaceAccountScope] = []
        let coordinator = try WorkspaceAccountCoordinator(deployment: deployment(), admission: admission,
            invalidateConnections: { fenced.append($0) }, makeIdentity: { _, _ in drivers.removeFirst() })
        let window = UUID()
        try coordinator.attach(windowID: window, scope: scope)
        await coordinator.restore(windowID: window)
        let login = Task { await coordinator.signIn(windowID: window) }
        await fresh.saveBarrier!.waitUntilEntered()
        coordinator.cancelSignIn(windowID: window)
        fresh.saveBarrier!.release()
        await login.value
        XCTAssertEqual(fenced, [scope])
        guard case .localDenied(let deniedScope, _) = coordinator.state(windowID: window) else {
            return XCTFail("Denied credential still appears active")
        }
        XCTAssertEqual(deniedScope, scope)
    }
}


extension WorkspaceAccountCoordinatorTests {
    func testProductionProofGateRejectsCancellationWhileChallengeIsSuspended() async throws {
        let gate = WorkspaceAccountProofGate()
        let challenge = Barrier()
        var authorizeCalls = 0
        var denied = false
        let request = Task {
            do {
                try gate.check()
                await challenge.enter()
                try gate.check()
                authorizeCalls += 1
            } catch { denied = true }
        }
        await challenge.waitUntilEntered()
        gate.cancel()
        challenge.release()
        await request.value
        XCTAssertFalse(request.isCancelled, "Explicit cancellation is independent of Task cancellation")
        XCTAssertTrue(denied)
        XCTAssertEqual(authorizeCalls, 0)
        XCTAssertThrowsError(try gate.check(), "The same driver cannot reopen proof admission")
    }
}

extension WorkspaceAccountCoordinatorTests {
    func testLogoutAPreservesVerifiedBWhileBSaveIsSuspended() async throws {
        let admission = FakeAdmission(), activeA = FakeIdentity(), verifiedB = FakeIdentity()
        let a = try WorkspaceAccountScope(origin: origin, profileID: "native", accountID: UUID())
        activeA.session = .init(accountID: a.accountID, sessionID: UUID(), expiresAt: Date().addingTimeInterval(600))
        verifiedB.session = .init(accountID: UUID(), sessionID: UUID(), expiresAt: Date().addingTimeInterval(600))
        verifiedB.saveBarrier = Barrier()
        var drivers = [activeA, verifiedB]
        var fenced: [WorkspaceAccountScope] = []
        let coordinator = try WorkspaceAccountCoordinator(deployment: deployment(), admission: admission,
            invalidateConnections: { fenced.append($0) }, makeIdentity: { _, _ in drivers.removeFirst() })
        let aWindow = UUID(), bWindow = UUID()
        try coordinator.attach(windowID: aWindow, scope: a)
        await coordinator.restore(windowID: aWindow)
        let loginB = Task { await coordinator.signIn(windowID: bWindow) }
        await verifiedB.saveBarrier!.waitUntilEntered()
        await coordinator.logout(scope: a, allSessions: true)
        verifiedB.saveBarrier!.release()
        await loginB.value
        guard case .active(let b, _, _) = coordinator.state(windowID: bWindow) else {
            return XCTFail("A logout rejected already-verified B")
        }
        XCTAssertEqual(b.accountID, verifiedB.session.accountID)
        XCTAssertEqual(admission.denied, [a])
        XCTAssertEqual(fenced, [a])
        XCTAssertEqual(verifiedB.discards, 0)
    }
}

extension WorkspaceAccountCoordinatorTests {
    func testStaleSameAccountSaveThrowConsumesOnlyItsOwnAttempt() async throws {
        try await checkStaleAttemptCleanup(throwingSave: true)
    }
    func testStaleSameAccountSaveReturnConsumesOnlyItsOwnAttempt() async throws {
        try await checkStaleAttemptCleanup(throwingSave: false)
    }
    private func checkStaleAttemptCleanup(throwingSave: Bool) async throws {
        let admission = FakeAdmission(), first = FakeIdentity(), newer = FakeIdentity()
        let account = UUID()
        first.session = .init(accountID: account, sessionID: UUID(), expiresAt: Date().addingTimeInterval(600))
        newer.session = .init(accountID: account, sessionID: UUID(), expiresAt: Date().addingTimeInterval(600))
        first.saveBarrier = Barrier()
        first.failSave = throwingSave
        var drivers = [first, newer]
        let coordinator = try WorkspaceAccountCoordinator(deployment: deployment(), admission: admission,
            makeIdentity: { _, _ in drivers.removeFirst() })
        let w1 = UUID(), w2 = UUID()
        let stale = Task { await coordinator.signIn(windowID: w1) }
        await first.saveBarrier!.waitUntilEntered()
        await coordinator.signIn(windowID: w2)
        first.saveBarrier!.release()
        await stale.value
        if case .signingIn = coordinator.state(windowID: w1) { XCTFail("Terminal stale attempt remained pending") }
        guard case .active = coordinator.state(windowID: w2) else { return XCTFail("Newer account admission lost") }
        XCTAssertEqual(first.discards, 1)
    }
}

extension WorkspaceAccountCoordinatorTests {
    private func deletionFixture(wrongAccount: Bool = false) async throws -> (WorkspaceAccountCoordinator, FakeAdmission, FakeIdentity, FakeIdentity, WorkspaceAccountScope, UUID) {
        let admission = FakeAdmission(), active = FakeIdentity(), fresh = FakeIdentity()
        let scope = try WorkspaceAccountScope(origin: origin, profileID: "native", accountID: UUID())
        active.session = .init(accountID: scope.accountID, sessionID: UUID(), expiresAt: Date().addingTimeInterval(600))
        fresh.session = .init(accountID: wrongAccount ? UUID() : scope.accountID, sessionID: UUID(), expiresAt: Date().addingTimeInterval(600))
        var drivers = [active, fresh]
        let coordinator = try WorkspaceAccountCoordinator(deployment: deployment(), admission: admission, makeIdentity: { _, _ in drivers.removeFirst() })
        let window = UUID()
        try coordinator.attach(windowID: window, scope: scope)
        await coordinator.restore(windowID: window)
        return (coordinator, admission, active, fresh, scope, window)
    }

    func testDeletionFencesBothWindowsBeforeDeleteAndNeverSavesFreshSession() async throws {
        let (coordinator, admission, _, fresh, scope, window) = try await deletionFixture()
        let second = UUID()
        try coordinator.attach(windowID: second, scope: scope)
        fresh.deleteBarrier = Barrier()
        let deletion = Task { await coordinator.deleteAccount(windowID: window, scope: scope) }
        await fresh.deleteBarrier!.waitUntilEntered()
        XCTAssertEqual(admission.denied, [scope])
        XCTAssertEqual(coordinator.state(windowID: second), .deleting(scope: scope))
        XCTAssertEqual(fresh.saves, 0)
        fresh.deleteBarrier!.release()
        let result = await deletion.value
        XCTAssertEqual(result, .confirmedAccountTombstone)
        XCTAssertEqual(fresh.discards, 1)
        XCTAssertEqual(admission.removals, 1)
    }

    func testWrongAccountDeletionPreservesOriginalAdmission() async throws {
        let (coordinator, admission, _, fresh, scope, window) = try await deletionFixture(wrongAccount: true)
        let before = coordinator.state(windowID: window)
        let result = await coordinator.deleteAccount(windowID: window, scope: scope)
        XCTAssertEqual(result, .wrongAccount)
        XCTAssertEqual(coordinator.state(windowID: window), before)
        XCTAssertTrue(admission.denied.isEmpty)
        XCTAssertEqual(fresh.deletes, 0)
        XCTAssertEqual(fresh.discards, 1)
    }

    func testCancelledDeletionEnrollmentOnlyDiscardsFreshSession() async throws {
        let (coordinator, admission, _, fresh, scope, window) = try await deletionFixture()
        fresh.loginBarrier = Barrier()
        let deletion = Task { await coordinator.deleteAccount(windowID: window, scope: scope) }
        await fresh.loginBarrier!.waitUntilEntered()
        coordinator.cancelAccountDeletion(windowID: window)
        fresh.loginBarrier!.release()
        let result = await deletion.value
        XCTAssertEqual(result, .cancelled)
        XCTAssertTrue(admission.denied.isEmpty)
        XCTAssertEqual(fresh.deletes, 0)
        XCTAssertEqual(fresh.discards, 1)
    }

    func testDeletionDenialFailureRetainsFreshDriverForCleanupOnlyRetry() async throws {
        let (coordinator, admission, _, fresh, scope, window) = try await deletionFixture()
        admission.failDenial = true
        let result = await coordinator.deleteAccount(windowID: window, scope: scope)
        XCTAssertEqual(result, .localPersistenceUnavailable)
        XCTAssertEqual(fresh.discards, 0)
        XCTAssertEqual(fresh.deletes, 0)
        admission.failDenial = false
        await coordinator.retryDeletionLocalCleanup(scope: scope)
        XCTAssertEqual(fresh.discards, 1)
        XCTAssertEqual(fresh.deletes, 0)
        XCTAssertEqual(admission.removals, 1)
    }

    func testExpiredReceiptAfterFenceDiscardsFreshSessionAndKeepsLocalDenial() async throws {
        let (coordinator, admission, _, fresh, scope, window) = try await deletionFixture()
        fresh.failDeleteReceipt = true
        let result = await coordinator.deleteAccount(windowID: window, scope: scope)
        XCTAssertEqual(result, .remoteDeletionUnknown)
        XCTAssertEqual(fresh.discards, 1)
        XCTAssertEqual(admission.removals, 1)
        XCTAssertEqual(coordinator.state(windowID: window), .localDenied(scope: scope, remoteOutcome: .deletionUnknown))
    }

    func testDeletionRemoveRetryNeverResendsConfirmedDelete() async throws {
        let (coordinator, admission, _, fresh, scope, window) = try await deletionFixture()
        admission.failRemoval = true
        _ = await coordinator.deleteAccount(windowID: window, scope: scope)
        XCTAssertEqual(fresh.deletes, 1)
        admission.failRemoval = false
        await coordinator.retryDeletionLocalCleanup(scope: scope)
        XCTAssertEqual(fresh.deletes, 1)
        XCTAssertEqual(coordinator.state(windowID: window), .localDenied(scope: scope, remoteOutcome: .confirmedAccountTombstone))
    }
}

extension WorkspaceAccountCoordinatorTests {
    func testDeletionReservationRejectsSameAccountSaveWhileAllowingB() async throws {
        let admission = FakeAdmission(), active = FakeIdentity(), deleting = FakeIdentity(), aLogin = FakeIdentity(), bLogin = FakeIdentity()
        let a = try WorkspaceAccountScope(origin: origin, profileID: "native", accountID: UUID())
        for driver in [active, deleting, aLogin] { driver.session = .init(accountID: a.accountID, sessionID: UUID(), expiresAt: Date().addingTimeInterval(600)) }
        bLogin.session = .init(accountID: UUID(), sessionID: UUID(), expiresAt: Date().addingTimeInterval(600))
        deleting.deleteBarrier = Barrier()
        var drivers = [active, deleting, aLogin, bLogin]
        let coordinator = try WorkspaceAccountCoordinator(deployment: deployment(), admission: admission, makeIdentity: { _, _ in drivers.removeFirst() })
        let aWindow = UUID(), bWindow = UUID()
        try coordinator.attach(windowID: aWindow, scope: a)
        await coordinator.restore(windowID: aWindow)
        let deletion = Task { await coordinator.deleteAccount(windowID: aWindow, scope: a) }
        await deleting.deleteBarrier!.waitUntilEntered()
        await coordinator.signIn(windowID: UUID())
        XCTAssertEqual(aLogin.saves, 0)
        XCTAssertEqual(aLogin.discards, 1)
        await coordinator.signIn(windowID: bWindow)
        guard case .active(let b, _, _) = coordinator.state(windowID: bWindow) else { return XCTFail("B admission was blocked") }
        XCTAssertEqual(b.accountID, bLogin.session.accountID)
        deleting.deleteBarrier!.release()
        _ = await deletion.value
    }

    func testCancelAtDurableDenialBeforeDeleteStillDiscardsFreshSession() async throws {
        let (coordinator, admission, _, fresh, scope, window) = try await deletionFixture()
        admission.onDenial = { coordinator.cancelAccountDeletion(windowID: window) }
        let result = await coordinator.deleteAccount(windowID: window, scope: scope)
        XCTAssertEqual(result, .remoteDeletionUnknown)
        XCTAssertEqual(fresh.deletes, 0)
        XCTAssertEqual(fresh.discards, 1)
        XCTAssertEqual(admission.removals, 1)
        XCTAssertEqual(coordinator.state(windowID: window), .localDenied(scope: scope, remoteOutcome: .deletionUnknown))
    }
}

extension WorkspaceAccountCoordinatorTests {
    func testWrongAccountDeletionReportsUnknownTargetedCleanupSeparately() async throws {
        let (coordinator, admission, _, fresh, scope, window) = try await deletionFixture(wrongAccount: true)
        fresh.discardOutcome = .remoteRevocationUnknown
        let before = coordinator.state(windowID: window)
        _ = await coordinator.deleteAccount(windowID: window, scope: scope)
        XCTAssertEqual(coordinator.deletionSessionCleanupOutcome(scope: scope), .remoteRevocationUnknown)
        XCTAssertEqual(coordinator.state(windowID: window), before)
        XCTAssertTrue(admission.denied.isEmpty)
    }
    func testCancelledPrefenceDeletionReportsUnknownTargetedCleanup() async throws {
        let (coordinator, _, _, fresh, scope, window) = try await deletionFixture()
        fresh.discardOutcome = .remoteRevocationUnknown
        fresh.loginBarrier = Barrier()
        let deletion = Task { await coordinator.deleteAccount(windowID: window, scope: scope) }
        await fresh.loginBarrier!.waitUntilEntered()
        coordinator.cancelAccountDeletion(windowID: window)
        fresh.loginBarrier!.release()
        _ = await deletion.value
        XCTAssertEqual(coordinator.deletionSessionCleanupOutcome(scope: scope), .remoteRevocationUnknown)
    }
    func testPostEnrollmentFailureReportsUnknownTargetedCleanup() async throws {
        let (coordinator, admission, _, fresh, scope, window) = try await deletionFixture()
        fresh.discardOutcome = .remoteRevocationUnknown
        fresh.failEnrollAfterIssuing = true
        _ = await coordinator.deleteAccount(windowID: window, scope: scope)
        XCTAssertEqual(coordinator.deletionSessionCleanupOutcome(scope: scope), .remoteRevocationUnknown)
        XCTAssertTrue(admission.denied.isEmpty)
    }
}

extension WorkspaceAccountCoordinatorTests {
    func testOlderCleanupRetryCannotClearNewDeletionReservationAfterAwait() async throws {
        let admission = FakeAdmission(), active = FakeIdentity(), abandoned = FakeIdentity(), newer = FakeIdentity()
        let scope = try WorkspaceAccountScope(origin: origin, profileID: "native", accountID: UUID())
        for driver in [active, abandoned, newer] { driver.session = .init(accountID: scope.accountID, sessionID: UUID(), expiresAt: Date().addingTimeInterval(600)) }
        var drivers = [active, abandoned, newer]
        let coordinator = try WorkspaceAccountCoordinator(deployment: deployment(), admission: admission, makeIdentity: { _, _ in drivers.removeFirst() })
        let window = UUID()
        try coordinator.attach(windowID: window, scope: scope)
        await coordinator.restore(windowID: window)
        admission.failDenial = true
        _ = await coordinator.deleteAccount(windowID: window, scope: scope)
        admission.failDenial = false
        await coordinator.logout(scope: scope, allSessions: true)
        let first = Barrier(), second = Barrier()
        abandoned.discardBarriers = [first, second]
        let oldRetry = Task { await coordinator.retryDeletionLocalCleanup(scope: scope) }
        await first.waitUntilEntered()
        let fasterRetry = Task { await coordinator.retryDeletionLocalCleanup(scope: scope) }
        await second.waitUntilEntered()
        second.release()
        await fasterRetry.value
        newer.deleteBarrier = Barrier()
        let deletion = Task { await coordinator.deleteAccount(windowID: window, scope: scope) }
        await newer.deleteBarrier!.waitUntilEntered()
        first.release()
        await oldRetry.value
        XCTAssertEqual(coordinator.state(windowID: window), .deleting(scope: scope))
        newer.deleteBarrier!.release()
        _ = await deletion.value
    }
}
