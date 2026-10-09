import Foundation

public enum WorkspaceIdentityAdmissionState: Equatable, Sendable {
    case signedOut, unvalidated, active(expiresAt: Date), expired
}
struct IdentityAdmissionSnapshot: Sendable {
    let epoch: UUID
    let credential: WorkspaceCredential
    let sessionID: UUID?
}
/// Production admission state; explicit clock inputs make expiry ordering
/// deterministic without a test-only way to mutate the actor's authority.
struct IdentitySessionState: Sendable {
    private(set) var epoch = UUID()
    private(set) var intentEpoch = UUID()
    private(set) var credential: WorkspaceCredential?
    private(set) var knownSessionID: UUID?
    private var expiresAt: Date?
    private var deadline: ContinuousClock.Instant?
    init(credential: WorkspaceCredential? = nil) { self.credential = credential }
    var snapshot: IdentityAdmissionSnapshot? {
        credential.map { IdentityAdmissionSnapshot(epoch: epoch, credential: $0, sessionID: knownSessionID) }
    }
    func state(at now: ContinuousClock.Instant) -> WorkspaceIdentityAdmissionState {
        guard credential != nil else { return .signedOut }
        guard let deadline, let expiresAt else { return .unvalidated }
        return now < deadline ? .active(expiresAt: expiresAt) : .expired
    }
    mutating func invalidate(advancingIntent: Bool = true) {
        credential = nil; knownSessionID = nil; expiresAt = nil; deadline = nil; epoch = UUID()
        if advancingIntent { intentEpoch = UUID() }
    }
    mutating func install(_ credential: WorkspaceCredential, session: WorkspaceIdentitySession, date: Date, instant: ContinuousClock.Instant) {
        epoch = UUID(); intentEpoch = UUID(); self.credential = credential
        cache(session, date: date, instant: instant, preservingLifetime: false)
    }
    mutating func validate(_ session: WorkspaceIdentitySession, for captured: IdentityAdmissionSnapshot, date: Date, instant: ContinuousClock.Instant) throws {
        guard matches(captured), session.accountID == captured.credential.accountID,
              captured.sessionID.map({ $0 == session.sessionID }) ?? true else { throw WorkspaceClientError.signedOut }
        cache(session, date: date, instant: instant, preservingLifetime: true)
    }
    @discardableResult mutating func invalidateIfMatching(_ captured: IdentityAdmissionSnapshot) -> Bool {
        guard matches(captured) else { return false }
        invalidate(advancingIntent: false); return true
    }
    private func matches(_ captured: IdentityAdmissionSnapshot) -> Bool {
        guard epoch == captured.epoch, let current = credential,
              current.origin == captured.credential.origin, current.accountID == captured.credential.accountID,
              current.profileID == captured.credential.profileID, current.token.utf8.elementsEqual(captured.credential.token.utf8) else { return false }
        return captured.sessionID.map({ $0 == knownSessionID }) ?? true
    }
    private mutating func cache(_ session: WorkspaceIdentitySession, date: Date, instant: ContinuousClock.Instant, preservingLifetime: Bool) {
        let expiry = preservingLifetime ? min(expiresAt ?? session.expiresAt, session.expiresAt) : session.expiresAt
        let proposed = instant.advanced(by: .seconds(max(0, min(28_800, expiry.timeIntervalSince(date)))))
        deadline = preservingLifetime ? min(deadline ?? proposed, proposed) : proposed
        knownSessionID = session.sessionID; expiresAt = expiry
    }
}
