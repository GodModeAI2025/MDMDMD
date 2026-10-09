import Foundation

public actor WorkspaceClient {
    public let origin: WorkspaceOrigin
    public let accountID: UUID?
    private var credential: WorkspaceCredential?
    private var inFlight = 0
    public init(origin: WorkspaceOrigin, credential: WorkspaceCredential? = nil) throws {
        guard credential?.origin == origin || credential == nil else { throw WorkspaceClientError.originMismatch }
        self.origin = origin; self.credential = credential; accountID = credential?.accountID
    }
    public var isSignedIn: Bool { credential != nil }
    public func readiness() async throws -> Bool {
        let reply = try await perform("GET", path: "/ready", authenticated: false, limit: 1024, allowed: [200, 503])
        let row = try WorkspaceWire.object(reply.data, keys: ["ready"])
        let ready = try WorkspaceWire.boolean(row["ready"])
        guard (reply.response.statusCode == 200) == ready else { throw WorkspaceClientError.invalidResponse }
        return ready
    }
    public func createLibrary(title: String) async throws -> UUID {
        try validateTitle(title)
        let reply = try await perform("POST", path: "/libraries", body: JSONSerialization.data(withJSONObject: ["title": title]), allowed: [201])
        return try WorkspaceWire.uuid(WorkspaceWire.object(reply.data, keys: ["libraryID"])["libraryID"])
    }
    public func createSpace(libraryID: UUID, title: String) async throws -> UUID {
        try validateTitle(title)
        let reply = try await perform("POST", path: "/libraries/\(libraryID.uuidString)/spaces", body: JSONSerialization.data(withJSONObject: ["title": title]), allowed: [201])
        return try WorkspaceWire.uuid(WorkspaceWire.object(reply.data, keys: ["spaceID"])["spaceID"])
    }
    public func readPage(_ address: WorkspacePageAddress) async throws -> WorkspaceEncryptedPage {
        let reply = try await perform("GET", path: address.path, limit: 3 * 1024 * 1024, allowed: [200])
        let row = try WorkspaceWire.object(reply.data, keys: ["revision", "envelope"])
        let revision = try WorkspaceWire.uuid(row["revision"]); try validateETag(reply, revision)
        return WorkspaceEncryptedPage(revision: revision, envelope: try WorkspaceWire.envelope(row["envelope"]))
    }
    public func createPage(_ address: WorkspacePageAddress, envelope: WorkspaceEnvelope) async throws -> UUID {
        try await write("POST", address: address, envelope: envelope, revision: nil)
    }
    public func writePage(_ address: WorkspacePageAddress, envelope: WorkspaceEnvelope, expectedRevision: UUID) async throws -> UUID {
        try await write("PUT", address: address, envelope: envelope, revision: expectedRevision)
    }
    private func write(_ method: String, address: WorkspacePageAddress, envelope: WorkspaceEnvelope, revision: UUID?) async throws -> UUID {
        let reply = try await perform(method, path: address.path, body: WorkspaceWire.encode(envelope), ifMatch: revision, allowed: method == "POST" ? [201] : [200])
        let next = try WorkspaceWire.uuid(WorkspaceWire.object(reply.data, keys: ["revision"])["revision"])
        try validateETag(reply, next); return next
    }
    public func setMembership(_ scope: WorkspaceMembershipScope, accountID: UUID, role: WorkspaceRole) async throws {
        let reply = try await perform("PUT", path: scope.path(account: accountID), body: JSONSerialization.data(withJSONObject: ["role": role.rawValue]), allowed: [204])
        guard reply.data.isEmpty else { throw WorkspaceClientError.invalidResponse }
    }
    public func revokeMembership(_ scope: WorkspaceMembershipScope, accountID: UUID) async throws {
        let reply = try await perform("DELETE", path: scope.path(account: accountID), allowed: [204])
        guard reply.data.isEmpty else { throw WorkspaceClientError.invalidResponse }
    }
    /// Local admission is cleared before the first suspension. Remote failure
    /// never restores the credential. Caller separately removes Keychain state.
    public func logout() async -> WorkspaceLogoutOutcome {
        guard let active = credential else { return .alreadySignedOut }
        credential = nil
        do {
            let reply = try await perform("POST", path: "/session/logout", overrideCredential: active, allowed: [204])
            return reply.data.isEmpty ? .confirmedRemoteRevocation : .remoteRevocationUnknown
        } catch { return .remoteRevocationUnknown }
    }
    private func validateTitle(_ title: String) throws {
        guard (1...4096).contains(title.utf8.count) else { throw WorkspaceClientError.invalidRequest }
    }
    private func validateETag(_ reply: WorkspaceHTTPResponse, _ revision: UUID) throws {
        guard let tag = reply.response.value(forHTTPHeaderField: "etag"), tag == "\"\(revision.uuidString.lowercased())\"" || tag == "\"\(revision.uuidString)\"" else { throw WorkspaceClientError.invalidResponse }
    }
    private func perform(_ method: String, path: String, body: Data? = nil, ifMatch: UUID? = nil, authenticated: Bool = true, overrideCredential: WorkspaceCredential? = nil, limit: Int = 65_536, allowed: Set<Int>) async throws -> WorkspaceHTTPResponse {
        let active = overrideCredential ?? credential
        guard !authenticated || active != nil else { throw WorkspaceClientError.signedOut }
        guard body.map({ $0.count <= 3 * 1024 * 1024 }) ?? true else { throw WorkspaceClientError.oversized }
        guard let url = URL(string: origin.url.absoluteString + path) else { throw WorkspaceClientError.invalidRequest }
        var request = URLRequest(url: url); request.httpMethod = method; request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "accept")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "content-type") }
        if authenticated, let active { request.setValue("Bearer " + active.token, forHTTPHeaderField: "authorization") }
        if let ifMatch { request.setValue("\"\(ifMatch.uuidString)\"", forHTTPHeaderField: "if-match") }
        guard inFlight < 8 else { throw WorkspaceClientError.unavailable }
        inFlight += 1
        defer { inFlight -= 1 }
        let reply = try await BoundedTransport(limit: limit).run(request)
        guard reply.response.url == url else { throw WorkspaceClientError.invalidResponse }
        guard allowed.contains(reply.response.statusCode) else {
            switch reply.response.statusCode {
            case 401: throw WorkspaceClientError.unauthenticated
            case 404: throw WorkspaceClientError.notFound
            case 409: throw WorkspaceClientError.conflict
            case 413: throw WorkspaceClientError.oversized
            case 429, 500...599: throw WorkspaceClientError.unavailable
            default: throw WorkspaceClientError.httpStatus(reply.response.statusCode)
            }
        }
        if reply.response.statusCode != 204 {
            guard let media = reply.response.value(forHTTPHeaderField: "content-type")?.lowercased().replacingOccurrences(of: " ", with: ""), ["application/json", "application/json;charset=utf-8"].contains(media), reply.response.value(forHTTPHeaderField: "content-encoding") == nil else { throw WorkspaceClientError.invalidResponse }
        }
        return reply
    }
}
