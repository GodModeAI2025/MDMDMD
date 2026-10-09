import Foundation
import Testing
@testable import SkriptumWorkspaceClient

private struct HTTPFixture: Decodable {
    let origin: String; let ownerToken: String; let ownerID: UUID
    let delayedOrigin: String; let delayedToken: String; let delayedID: UUID
    let viewerToken: String; let viewerID: UUID
    let libraryID: UUID; let spaceID: UUID; let pageID: UUID
    let keyReference: String
    let redirectOrigin: String; let oversizedOrigin: String; let malformedOrigin: String; let slowOrigin: String
}
/// Intentionally fails without explicit real fixture opt-in. No skipped/mocked
/// PostgreSQL suite can be reported as real cross-language proof.
@Test func realWorkspaceHTTPPostgres() async throws {
    guard let path = ProcessInfo.processInfo.environment["SCRIPTUM_CLIENT_VERIFICATION_FIXTURE"] else { throw WorkspaceClientError.invalidConfiguration }
    let fixture = try JSONDecoder().decode(HTTPFixture.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
    let origin = try WorkspaceOrigin.loopbackForTesting(fixture.origin)
    let ownerCredential = try WorkspaceCredential(origin: origin, accountID: fixture.ownerID, token: fixture.ownerToken)
    let viewerCredential = try WorkspaceCredential(origin: origin, accountID: fixture.viewerID, token: fixture.viewerToken)
    let owner = try WorkspaceClient(origin: origin, credential: ownerCredential)
    let viewer = try WorkspaceClient(origin: origin, credential: viewerCredential)
    #expect(try await owner.readiness())
    let newLibrary = try await owner.createLibrary(title: "Client e\u{301}\r\n")
    _ = try await owner.createSpace(libraryID: newLibrary, title: "Space 🦊")
    let address = WorkspacePageAddress(libraryID: fixture.libraryID, spaceID: fixture.spaceID, pageID: fixture.pageID)
    let initial = try await owner.readPage(address)
    let originalBytes = initial.envelope
    var ciphertext = Data("e\u{301}\r\n🦊".utf8); ciphertext.append(Data(repeating: 4, count: 40))
    let envelope = try WorkspaceEnvelope(ciphertext: ciphertext, nonce: Data(UUID().uuidString.utf8.prefix(12)), digest: Data(repeating: 6, count: 32), keyReference: fixture.keyReference)
    let next = try await owner.writePage(address, envelope: envelope, expectedRevision: initial.revision)
    #expect(next != initial.revision)
    let current = try await owner.readPage(address)
    #expect(current.envelope == envelope)
    #expect(current.envelope.ciphertext != originalBytes.ciphertext)
    do { _ = try await owner.writePage(address, envelope: initial.envelope, expectedRevision: initial.revision); Issue.record("Stale CAS accepted") }
    catch { #expect(error as? WorkspaceClientError == .conflict) }
    #expect(try await owner.readPage(address) == current)
    do { _ = try await viewer.writePage(address, envelope: envelope, expectedRevision: current.revision); Issue.record("Viewer wrote") }
    catch { #expect(error as? WorkspaceClientError == .notFound) }
    #expect(try await viewer.readPage(address) == current)
    try await owner.setMembership(.page(address), accountID: fixture.viewerID, role: .none)
    do { _ = try await viewer.readPage(address); Issue.record("Restricted viewer read") }
    catch { #expect(error as? WorkspaceClientError == .notFound) }
    try await owner.revokeMembership(.page(address), accountID: fixture.viewerID)
    #expect(try await viewer.readPage(address) == current)
    let createdAddress = WorkspacePageAddress(libraryID: fixture.libraryID, spaceID: fixture.spaceID, pageID: UUID())
    let createdEnvelope = try WorkspaceEnvelope(ciphertext: Data(repeating: 9, count: 33), nonce: Data(UUID().uuidString.utf8.suffix(12)), digest: Data(repeating: 8, count: 32), keyReference: fixture.keyReference)
    let createdRevision = try await owner.createPage(createdAddress, envelope: createdEnvelope)
    #expect(try await owner.readPage(createdAddress).revision == createdRevision)
    #expect(await owner.logout() == .confirmedRemoteRevocation)
    #expect(await owner.isSignedIn == false)
    #expect(await owner.logout() == .alreadySignedOut)
    do { _ = try await owner.readPage(address); Issue.record("Local signed-out access") }
    catch { #expect(error as? WorkspaceClientError == .signedOut) }
    let replay = try WorkspaceClient(origin: origin, credential: ownerCredential)
    do { _ = try await replay.readPage(address); Issue.record("Revoked token accepted") }
    catch { #expect(error as? WorkspaceClientError == .unauthenticated) }
    for (url, expected) in [(fixture.redirectOrigin, WorkspaceClientError.redirectDenied), (fixture.oversizedOrigin, .oversized), (fixture.malformedOrigin, .invalidResponse)] {
        let client = try WorkspaceClient(origin: WorkspaceOrigin.loopbackForTesting(url))
        do { _ = try await client.readiness(); Issue.record("Unsafe response accepted") }
        catch { #expect(error as? WorkspaceClientError == expected) }
    }
    let slow = try WorkspaceClient(origin: WorkspaceOrigin.loopbackForTesting(fixture.slowOrigin))
    let requests = (0..<8).map { _ in Task { try await slow.readiness() } }
    try await waitForControl(fixture.slowOrigin, path: "/control/arrivals") { ($0["count"] as? Int) == 8 }
    do { _ = try await slow.readiness(); Issue.record("Client concurrency exceeded bound") }
    catch { #expect(error as? WorkspaceClientError == .unavailable) }
    for request in requests { request.cancel() }
    for request in requests {
        do { _ = try await request.value; Issue.record("Cancelled client request completed") }
        catch { #expect(error as? WorkspaceClientError == .cancelled) }
    }
    _ = try await control(fixture.slowOrigin, path: "/control/release")
    let racing = Task { try await slow.readiness() }
    try await waitForControl(fixture.slowOrigin, path: "/control/arrivals") { ($0["count"] as? Int) == 9 }
    _ = try await control(fixture.slowOrigin, path: "/control/release")
    racing.cancel()
    do { #expect(try await racing.value) }
    catch { #expect(error as? WorkspaceClientError == .cancelled) }
    let delayedOrigin = try WorkspaceOrigin.loopbackForTesting(fixture.delayedOrigin)
    let delayed = try WorkspaceClient(origin: delayedOrigin, credential: WorkspaceCredential(origin: delayedOrigin, accountID: fixture.delayedID, token: fixture.delayedToken))
    let preceding = Task { try await delayed.readPage(address) }
    try await waitForControl(fixture.delayedOrigin, path: "/control/admitted") { ($0["admitted"] as? Bool) == true }
    #expect(await delayed.logout() == .confirmedRemoteRevocation)
    for _ in 0..<3 {
        do { _ = try await delayed.readPage(address); Issue.record("Post-logout request admitted") }
        catch { #expect(error as? WorkspaceClientError == .signedOut) }
    }
    let metrics = try await control(fixture.delayedOrigin, path: "/control/admitted")
    #expect(metrics["count"] as? Int == 1)
    _ = try await control(fixture.delayedOrigin, path: "/control/release")
    #expect(try await preceding.value == current)
    let mismatched = try WorkspaceOrigin.loopbackForTesting(fixture.redirectOrigin)
    #expect(throws: WorkspaceClientError.originMismatch) { try WorkspaceClient(origin: mismatched, credential: ownerCredential) }
    let failedLogout = try WorkspaceClient(origin: mismatched, credential: WorkspaceCredential(origin: mismatched, accountID: fixture.ownerID, token: fixture.ownerToken))
    #expect(await failedLogout.logout() == .remoteRevocationUnknown)
    #expect(await failedLogout.isSignedIn == false)
}

private func control(_ origin: String, path: String) async throws -> [String: Any] {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.httpCookieStorage = nil; configuration.urlCredentialStorage = nil
    configuration.timeoutIntervalForRequest = 2; configuration.timeoutIntervalForResource = 2
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }
    let (data, response) = try await session.data(from: #require(URL(string: origin + path)))
    guard data.count <= 1024, (response as? HTTPURLResponse)?.statusCode == 200,
          let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw WorkspaceClientError.invalidResponse }
    return object
}
private func waitForControl(_ origin: String, path: String, condition: ([String: Any]) -> Bool) async throws {
    for _ in 0..<100 {
        if condition(try await control(origin, path: path)) { return }
        try await Task.sleep(for: .milliseconds(20))
    }
    throw WorkspaceClientError.unavailable
}
