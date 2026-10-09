import Foundation

/// The exact reviewed DTO shapes. The common strict JSON boundary remains the
/// only parser; these functions add identity-specific scope and lifetime rules.
enum WorkspaceIdentityWire {
    static func challenge(_ data: Data, origin: WorkspaceOrigin, profileID: String, ownerID: UUID, epoch: UUID, started: ContinuousClock.Instant, now: Date = Date()) throws -> WorkspaceIdentityChallenge {
        let row = try WorkspaceWire.object(data, keys: ["challengeID", "challengeSecret", "nonce", "state", "expiresAt"])
        guard let secret = row["challengeSecret"] as? String, IdentityBounds.random(secret),
              let nonce = row["nonce"] as? String, IdentityBounds.random(nonce),
              let state = row["state"] as? String, IdentityBounds.random(state) else { throw WorkspaceClientError.invalidResponse }
        let expiry = try IdentityBounds.date(row["expiresAt"], now: now, maximumLifetime: 360)
        let deadline = min(started.advanced(by: .seconds(300)), ContinuousClock().now.advanced(by: .seconds(expiry.timeIntervalSince(now))))
        return WorkspaceIdentityChallenge(id: try WorkspaceWire.uuid(row["challengeID"]), nonce: nonce, state: state, expiresAt: expiry, secret: secret, origin: origin, profileID: profileID, ownerID: ownerID, epoch: epoch, deadline: deadline)
    }
    static func enrollment(_ data: Data, origin: WorkspaceOrigin, profileID: String, started: ContinuousClock.Instant, now: Date = Date()) throws -> WorkspaceIdentityEnrollment {
        let row = try WorkspaceWire.object(data, keys: ["sessionToken", "sessionID", "accountID", "expiresAt", "reauthenticationReceipt"])
        guard let token = row["sessionToken"] as? String, IdentityBounds.random(token),
              let receiptToken = row["reauthenticationReceipt"] as? String, IdentityBounds.random(receiptToken) else { throw WorkspaceClientError.invalidResponse }
        let account = try WorkspaceWire.uuid(row["accountID"])
        let session = WorkspaceIdentitySession(accountID: account, sessionID: try WorkspaceWire.uuid(row["sessionID"]), expiresAt: try IdentityBounds.date(row["expiresAt"], now: now, maximumLifetime: 28_860))
        let next = try WorkspaceCredential(origin: origin, accountID: account, token: token, profileID: profileID)
        let receipt = WorkspaceReauthenticationReceipt(token: receiptToken, origin: origin, profileID: profileID, accountID: account, deadline: started.advanced(by: .seconds(300)))
        return WorkspaceIdentityEnrollment(credential: next, session: session, reauthenticationReceipt: receipt)
    }
    static func session(_ data: Data, accountID: UUID, expectedSessionID: UUID?, now: Date = Date()) throws -> WorkspaceIdentitySession {
        let row = try WorkspaceWire.object(data, keys: ["accountID", "sessionID", "expiresAt"])
        let session = WorkspaceIdentitySession(accountID: try WorkspaceWire.uuid(row["accountID"]), sessionID: try WorkspaceWire.uuid(row["sessionID"]), expiresAt: try IdentityBounds.date(row["expiresAt"], now: now, maximumLifetime: 28_860))
        guard session.accountID == accountID, expectedSessionID.map({ $0 == session.sessionID }) ?? true else { throw WorkspaceIdentityClientError.unexpectedAccount }
        return session
    }
}
