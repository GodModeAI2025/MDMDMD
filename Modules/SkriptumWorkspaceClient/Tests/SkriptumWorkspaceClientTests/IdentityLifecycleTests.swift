#if os(macOS)
import Foundation
import Testing
@testable import SkriptumWorkspaceClient

private struct IdentityLifecycleFixture: Decodable { let origin: String; let accountID: UUID; let oldToken: String }
@Test func identityFreshLoginSurvivesPriorSession401() async throws {
    let owned = try await OwnedIdentityLifecycleFixture()
    defer { owned.close() }
    let fixture = owned.value
    let origin = try WorkspaceOrigin.loopbackForTesting(fixture.origin)
    let credential = try WorkspaceCredential(origin: origin, accountID: fixture.accountID, token: fixture.oldToken, profileID: "apple")
    let client = try WorkspaceIdentityClient(origin: origin, profileID: "apple", consentVersion: "v1", credential: credential)
    #expect(await client.admissionState == .unvalidated)
    let oldValidation = Task { try await client.currentSession() }
    try await awaitIdentityFixture(fixture.origin) { $0["pending401"] as? Bool == true }
    let challenge = try await client.challenge()
    let proof = try WorkspaceIdentityProof(identityToken: "e30.e30." + String(repeating: "A", count: 43), authorizationCode: "synthetic-code", state: challenge.state)
    let enrollment = Task { try await client.enroll(challenge: challenge, proof: proof) }
    try await awaitIdentityFixture(fixture.origin) { $0["pendingEnroll"] as? Bool == true }
    _ = try await identityControl(fixture.origin, path: "/control/release401")
    do { _ = try await oldValidation.value; Issue.record("Old expired token accepted") }
    catch { #expect(error as? WorkspaceClientError == .unauthenticated) }
    _ = try await identityControl(fixture.origin, path: "/control/releaseEnrollment")
    let result = try await enrollment.value
    #expect(result.credential.accountID == fixture.accountID)
    #expect(await client.isSignedIn)
    #expect(try await client.currentSession().sessionID == result.session.sessionID)
    let status = try await identityControl(fixture.origin, path: "/control/state")
    #expect(status["logoutCount"] as? Int == 0)
    #expect(try await client.deleteAccount(using: result.reauthenticationReceipt) == .confirmedAccountTombstone)
    #expect(await client.admissionState == .signedOut)
}
@Test func identityExplicitLogoutFencesLateEnrollmentAndCleansSession() async throws {
    let owned = try await OwnedIdentityLifecycleFixture(); defer { owned.close() }
    let fixture = owned.value, origin = try WorkspaceOrigin.loopbackForTesting(fixture.origin)
    let client = try WorkspaceIdentityClient(origin: origin, profileID: "apple", consentVersion: "v1", credential: WorkspaceCredential(origin: origin, accountID: fixture.accountID, token: fixture.oldToken, profileID: "apple"))
    let challenge = try await client.challenge()
    let proof = try WorkspaceIdentityProof(identityToken: "e30.e30." + String(repeating: "A", count: 43), authorizationCode: "synthetic-code", state: challenge.state)
    let enrollment = Task { try await client.enroll(challenge: challenge, proof: proof) }
    try await awaitIdentityFixture(fixture.origin) { $0["pendingEnroll"] as? Bool == true }
    #expect(await client.logoutAll() == .confirmedRemoteRevocation)
    #expect(await client.admissionState == .signedOut)
    _ = try await identityControl(fixture.origin, path: "/control/releaseEnrollment")
    do { _ = try await enrollment.value; Issue.record("Late enrollment reinstalled after explicit logout") }
    catch { #expect(error as? WorkspaceIdentityClientError == .supersededEnrollment(remoteRevocationConfirmed: true)) }
    #expect(await client.admissionState == .signedOut)
    let state = try await identityControl(fixture.origin, path: "/control/state")
    #expect(state["logoutCount"] as? Int == 2)
}
@Test func identityLateOld401CannotClearInstalledFreshSession() async throws {
    let owned = try await OwnedIdentityLifecycleFixture(); defer { owned.close() }
    let fixture = owned.value, origin = try WorkspaceOrigin.loopbackForTesting(fixture.origin)
    let client = try WorkspaceIdentityClient(origin: origin, profileID: "apple", consentVersion: "v1", credential: WorkspaceCredential(origin: origin, accountID: fixture.accountID, token: fixture.oldToken, profileID: "apple"))
    let oldValidation = Task { try await client.currentSession() }
    try await awaitIdentityFixture(fixture.origin) { $0["pending401"] as? Bool == true }
    let challenge = try await client.challenge()
    let proof = try WorkspaceIdentityProof(identityToken: "e30.e30." + String(repeating: "A", count: 43), authorizationCode: "synthetic-code", state: challenge.state)
    let enrollment = Task { try await client.enroll(challenge: challenge, proof: proof) }
    try await awaitIdentityFixture(fixture.origin) { $0["pendingEnroll"] as? Bool == true }
    _ = try await identityControl(fixture.origin, path: "/control/releaseEnrollment")
    let installed = try await enrollment.value
    _ = try await identityControl(fixture.origin, path: "/control/release401")
    do { _ = try await oldValidation.value; Issue.record("Old expired token accepted") }
    catch { #expect(error as? WorkspaceClientError == .unauthenticated) }
    #expect(await client.isSignedIn)
    #expect(try await client.currentSession().sessionID == installed.session.sessionID)
}
#if SWIFT_PACKAGE && DEBUG
@Test(arguments: [false, true]) func identityCancelledAfterParsedResponseNeverInstallsCredential(remoteFailure: Bool) async throws {
    let owned = try await OwnedIdentityLifecycleFixture(); defer { owned.close() }
    let fixture = owned.value, origin = try WorkspaceOrigin.loopbackForTesting(fixture.origin)
    let checkpoint = IdentityAdmissionCheckpoint()
    let configuration = try IdentityClientConfiguration(origin: origin, profileID: "apple", consentVersion: "v1", credential: nil)
    let client = WorkspaceIdentityClient(configuration: configuration, beforeEnrollmentAdmission: { await checkpoint.pause() })
    let challenge = try await client.challenge()
    let proof = try WorkspaceIdentityProof(identityToken: "e30.e30." + String(repeating: "A", count: 43), authorizationCode: "synthetic-code", state: challenge.state)
    let enrollment = Task { try await client.enroll(challenge: challenge, proof: proof) }
    try await awaitIdentityFixture(fixture.origin) { $0["pendingEnroll"] as? Bool == true }
    _ = try await identityControl(fixture.origin, path: "/control/releaseEnrollment")
    for _ in 0..<100 { if await checkpoint.isPaused { break }; try await Task.sleep(for: .milliseconds(20)) }
    #expect(await checkpoint.isPaused)
    if remoteFailure { _ = try await identityControl(fixture.origin, path: "/control/failLogout") }
    enrollment.cancel()
    await checkpoint.release()
    do { _ = try await enrollment.value; Issue.record("Cancelled task installed the parsed fresh credential") }
    catch { #expect(error as? WorkspaceIdentityClientError == .cancelledEnrollment(remoteRevocationConfirmed: !remoteFailure)) }
    #expect(await client.admissionState == .signedOut)
    let status = try await identityControl(fixture.origin, path: "/control/state")
    #expect(status["logoutCount"] as? Int == 1)
}
private actor IdentityAdmissionCheckpoint {
    private var pending: CheckedContinuation<Void, Never>?
    var isPaused: Bool { pending != nil }
    func pause() async { await withCheckedContinuation { pending = $0 } }
    func release() { let continuation = pending; pending = nil; continuation?.resume() }
}
#endif
private final class OwnedIdentityLifecycleFixture {
    let directory: URL
    let process: Process
    let input: Pipe
    let value: IdentityLifecycleFixture
    init() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let file = directory.appendingPathComponent("private-fixture.json")
        let script = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Verification/identity-lifecycle-fixture.mjs")
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/env"); process.arguments = ["node", script.path, file.path]
        let input = Pipe(); process.standardInput = input
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            for _ in 0..<100 {
                if FileManager.default.fileExists(atPath: file.path) { break }
                try await Task.sleep(for: .milliseconds(20))
            }
            value = try JSONDecoder().decode(IdentityLifecycleFixture.self, from: Data(contentsOf: file))
        } catch {
            if process.isRunning { process.terminate(); process.waitUntilExit() }
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
        self.directory = directory; self.process = process; self.input = input
    }
    func close() {
        if process.isRunning { process.terminate(); process.waitUntilExit() }
        try? FileManager.default.removeItem(at: directory)
    }
}
private func identityControl(_ origin: String, path: String) async throws -> [String: Any] {
    let configuration = URLSessionConfiguration.ephemeral; configuration.httpCookieStorage = nil; configuration.urlCredentialStorage = nil
    configuration.timeoutIntervalForRequest = 2; configuration.timeoutIntervalForResource = 2
    let session = URLSession(configuration: configuration); defer { session.invalidateAndCancel() }
    let (data, response) = try await session.data(from: #require(URL(string: origin + path)))
    guard data.count <= 1024, (response as? HTTPURLResponse)?.statusCode == 200,
          let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw WorkspaceClientError.invalidResponse }
    return object
}
private func awaitIdentityFixture(_ origin: String, condition: ([String: Any]) -> Bool) async throws {
    for _ in 0..<100 {
        if condition(try await identityControl(origin, path: "/control/state")) { return }
        try await Task.sleep(for: .milliseconds(20))
    }
    throw WorkspaceClientError.unavailable
}
#endif
