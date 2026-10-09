import Foundation
import Observation
import XCTest
@testable import SkriptumWorkspaceModel
import SkriptumWorkspaceClient

@MainActor final class WorkspaceAccountObservationTests: XCTestCase {
    private func deployment() throws -> WorkspaceDeploymentConfiguration {
        try WorkspaceDeploymentConfiguration(origin: "https://workspace.example", profileID: "native", consentVersion: "v1", operatorName: "Owned operator", privacyURL: "https://operator.example/privacy", serviceURL: "https://operator.example/service", consentDisclosure: "Separate library upload.")
    }
    private func scope(_ account: UUID = UUID()) throws -> WorkspaceAccountScope {
        try WorkspaceAccountScope(origin: WorkspaceOrigin("https://workspace.example"), profileID: "native", accountID: account)
    }

    func testTwoAccountAModelsFenceBeforeBlockedRevocationAndBStaysActive() async throws {
        let admission = ObservationAdmission(), aDriver = ObservationIdentity(), bDriver = ObservationIdentity()
        let a = try scope(), b = try scope()
        aDriver.session = .init(accountID: a.accountID, sessionID: UUID(), expiresAt: Date().addingTimeInterval(600))
        bDriver.session = .init(accountID: b.accountID, sessionID: UUID(), expiresAt: Date().addingTimeInterval(600))
        let coordinator = try WorkspaceAccountCoordinator(deployment: deployment(), admission: admission,
            makeIdentity: { credential, _ in credential?.accountID == b.accountID ? bDriver : aDriver })
        let w1 = UUID(), w2 = UUID(), wb = UUID()
        try coordinator.attach(windowID: w1, scope: a)
        try coordinator.attach(windowID: w2, scope: a)
        try coordinator.attach(windowID: wb, scope: b)
        let first = try coordinator.observe(windowID: w1), second = try coordinator.observe(windowID: w2), other = try coordinator.observe(windowID: wb)
        await coordinator.restore(windowID: w1)
        await coordinator.restore(windowID: wb)
        let bState = other.state
        let aChanges = ObservationCounter(), bChanges = ObservationCounter()
        withObservationTracking { _ = first.state } onChange: { aChanges.increment() }
        withObservationTracking { _ = other.state } onChange: { bChanges.increment() }
        aDriver.logoutBarrier = ObservationBarrier()
        let logout = Task { await coordinator.logout(scope: a, allSessions: true) }
        await aDriver.logoutBarrier!.entered()
        XCTAssertEqual(first.state, .signingOut(scope: a))
        XCTAssertEqual(second.state, first.state)
        XCTAssertEqual(other.state, bState)
        XCTAssertTrue(first.isBusy)
        XCTAssertEqual(aChanges.value, 1)
        XCTAssertEqual(bChanges.value, 0)
        aDriver.logoutBarrier!.release()
        await logout.value
        XCTAssertEqual(first.state, .localDenied(scope: a, remoteOutcome: .revocationUnknown))
        XCTAssertEqual(second.state, first.state)
        XCTAssertFalse(first.isBusy)
        XCTAssertEqual(other.state, bState)
    }

    func testRestoreAndLoginPublishBeforeTheirSuspensionsAndCancelUpdatesModel() async throws {
        let driver = ObservationIdentity(), admission = ObservationAdmission(), a = try scope()
        driver.session = .init(accountID: a.accountID, sessionID: UUID(), expiresAt: Date().addingTimeInterval(600))
        driver.restoreBarrier = ObservationBarrier()
        let coordinator = try WorkspaceAccountCoordinator(deployment: deployment(), admission: admission, makeIdentity: { _, _ in driver })
        let window = UUID()
        try coordinator.attach(windowID: window, scope: a)
        let model = try coordinator.observe(windowID: window)
        let restore = Task { await coordinator.restore(windowID: window) }
        await driver.restoreBarrier!.entered()
        XCTAssertEqual(model.state, .restoring(scope: a))
        driver.restoreBarrier!.release()
        await restore.value
        guard case .active = model.state else { return XCTFail("Restore completion not published") }
        driver.enrollBarrier = ObservationBarrier()
        let login = Task { await coordinator.signIn(windowID: window) }
        await driver.enrollBarrier!.entered()
        guard case .signingIn = model.state else { return XCTFail("Login start not published") }
        coordinator.cancelSignIn(windowID: window)
        guard case .active = model.state else { return XCTFail("Cancel left stale busy state") }
        driver.enrollBarrier!.release()
        await login.value
    }

    func testDeletionPublishesReauthenticationFenceAndControlledCleanup() async throws {
        let active = ObservationIdentity(), fresh = ObservationIdentity(), a = try scope(), admission = ObservationAdmission()
        for driver in [active, fresh] { driver.session = .init(accountID: a.accountID, sessionID: UUID(), expiresAt: Date().addingTimeInterval(600)) }
        fresh.enrollBarrier = ObservationBarrier()
        fresh.deleteBarrier = ObservationBarrier()
        var drivers = [active, fresh]
        let coordinator = try WorkspaceAccountCoordinator(deployment: deployment(), admission: admission, makeIdentity: { _, _ in drivers.removeFirst() })
        let window = UUID()
        try coordinator.attach(windowID: window, scope: a)
        await coordinator.restore(windowID: window)
        let model = try coordinator.observe(windowID: window)
        let deletion = Task { await coordinator.deleteAccount(windowID: window, scope: a) }
        await fresh.enrollBarrier!.entered()
        guard case .reauthenticatingForDeletion = model.state else { return XCTFail("Reauthentication not published") }
        fresh.enrollBarrier!.release()
        await fresh.deleteBarrier!.entered()
        XCTAssertEqual(model.state, .deleting(scope: a))
        fresh.deleteBarrier!.release()
        _ = await deletion.value
        XCTAssertEqual(model.state, .localDenied(scope: a, remoteOutcome: .confirmedAccountTombstone))
        XCTAssertEqual(model.cleanupOutcome, .remoteRevocationUnknown)
        XCTAssertEqual(model.operationOutcome, .deletion(.confirmedAccountTombstone))
    }

    func testWeakSubscriptionsPruneAndUnsubscribedRetainedModelStopsReceiving() async throws {
        let coordinator = try WorkspaceAccountCoordinator(deployment: deployment(), admission: ObservationAdmission(), capacity: 1, makeIdentity: { _, _ in ObservationIdentity() })
        var released: WorkspaceAccountPresentation? = try coordinator.observe(windowID: UUID())
        weak var weakModel = released
        released = nil
        XCTAssertNil(weakModel)
        let id = UUID()
        let old = try coordinator.observe(windowID: id)
        XCTAssertTrue(old === (try coordinator.observe(windowID: id)))
        coordinator.unsubscribe(windowID: id)
        let replacement = try coordinator.observe(windowID: id)
        XCTAssertFalse(old === replacement)
        let account = try scope()
        try coordinator.attach(windowID: id, scope: account)
        await coordinator.logout(scope: account, allSessions: false)
        XCTAssertEqual(old.state, .signedOut)
        XCTAssertNotEqual(replacement.state, old.state)
    }


}

private struct ObservationTicket: WorkspaceAccountAdmissionTicket { let scope: WorkspaceAccountScope }
@MainActor private final class ObservationAdmission: WorkspaceAccountAdmission {
    var failDenial = false
    var failRemoval = false
    func capture(scope: WorkspaceAccountScope) throws -> any WorkspaceAccountAdmissionTicket { ObservationTicket(scope: scope) }
    func beginEnrollment(expected: any WorkspaceAccountAdmissionTicket) throws -> any WorkspaceAccountAdmissionTicket { expected }
    func deny(expected: any WorkspaceAccountAdmissionTicket, reason: WorkspaceAccountDenialReason) throws -> any WorkspaceAccountAdmissionTicket { if failDenial { throw WorkspaceAccountAdmissionFailure.unavailable }; return expected }
    func load(expected: any WorkspaceAccountAdmissionTicket) async throws -> WorkspaceAccountLoadedCredential? {
        let scope = (expected as! ObservationTicket).scope
        return WorkspaceAccountLoadedCredential(credential: try WorkspaceCredential(origin: scope.origin, accountID: scope.accountID, token: String(repeating: "a", count: 43), profileID: scope.profileID), ticket: expected)
    }
    func remove(expected: any WorkspaceAccountAdmissionTicket) async throws { if failRemoval { throw WorkspaceAccountAdmissionFailure.unavailable } }
}
@MainActor private final class ObservationIdentity: WorkspaceAccountIdentityDriver {
    var session: WorkspaceAccountVerifiedSession!
    var restoreBarrier: ObservationBarrier?, enrollBarrier: ObservationBarrier?, logoutBarrier: ObservationBarrier?, deleteBarrier: ObservationBarrier?
    func restore() async throws -> WorkspaceAccountVerifiedSession { await restoreBarrier?.pause(); return session }
    func enroll() async throws -> WorkspaceAccountVerifiedSession { await enrollBarrier?.pause(); return session }
    func save(expected: any WorkspaceAccountAdmissionTicket) async throws -> any WorkspaceAccountAdmissionTicket { expected }
    func discardEnrollment() async -> WorkspaceLogoutOutcome { .remoteRevocationUnknown }
    func logout(allSessions: Bool) async -> WorkspaceLogoutOutcome { await logoutBarrier?.pause(); return .remoteRevocationUnknown }
    func deleteFreshEnrollment() async throws -> WorkspaceAccountDeletionOutcome { await deleteBarrier?.pause(); return .confirmedAccountTombstone }
    func invalidate() async {}
    func cancelProof() {}
}
@MainActor private final class ObservationBarrier {
    private var didEnter = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var suspension: CheckedContinuation<Void, Never>?
    func pause() async { didEnter = true; waiters.forEach { $0.resume() }; waiters.removeAll(); await withCheckedContinuation { suspension = $0 } }
    func entered() async { if didEnter { return }; await withCheckedContinuation { waiters.append($0) } }
    func release() { suspension?.resume(); suspension = nil }
}

private final class ObservationCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func increment() { lock.withLock { count += 1 } }
    var value: Int { lock.withLock { count } }
}

extension WorkspaceAccountObservationTests {
    func testWrongAccountDeletionPublishesControlledOutcomeWithoutReplacingActiveState() async throws {
        let active = ObservationIdentity(), wrong = ObservationIdentity(), admission = ObservationAdmission()
        let a = try scope()
        active.session = .init(accountID: a.accountID, sessionID: UUID(), expiresAt: Date().addingTimeInterval(600))
        wrong.session = .init(accountID: UUID(), sessionID: UUID(), expiresAt: Date().addingTimeInterval(600))
        var drivers = [active, wrong]
        let coordinator = try WorkspaceAccountCoordinator(deployment: deployment(), admission: admission, makeIdentity: { _, _ in drivers.removeFirst() })
        let window = UUID()
        try coordinator.attach(windowID: window, scope: a)
        await coordinator.restore(windowID: window)
        let model = try coordinator.observe(windowID: window)
        let activeState = model.state
        _ = await coordinator.deleteAccount(windowID: window, scope: a)
        XCTAssertEqual(model.state, activeState)
        XCTAssertEqual(model.operationOutcome, .deletion(.wrongAccount))
        XCTAssertEqual(model.cleanupOutcome, .remoteRevocationUnknown)
    }

    func testDeletionPersistenceErrorAndCleanupRetryPublishCompletion() async throws {
        let active = ObservationIdentity(), fresh = ObservationIdentity(), admission = ObservationAdmission()
        let a = try scope()
        for driver in [active, fresh] { driver.session = .init(accountID: a.accountID, sessionID: UUID(), expiresAt: Date().addingTimeInterval(600)) }
        var drivers = [active, fresh]
        let coordinator = try WorkspaceAccountCoordinator(deployment: deployment(), admission: admission, makeIdentity: { _, _ in drivers.removeFirst() })
        let window = UUID()
        try coordinator.attach(windowID: window, scope: a)
        await coordinator.restore(windowID: window)
        let model = try coordinator.observe(windowID: window)
        admission.failDenial = true
        _ = await coordinator.deleteAccount(windowID: window, scope: a)
        XCTAssertEqual(model.state, .unavailable(.localSignOutPersistenceUnavailable))
        XCTAssertEqual(model.operationOutcome, .deletion(.localPersistenceUnavailable))
        XCTAssertFalse(model.isBusy)
        admission.failDenial = false
        await coordinator.retryDeletionLocalCleanup(scope: a)
        XCTAssertEqual(model.state, .localDenied(scope: a, remoteOutcome: .deletionUnknown))
        XCTAssertEqual(model.operationOutcome, .deletion(.remoteDeletionUnknown))
        XCTAssertEqual(model.cleanupOutcome, .remoteRevocationUnknown)
    }
}

extension WorkspaceAccountObservationTests {
    func testCancelAfterDeleteStartKeepsBusyWithoutClaimingPrestartCancellation() async throws {
        let active = ObservationIdentity(), fresh = ObservationIdentity(), admission = ObservationAdmission(), a = try scope()
        for driver in [active, fresh] { driver.session = .init(accountID: a.accountID, sessionID: UUID(), expiresAt: Date().addingTimeInterval(600)) }
        fresh.deleteBarrier = ObservationBarrier()
        var drivers = [active, fresh]
        let coordinator = try WorkspaceAccountCoordinator(deployment: deployment(), admission: admission, makeIdentity: { _, _ in drivers.removeFirst() })
        let window = UUID()
        try coordinator.attach(windowID: window, scope: a)
        await coordinator.restore(windowID: window)
        let model = try coordinator.observe(windowID: window)
        let deletion = Task { await coordinator.deleteAccount(windowID: window, scope: a) }
        await fresh.deleteBarrier!.entered()
        coordinator.cancelAccountDeletion(windowID: window)
        XCTAssertEqual(model.state, .deleting(scope: a))
        XCTAssertTrue(model.isBusy)
        XCTAssertNil(model.operationOutcome, "Cancellation after start cannot claim that DELETE was prevented")
        fresh.deleteBarrier!.release()
        _ = await deletion.value
        XCTAssertEqual(model.operationOutcome, .deletion(.confirmedAccountTombstone))
    }

    func testReauthenticationCancellationIsPublishedOnlyAfterActualCancelledResult() async throws {
        let active = ObservationIdentity(), fresh = ObservationIdentity(), admission = ObservationAdmission(), a = try scope()
        for driver in [active, fresh] { driver.session = .init(accountID: a.accountID, sessionID: UUID(), expiresAt: Date().addingTimeInterval(600)) }
        fresh.enrollBarrier = ObservationBarrier()
        var drivers = [active, fresh]
        let coordinator = try WorkspaceAccountCoordinator(deployment: deployment(), admission: admission, makeIdentity: { _, _ in drivers.removeFirst() })
        let window = UUID()
        try coordinator.attach(windowID: window, scope: a)
        await coordinator.restore(windowID: window)
        let model = try coordinator.observe(windowID: window)
        let deletion = Task { await coordinator.deleteAccount(windowID: window, scope: a) }
        await fresh.enrollBarrier!.entered()
        coordinator.cancelAccountDeletion(windowID: window)
        XCTAssertNotEqual(model.operationOutcome, .cancelled)
        fresh.enrollBarrier!.release()
        let result = await deletion.value
        XCTAssertEqual(result, .cancelled)
        XCTAssertEqual(model.operationOutcome, .deletion(.cancelled))
    }
}

extension WorkspaceAccountObservationTests {
    func testCleanupRetryAvailabilityComesOnlyFromAttachedActualRecord() async throws {
        let active = ObservationIdentity(), fresh = ObservationIdentity(), admission = ObservationAdmission(), a = try scope()
        for driver in [active, fresh] { driver.session = .init(accountID: a.accountID, sessionID: UUID(), expiresAt: Date().addingTimeInterval(600)) }
        var drivers = [active, fresh]
        let coordinator = try WorkspaceAccountCoordinator(deployment: deployment(), admission: admission, makeIdentity: { _, _ in drivers.removeFirst() })
        let window = UUID(), sibling = UUID(), unrelated = UUID()
        try coordinator.attach(windowID: window, scope: a)
        try coordinator.attach(windowID: sibling, scope: a)
        try coordinator.attach(windowID: unrelated, scope: scope())
        await coordinator.restore(windowID: window)
        let model = try coordinator.observe(windowID: window), second = try coordinator.observe(windowID: sibling), other = try coordinator.observe(windowID: unrelated)
        XCTAssertNil(coordinator.deletionCleanupScope(windowID: window))
        admission.failRemoval = true
        _ = await coordinator.deleteAccount(windowID: window, scope: a)
        XCTAssertEqual(coordinator.deletionCleanupScope(windowID: window), a)
        XCTAssertEqual(coordinator.deletionCleanupScope(windowID: sibling), a)
        XCTAssertNil(coordinator.deletionCleanupScope(windowID: unrelated))
        XCTAssertNil(coordinator.deletionCleanupScope(windowID: UUID()))
        XCTAssertTrue(model.canRetryDeletionLocalCleanup)
        XCTAssertTrue(second.canRetryDeletionLocalCleanup)
        XCTAssertFalse(other.canRetryDeletionLocalCleanup)
        admission.failRemoval = false
        await coordinator.retryDeletionLocalCleanup(scope: a)
        XCTAssertNil(coordinator.deletionCleanupScope(windowID: window))
        XCTAssertFalse(model.canRetryDeletionLocalCleanup)
        XCTAssertFalse(second.canRetryDeletionLocalCleanup)
    }
}
