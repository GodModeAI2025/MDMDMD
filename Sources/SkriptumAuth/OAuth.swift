import Foundation
import CryptoKit
import Security

public nonisolated enum AuthError: Error, LocalizedError, Sendable, Equatable {
    case malformedCallback, stateMismatch, expiredAttempt, denied, registrationIncomplete, clientMismatch
    case invalidToken, missingPermission, invalidSignature, invalidIdentity, noAccount, transport(Int), keychain(Int32), refreshTooEarly
    case browserUnavailable, cancelled, listenerFailed
    public var errorDescription: String? {
        switch self {
        case .missingPermission: "ChatGPT plan usage was not authorized. Continue with ChatGPT again and review the permissions."
        case .denied, .cancelled: "ChatGPT sign-in was cancelled."
        case .noAccount: "Continue with ChatGPT to connect your account."
        case .transport(let status): "ChatGPT returned HTTP \(status). Please try again."
        case .refreshTooEarly: "ChatGPT cannot renew this session yet. Please try again later."
        default: "ChatGPT sign-in could not be securely verified. Please try again."
        }
    }
}

extension Data {
    nonisolated var base64URL: String { base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
    nonisolated init?(base64URL: String) {
        guard base64URL.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }) else { return nil }
        let s = base64URL.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        self.init(base64Encoded: s + String(repeating: "=", count: (4 - s.count % 4) % 4))
    }
}

public nonisolated struct OAuthAttempt: Sendable {
    public static let resource = "https://api.openai.com/v1"
    public static let scopes = "openid profile email offline_access resource.invoke chatgpt.tokens.use.direct"
    public let state: String
    public let nonce: String
    public let verifier: String
    public let redirectURI: URL
    public let hostID: String
    public let returningClientID: String?
    public let createdAt: Date
    public init(port: UInt16, hostID: String, returningClientID: String? = nil) throws {
        guard port != 0, !hostID.isEmpty, returningClientID != "dynamic_agent_client" else { throw AuthError.registrationIncomplete }
        state = try Self.random(); nonce = try Self.random(); verifier = try Self.random(count: 64)
        redirectURI = URL(string: "http://127.0.0.1:\(port)/auth/callback")!
        self.hostID = hostID; self.returningClientID = returningClientID; createdAt = Date()
    }
    private static func random(count: Int = 32) throws -> String {
        var bytes = [UInt8](repeating: 0, count: count)
        guard SecRandomCopyBytes(kSecRandomDefault, count, &bytes) == errSecSuccess else { throw AuthError.invalidToken }
        return Data(bytes).base64URL
    }
    public static func challenge(for verifier: String) -> String { Data(SHA256.hash(data: Data(verifier.utf8))).base64URL }
    public func authorizationURL(idTokenHint: String? = nil, loginHint: String? = nil) -> URL {
        var components = URLComponents(string: "https://auth.openai.com/api/accounts/authorize")!
        var pairs = ["client_id": returningClientID ?? "dynamic_agent_client", "ext_agent_host_id": hostID,
                     "response_type": "code", "redirect_uri": redirectURI.absoluteString, "scope": Self.scopes,
                     "resource": Self.resource, "state": state, "nonce": nonce,
                     "code_challenge_method": "S256", "code_challenge": Self.challenge(for: verifier)]
        if returningClientID == nil { pairs["agent_name_hint"] = "Scriptum" }
        else { pairs["id_token_hint"] = idTokenHint; pairs["login_hint"] = loginHint }
        components.queryItems = pairs.sorted(by: { $0.key < $1.key }).map { URLQueryItem(name: $0.key, value: $0.value) }
        return components.url!
    }
    public struct Callback: Sendable { public let code: String; public let clientID: String }
    public func parseCallback(_ url: URL, now: Date = Date()) throws -> Callback {
        guard now.timeIntervalSince(createdAt) < 600 else { throw AuthError.expiredAttempt }
        guard let c = URLComponents(url: url, resolvingAgainstBaseURL: false), c.scheme == "http", c.host == "127.0.0.1", c.port == redirectURI.port, c.path == "/auth/callback", c.user == nil, c.password == nil, c.fragment == nil else { throw AuthError.malformedCallback }
        var fields: [String: String] = [:]
        for item in c.queryItems ?? [] {
            guard fields[item.name] == nil, let value = item.value else { throw AuthError.malformedCallback }
            fields[item.name] = value
        }
        guard fields["state"] == state else { throw AuthError.stateMismatch }
        if fields["error"] != nil { throw AuthError.denied }
        guard let code = fields["code"], !code.isEmpty else { throw AuthError.malformedCallback }
        let client = fields["client_id"] ?? returningClientID
        guard let client, client.hasPrefix("oaiapp_"), client != "dynamic_agent_client" else { throw AuthError.registrationIncomplete }
        if let returningClientID, returningClientID != client { throw AuthError.clientMismatch }
        return Callback(code: code, clientID: client)
    }
    public func exchangeRequest(_ callback: Callback) -> URLRequest {
        tokenRequest(["grant_type": "authorization_code", "client_id": callback.clientID, "code": callback.code,
                      "code_verifier": verifier, "redirect_uri": redirectURI.absoluteString, "resource": Self.resource])
    }
}
nonisolated func tokenRequest(_ fields: [String: String]) -> URLRequest {
    var r = URLRequest(url: URL(string: "https://auth.openai.com/api/accounts/oauth/token")!)
    r.httpMethod = "POST"; r.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    r.setValue("application/json", forHTTPHeaderField: "Accept")
    let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
    r.httpBody = Data(fields.sorted(by: { $0.key < $1.key }).map { "\($0.key.addingPercentEncoding(withAllowedCharacters: allowed)!)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed)!)" }.joined(separator: "&").utf8)
    return r
}

nonisolated struct TokenResponse: Decodable, Sendable {
    let access_token: String
    let refresh_token: String
    let id_token: String?
    let token_type: String
    let expires_in: Double
    let scope: String
    let earliest_refresh_at: Double?
    var scopes: Set<String> { Set(scope.split(separator: " ").map(String.init)) }
    func validate(requireIDToken: Bool) throws {
        guard !access_token.isEmpty, !refresh_token.isEmpty, token_type.lowercased() == "bearer", expires_in.isFinite, expires_in > 0,
              !requireIDToken || !(id_token ?? "").isEmpty else { throw AuthError.invalidToken }
        guard scopes.isSuperset(of: ["openid", "offline_access", "resource.invoke", "chatgpt.tokens.use.direct"]) else { throw AuthError.missingPermission }
    }
}
