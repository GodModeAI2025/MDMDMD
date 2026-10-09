import Foundation
import CryptoKit

public struct WorkspaceCredentialScope: Hashable, Sendable {
    public let origin: WorkspaceOrigin; public let profileID: String; public let accountID: UUID
    public init(origin: WorkspaceOrigin, profileID: String, accountID: UUID) throws {
        guard WorkspaceCredential.validProfile(profileID), origin.url.absoluteString.utf8.count <= 2048 else { throw WorkspaceCredentialAdmissionError.invalidScope }
        self.origin = origin; self.profileID = profileID; self.accountID = accountID
    }
}
public enum WorkspaceCredentialAdmissionError: Error, Equatable, Sendable {
    case invalidScope, conflictingContext, staleTicket, denied, invalidDenialState, persistenceUnavailable, capacityExceeded
}
public enum WorkspaceCredentialDenialReason: String, Codable, Sendable {
    case localLogout, logoutAll, accountDeletion, unauthorized, providerRevoked
}
public struct WorkspaceCredentialAdmissionTicket: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let scope: WorkspaceCredentialScope
    let gateID: UUID; let generation: UUID; let denialGeneration: UUID?
    let fingerprint: Data?; let sessionID: UUID?
    public var description: String { "WorkspaceCredentialAdmissionTicket(<opaque>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: ["ticket": "<opaque>"]) }
}
public struct WorkspaceAdmittedCredential: Sendable {
    public let credential: WorkspaceCredential
    public let ticket: WorkspaceCredentialAdmissionTicket
}
protocol WorkspaceAdmissionSecurity: Sendable {
    func load(scope: WorkspaceCredentialScope) throws -> WorkspaceCredential?
    func save(_ credential: WorkspaceCredential, scope: WorkspaceCredentialScope) throws
    func remove(scope: WorkspaceCredentialScope) throws
}
#if canImport(Security)
private struct AdmissionKeychainSecurity: WorkspaceAdmissionSecurity {
    let service: String
    func primitive(_ scope: WorkspaceCredentialScope) throws -> WorkspaceKeychainPrimitive { try WorkspaceKeychainPrimitive(profileID: scope.profileID, service: service) }
    func load(scope: WorkspaceCredentialScope) throws -> WorkspaceCredential? { try primitive(scope).load(origin: scope.origin, accountID: scope.accountID) }
    func save(_ credential: WorkspaceCredential, scope: WorkspaceCredentialScope) throws { try primitive(scope).save(credential) }
    func remove(scope: WorkspaceCredentialScope) throws { try primitive(scope).remove(origin: scope.origin, accountID: scope.accountID) }
}
#endif

/// A process-shared synchronous transaction gate. It is not cross-process locking.
public final class WorkspaceCredentialAdmissionContext: @unchecked Sendable {
    private struct Slot {
        enum State { case eligible, enrolling, admitted, denied }
        var generation: UUID; var denialGeneration: UUID?; var fingerprint: Data?; var sessionID: UUID?
        var state: State; var failed = false
    }
    private final class Registry: @unchecked Sendable {
        let lock = NSLock(); var contexts: [String: WorkspaceCredentialAdmissionContext] = [:]
    }
    private static let registry = Registry()
    private let gateID = UUID()
    private let namespace: String
    private let lock = NSLock()
    private let repository: AdmissionDenialRepository
    private let security: any WorkspaceAdmissionSecurity
    private var ledger: AdmissionDenialLedger
    private var bytes: Data?
    private var slots: [WorkspaceCredentialScope: Slot] = [:]

    public static func shared(denialDirectory: URL, keychainService: String = "app.scriptum.workspace.sessions.v1") throws -> WorkspaceCredentialAdmissionContext {
        #if canImport(Security)
        _ = try WorkspaceKeychainPrimitive(profileID: "admission-validation", service: keychainService)
        let repository = try AdmissionDenialRepository(directory: denialDirectory)
        let key = keychainService
        return try registry.lock.withLock {
            if let existing = registry.contexts[key] {
                guard existing.repository.identity == repository.identity else { throw WorkspaceCredentialAdmissionError.conflictingContext }
                return existing
            }
            guard registry.contexts.count < 32 else { throw WorkspaceCredentialAdmissionError.capacityExceeded }
            let context = try WorkspaceCredentialAdmissionContext(repository: repository, namespace: keychainService, security: AdmissionKeychainSecurity(service: keychainService))
            registry.contexts[key] = context; return context
        }
        #else
        throw WorkspaceCredentialAdmissionError.persistenceUnavailable
        #endif
    }
    init(denialDirectory: URL, keychainService: String, security: any WorkspaceAdmissionSecurity) throws {
        repository = try AdmissionDenialRepository(directory: denialDirectory); namespace = keychainService; self.security = security
        let loaded = try repository.read(); ledger = loaded.ledger; bytes = loaded.bytes
    }
    private init(repository: AdmissionDenialRepository, namespace: String, security: any WorkspaceAdmissionSecurity) throws {
        self.repository = repository; self.namespace = namespace; self.security = security
        let loaded = try repository.read(); ledger = loaded.ledger; bytes = loaded.bytes
    }
    public func capture(scope: WorkspaceCredentialScope) throws -> WorkspaceCredentialAdmissionTicket {
        try lock.withLock {
            if slots[scope] == nil {
                guard slots.count < 1024 else { throw WorkspaceCredentialAdmissionError.capacityExceeded }
                let record = ledger.denials.first { $0.scope == scope }
                let stored = try security.load(scope: scope)
                slots[scope] = Slot(generation: record?.generation ?? UUID(), denialGeneration: record?.generation, fingerprint: stored.map(Self.fingerprint), sessionID: nil, state: record == nil ? .eligible : .denied)
            }
            try verifyLedger()
            return ticket(scope)
        }
    }
    public func beginExplicitEnrollment(expected: WorkspaceCredentialAdmissionTicket) throws -> WorkspaceCredentialAdmissionTicket {
        try lock.withLock {
            var slot = try checked(expected)
            guard !slot.failed else { throw WorkspaceCredentialAdmissionError.persistenceUnavailable }
            guard ledger.denials.count < 1024 || ledger.denials.contains(where: { $0.scope == expected.scope }) else { throw WorkspaceCredentialAdmissionError.capacityExceeded }
            try verifyLedger()
            let actual = try security.load(scope: expected.scope)
            let fingerprint = actual.map(Self.fingerprint)
            guard fingerprint == expected.fingerprint || (slot.state == .denied && actual == nil) else { throw WorkspaceCredentialAdmissionError.staleTicket }
            slot.fingerprint = fingerprint; if actual == nil { slot.sessionID = nil }
            slot.generation = UUID(); slot.state = .enrolling; slots[expected.scope] = slot
            return ticket(expected.scope)
        }
    }
    @discardableResult public func commitDenial(expected: WorkspaceCredentialAdmissionTicket, reason: WorkspaceCredentialDenialReason) throws -> WorkspaceCredentialAdmissionTicket {
        try lock.withLock {
            var slot = try checked(expected)
            slot.generation = UUID(); slot.state = .denied; slots[expected.scope] = slot
            var next = ledger; next.denials.removeAll { $0.scope == expected.scope }
            next.denials.append(AdmissionDenialRecord(scope: expected.scope, generation: slot.generation, reason: reason))
            do {
                try persist(next)
                slot.denialGeneration = slot.generation; slot.failed = false; slots[expected.scope] = slot
            } catch {
                slot.failed = true; slots[expected.scope] = slot
                throw WorkspaceCredentialAdmissionError.persistenceUnavailable
            }
            return ticket(expected.scope)
        }
    }
    fileprivate func load(expected: WorkspaceCredentialAdmissionTicket) throws -> WorkspaceAdmittedCredential? {
        try lock.withLock {
            let slot = try checked(expected)
            guard !slot.failed else { throw WorkspaceCredentialAdmissionError.persistenceUnavailable }
            guard slot.state == .eligible || slot.state == .admitted, slot.denialGeneration == nil else { throw WorkspaceCredentialAdmissionError.denied }
            try verifyLedger()
            let credential = try security.load(scope: expected.scope)
            guard credential.map(Self.fingerprint) == slot.fingerprint else { throw WorkspaceCredentialAdmissionError.staleTicket }
            return credential.map { WorkspaceAdmittedCredential(credential: $0, ticket: ticket(expected.scope)) }
        }
    }
    fileprivate func save(_ enrollment: WorkspaceIdentityEnrollment, expected: WorkspaceCredentialAdmissionTicket) throws -> WorkspaceCredentialAdmissionTicket {
        try lock.withLock {
            var slot = try checked(expected)
            guard !slot.failed else { throw WorkspaceCredentialAdmissionError.persistenceUnavailable }
            guard slot.state == .enrolling else { throw WorkspaceCredentialAdmissionError.denied }
            let credential = enrollment.credential
            guard credential.origin == expected.scope.origin, credential.profileID == expected.scope.profileID,
                  credential.accountID == expected.scope.accountID, enrollment.session.accountID == expected.scope.accountID,
                  enrollment.session.expiresAt > Date() else { throw WorkspaceCredentialAdmissionError.invalidScope }
            try verifyLedger()
            try checkActual(expected)
            try security.save(credential, scope: expected.scope)
            var next = ledger; next.denials.removeAll { $0.scope == expected.scope }
            do {
                if slot.denialGeneration != nil { try persist(next) }
            } catch {
                slot.generation = UUID(); slot.state = .denied; slot.failed = true
                slot.fingerprint = Self.fingerprint(credential); slot.sessionID = enrollment.session.sessionID; slots[expected.scope] = slot
                // Matching new credential only; unrelated tokens must survive.
                if (try? security.load(scope: expected.scope)).map(Self.fingerprint) == slot.fingerprint { try? security.remove(scope: expected.scope) }
                throw WorkspaceCredentialAdmissionError.persistenceUnavailable
            }
            slot.generation = UUID(); slot.denialGeneration = nil; slot.fingerprint = Self.fingerprint(credential)
            slot.sessionID = enrollment.session.sessionID; slot.state = .admitted; slots[expected.scope] = slot
            return ticket(expected.scope)
        }
    }
    fileprivate func remove(expected: WorkspaceCredentialAdmissionTicket) throws {
        try lock.withLock {
            let slot = try checked(expected)
            guard slot.state == .denied else { throw WorkspaceCredentialAdmissionError.denied }
            try verifyLedger()
            guard let actual = try security.load(scope: expected.scope) else { return }
            guard Self.fingerprint(actual) == slot.fingerprint else { throw WorkspaceCredentialAdmissionError.staleTicket }
            try security.remove(scope: expected.scope)
        }
    }
    private func checked(_ expected: WorkspaceCredentialAdmissionTicket) throws -> Slot {
        guard expected.gateID == gateID, let slot = slots[expected.scope], slot.generation == expected.generation,
              slot.denialGeneration == expected.denialGeneration, slot.fingerprint == expected.fingerprint,
              slot.sessionID == expected.sessionID else { throw WorkspaceCredentialAdmissionError.staleTicket }
        return slot
    }
    private func ticket(_ scope: WorkspaceCredentialScope) -> WorkspaceCredentialAdmissionTicket {
        let slot = slots[scope]!
        return WorkspaceCredentialAdmissionTicket(scope: scope, gateID: gateID, generation: slot.generation, denialGeneration: slot.denialGeneration, fingerprint: slot.fingerprint, sessionID: slot.sessionID)
    }
    private func checkActual(_ expected: WorkspaceCredentialAdmissionTicket) throws {
        guard (try security.load(scope: expected.scope)).map(Self.fingerprint) == expected.fingerprint else { throw WorkspaceCredentialAdmissionError.staleTicket }
    }
    private static func fingerprint(_ credential: WorkspaceCredential) -> Data { Data(SHA256.hash(data: Data(credential.token.utf8))) }
    private func verifyLedger() throws {
        guard try repository.read().bytes == bytes else { throw WorkspaceCredentialAdmissionError.staleTicket }
    }
    private func persist(_ next: AdmissionDenialLedger) throws {
        let written = try repository.write(next, expected: bytes)
        ledger = written.ledger; bytes = written.bytes
    }
}
public actor WorkspaceCredentialAdmissionStore {
    private let context: WorkspaceCredentialAdmissionContext
    public init(context: WorkspaceCredentialAdmissionContext) { self.context = context }
    public func loadIfAdmitted(expected: WorkspaceCredentialAdmissionTicket) throws -> WorkspaceAdmittedCredential? { try context.load(expected: expected) }
    public func saveIfAdmitted(_ enrollment: WorkspaceIdentityEnrollment, expected: WorkspaceCredentialAdmissionTicket) throws -> WorkspaceCredentialAdmissionTicket { try context.save(enrollment, expected: expected) }
    public func removeIfDenied(expected: WorkspaceCredentialAdmissionTicket) throws { try context.remove(expected: expected) }
}
