import Foundation
import Security

public nonisolated struct ChatGPTAccount: Sendable, Equatable {
    public let clientID: String
    public let identity: VerifiedIdentity
}
nonisolated struct CredentialRecord: Codable, Sendable {
    let clientID: String
    let identity: VerifiedIdentity
    let hostID: String
    var idToken: String
    var accessToken: String
    var refreshToken: String
    var scopes: Set<String>
    var expiresAt: Date
    var earliestRefreshAt: Date?
    var activationID: String? = nil
}
public nonisolated protocol CredentialStorage: Sendable {
    func read(_ key: String) throws -> Data?
    func write(_ data: Data, key: String) throws
    func remove(_ key: String) throws
}

public nonisolated struct KeychainStore: CredentialStorage {
    private let service: String
    public init(service: String = "org.skriptum.chatgpt") { self.service = service }
    public func read(_ key: String) throws -> Data? {
        let query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: key, kSecReturnData: true, kSecMatchLimit: kSecMatchLimitOne]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw AuthError.keychain(status) }
        return result as? Data
    }
    public func write(_ data: Data, key: String) throws {
        let query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: key]
        var attrs: [CFString: Any] = [kSecValueData: data, kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        if status == errSecItemNotFound {
            attrs.merge(query) { current, _ in current }
            let added = SecItemAdd(attrs as CFDictionary, nil)
            guard added == errSecSuccess else { throw AuthError.keychain(added) }
        } else if status != errSecSuccess { throw AuthError.keychain(status) }
    }
    public func remove(_ key: String) throws {
        let status = SecItemDelete([kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: key] as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw AuthError.keychain(status) }
    }
}

/// Owns tokens privately; only authenticated public API requests leave this actor.
nonisolated final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

/// Serializes local credential transactions across actor instances. Never held across an await.
/// This is process-local; another executable sharing these Keychain items needs a separate IPC authority.
nonisolated enum CredentialTransactions {
    static let lock = NSLock()
    static func perform<T>(_ operation: () throws -> T) rethrows -> T {
        try lock.withLock(operation)
    }
}

public actor ChatGPTCredentials {
    private let store: any CredentialStorage
    private let session: URLSession
    private var record: CredentialRecord?
    private var refreshTask: Task<CredentialRecord, Error>?
    private var consumedStates: Set<String> = []
    private var pendingGenerations: [String: (UInt64, String)] = [:]
    private var epoch: UInt64 = 0
    static func protectedSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.urlCredentialStorage = nil
        return URLSession(configuration: config, delegate: NoRedirectDelegate(), delegateQueue: nil)
    }
    public init(store: any CredentialStorage = KeychainStore(), session: URLSession? = nil) { self.store = store; self.session = session ?? Self.protectedSession() }
    public func hostID() throws -> String {
        try CredentialTransactions.perform {
            if let data = try store.read("host"), let id = String(data: data, encoding: .utf8) { return id }
            let id = "urn:uuid:" + UUID().uuidString.lowercased()
            try store.write(Data(id.utf8), key: "host"); return id
        }
    }
    private func durableGeneration() throws -> String {
        if let data = try store.read("generation"), let value = String(data: data, encoding: .utf8) { return value }
        let value = UUID().uuidString
        try store.write(Data(value.utf8), key: "generation")
        return value
    }
    private func activeRecord() throws -> CredentialRecord? {
        try store.read("active").map { try JSONDecoder().decode(CredentialRecord.self, from: $0) }
    }
    private func validatedActiveUnlocked(_ expected: CredentialRecord) throws -> CredentialRecord {
        guard let id = expected.activationID, try durableGeneration() == id,
              let active = try activeRecord(), active.activationID == id,
              active.clientID == expected.clientID, active.identity.subject == expected.identity.subject else { throw AuthError.noAccount }
        return active
    }
    private func validatedActive(_ expected: CredentialRecord) throws -> CredentialRecord {
        try CredentialTransactions.perform { try validatedActiveUnlocked(expected) }
    }
    public func restore() throws -> ChatGPTAccount? {
        epoch &+= 1; refreshTask?.cancel(); refreshTask = nil; record = nil
        record = try CredentialTransactions.perform {
            guard var active = try activeRecord() else { _ = try durableGeneration(); return nil }
            let generation = try durableGeneration()
            if active.activationID == nil {
                active.activationID = generation
                try store.write(JSONEncoder().encode(active), key: "active")
            }
            guard active.activationID == generation else { throw AuthError.noAccount }
            return active
        }
        return account()
    }
    public func account() -> ChatGPTAccount? { record.map { ChatGPTAccount(clientID: $0.clientID, identity: $0.identity) } }
    public func makeAttempt(port: UInt16, addAccount: Bool = false) throws -> OAuthAttempt {
        if let record { _ = try validatedActive(record) }
        let attempt = try OAuthAttempt(port: port, hostID: hostID(), returningClientID: addAccount ? nil : record?.clientID)
        let generation = try CredentialTransactions.perform { try durableGeneration() }
        pendingGenerations[attempt.state] = (epoch, generation)
        return attempt
    }
    public func authorizationURL(for attempt: OAuthAttempt) -> URL {
        attempt.authorizationURL(idTokenHint: attempt.returningClientID == record?.clientID ? record?.idToken : nil,
                                 loginHint: attempt.returningClientID == record?.clientID ? record?.identity.email : nil)
    }
    public func complete(_ url: URL, attempt: OAuthAttempt) async throws -> ChatGPTAccount {
        let startingEpoch = epoch
        if let record { _ = try validatedActive(record) }
        let currentGeneration = try CredentialTransactions.perform { try durableGeneration() }
        let binding = pendingGenerations.removeValue(forKey: attempt.state)
        if let binding, binding.0 != epoch || binding.1 != currentGeneration { throw AuthError.cancelled }
        let startingGeneration = binding?.1 ?? currentGeneration
        guard !consumedStates.contains(attempt.state) else { throw AuthError.expiredAttempt }
        let callback = try attempt.parseCallback(url)
        consumedStates.insert(attempt.state)
        let tokens = try await requestTokens(attempt.exchangeRequest(callback), requireIDToken: true)
        try Task.checkCancellation()
        guard epoch == startingEpoch else { throw AuthError.cancelled }
        guard try CredentialTransactions.perform({ try durableGeneration() }) == startingGeneration else { throw AuthError.cancelled }
        let keys = try await fetchJWKS()
        let identity = try OIDCVerifier.verify(token: tokens.id_token!, jwks: keys, clientID: callback.clientID, nonce: attempt.nonce)
        if attempt.returningClientID != nil, identity.issuer != record?.identity.issuer || identity.subject != record?.identity.subject { throw AuthError.invalidIdentity }
        var next = CredentialRecord(clientID: callback.clientID, identity: identity, hostID: attempt.hostID, idToken: tokens.id_token!, accessToken: tokens.access_token, refreshToken: tokens.refresh_token, scopes: tokens.scopes, expiresAt: Date().addingTimeInterval(tokens.expires_in), earliestRefreshAt: tokens.earliest_refresh_at.map { Date(timeIntervalSince1970: $0) })
        try Task.checkCancellation()
        guard epoch == startingEpoch else { throw AuthError.cancelled }
        epoch &+= 1; refreshTask?.cancel(); refreshTask = nil
        next.activationID = UUID().uuidString
        try save(next, expectedGeneration: startingGeneration, expectedRefreshToken: nil); return ChatGPTAccount(clientID: next.clientID, identity: identity)
    }
    public func signOut() throws {
        epoch &+= 1
        refreshTask?.cancel(); refreshTask = nil
        let old = record; record = nil
        try CredentialTransactions.perform {
            let generation = try durableGeneration()
            // A stale window must not sign out a newer activation, even for the same client/account.
            if let old, old.activationID != generation { return }
            try store.write(Data(UUID().uuidString.utf8), key: "generation")
            try store.remove("active")
            if let clientID = old?.clientID { try store.remove("registration." + clientID) }
        }
    }
    public func authorizedRequest(url: URL) async throws -> URLRequest {
        guard url.scheme == "https", url.host == "api.openai.com", url.port == nil, url.user == nil, url.password == nil,
              ["/v1/models", "/v1/responses"].contains(url.path) else { throw AuthError.missingPermission }
        guard let cached = record else { throw AuthError.noAccount }
        var current = try validatedActive(cached)
        record = current
        if current.expiresAt.timeIntervalSinceNow < 60 { current = try await refreshed() }
        return try CredentialTransactions.perform {
            let active = try validatedActiveUnlocked(current)
            guard active.scopes.isSuperset(of: ["resource.invoke", "chatgpt.tokens.use.direct"]) else { throw AuthError.missingPermission }
            var request = URLRequest(url: url)
            request.setValue("Bearer " + active.accessToken, forHTTPHeaderField: "Authorization")
            return request
        }
    }
    private func save(_ next: CredentialRecord, expectedGeneration: String, expectedRefreshToken: String?) throws {
        try CredentialTransactions.perform {
            try Task.checkCancellation()
            guard try durableGeneration() == expectedGeneration else { throw AuthError.noAccount }
            if let expectedRefreshToken {
                guard let active = try activeRecord(), active.activationID == expectedGeneration,
                      active.refreshToken == expectedRefreshToken else { throw AuthError.noAccount }
            }
            let encoded = try JSONEncoder().encode(next)
            try store.write(encoded, key: "registration." + next.clientID)
            try store.write(encoded, key: "active")
            try store.write(Data((next.activationID ?? expectedGeneration).utf8), key: "generation")
            record = next
        }
    }
    private func refreshed() async throws -> CredentialRecord {
        if let refreshTask {
            let startingEpoch = epoch
            let clientID = record?.clientID
            let previousRefreshToken = record?.refreshToken
            let result = try await refreshTask.value
            try Task.checkCancellation()
            guard epoch == startingEpoch, record?.clientID == clientID, clientID != nil else { throw AuthError.noAccount }
            let active = try validatedActive(result)
            if active.refreshToken != result.refreshToken {
                guard let previousRefreshToken, active.refreshToken == previousRefreshToken, let activationID = result.activationID else { throw AuthError.noAccount }
                try save(result, expectedGeneration: activationID, expectedRefreshToken: previousRefreshToken)
            }
            return result
        }
        let startingEpoch = epoch
        guard let cached = record else { throw AuthError.noAccount }
        let old = try validatedActive(cached)
        guard let activationID = old.activationID else { throw AuthError.noAccount }
        if let earliest = old.earliestRefreshAt, earliest > Date() { throw AuthError.refreshTooEarly }
        let task = Task { [self] in
            let tokens = try await requestTokens(tokenRequest(["grant_type": "refresh_token", "client_id": old.clientID, "refresh_token": old.refreshToken, "resource": OAuthAttempt.resource]), requireIDToken: false)
            try Task.checkCancellation()
            guard epoch == startingEpoch else { throw AuthError.cancelled }
            _ = try validatedActive(old)
            var next = old
            if let id = tokens.id_token {
                let identity = try OIDCVerifier.verify(token: id, jwks: await fetchJWKS(), clientID: old.clientID, nonce: nil)
                guard identity.issuer == old.identity.issuer, identity.subject == old.identity.subject else { throw AuthError.invalidIdentity }
                next.idToken = id
            }
            next.accessToken = tokens.access_token; next.refreshToken = tokens.refresh_token; next.scopes = tokens.scopes
            next.expiresAt = Date().addingTimeInterval(tokens.expires_in)
            next.earliestRefreshAt = tokens.earliest_refresh_at.map { Date(timeIntervalSince1970: $0) }
            return next
        }
        refreshTask = task
        defer { if epoch == startingEpoch { refreshTask = nil } }
        let next = try await task.value
        try Task.checkCancellation()
        guard epoch == startingEpoch, record?.clientID == old.clientID, record?.identity.subject == old.identity.subject else { throw AuthError.noAccount }
        try Task.checkCancellation()
        try save(next, expectedGeneration: activationID, expectedRefreshToken: old.refreshToken); return next
    }
    private func requestTokens(_ request: URLRequest, requireIDToken: Bool) async throws -> TokenResponse {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw AuthError.transport((response as? HTTPURLResponse)?.statusCode ?? 0) }
        let tokens: TokenResponse
        do { tokens = try JSONDecoder().decode(TokenResponse.self, from: data) } catch { throw AuthError.invalidToken }
        try tokens.validate(requireIDToken: requireIDToken); return tokens
    }
    private func fetchJWKS() async throws -> Data {
        let (data, response) = try await session.data(from: URL(string: "https://auth.openai.com/.well-known/jwks.json")!)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw AuthError.invalidSignature }
        return data
    }
}
