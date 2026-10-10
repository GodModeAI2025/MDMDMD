import Foundation
import Testing
@testable import SkriptumWorkspaceClient

private struct VerificationTLSFixture {
    let root: URL
    let process: Process
    let origin: WorkspaceOrigin
    init() throws {
        let ownedRoot = URL(fileURLWithPath: "/private/tmp/ScriptumVerificationTLS-" + UUID().uuidString)
        let child = Process()
        var created = false
        var launched = false
        do {
            try FileManager.default.createDirectory(at: ownedRoot, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            created = true
            child.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Verification/verification-tls-fixture.mjs")
            child.arguments = ["node", fixture.path, ownedRoot.path]
            child.standardOutput = FileHandle.nullDevice; child.standardError = FileHandle.nullDevice
            try child.run()
            launched = true
            let deadline = Date().addingTimeInterval(12)
            let ready = ownedRoot.appendingPathComponent("ready.json")
            while !FileManager.default.fileExists(atPath: ready.path), child.isRunning, Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
            guard FileManager.default.fileExists(atPath: ready.path) else { throw FixtureFailure.start }
            let data = try Data(contentsOf: ready)
            let row = try JSONSerialization.jsonObject(with: data) as? [String: Int]
            guard let port = row?["port"], (1...65535).contains(port) else { throw FixtureFailure.start }
            // Certificate reads are also covered by the same owned cleanup boundary.
            for name in ["server", "wrong"] {
                let der = try Data(contentsOf: ownedRoot.appendingPathComponent(name + ".der"))
                guard (1...65536).contains(der.count) else { throw FixtureFailure.start }
            }
            let ownedOrigin = try WorkspaceOrigin("https://127.0.0.1:\(port)")
            root = ownedRoot; process = child; origin = ownedOrigin
        } catch {
            if launched { if child.isRunning { child.terminate() }; child.waitUntilExit() }
            if created { try? FileManager.default.removeItem(at: ownedRoot) }
            throw error
        }
    }
    func cleanup() { if process.isRunning { process.terminate() }; process.waitUntilExit(); try? FileManager.default.removeItem(at: root) }
    func request(_ path: String = "/ok") -> URLRequest { URLRequest(url: URL(string: origin.url.absoluteString + path)!) }
    func certificate(_ name: String = "server") throws -> Data { try Data(contentsOf: root.appendingPathComponent(name + ".der")) }
    private enum FixtureFailure: Error { case start }
}

@Test func verificationTLSDefaultTransportRejectsOwnedUntrustedCertificate() async throws {
    let fixture = try VerificationTLSFixture(); defer { fixture.cleanup() }
    do { _ = try await BoundedTransport(limit: 1024).run(fixture.request()); Issue.record("Platform trust accepted the owned untrusted certificate") }
    catch { #expect(error as? WorkspaceClientError == .transport) }
}


@Test func verificationTLSExplicitInstanceAnchorAllowsActualOwnedHTTPS() async throws {
    let fixture = try VerificationTLSFixture(); defer { fixture.cleanup() }
    let anchor = try WorkspaceVerificationTLSAnchor(origin: fixture.origin, certificateDER: fixture.certificate())
    let reply = try await BoundedTransport(limit: 1024, verificationTLSAnchor: anchor).run(fixture.request())
    #expect(reply.response.statusCode == 200)
    #expect(reply.data == Data("{\"ready\":true}".utf8))
    // The opt-in instance never installs platform-wide trust.
    do { _ = try await BoundedTransport(limit: 1024).run(fixture.request()); Issue.record("Verification leaked into default transport") }
    catch { #expect(error as? WorkspaceClientError == .transport) }
    _ = try WorkspaceIdentityClient(origin: fixture.origin, profileID: "apple", consentVersion: "v1", verificationTLSAnchor: anchor)
}

@Test func verificationTLSWrongAnchorAndExactHostPortCannotAuthorizeRequest() async throws {
    let fixture = try VerificationTLSFixture(); defer { fixture.cleanup() }
    let wrong = try WorkspaceVerificationTLSAnchor(origin: fixture.origin, certificateDER: fixture.certificate("wrong"))
    do { _ = try await BoundedTransport(limit: 1024, verificationTLSAnchor: wrong).run(fixture.request()); Issue.record("Wrong certificate authorized HTTPS") }
    catch { #expect(error as? WorkspaceClientError == .transport) }
    let anchor = try WorkspaceVerificationTLSAnchor(origin: fixture.origin, certificateDER: fixture.certificate())
    let port = fixture.origin.url.port!
    for address in ["https://localhost:\(port)", "https://127.0.0.1:\(port == 65535 ? port - 1 : port + 1)"] {
        let other = try WorkspaceOrigin(address)
        #expect(throws: (any Error).self) {
            try WorkspaceIdentityClient(origin: other, profileID: "apple", consentVersion: "v1", verificationTLSAnchor: anchor)
        }
        do { _ = try await BoundedTransport(limit: 1024, verificationTLSAnchor: anchor).run(URLRequest(url: other.url)); Issue.record("Different host or port authorized") }
        catch { #expect(error as? WorkspaceClientError == .transport) }
    }
}

@Test func verificationTLSAnchorRejectsMalformedOversizedAndNonloopbackPolicy() throws {
    let loopback = try WorkspaceOrigin("https://127.0.0.1:443")
    for bytes in [Data(), Data([1, 2, 3]), Data(repeating: 0, count: 65537)] {
        #expect(throws: (any Error).self) { try WorkspaceVerificationTLSAnchor(origin: loopback, certificateDER: bytes) }
    }
    let fixture = try VerificationTLSFixture(); defer { fixture.cleanup() }
    for address in ["https://workspace.example:443", "https://127.0.0.1"] {
        #expect(throws: (any Error).self) { try WorkspaceVerificationTLSAnchor(origin: WorkspaceOrigin(address), certificateDER: fixture.certificate()) }
    }
    #expect(throws: (any Error).self) {
        try WorkspaceVerificationTLSAnchor(origin: WorkspaceOrigin.loopbackForTesting("http://127.0.0.1:443"), certificateDER: fixture.certificate())
    }
}

@Test func verificationTLSAnchorPreservesRedirectResponseAndCredentialBounds() async throws {
    let fixture = try VerificationTLSFixture(); defer { fixture.cleanup() }
    let anchor = try WorkspaceVerificationTLSAnchor(origin: fixture.origin, certificateDER: fixture.certificate())
    for (path, expected) in [("/redirect", WorkspaceClientError.redirectDenied), ("/oversized", .oversized), ("/credential", .transport)] {
        do { _ = try await BoundedTransport(limit: 1024, verificationTLSAnchor: anchor).run(fixture.request(path)); Issue.record("Bounded TLS transport accepted forbidden response") }
        catch { #expect(error as? WorkspaceClientError == expected) }
    }
}

@Test func verificationTLSIdentityStillRejectsMalformedWireMetadata() async throws {
    let fixture = try VerificationTLSFixture(); defer { fixture.cleanup() }
    let anchor = try WorkspaceVerificationTLSAnchor(origin: fixture.origin, certificateDER: fixture.certificate())
    let credential = try WorkspaceCredential(origin: fixture.origin, accountID: UUID(), token: String(repeating: "A", count: 43), profileID: "apple")
    let client = try WorkspaceIdentityClient(origin: fixture.origin, profileID: "apple", consentVersion: "v1", credential: credential, verificationTLSAnchor: anchor)
    // Owned HTTPS returns readiness JSON, never a signed identity/session assertion.
    do { _ = try await client.currentSession(); Issue.record("TLS trust bypassed session wire validation") }
    catch { #expect(error as? WorkspaceClientError == .invalidResponse) }
}
