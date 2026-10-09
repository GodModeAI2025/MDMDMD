import Foundation
import Security

/// Actual original protection checks plus uniquely scoped gated Security IO.
func runWorkspaceKeychainAndAdmissionProbe() async throws -> (original: Int, admission: Int) {
    let original = try await runWorkspaceKeychainProbe()
    let directory = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("admission-proof-" + UUID().uuidString)
    let service = "test.admission." + UUID().uuidString
    let origin = try WorkspaceOrigin("https://admission-proof.example"), account = UUID()
    let scope = try WorkspaceCredentialScope(origin: origin, profileID: "profile-a", accountID: account)
    let context = try WorkspaceCredentialAdmissionContext.shared(denialDirectory: directory, keychainService: service)
    let store = WorkspaceCredentialAdmissionStore(context: context)
    var checks = 0
    func require(_ value: Bool) throws { guard value else { throw WorkspaceCredentialAdmissionError.invalidScope }; checks += 1 }
    func candidate(_ token: String) throws -> WorkspaceIdentityEnrollment {
        let credential = try WorkspaceCredential(origin: origin, accountID: account, token: token, profileID: scope.profileID)
        let session = WorkspaceIdentitySession(accountID: account, sessionID: UUID(), expiresAt: Date().addingTimeInterval(3600))
        let receipt = WorkspaceReauthenticationReceipt(token: token, origin: origin, profileID: scope.profileID, accountID: account, deadline: ContinuousClock().now.advanced(by: .seconds(300)))
        return WorkspaceIdentityEnrollment(credential: credential, session: session, reauthenticationReceipt: receipt)
    }
    do {
        let start = try context.capture(scope: scope)
        try require(try await store.loadIfAdmitted(expected: start) == nil)
        let a = try candidate(String(repeating: "A", count: 43))
        let active = try await store.saveIfAdmitted(a, expected: context.beginExplicitEnrollment(expected: start))
        try require(try await store.loadIfAdmitted(expected: active)?.credential.token == a.credential.token)
        let denied = try context.commitDenial(expected: active, reason: .localLogout)
        do { _ = try await store.loadIfAdmitted(expected: denied); throw WorkspaceClientError.invalidResponse }
        catch WorkspaceCredentialAdmissionError.denied { checks += 1 }
        try await store.removeIfDenied(expected: denied)
        try await store.removeIfDenied(expected: denied); checks += 1
        let c = try candidate(String(repeating: "C", count: 43))
        let restored = try await store.saveIfAdmitted(c, expected: context.beginExplicitEnrollment(expected: context.capture(scope: scope)))
        try require(try await store.loadIfAdmitted(expected: restored)?.credential.token == c.credential.token)
        do { try await store.removeIfDenied(expected: denied); throw WorkspaceClientError.invalidResponse }
        catch WorkspaceCredentialAdmissionError.staleTicket { checks += 1 }
        do { _ = try context.commitDenial(expected: active, reason: .unauthorized); throw WorkspaceClientError.invalidResponse }
        catch WorkspaceCredentialAdmissionError.staleTicket { checks += 1 }
        try require(try await store.loadIfAdmitted(expected: restored)?.credential.token == c.credential.token)
        let other = try WorkspaceCredentialScope(origin: origin, profileID: "profile-b", accountID: account)
        try require(try await store.loadIfAdmitted(expected: context.capture(scope: other)) == nil)
        let final = try context.commitDenial(expected: restored, reason: .localLogout)
        try await store.removeIfDenied(expected: final)
        let raw = try WorkspaceKeychainCredentialStore(profileID: scope.profileID, service: service)
        try require(try await raw.load(origin: origin, accountID: account) == nil)
    } catch {
        let cleanup = try? WorkspaceKeychainCredentialStore(profileID: scope.profileID, service: service)
        try? await cleanup?.remove(origin: origin, accountID: account)
        try? FileManager.default.removeItem(at: directory)
        throw error
    }
    try FileManager.default.removeItem(at: directory)
    return (original, checks)
}
