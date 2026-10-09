import Foundation

public enum WorkspaceClientError: Error, Equatable, Sendable {
    case invalidConfiguration, invalidCredential, originMismatch, invalidEnvelope, invalidRequest
    case signedOut, unauthenticated, notFound, conflict, oversized, unavailable, invalidResponse, redirectDenied, cancelled, transport
    case httpStatus(Int)
}
public struct WorkspaceOrigin: Equatable, Hashable, Sendable {
    public let url: URL
    public init(_ value: String) throws { self = try Self.parse(value, allowLoopback: false) }
    public static func loopbackForTesting(_ value: String) throws -> Self { try parse(value, allowLoopback: true) }
    private init(url: URL) { self.url = url }
    private static func parse(_ value: String, allowLoopback: Bool) throws -> Self {
        guard !value.contains("%"), !value.contains("\\"), !value.contains(where: { $0.isWhitespace }),
              let c = URLComponents(string: value), let host = c.host, !host.isEmpty,
              c.user == nil, c.password == nil, c.query == nil, c.fragment == nil,
              c.path.isEmpty || c.path == "/", c.port.map({ (1...65535).contains($0) }) ?? true,
              c.scheme == "https" || (allowLoopback && c.scheme == "http" && ["127.0.0.1", "[::1]", "localhost"].contains(host)),
              let url = c.url else { throw WorkspaceClientError.invalidConfiguration }
        var canonical = c; canonical.path = ""; canonical.host = host.lowercased()
        if (canonical.scheme == "https" && canonical.port == 443) || (canonical.scheme == "http" && canonical.port == 80) { canonical.port = nil }
        guard let normalized = canonical.url, url.host != nil else { throw WorkspaceClientError.invalidConfiguration }
        return Self(url: normalized)
    }
}
public struct WorkspaceCredential: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let origin: WorkspaceOrigin
    public let accountID: UUID
    let token: String
    public init(origin: WorkspaceOrigin, accountID: UUID, token: String) throws {
        guard (43...128).contains(token.utf8.count), token.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95 }) else { throw WorkspaceClientError.invalidCredential }
        self.origin = origin; self.accountID = accountID; self.token = token
    }
    public var description: String { "WorkspaceCredential(<redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: ["credential": "<redacted>"]) }
}
/// Integration must implement an origin/account-scoped, device-only Keychain store.
public protocol WorkspaceCredentialStore: Sendable {
    func load(origin: WorkspaceOrigin, accountID: UUID) async throws -> WorkspaceCredential?
    func save(_ credential: WorkspaceCredential) async throws
    func remove(origin: WorkspaceOrigin, accountID: UUID) async throws
}
public struct WorkspaceEnvelope: Equatable, Sendable {
    public let ciphertext: Data
    public let nonce: Data
    public let digest: Data
    public let keyReference: String
    public let version: Int
    public init(ciphertext: Data, nonce: Data, digest: Data, keyReference: String, version: Int = 1) throws {
        guard (17...2_097_168).contains(ciphertext.count), nonce.count == 12, digest.count == 32,
              (1...256).contains(keyReference.utf8.count), version == 1 else { throw WorkspaceClientError.invalidEnvelope }
        self.ciphertext = ciphertext; self.nonce = nonce; self.digest = digest; self.keyReference = keyReference; self.version = version
    }
}
public struct WorkspacePageAddress: Equatable, Sendable {
    public let libraryID: UUID; public let spaceID: UUID; public let pageID: UUID
    public init(libraryID: UUID, spaceID: UUID, pageID: UUID) { self.libraryID = libraryID; self.spaceID = spaceID; self.pageID = pageID }
    var path: String { "/libraries/\(libraryID.uuidString)/spaces/\(spaceID.uuidString)/pages/\(pageID.uuidString)" }
}
public enum WorkspaceMembershipScope: Sendable {
    case library(UUID), space(library: UUID, space: UUID), page(WorkspacePageAddress)
    func path(account: UUID) -> String {
        switch self {
        case .library(let id): return "/libraries/\(id.uuidString)/memberships/\(account.uuidString)"
        case .space(let library, let space): return "/libraries/\(library.uuidString)/spaces/\(space.uuidString)/memberships/\(account.uuidString)"
        case .page(let page): return page.path + "/memberships/\(account.uuidString)"
        }
    }
}
public enum WorkspaceRole: String, Sendable { case none, viewer, editor, owner }
public struct WorkspaceEncryptedPage: Equatable, Sendable { public let revision: UUID; public let envelope: WorkspaceEnvelope }
public enum WorkspaceLogoutOutcome: Equatable, Sendable { case confirmedRemoteRevocation, remoteRevocationUnknown, alreadySignedOut }
