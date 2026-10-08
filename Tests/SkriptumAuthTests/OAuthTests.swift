import Foundation
import Testing
@testable import SkriptumAuth

@Test func pkceRFC7636Vector() {
    #expect(OAuthAttempt.challenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk") == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
}
@Test func callbackSecurity() throws {
    let attempt = try OAuthAttempt(port: 1455, hostID: "urn:uuid:test")
    let base = attempt.redirectURI.absoluteString
    #expect(throws: AuthError.self) { try attempt.parseCallback(URL(string: base + "?code=x&state=wrong&client_id=oaiapp_x")!) }
    #expect(throws: AuthError.self) { try attempt.parseCallback(URL(string: base + "?code=x&state=\(attempt.state)&state=\(attempt.state)&client_id=oaiapp_x")!) }
    #expect(throws: AuthError.self) { try attempt.parseCallback(URL(string: base + "?code=x&state=\(attempt.state)")!) }
    #expect(throws: AuthError.self) { try attempt.parseCallback(URL(string: "http://localhost:1455/auth/callback?code=x&state=\(attempt.state)&client_id=oaiapp_x")!) }
    let result = try attempt.parseCallback(URL(string: base + "?code=x&state=\(attempt.state)&client_id=oaiapp_x")!)
    #expect(result.clientID == "oaiapp_x")
}
@Test func returningClientCannotChange() throws {
    let attempt = try OAuthAttempt(port: 1455, hostID: "host", returningClientID: "oaiapp_selected")
    #expect(throws: AuthError.self) { try attempt.parseCallback(URL(string: attempt.redirectURI.absoluteString + "?code=x&state=\(attempt.state)&client_id=oaiapp_other")!) }
}
@Test func rejectsIncompletePermissions() throws {
    let json = Data(#"{"access_token":"access","refresh_token":"refresh","id_token":"id","token_type":"Bearer","expires_in":3600,"scope":"openid"}"#.utf8)
    let token = try JSONDecoder().decode(TokenResponse.self, from: json)
    #expect(throws: AuthError.self) { try token.validate(requireIDToken: true) }
}
@Test func unverifiedJWTNeverAccepted() {
    #expect(throws: AuthError.self) { try OIDCVerifier.verify(token: "eyJhbGciOiJub25lIn0.e30.", jwks: Data(#"{"keys":[]}"#.utf8), clientID: "oaiapp_x", nonce: "x") }
}

@Test func signedJWTClaimsAndTampering() throws {
    let now = Date(timeIntervalSince1970: 1800000000)
    let jwks = Data(#"{"keys": [{"kid": "fixture", "kty": "RSA", "alg": "RS256", "use": "sig", "n": "tKTYHs-wWggVjXBW-t4F8R6mnpH-HC4GVSQZy3Qga3oCLq4Fev-k4Njbdtnlx-2Jhar4kiQDIFIqpcOq3_-77eh55rIB8tlzI99eAU0KH0y0jOb1nXTbYsKZYVmTYnAk93iGYMu29LaNfkniTdMI7FGaMnrHYWbOr6U73jZNQ0DF9sDUGOM7Y5bL9jR9g6ehuWnS-4JxsmRJe-spG04LorxsXO70mYCikKp9GKoQuFPJLlh2gwvXCFNj6VKVR3AmG9v6Jb7ego44W9LUTg9Ozad5GzGZdOMTqCqZjqcOJnSr6Y5VuBnDHB5pYCspC61RS6_LKZ4bj3Vs3iCXD_QlBQ", "e": "AQAB"}]}"#.utf8)
    let tokens = ["eyJhbGciOiJSUzI1NiIsImtpZCI6ImZpeHR1cmUifQ.eyJpc3MiOiAiaHR0cHM6Ly9hdXRoLm9wZW5haS5jb20iLCAic3ViIjogInZlcmlmaWVkLXN1YiIsICJhdWQiOiAib2FpYXBwX2ZpeHR1cmUiLCAiZXhwIjogMTgwMDAwMDYwMCwgImlhdCI6IDE4MDAwMDAwMDAsICJub25jZSI6ICJub25jZSJ9.GadWcTF_GFP6zY9ComgcJwBWH7iZkgEzZwwwduB26jNXVgUnXeDuuMUS-h1qZ_ABTraq8ezdacfp7q0gH_j3QuzCoPOzzpHgwqmtqRyeN_xyurnT8JMn386pUVR1s8ol_BGmjXpOrN-FcIiVEfLNTviQ4kZd_4p0gMRfnK5zQs_QT0MufUS6eRywU4okNd7OaKatmJVgOfbHI_6qNehOsgKeGHVcJyoEj4syIzunnOfEpzdV_iXcfbbhQtwtsXTcwadssiLGUR7ae29L_LlRQaje6rw_c_GszGkYNGb-epk2EG7vFh3mMFUu_8lOla6ZiD8U5ODcsUZErQV2AXs-tQ", "eyJhbGciOiJSUzI1NiIsImtpZCI6ImZpeHR1cmUifQ.eyJpc3MiOiAiaHR0cHM6Ly9ldmlsLmV4YW1wbGUiLCAic3ViIjogInZlcmlmaWVkLXN1YiIsICJhdWQiOiAib2FpYXBwX2ZpeHR1cmUiLCAiZXhwIjogMTgwMDAwMDYwMCwgImlhdCI6IDE4MDAwMDAwMDAsICJub25jZSI6ICJub25jZSJ9.kmI2EuCFTH4X11pWDUMHrSBBjOm8xE5okR3viFATjAx8xS-P8awSR0Qy7mipdZ9q8XHf6K6fxNsUAwDY1Ij_6G5nno4tdhu62fnlA4kR0W3kKIO4Tw5A8BEpBsHQyUdbGeAmjLVkUahXzqXYJZScXmihvv9-DXt48ZgTUzhc3S2GGGIPwkiVPsqH3Xvng6i9im_TsOzTMRhCua643gbQ1v6HNuqTUog9MdIfXpEMvfnmoYxN-qCqXqL9bby2m8NqEQWGax8kDE9oX5XAMaWL3PpDAlRKuEca3mCddW-oT2OefkjxNC4nIObWn5kjyav04zF53b-tjvzZl4qynnp_aw", "eyJhbGciOiJSUzI1NiIsImtpZCI6ImZpeHR1cmUifQ.eyJpc3MiOiAiaHR0cHM6Ly9hdXRoLm9wZW5haS5jb20iLCAic3ViIjogInZlcmlmaWVkLXN1YiIsICJhdWQiOiAib3RoZXIiLCAiZXhwIjogMTgwMDAwMDYwMCwgImlhdCI6IDE4MDAwMDAwMDAsICJub25jZSI6ICJub25jZSJ9.Dkj3V9YUxzwgYRxD1GtJ0lIWjmA3nZIVSlYJnWGfG6NvJ2Xv2JqXzHmq_oIcl66S03ovduuvuMsAh1HQB7bvQzugaJM6ZHBg6Cul1H2libS1f1GKuEFTM-0iCf3tKrMjA75wwmU33YLJr5U20gB4hmTfBPQCqvCdJxfMfFBzC8r-U8V2WwnHZiYV-6suUz6plG6bm02wDwlPdDdG5odqnSzONIbVu6KCj59vScB8HCi5DNagFwTTfry59cqqwuht1LWAnYJrBAxbh0-1AkvOOEfBIpU_3jOV61qI6ls7Q-kEjLIRSRe_NoqzFSa5om-oZ5wKntjUm4C6JOTkHiH9-Q", "eyJhbGciOiJSUzI1NiIsImtpZCI6ImZpeHR1cmUifQ.eyJpc3MiOiAiaHR0cHM6Ly9hdXRoLm9wZW5haS5jb20iLCAic3ViIjogInZlcmlmaWVkLXN1YiIsICJhdWQiOiAib2FpYXBwX2ZpeHR1cmUiLCAiZXhwIjogMCwgImlhdCI6IDE4MDAwMDAwMDAsICJub25jZSI6ICJub25jZSJ9.NlyGAX9Zkze8yUGKS0XOjxhK996AiH7LdslNJ91EvfZMzD6GP75K8ESE7vPuHiuZ44LZrWH74BQXIc-qJb1SWOYuyojBuuEJ3jhx1WpepwrToP1WLlNoUdYfo0MwqX6e-oBn-Z4f_-ZKsB4Yw8yOm9zDVJ9eCnY7IcptTUw936x-KAA-AEN4oVmQA8A2Of14Fb-kvbRzbip9ufWu5LAKUQKBFd6mrzsAJFsiDHfX7qhRVjJuWQa9KZCgzo-o206D-SCxDUTbYGDFm21vwtlP5su6bj2n7UApN4cJzmjsKooQYu8AcOIjv-VqHGucI8JTM8IrDSHZfEBPfT3fTcHzwg", "eyJhbGciOiJSUzI1NiIsImtpZCI6ImZpeHR1cmUifQ.eyJpc3MiOiAiaHR0cHM6Ly9hdXRoLm9wZW5haS5jb20iLCAic3ViIjogInZlcmlmaWVkLXN1YiIsICJhdWQiOiAib2FpYXBwX2ZpeHR1cmUiLCAiZXhwIjogMTgwMDAwMDYwMCwgImlhdCI6IDE4MDAwMDAwMDAsICJub25jZSI6ICJvdGhlciJ9.QtITbiqQWNgw4DxalTII8JKQAaNHDWQjuDOUcdW_MTvsVuvagYDgoirqlwpOJxBEfCfGq8ZIA7fbImRWoYgKIBrLTe9tdutkyRXBUteFLAh1A3ugDik9vw3mc3FZjZSuO7kG0Tqc63O57ykdCMI1z-e5FohaLVMiEjudpcm0y2KG2s1qWyFlcR2R2KSdz3e5FC4UPMRXjvBFU2mFbEBo3PgeCn9x4hk9k8AT8SkV-oPnB2lC9qHdcyYCpwofop9MSDCxVLTb3OsjtDGWtyypwIbMYY11LleTQYKx8ZnRP0L2XxgpZTzY9YrsjT-7ds6bda2FXIW9IIfcv3Db9XSj4Q"]
    #expect(try OIDCVerifier.verify(token: tokens[0], jwks: jwks, clientID: "oaiapp_fixture", nonce: "nonce", now: now).subject == "verified-sub")
    for bad in tokens.dropFirst() {
        #expect(throws: AuthError.self) { try OIDCVerifier.verify(token: bad, jwks: jwks, clientID: "oaiapp_fixture", nonce: "nonce", now: now) }
    }
    let parts = tokens[0].split(separator: ".")
    let tampered = String(parts[0]) + "." + Data(#"{"sub":"attacker"}"#.utf8).base64URL + "." + parts[2]
    #expect(throws: AuthError.self) { try OIDCVerifier.verify(token: tampered, jwks: jwks, clientID: "oaiapp_fixture", nonce: "nonce", now: now) }
}

private final class IncompleteTokenProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let data = Data(#"{"access_token":"access","refresh_token":"refresh","id_token":"id","token_type":"Bearer","expires_in":3600,"scope":"openid"}"#.utf8)
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type":"application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
@Test func mockedExchangeCannotEnablePlanWithoutGrantedScopes() async throws {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [IncompleteTokenProtocol.self]
    let credentials = ChatGPTCredentials(store: MemoryCredentials(), session: URLSession(configuration: config))
    let attempt = try OAuthAttempt(port: 1455, hostID: "fixture")
    let callback = URL(string: attempt.redirectURI.absoluteString + "?code=fixture&state=\(attempt.state)&client_id=oaiapp_fixture")!
    do { _ = try await credentials.complete(callback, attempt: attempt); Issue.record("Missing scopes must fail") }
    catch { #expect(error as? AuthError == .missingPermission) }
    #expect(await credentials.account() == nil)
    await #expect(throws: AuthError.self) { try await credentials.complete(callback, attempt: attempt) }
}
@Test func formExchangePreservesOriginalRedirectAndPKCE() throws {
    let attempt = try OAuthAttempt(port: 54321, hostID: "fixture")
    let callback = try attempt.parseCallback(URL(string: attempt.redirectURI.absoluteString + "?code=a%2Bb&state=\(attempt.state)&client_id=oaiapp_fixture")!)
    let request = attempt.exchangeRequest(callback)
    let body = String(data: request.httpBody!, encoding: .utf8)!
    #expect(body.contains("code=a%2Bb"))
    #expect(body.contains("redirect_uri=http%3A%2F%2F127.0.0.1%3A54321%2Fauth%2Fcallback"))
    #expect(body.contains("code_verifier=" + attempt.verifier))
    #expect(!body.contains("client_secret"))
}

private final class MemoryCredentials: CredentialStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]
    func read(_ key: String) throws -> Data? { lock.withLock { values[key] } }
    func write(_ data: Data, key: String) throws { lock.withLock { values[key] = data } }
    func remove(_ key: String) throws { _ = lock.withLock { values.removeValue(forKey: key) } }
}
private class DelayedTokenProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    var refreshResponse: Bool { false }
    override func startLoading() {
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.15) { [self] in
            let isRefresh = refreshResponse
            let payload = isRefresh
                ? #"{"access_token":"renewed","refresh_token":"rotated","token_type":"Bearer","expires_in":3600,"scope":"openid offline_access resource.invoke chatgpt.tokens.use.direct"}"#
                : #"{"access_token":"access","refresh_token":"refresh","id_token":"unverified","token_type":"Bearer","expires_in":3600,"scope":"openid offline_access resource.invoke chatgpt.tokens.use.direct"}"#
            let data = Data(payload.utf8)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() {}
}
private final class DelayedRefreshProtocol: DelayedTokenProtocol, @unchecked Sendable {
    override var refreshResponse: Bool { true }
}
@Test func signoutInvalidatesOutstandingCodeExchange() async throws {
    let store = MemoryCredentials()
    let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [DelayedTokenProtocol.self]
    let credentials = ChatGPTCredentials(store: store, session: URLSession(configuration: config))
    let attempt = try OAuthAttempt(port: 1455, hostID: "fixture")
    let callback = URL(string: attempt.redirectURI.absoluteString + "?code=fixture&state=\(attempt.state)&client_id=oaiapp_fixture")!
    let pending = Task { try await credentials.complete(callback, attempt: attempt) }
    try await Task.sleep(for: .milliseconds(30))
    try await credentials.signOut()
    do { _ = try await pending.value; Issue.record("Cancelled exchange must not save") }
    catch { #expect(error as? AuthError == .cancelled) }
    #expect(await credentials.account() == nil)
    #expect(try store.read("active") == nil)
}
@Test func signoutInvalidatesOutstandingRefresh() async throws {
    let store = MemoryCredentials()
    let old = CredentialRecord(clientID: "oaiapp_fixture", identity: VerifiedIdentity(issuer: "https://auth.openai.com", subject: "fixture", email: nil), hostID: "host", idToken: "old", accessToken: "expired", refreshToken: "refresh", scopes: ["resource.invoke", "chatgpt.tokens.use.direct"], expiresAt: Date(timeIntervalSince1970: 0), earliestRefreshAt: nil)
    try store.write(JSONEncoder().encode(old), key: "active")
    let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [DelayedRefreshProtocol.self]
    let credentials = ChatGPTCredentials(store: store, session: URLSession(configuration: config))
    _ = try await credentials.restore()
    let pending = Task { try await credentials.authorizedRequest(url: URL(string: "https://api.openai.com/v1/models")!) }
    try await Task.sleep(for: .milliseconds(30))
    try await credentials.signOut()
    await #expect(throws: (any Error).self) { _ = try await pending.value }
    #expect(await credentials.account() == nil)
    #expect(try store.read("active") == nil)
}

@Test func productionSessionCannotRedirectOrPersistCredentials() async throws {
    let session = ChatGPTCredentials.protectedSession()
    defer { session.invalidateAndCancel() }
    #expect(session.configuration.urlCache == nil)
    #expect(session.configuration.httpCookieStorage == nil)
    #expect(session.configuration.urlCredentialStorage == nil)
    #expect(!session.configuration.httpShouldSetCookies)
    let delegate = try #require(session.delegate as? NoRedirectDelegate)
    let original = URL(string: "https://auth.openai.com/api/accounts/oauth/token")!
    let task = session.dataTask(with: original)
    let redirected = URLRequest(url: URL(string: "https://other.example/collect")!)
    let response = HTTPURLResponse(url: original, statusCode: 307, httpVersion: nil, headerFields: ["Location": redirected.url!.absoluteString])!
    delegate.urlSession(session, task: task, willPerformHTTPRedirection: response, newRequest: redirected) { request in
        #expect(request == nil)
    }
}

private func seededStore(expired: Bool) throws -> MemoryCredentials {
    let store = MemoryCredentials()
    let old = CredentialRecord(clientID: "oaiapp_fixture", identity: VerifiedIdentity(issuer: "https://auth.openai.com", subject: "fixture", email: nil), hostID: "host", idToken: "old", accessToken: "access", refreshToken: "refresh", scopes: ["resource.invoke", "chatgpt.tokens.use.direct"], expiresAt: expired ? Date(timeIntervalSince1970: 0) : Date().addingTimeInterval(600), earliestRefreshAt: nil)
    try store.write(JSONEncoder().encode(old), key: "active")
    return store
}
@Test func anotherActorLogoutInvalidatesRestoredCredentials() async throws {
    let store = try seededStore(expired: false)
    let first = ChatGPTCredentials(store: store)
    let second = ChatGPTCredentials(store: store)
    _ = try await first.restore(); _ = try await second.restore()
    _ = try await second.authorizedRequest(url: URL(string: "https://api.openai.com/v1/models")!)
    try await first.signOut()
    await #expect(throws: AuthError.self) { _ = try await second.authorizedRequest(url: URL(string: "https://api.openai.com/v1/models")!) }
    #expect(try store.read("active") == nil)
}
@Test func anotherActorLogoutPreventsRefreshResurrection() async throws {
    let store = try seededStore(expired: true)
    let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [DelayedRefreshProtocol.self]
    let first = ChatGPTCredentials(store: store)
    let second = ChatGPTCredentials(store: store, session: URLSession(configuration: config))
    _ = try await first.restore(); _ = try await second.restore()
    let pending = Task { try await second.authorizedRequest(url: URL(string: "https://api.openai.com/v1/models")!) }
    try await Task.sleep(for: .milliseconds(30))
    try await first.signOut()
    await #expect(throws: AuthError.self) { _ = try await pending.value }
    #expect(try store.read("active") == nil)
    await #expect(throws: AuthError.self) { _ = try await second.authorizedRequest(url: URL(string: "https://api.openai.com/v1/models")!) }
}
@Test func sameClientNewActivationInvalidatesOldActor() async throws {
    let store = try seededStore(expired: false)
    let first = ChatGPTCredentials(store: store)
    _ = try await first.restore()
    var replacement = try JSONDecoder().decode(CredentialRecord.self, from: #require(try store.read("active")))
    replacement.activationID = UUID().uuidString
    try CredentialTransactions.perform {
        try store.write(JSONEncoder().encode(replacement), key: "active")
        try store.write(Data(replacement.activationID!.utf8), key: "generation")
    }
    await #expect(throws: AuthError.self) { _ = try await first.authorizedRequest(url: URL(string: "https://api.openai.com/v1/models")!) }
    try await first.signOut()
    #expect(try store.read("active") != nil)
}

@Test func logoutWhileBrowserPendingInvalidatesAttemptAcrossActors() async throws {
    let store = try seededStore(expired: false)
    let first = ChatGPTCredentials(store: store)
    let second = ChatGPTCredentials(store: store)
    _ = try await first.restore(); _ = try await second.restore()
    let attempt = try await second.makeAttempt(port: 1455)
    try await first.signOut()
    let callback = URL(string: attempt.redirectURI.absoluteString + "?code=fixture&state=\(attempt.state)")!
    await #expect(throws: AuthError.self) { _ = try await second.complete(callback, attempt: attempt) }
    #expect(try store.read("active") == nil)
}

@Test func successfulRefreshRotatesAndOtherActorReadsRenewedCredential() async throws {
    let store = try seededStore(expired: true)
    let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [DelayedRefreshProtocol.self]
    let first = ChatGPTCredentials(store: store, session: URLSession(configuration: config))
    _ = try await first.restore()
    let request = try await first.authorizedRequest(url: URL(string: "https://api.openai.com/v1/models")!)
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer renewed")
    let active = try JSONDecoder().decode(CredentialRecord.self, from: #require(try store.read("active")))
    #expect(active.refreshToken == "rotated")
    let second = ChatGPTCredentials(store: store)
    _ = try await second.restore()
    let secondRequest = try await second.authorizedRequest(url: URL(string: "https://api.openai.com/v1/models")!)
    #expect(secondRequest.value(forHTTPHeaderField: "Authorization") == "Bearer renewed")
}
