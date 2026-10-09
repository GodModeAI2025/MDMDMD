import Foundation
import CryptoKit
import Darwin

private struct IdentityServerFixture: Decodable {
    let origin: String; let controlOrigin: String; let controlSecret: String
    let profileID: String; let consentVersion: String
}
/// Actual production actor/client with signed test-issuer proof. No Apple UI,
/// plaintext provider grant or production authentication claim.
@main struct IdentityServerProbe {
    @MainActor static func main() async {
        do {
            guard CommandLine.arguments.count == 2 else { throw WorkspaceClientError.invalidConfiguration }
            let file = URL(fileURLWithPath: CommandLine.arguments[1])
            let fixture = try JSONDecoder().decode(IdentityServerFixture.self, from: Data(contentsOf: file))
            let count = try await run(fixture)
            print("Actual Swift/signed HTTPS issuer/HTTP/PG identity assertions: \(count) PASS")
        } catch { print("Identity server probe failed (details redacted)"); exit(1) }
    }
    @MainActor private static func run(_ fixture: IdentityServerFixture) async throws -> Int {
        let origin = try WorkspaceOrigin.loopbackForTesting(fixture.origin)
        let client = try WorkspaceIdentityClient(origin: origin, profileID: fixture.profileID, consentVersion: fixture.consentVersion)
        var checks = 0
        func require(_ condition: Bool) throws { guard condition else { throw WorkspaceClientError.invalidResponse }; checks += 1 }
        try require(await client.admissionState == .signedOut)
        let first = try await login(client, fixture: fixture, account: "owner")
        try require(first.credential.profileID == fixture.profileID)
        try require(await client.isSignedIn)
        try require(try await client.currentSession().accountID == first.session.accountID)
        let workspace = try WorkspaceClient(origin: origin, credential: first.credential)
        // Escaping this valid 4096-byte title produces a reply above the old
        // identity-only 24 KiB ceiling without changing corpus cardinality.
        let discoveryTitle = String(repeating: "\u{0001}", count: 4096)
        let library = try await workspace.createLibrary(title: discoveryTitle)
        let ownerMetadata = try await client.libraryMetadata(id: library)
        try require(ownerMetadata.libraryID == library && ownerMetadata.role == .owner)
        try require(ownerMetadata.title.utf8.elementsEqual(discoveryTitle.utf8))
        let ownerListing = try await client.listLibraries()
        try require(ownerListing.libraries == [ownerMetadata] && ownerListing.nextAfter == nil)
        let space = try await workspace.createSpace(libraryID: library, title: "Private source")
        let key = try await control(fixture, path: "/key", body: ["libraryID": library.uuidString], keys: ["keyReference"])
        guard let keyReference = key["keyReference"] as? String else { throw WorkspaceClientError.invalidResponse }
        let envelope = try WorkspaceEnvelope(ciphertext: Data(repeating: 0xa0, count: 64), nonce: Data(repeating: 0xb0, count: 12), digest: Data(SHA256.hash(data: Data(repeating: 0xa0, count: 64))), keyReference: keyReference)
        let address = WorkspacePageAddress(libraryID: library, spaceID: space, pageID: UUID())
        let revision = try await workspace.createPage(address, envelope: envelope)
        try require(try await workspace.readPage(address) == WorkspaceEncryptedPage(revision: revision, envelope: envelope))
        let second = try WorkspaceIdentityClient(origin: origin, profileID: fixture.profileID, consentVersion: fixture.consentVersion)
        let secondLogin = try await login(second, fixture: fixture, account: "owner")
        try require(secondLogin.session.accountID == first.session.accountID)
        try require(secondLogin.session.sessionID != first.session.sessionID)
        let viewerIdentity = try WorkspaceIdentityClient(origin: origin, profileID: fixture.profileID, consentVersion: fixture.consentVersion)
        let viewerLogin = try await login(viewerIdentity, fixture: fixture, account: "viewer")
        try require(viewerLogin.session.accountID != first.session.accountID)
        let viewer = try WorkspaceClient(origin: origin, credential: viewerLogin.credential)
        try require(try await viewerIdentity.listLibraries().libraries.isEmpty)
        do { _ = try await viewerIdentity.libraryMetadata(id: library); throw WorkspaceClientError.invalidResponse }
        catch WorkspaceClientError.notFound { checks += 1 }
        do { _ = try await viewer.readPage(address); throw WorkspaceClientError.invalidResponse }
        catch WorkspaceClientError.notFound { checks += 1 }
        try await workspace.setMembership(.library(library), accountID: viewerLogin.session.accountID, role: .viewer)
        let viewerMetadata = try await viewerIdentity.libraryMetadata(id: library)
        try require(viewerMetadata.role == .viewer && viewerMetadata.libraryID == library)
        try require(viewerMetadata.title.utf8.elementsEqual(discoveryTitle.utf8))
        try require(try await viewerIdentity.listLibraries().libraries == [viewerMetadata])
        try await workspace.revokeMembership(.library(library), accountID: viewerLogin.session.accountID)
        try require(try await viewerIdentity.listLibraries().libraries.isEmpty)
        do { _ = try await viewerIdentity.libraryMetadata(id: library); throw WorkspaceClientError.invalidResponse }
        catch WorkspaceClientError.notFound { checks += 1 }
        try await workspace.setMembership(.library(library), accountID: viewerLogin.session.accountID, role: .viewer)
        try require(try await viewer.readPage(address).envelope == envelope)
        do { _ = try await viewer.writePage(address, envelope: envelope, expectedRevision: revision); throw WorkspaceClientError.invalidResponse }
        catch WorkspaceClientError.notFound { checks += 1 }
        try require(await client.logoutAll() == .confirmedRemoteRevocation)
        try require(await client.admissionState == .signedOut)
        do { _ = try await client.listLibraries(); throw WorkspaceClientError.invalidResponse }
        catch WorkspaceClientError.signedOut { checks += 1 }
        do { _ = try await second.currentSession(); throw WorkspaceClientError.invalidResponse }
        catch WorkspaceClientError.unauthenticated { checks += 1 }
        try require(await second.admissionState == .signedOut)
        do { _ = try await workspace.readPage(address); throw WorkspaceClientError.invalidResponse }
        catch WorkspaceClientError.unauthenticated { checks += 1 }
        let restored = try await login(client, fixture: fixture, account: "owner")
        try require(restored.session.accountID == first.session.accountID)
        try require(await client.deleteAccount(using: restored.reauthenticationReceipt) == .confirmedAccountTombstone)
        try require(await client.admissionState == .signedOut)
        try require(try await viewer.readPage(address).envelope == envelope)
        try require(try await viewerIdentity.libraryMetadata(id: library) == viewerMetadata)
        return checks
    }
    @MainActor private static func login(_ client: WorkspaceIdentityClient, fixture: IdentityServerFixture, account: String) async throws -> WorkspaceIdentityEnrollment {
        let challenge = try await client.challenge()
        let result = try await control(fixture, path: "/authorize", body: ["nonce": challenge.nonce, "account": account], keys: ["identityToken", "authorizationCode"])
        guard let token = result["identityToken"] as? String, let code = result["authorizationCode"] as? String else { throw WorkspaceClientError.invalidResponse }
        let proof = try WorkspaceIdentityProof(identityToken: token, authorizationCode: code, state: challenge.state)
        return try await client.enroll(challenge: challenge, proof: proof)
    }
    @MainActor private static func control(_ fixture: IdentityServerFixture, path: String, body: [String: String], keys: Set<String>) async throws -> [String: Any] {
        let origin = try WorkspaceOrigin.loopbackForTesting(fixture.controlOrigin)
        guard IdentityBounds.random(fixture.controlSecret), let url = URL(string: origin.url.absoluteString + path) else { throw WorkspaceClientError.invalidConfiguration }
        var request = URLRequest(url: url); request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("Bearer " + fixture.controlSecret, forHTTPHeaderField: "authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let reply = try await BoundedTransport(limit: 24_576).run(request)
        guard reply.response.statusCode == 200, reply.response.url == url else { throw WorkspaceClientError.invalidResponse }
        return try WorkspaceWire.object(reply.data, keys: keys)
    }
}
