import Foundation
import Testing
@testable import SkriptumWorkspaceClient

private struct MetadataAdmissionFixture: Sendable {
    let root: URL
    let security = AdmissionMemorySecurity()
    let context: WorkspaceCredentialAdmissionContext
    let store: WorkspaceCredentialAdmissionStore
    let scope: WorkspaceCredentialScope
    init() throws {
        root = URL(fileURLWithPath: "/private/tmp").appendingPathComponent("ScriptumMetadataAdmission-" + UUID().uuidString)
        context = try WorkspaceCredentialAdmissionContext(denialDirectory: root, keychainService: "owned.metadata.test", security: security)
        store = WorkspaceCredentialAdmissionStore(context: context)
        scope = try WorkspaceCredentialScope(origin: WorkspaceOrigin("https://workspace.example"), profileID: "native", accountID: UUID())
    }
    func enrollment(scope: WorkspaceCredentialScope? = nil, token: String = String(repeating: "A", count: 43)) throws -> WorkspaceIdentityEnrollment {
        let selected = scope ?? self.scope
        let credential = try WorkspaceCredential(origin: selected.origin, accountID: selected.accountID, token: token, profileID: selected.profileID)
        return WorkspaceIdentityEnrollment(credential: credential,
            session: WorkspaceIdentitySession(accountID: selected.accountID, sessionID: UUID(), expiresAt: Date().addingTimeInterval(600)),
            reauthenticationReceipt: WorkspaceReauthenticationReceipt(token: token, origin: selected.origin, profileID: selected.profileID, accountID: selected.accountID, deadline: ContinuousClock().now.advanced(by: .seconds(300))))
    }
    func admitted(_ candidate: WorkspaceIdentityEnrollment) async throws -> WorkspaceCredentialAdmissionTicket {
        try await store.saveIfAdmitted(candidate, expected: context.beginExplicitEnrollment(expected: context.capture(scope: scope)))
    }
}

@Test func metadataAdmissionCorrectOpaqueCredentialAllowsTrustedSynchronousCommit() async throws {
    let fixture = try MetadataAdmissionFixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let enrollment = try fixture.enrollment(), ticket = try await fixture.admitted(enrollment)
    try fixture.context.validateIfAdmitted(expected: ticket, matching: enrollment.credential)
    let value = try fixture.context.withAdmittedCredential(expected: ticket, matching: enrollment.credential) { "owned-binding-result" }
    #expect(value == "owned-binding-result")
    // A restored eligible credential is also valid locally; server admission
    // remains the separate identity actor's responsibility.
    let restarted = try WorkspaceCredentialAdmissionContext(denialDirectory: fixture.root, keychainService: "owned.metadata.test", security: fixture.security)
    try restarted.validateIfAdmitted(expected: restarted.capture(scope: fixture.scope), matching: enrollment.credential)
}

@Test func metadataAdmissionMismatchedTokenOriginProfileAndAccountNeverInvokeCommit() async throws {
    let fixture = try MetadataAdmissionFixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let enrollment = try fixture.enrollment(), ticket = try await fixture.admitted(enrollment)
    let mismatches = [
        try fixture.enrollment(token: String(repeating: "B", count: 43)).credential,
        try fixture.enrollment(scope: WorkspaceCredentialScope(origin: WorkspaceOrigin("https://other.example"), profileID: "native", accountID: fixture.scope.accountID)).credential,
        try fixture.enrollment(scope: WorkspaceCredentialScope(origin: fixture.scope.origin, profileID: "Native", accountID: fixture.scope.accountID)).credential,
        try fixture.enrollment(scope: WorkspaceCredentialScope(origin: fixture.scope.origin, profileID: "native", accountID: UUID())).credential,
    ]
    var calls = 0
    for candidate in mismatches {
        #expect(throws: (any Error).self) { try fixture.context.validateIfAdmitted(expected: ticket, matching: candidate) }
        #expect(throws: (any Error).self) { try fixture.context.withAdmittedCredential(expected: ticket, matching: candidate) { calls += 1 } }
    }
    #expect(calls == 0)
}

@Test func metadataAdmissionChangedActualTokenDenialAndReplacementRejectOldCommit() async throws {
    let fixture = try MetadataAdmissionFixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let original = try fixture.enrollment(), active = try await fixture.admitted(original)
    let external = try fixture.enrollment(token: String(repeating: "C", count: 43))
    try fixture.security.save(external.credential, scope: fixture.scope)
    var calls = 0
    #expect(throws: WorkspaceCredentialAdmissionError.staleTicket) { try fixture.context.withAdmittedCredential(expected: active, matching: original.credential) { calls += 1 } }
    try fixture.security.save(original.credential, scope: fixture.scope)
    let denied = try fixture.context.commitDenial(expected: active, reason: .localLogout)
    #expect(throws: WorkspaceCredentialAdmissionError.staleTicket) { try fixture.context.validateIfAdmitted(expected: active, matching: original.credential) }
    #expect(throws: WorkspaceCredentialAdmissionError.denied) { try fixture.context.withAdmittedCredential(expected: denied, matching: original.credential) { calls += 1 } }
    let replacement = try fixture.enrollment(token: String(repeating: "D", count: 43))
    let fresh = try await fixture.store.saveIfAdmitted(replacement, expected: fixture.context.beginExplicitEnrollment(expected: denied))
    #expect(throws: WorkspaceCredentialAdmissionError.staleTicket) { try fixture.context.withAdmittedCredential(expected: active, matching: original.credential) { calls += 1 } }
    try fixture.context.validateIfAdmitted(expected: fresh, matching: replacement.credential)
    #expect(calls == 0)
}

@Test func metadataAdmissionFailedOrExternallyChangedLedgerNeverAuthorizesCommit() async throws {
    let fixture = try MetadataAdmissionFixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let original = try fixture.enrollment(), active = try await fixture.admitted(original)
    let file = fixture.root.appendingPathComponent(AdmissionDenialRepository.filename)
    try FileManager.default.createDirectory(at: fixture.root, withIntermediateDirectories: false)
    let unexpected = Data("invalid-owned-ledger".utf8)
    try unexpected.write(to: file)
    #expect(chmod(file.path, 0o600) == 0)
    var calls = 0
    #expect(throws: (any Error).self) { try fixture.context.withAdmittedCredential(expected: active, matching: original.credential) { calls += 1 } }
    #expect(try Data(contentsOf: file) == unexpected)
    try FileManager.default.removeItem(at: file)
    #expect(chmod(fixture.root.path, 0o500) == 0)
    defer { _ = chmod(fixture.root.path, 0o700) }
    #expect(throws: WorkspaceCredentialAdmissionError.persistenceUnavailable) { try fixture.context.commitDenial(expected: active, reason: .unauthorized) }
    let failed = try fixture.context.capture(scope: fixture.scope)
    #expect(throws: WorkspaceCredentialAdmissionError.persistenceUnavailable) { try fixture.context.withAdmittedCredential(expected: failed, matching: original.credential) { calls += 1 } }
    #expect(calls == 0)
}

@Test func metadataAdmissionDenialFirstRunsNoCommitAndPreservesAccountB() async throws {
    let fixture = try MetadataAdmissionFixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let a = try fixture.enrollment(), activeA = try await fixture.admitted(a)
    let bScope = try WorkspaceCredentialScope(origin: fixture.scope.origin, profileID: "native", accountID: UUID())
    let b = try fixture.enrollment(scope: bScope)
    let activeB = try await fixture.store.saveIfAdmitted(b, expected: fixture.context.beginExplicitEnrollment(expected: fixture.context.capture(scope: bScope)))
    _ = try fixture.context.commitDenial(expected: activeA, reason: .logoutAll)
    var calls = 0
    #expect(throws: WorkspaceCredentialAdmissionError.staleTicket) { try fixture.context.withAdmittedCredential(expected: activeA, matching: a.credential) { calls += 1 } }
    #expect(calls == 0)
    try fixture.context.validateIfAdmitted(expected: activeB, matching: b.credential)
}

@Test func metadataAdmissionCommitFirstHoldsSameGateUntilTrustedCallbackCompletes() async throws {
    let fixture = try MetadataAdmissionFixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let candidate = try fixture.enrollment(), active = try await fixture.admitted(candidate)
    let entered = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0), denialStarted = DispatchSemaphore(value: 0), denialFinished = DispatchSemaphore(value: 0)
    defer { release.signal() }
    let commits = MetadataCommitCounter()
    let commit = Task.detached {
        try fixture.context.withAdmittedCredential(expected: active, matching: candidate.credential) {
            entered.signal()
            guard release.wait(timeout: .now() + 3) == .success else { throw MetadataBarrierError.deadline }
            commits.increment()
            return "committed"
        }
    }
    #expect(await metadataWait(entered) == .success)
    let denial = Task.detached {
        denialStarted.signal()
        let ticket = try fixture.context.commitDenial(expected: active, reason: .localLogout)
        denialFinished.signal()
        return ticket
    }
    #expect(await metadataWait(denialStarted) == .success)
    #expect(denialFinished.wait(timeout: .now() + .milliseconds(100)) == .timedOut)
    release.signal()
    #expect(try await commit.value == "committed")
    let denied = try await denial.value
    #expect(commits.value == 1)
    #expect(throws: WorkspaceCredentialAdmissionError.denied) { try fixture.context.withAdmittedCredential(expected: denied, matching: candidate.credential) { commits.increment() } }
    #expect(commits.value == 1)
}

private enum MetadataBarrierError: Error { case deadline }
private final class MetadataCommitCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func increment() { lock.withLock { count += 1 } }
    var value: Int { lock.withLock { count } }
}
private func metadataWait(_ semaphore: DispatchSemaphore) async -> DispatchTimeoutResult {
    await withCheckedContinuation { continuation in
        DispatchQueue.global().async { continuation.resume(returning: semaphore.wait(timeout: .now() + 3)) }
    }
}
