import Foundation

/// Identity wire only. Apple framework UI and global multi-library session
/// invalidation are separate integration responsibilities.
public actor WorkspaceIdentityClient {
    public let origin: WorkspaceOrigin
    public let profileID: String
    public let consentVersion: String
    private let ownerID = UUID()
    private var admission: IdentitySessionState
    private var inFlight = 0
    private var enrolling = false
    #if SWIFT_PACKAGE && DEBUG
    private let beforeEnrollmentAdmission: (@Sendable () async -> Void)?
    #endif
    public init(origin: WorkspaceOrigin, profileID: String, consentVersion: String, credential: WorkspaceCredential? = nil) throws {
        let configuration = try IdentityClientConfiguration(origin: origin, profileID: profileID, consentVersion: consentVersion, credential: credential)
        self.origin = configuration.origin; self.profileID = configuration.profileID; self.consentVersion = configuration.consentVersion
        admission = IdentitySessionState(credential: configuration.credential)
        #if SWIFT_PACKAGE && DEBUG
        beforeEnrollmentAdmission = nil
        #endif
    }
    #if SWIFT_PACKAGE && DEBUG
    init(configuration: IdentityClientConfiguration, beforeEnrollmentAdmission: @escaping @Sendable () async -> Void) {
        origin = configuration.origin; profileID = configuration.profileID; consentVersion = configuration.consentVersion
        admission = IdentitySessionState(credential: configuration.credential)
        self.beforeEnrollmentAdmission = beforeEnrollmentAdmission
    }
    #endif
    public var admissionState: WorkspaceIdentityAdmissionState { admission.state(at: ContinuousClock().now) }
    public var isSignedIn: Bool { if case .active = admissionState { return true }; return false }
    public func invalidateLocally() { admission.invalidate() }
    public func challenge() async throws -> WorkspaceIdentityChallenge {
        let capturedEpoch = admission.intentEpoch; let started = ContinuousClock().now
        let reply = try await request("POST", path: "/identity/challenges", body: ["profileID": profileID, "consentVersion": consentVersion], allowed: [201])
        let challenge = try WorkspaceIdentityWire.challenge(reply.data, origin: origin, profileID: profileID, ownerID: ownerID, epoch: capturedEpoch, started: started)
        guard admission.intentEpoch == capturedEpoch else { throw WorkspaceClientError.signedOut }
        return challenge
    }
    public func enroll(challenge: WorkspaceIdentityChallenge, proof: WorkspaceIdentityProof) async throws -> WorkspaceIdentityEnrollment {
        guard challenge.origin == origin, challenge.profileID == profileID, challenge.ownerID == ownerID, challenge.epoch == admission.intentEpoch, challenge.state.utf8.elementsEqual(proof.state.utf8) else { throw WorkspaceIdentityClientError.scopeMismatch }
        guard ContinuousClock().now < challenge.deadline else { throw WorkspaceIdentityClientError.expiredChallenge }
        guard !enrolling else { throw WorkspaceClientError.unavailable }
        enrolling = true; defer { enrolling = false }
        let capturedEpoch = admission.intentEpoch; let started = ContinuousClock().now
        let reply = try await request("POST", path: "/identity/enroll", body: ["challengeID": challenge.id.uuidString, "challengeSecret": challenge.secret, "state": proof.state, "identityToken": proof.identityToken, "authorizationCode": proof.authorizationCode], allowed: [201])
        let enrollment = try WorkspaceIdentityWire.enrollment(reply.data, origin: origin, profileID: profileID, started: started)
        #if SWIFT_PACKAGE && DEBUG
        if let beforeEnrollmentAdmission { await beforeEnrollmentAdmission() }
        #endif
        let cancelled = Task.isCancelled
        guard !cancelled, capturedEpoch == admission.intentEpoch else {
            let confirmed = await revokeDiscardedSession(enrollment.credential)
            if cancelled { throw WorkspaceIdentityClientError.cancelledEnrollment(remoteRevocationConfirmed: confirmed) }
            throw WorkspaceIdentityClientError.supersededEnrollment(remoteRevocationConfirmed: confirmed)
        }
        admission.install(enrollment.credential, session: enrollment.session, date: Date(), instant: ContinuousClock().now)
        return enrollment
    }
    public func currentSession() async throws -> WorkspaceIdentitySession {
        guard let captured = admission.snapshot else { throw WorkspaceClientError.signedOut }
        guard admissionState != .expired else { throw WorkspaceClientError.signedOut }
        let reply = try await request("GET", path: "/session", token: captured.credential.token, capturedAdmission: captured, allowed: [200])
        let session = try WorkspaceIdentityWire.session(reply.data, accountID: captured.credential.accountID, expectedSessionID: captured.sessionID)
        try admission.validate(session, for: captured, date: Date(), instant: ContinuousClock().now)
        return session
    }
    public func logoutAll() async -> WorkspaceLogoutOutcome {
        guard let active = admission.credential else { invalidateLocally(); return .alreadySignedOut }
        invalidateLocally()
        do { let reply = try await request("POST", path: "/session/logout-all", token: active.token, allowed: [204]); return reply.data.isEmpty ? .confirmedRemoteRevocation : .remoteRevocationUnknown }
        catch { return .remoteRevocationUnknown }
    }
    /// Signs out this device session only; never substitutes logout-all.
    public func logoutCurrentSession() async -> WorkspaceLogoutOutcome {
        guard let active = admission.credential else { invalidateLocally(); return .alreadySignedOut }
        invalidateLocally()
        return await revokeDiscardedSession(active) ? .confirmedRemoteRevocation : .remoteRevocationUnknown
    }
    /// Coordinator cleanup for a returned enrollment rejected by its own fence.
    /// A newer actor credential or another account is never invalidated.
    public func discardIssuedSession(_ credential: WorkspaceCredential) async throws -> WorkspaceLogoutOutcome {
        guard credential.origin == origin, credential.profileID == profileID else { throw WorkspaceIdentityClientError.scopeMismatch }
        if let active = admission.credential, active.accountID == credential.accountID,
           active.token.utf8.elementsEqual(credential.token.utf8) { invalidateLocally() }
        return await revokeDiscardedSession(credential) ? .confirmedRemoteRevocation : .remoteRevocationUnknown
    }
    public func deleteAccount(using receipt: WorkspaceReauthenticationReceipt) async throws -> WorkspaceAccountDeletionOutcome {
        guard let active = admission.credential else { throw WorkspaceClientError.signedOut }
        guard admissionState != .expired else { throw WorkspaceClientError.signedOut }
        let proof = try receipt.claim(origin: origin, profileID: profileID, accountID: active.accountID)
        invalidateLocally()
        do { let reply = try await request("DELETE", path: "/account", token: active.token, body: ["reauthenticationReceipt": proof, "retentionConfirmation": "preserve-owned-libraries"], allowed: [204]); return reply.data.isEmpty ? .confirmedAccountTombstone : .remoteDeletionUnknown }
        catch { return .remoteDeletionUnknown }
    }
    /// Cleanup must run in a fresh unstructured task: a cancelled caller cannot
    /// cancel the new session's bounded targeted revocation before it starts.
    private func revokeDiscardedSession(_ credential: WorkspaceCredential) async -> Bool {
        let cleanup = Task { [self] in
            let reply = try? await request("POST", path: "/session/logout", token: credential.token, allowed: [204])
            return reply?.data.isEmpty == true
        }
        return await cleanup.value
    }
    private func request(_ method: String, path: String, token: String? = nil, capturedAdmission: IdentityAdmissionSnapshot? = nil, body: [String: String]? = nil, allowed: Set<Int>) async throws -> WorkspaceHTTPResponse {
        guard inFlight < 8 else { throw WorkspaceClientError.unavailable }
        guard let url = URL(string: origin.url.absoluteString + path) else { throw WorkspaceClientError.invalidConfiguration }
        var request = URLRequest(url: url); request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "accept")
        if let body {
            let bytes = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
            guard bytes.count <= 24_576 else { throw WorkspaceClientError.oversized }
            request.httpBody = bytes; request.setValue("application/json", forHTTPHeaderField: "content-type")
        }
        if let token { request.setValue("Bearer " + token, forHTTPHeaderField: "authorization") }
        inFlight += 1; defer { inFlight -= 1 }
        let reply = try await BoundedTransport(limit: 24_576).run(request)
        guard reply.response.url == url else { throw WorkspaceClientError.invalidResponse }
        guard allowed.contains(reply.response.statusCode) else {
            switch reply.response.statusCode {
            case 401:
                if let capturedAdmission { admission.invalidateIfMatching(capturedAdmission) }
                throw WorkspaceClientError.unauthenticated
            case 404: throw WorkspaceClientError.notFound
            case 409: throw WorkspaceClientError.conflict
            case 413: throw WorkspaceClientError.oversized
            case 429, 500...599: throw WorkspaceClientError.unavailable
            default: throw WorkspaceClientError.httpStatus(reply.response.statusCode)
            }
        }
        let cache = reply.response.value(forHTTPHeaderField: "cache-control")?.lowercased().split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard cache?.contains("no-store") == true, reply.response.value(forHTTPHeaderField: "content-encoding") == nil else { throw WorkspaceClientError.invalidResponse }
        if reply.response.statusCode == 204 { guard reply.data.isEmpty else { throw WorkspaceClientError.invalidResponse } }
        else {
            let media = reply.response.value(forHTTPHeaderField: "content-type")?.lowercased().replacingOccurrences(of: " ", with: "")
            guard media == "application/json" || media == "application/json;charset=utf-8" else { throw WorkspaceClientError.invalidResponse }
        }
        return reply
    }
}

struct IdentityClientConfiguration: Sendable {
    let origin: WorkspaceOrigin; let profileID: String; let consentVersion: String
    let credential: WorkspaceCredential?
    init(origin: WorkspaceOrigin, profileID: String, consentVersion: String, credential: WorkspaceCredential?) throws {
        guard WorkspaceCredential.validProfile(profileID), WorkspaceCredential.validProfile(consentVersion) else { throw WorkspaceClientError.invalidConfiguration }
        guard credential.map({ $0.origin == origin && $0.profileID == profileID }) ?? true else { throw WorkspaceIdentityClientError.scopeMismatch }
        self.origin = origin; self.profileID = profileID; self.consentVersion = consentVersion; self.credential = credential
    }
}
