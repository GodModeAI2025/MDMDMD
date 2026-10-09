import Foundation
import Testing
@testable import SkriptumWorkspaceClient

@Test func identityProofAndRandomBounds() throws {
    let token = "e30.e30." + String(repeating: "A", count: 43)
    let proof = try WorkspaceIdentityProof(identityToken: token, authorizationCode: "code", state: String(repeating: "A", count: 43))
    #expect(!String(reflecting: proof).contains("code"))
    #expect(throws: WorkspaceClientError.invalidRequest) { try WorkspaceIdentityProof(identityToken: "https://bad.example/token", authorizationCode: "code", state: String(repeating: "A", count: 43)) }
    #expect(throws: WorkspaceClientError.invalidRequest) { try WorkspaceIdentityProof(identityToken: token, authorizationCode: String(repeating: "x", count: 4097), state: String(repeating: "A", count: 43)) }
    #expect(throws: WorkspaceClientError.invalidRequest) { try WorkspaceIdentityProof(identityToken: token, authorizationCode: "code", state: String(repeating: "B", count: 43)) }
}

@Test func identityResponseShapesAndTimeAreStrict() throws {
    let origin = try WorkspaceOrigin("https://workspace.example")
    let random = String(repeating: "A", count: 43), id = UUID(), epoch = UUID(), owner = UUID()
    let now = Date(); let clock = ContinuousClock().now
    let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    var row: [String: Any] = ["challengeID": id.uuidString, "challengeSecret": random, "nonce": random, "state": random, "expiresAt": formatter.string(from: now.addingTimeInterval(300))]
    func parse(_ row: [String: Any]) throws -> WorkspaceIdentityChallenge {
        try WorkspaceIdentityWire.challenge(JSONSerialization.data(withJSONObject: row), origin: origin, profileID: "apple", ownerID: owner, epoch: epoch, started: clock, now: now)
    }
    let challenge = try parse(row)
    #expect(challenge.id == id)
    #expect(challenge.deadline <= clock.advanced(by: .seconds(300)))
    #expect(!String(reflecting: challenge).contains(random))
    for field in ["nonce", "state", "challengeSecret"] {
        var changed = row; changed[field] = String(repeating: "B", count: 43)
        #expect(throws: WorkspaceClientError.invalidResponse) { try parse(changed) }
        changed[field] = true
        #expect(throws: WorkspaceClientError.invalidResponse) { try parse(changed) }
    }
    row["role"] = "owner"
    #expect(throws: WorkspaceClientError.invalidResponse) { try parse(row) }
    row.removeValue(forKey: "role")
    for date in [formatter.string(from: now.addingTimeInterval(-120)), formatter.string(from: now.addingTimeInterval(400)), "2026-02-30T00:00:00.000Z", "2026-10-09T00:00:00Z"] {
        row["expiresAt"] = date
        #expect(throws: WorkspaceClientError.invalidResponse) { try parse(row) }
    }
    let duplicate = "{\"challengeID\":\"\(id)\",\"nonce\":\"\(random)\",\"nonce\":\"\(random)\"}"
    #expect(throws: WorkspaceClientError.invalidResponse) { try WorkspaceIdentityWire.challenge(Data(duplicate.utf8), origin: origin, profileID: "apple", ownerID: owner, epoch: epoch, started: clock, now: now) }
}

@Test func identityEnrollmentAndSessionScopeContract() throws {
    let origin = try WorkspaceOrigin("https://workspace.example"), account = UUID(), session = UUID(), now = Date()
    let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    var row: [String: Any] = ["sessionToken": String(repeating: "A", count: 43), "sessionID": session.uuidString, "accountID": account.uuidString, "expiresAt": formatter.string(from: now.addingTimeInterval(28_800)), "reauthenticationReceipt": String(repeating: "A", count: 43)]
    let result = try WorkspaceIdentityWire.enrollment(JSONSerialization.data(withJSONObject: row), origin: origin, profileID: "apple", started: ContinuousClock().now, now: now)
    #expect(result.credential.profileID == "apple")
    #expect(result.credential.accountID == account)
    #expect(result.reauthenticationReceipt.accountID == account)
    #expect(!String(reflecting: result).contains(String(repeating: "A", count: 43)))
    row["sessionToken"] = String(repeating: "A", count: 128)
    #expect(throws: WorkspaceClientError.invalidResponse) { try WorkspaceIdentityWire.enrollment(JSONSerialization.data(withJSONObject: row), origin: origin, profileID: "apple", started: ContinuousClock().now, now: now) }
    let current: [String: Any] = ["sessionID": session.uuidString, "accountID": account.uuidString, "expiresAt": formatter.string(from: now.addingTimeInterval(100))]
    let data = try JSONSerialization.data(withJSONObject: current)
    #expect(try WorkspaceIdentityWire.session(data, accountID: account, expectedSessionID: session, now: now).sessionID == session)
    #expect(throws: WorkspaceIdentityClientError.unexpectedAccount) { try WorkspaceIdentityWire.session(data, accountID: UUID(), expectedSessionID: nil, now: now) }
    #expect(throws: WorkspaceIdentityClientError.unexpectedAccount) { try WorkspaceIdentityWire.session(data, accountID: account, expectedSessionID: UUID(), now: now) }
}

@Test func identityReceiptIsScopedMemoryOnlyAndOneUseAcrossCopies() async throws {
    let origin = try WorkspaceOrigin("https://workspace.example"), account = UUID()
    let receipt = WorkspaceReauthenticationReceipt(token: String(repeating: "A", count: 43), origin: origin, profileID: "apple", accountID: account, deadline: ContinuousClock().now.advanced(by: .seconds(300)))
    #expect(!String(reflecting: receipt).contains(String(repeating: "A", count: 43)))
    #expect(throws: WorkspaceIdentityClientError.scopeMismatch) { try receipt.claim(origin: origin, profileID: "other", accountID: account) }
    let successes = await withTaskGroup(of: Bool.self) { group in
        for _ in 0..<20 { group.addTask { (try? receipt.claim(origin: origin, profileID: "apple", accountID: account)) != nil } }
        var successes = 0
        for await success in group { if success { successes += 1 } }
        return successes
    }
    #expect(successes == 1)
    let copy = receipt
    #expect(throws: WorkspaceIdentityClientError.receiptConsumed) { try copy.claim(origin: origin, profileID: "apple", accountID: account) }
    let expired = WorkspaceReauthenticationReceipt(token: String(repeating: "A", count: 43), origin: origin, profileID: "apple", accountID: account, deadline: ContinuousClock().now.advanced(by: .seconds(-1)))
    #expect(throws: WorkspaceIdentityClientError.expiredReceipt) { try expired.claim(origin: origin, profileID: "apple", accountID: account) }
}

@Test func identityKnownExpiryAndStaleUnauthorizedAdmission() throws {
    let origin = try WorkspaceOrigin("https://workspace.example"), account = UUID(), now = Date(), clock = ContinuousClock().now
    let first = try WorkspaceCredential(origin: origin, accountID: account, token: String(repeating: "A", count: 43), profileID: "apple")
    var state = IdentitySessionState(credential: first)
    #expect(state.state(at: clock) == .unvalidated)
    let old = try #require(state.snapshot)
    let session = WorkspaceIdentitySession(accountID: account, sessionID: UUID(), expiresAt: now.addingTimeInterval(10))
    try state.validate(session, for: old, date: now, instant: clock)
    #expect(state.state(at: clock) == .active(expiresAt: session.expiresAt))
    #expect(state.state(at: clock.advanced(by: .seconds(10))) == .expired)
    #expect(state.credential != nil) // retained solely for best-effort logout
    let stale = try #require(state.snapshot)
    let second = try WorkspaceCredential(origin: origin, accountID: account, token: String(repeating: "C", count: 43), profileID: "apple")
    let newer = WorkspaceIdentitySession(accountID: account, sessionID: UUID(), expiresAt: now.addingTimeInterval(100))
    state.install(second, session: newer, date: now, instant: clock)
    let staleInvalidated = state.invalidateIfMatching(stale)
    #expect(staleInvalidated == false)
    #expect(state.state(at: clock) == .active(expiresAt: newer.expiresAt))
    #expect(throws: WorkspaceClientError.signedOut) { try state.validate(session, for: stale, date: now, instant: clock) }
    let current = try #require(state.snapshot)
    let currentInvalidated = state.invalidateIfMatching(current)
    #expect(currentInvalidated)
    #expect(state.state(at: clock) == .signedOut)
}

@Test func identityValidationNeverExtendsKnownAbsoluteLifetime() throws {
    let origin = try WorkspaceOrigin("https://workspace.example"), account = UUID(), date = Date(), clock = ContinuousClock().now
    let credential = try WorkspaceCredential(origin: origin, accountID: account, token: String(repeating: "A", count: 43), profileID: "apple")
    let session = WorkspaceIdentitySession(accountID: account, sessionID: UUID(), expiresAt: date.addingTimeInterval(10))
    var state = IdentitySessionState(credential: credential)
    try state.validate(session, for: #require(state.snapshot), date: date, instant: clock)
    let captured = try #require(state.snapshot)
    let laterExpiry = WorkspaceIdentitySession(accountID: account, sessionID: session.sessionID, expiresAt: date.addingTimeInterval(1000))
    try state.validate(laterExpiry, for: captured, date: date.addingTimeInterval(-100), instant: clock.advanced(by: .seconds(5)))
    #expect(state.state(at: clock.advanced(by: .seconds(10))) == .expired)
    state.install(credential, session: laterExpiry, date: date, instant: clock.advanced(by: .seconds(20)))
    #expect(state.state(at: clock.advanced(by: .seconds(30))) == .active(expiresAt: laterExpiry.expiresAt))
}
