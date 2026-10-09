import Foundation

public enum WorkspaceIdentityClientError: Error, Equatable, Sendable {
    case scopeMismatch, expiredChallenge, expiredReceipt, receiptConsumed, unexpectedAccount
    case supersededEnrollment(remoteRevocationConfirmed: Bool)
    case cancelledEnrollment(remoteRevocationConfirmed: Bool)
}
public struct WorkspaceIdentityProof: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    let identityToken: String; let authorizationCode: String; let state: String
    public init(identityToken: String, authorizationCode: String, state: String) throws {
        let parts = identityToken.split(separator: ".", omittingEmptySubsequences: false)
        guard identityToken.utf8.count <= 16_384, parts.count == 3,
              IdentityBounds.decode(String(parts[0]), maximum: 1024) != nil,
              IdentityBounds.decode(String(parts[1]), maximum: 8192) != nil,
              IdentityBounds.decode(String(parts[2]), maximum: 2048) != nil,
              (1...4096).contains(authorizationCode.utf8.count),
              authorizationCode.utf8.allSatisfy({ $0 >= 32 && $0 != 127 }), IdentityBounds.random(state) else { throw WorkspaceClientError.invalidRequest }
        self.identityToken = identityToken; self.authorizationCode = authorizationCode; self.state = state
    }
    public var description: String { "WorkspaceIdentityProof(<redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: ["proof": "<redacted>"]) }
}
public struct WorkspaceIdentityChallenge: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let id: UUID
    public let nonce: String
    public let state: String
    public let expiresAt: Date
    public var remainingLifetime: Duration { max(.zero, ContinuousClock().now.duration(to: deadline)) }
    let secret: String; let origin: WorkspaceOrigin; let profileID: String
    let ownerID: UUID; let epoch: UUID; let deadline: ContinuousClock.Instant
    public var description: String { "WorkspaceIdentityChallenge(<redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: ["challenge": "<redacted>"]) }
}
public struct WorkspaceIdentitySession: Equatable, Sendable {
    public let accountID: UUID; public let sessionID: UUID; public let expiresAt: Date
}
public struct WorkspaceIdentityEnrollment: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let credential: WorkspaceCredential
    public let session: WorkspaceIdentitySession
    public let reauthenticationReceipt: WorkspaceReauthenticationReceipt
    public var description: String { "WorkspaceIdentityEnrollment(<redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: ["enrollment": "<redacted>"]) }
}
public struct WorkspaceReauthenticationReceipt: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let accountID: UUID
    let origin: WorkspaceOrigin; let profileID: String; let deadline: ContinuousClock.Instant
    private let token: String
    private let consumption = ReceiptConsumption()
    init(token: String, origin: WorkspaceOrigin, profileID: String, accountID: UUID, deadline: ContinuousClock.Instant) {
        self.token = token; self.origin = origin; self.profileID = profileID; self.accountID = accountID; self.deadline = deadline
    }
    public var isExpired: Bool { ContinuousClock().now >= deadline }
    func claim(origin: WorkspaceOrigin, profileID: String, accountID: UUID) throws -> String {
        guard self.origin == origin, self.profileID == profileID, self.accountID == accountID else { throw WorkspaceIdentityClientError.scopeMismatch }
        guard !isExpired else { throw WorkspaceIdentityClientError.expiredReceipt }
        try consumption.claim(); return token
    }
    public var description: String { "WorkspaceReauthenticationReceipt(<redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: ["receipt": "<redacted>"]) }
}
private final class ReceiptConsumption: @unchecked Sendable {
    private let lock = NSLock(); private var consumed = false
    func claim() throws {
        try lock.withLock {
            guard !consumed else { throw WorkspaceIdentityClientError.receiptConsumed }
            consumed = true
        }
    }
}
public enum WorkspaceAccountDeletionOutcome: Equatable, Sendable {
    case confirmedAccountTombstone, remoteDeletionUnknown
}
enum IdentityBounds {
    static func decode(_ string: String, maximum: Int) -> Data? {
        guard !string.isEmpty, string.utf8.count <= (maximum * 4 + 2) / 3,
              string.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95 }) else { return nil }
        let standard = string.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        guard let data = Data(base64Encoded: standard + String(repeating: "=", count: (4 - standard.utf8.count % 4) % 4)), !data.isEmpty, data.count <= maximum,
              data.base64EncodedString().replacingOccurrences(of: "=", with: "").replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_") == string else { return nil }
        return data
    }
    static func random(_ string: String) -> Bool { string.utf8.count == 43 && decode(string, maximum: 32)?.count == 32 }
    static func date(_ value: Any?, now: Date, maximumLifetime: TimeInterval) throws -> Date {
        guard let text = value as? String,
              text.range(of: #"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3}Z$"#, options: .regularExpression) != nil else { throw WorkspaceClientError.invalidResponse }
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: text), formatter.string(from: date) == text,
              date.timeIntervalSinceReferenceDate.isFinite, date > now, date.timeIntervalSince(now) <= maximumLifetime else { throw WorkspaceClientError.invalidResponse }
        return date
    }
}
