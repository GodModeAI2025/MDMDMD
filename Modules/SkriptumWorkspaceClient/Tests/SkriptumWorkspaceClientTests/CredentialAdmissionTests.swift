import Foundation
import Testing
@testable import SkriptumWorkspaceClient

final class AdmissionMemorySecurity: WorkspaceAdmissionSecurity, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [WorkspaceCredentialScope: WorkspaceCredential] = [:]
    private var removalFailure = false
    private var saveCallback: (@Sendable () -> Void)?
    var failRemove: Bool { get { lock.withLock { removalFailure } } set { lock.withLock { removalFailure = newValue } } }
    var onSave: (@Sendable () -> Void)? { get { lock.withLock { saveCallback } } set { lock.withLock { saveCallback = newValue } } }
    func load(scope: WorkspaceCredentialScope) throws -> WorkspaceCredential? { lock.withLock { values[scope] } }
    func save(_ credential: WorkspaceCredential, scope: WorkspaceCredentialScope) throws { lock.withLock { values[scope] = credential; saveCallback?() } }
    func remove(scope: WorkspaceCredentialScope) throws {
        try lock.withLock { if removalFailure { throw WorkspaceCredentialStoreError.keychainStatus(-1) }; values.removeValue(forKey: scope) }
    }
}
private func admittedCandidate(_ scope: WorkspaceCredentialScope, token: String = String(repeating: "A", count: 43)) throws -> WorkspaceIdentityEnrollment {
    let credential = try WorkspaceCredential(origin: scope.origin, accountID: scope.accountID, token: token, profileID: scope.profileID)
    let session = WorkspaceIdentitySession(accountID: scope.accountID, sessionID: UUID(), expiresAt: Date().addingTimeInterval(3600))
    let receipt = WorkspaceReauthenticationReceipt(token: token, origin: scope.origin, profileID: scope.profileID, accountID: scope.accountID, deadline: ContinuousClock().now.advanced(by: .seconds(300)))
    return WorkspaceIdentityEnrollment(credential: credential, session: session, reauthenticationReceipt: receipt)
}
@Test func credentialAdmissionDenialFencesOldSaveAndFreshEnrollmentFencesOldRemoval() async throws {
    let root = URL(fileURLWithPath: "/private/tmp").appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let security = AdmissionMemorySecurity()
    let context = try WorkspaceCredentialAdmissionContext(denialDirectory: root, keychainService: "test.admission", security: security)
    let store = WorkspaceCredentialAdmissionStore(context: context)
    let scope = try WorkspaceCredentialScope(origin: WorkspaceOrigin("https://workspace.example"), profileID: "apple", accountID: UUID())
    let start = try context.capture(scope: scope)
    let pending = try context.beginExplicitEnrollment(expected: start)
    let active = try await store.saveIfAdmitted(admittedCandidate(scope), expected: pending)
    let denied = try context.commitDenial(expected: active, reason: .localLogout)
    do { _ = try await store.saveIfAdmitted(admittedCandidate(scope), expected: pending); Issue.record("Stale save admitted") }
    catch { #expect(error as? WorkspaceCredentialAdmissionError == .staleTicket) }
    do { _ = try await store.loadIfAdmitted(expected: denied); Issue.record("Denied load admitted") }
    catch { #expect(error as? WorkspaceCredentialAdmissionError == .denied) }
    let next = try context.beginExplicitEnrollment(expected: denied)
    let fresh = try await store.saveIfAdmitted(admittedCandidate(scope, token: String(repeating: "C", count: 43)), expected: next)
    do { try await store.removeIfDenied(expected: denied); Issue.record("Old removal deleted new token") }
    catch { #expect(error as? WorkspaceCredentialAdmissionError == .staleTicket) }
    #expect(try await store.loadIfAdmitted(expected: fresh)?.credential.token == String(repeating: "C", count: 43))
    #expect(throws: WorkspaceCredentialAdmissionError.staleTicket) { try context.commitDenial(expected: active, reason: .unauthorized) }
}
@Test func credentialAdmissionFailedRemovalAndColdRestartStayDenied() async throws {
    let root = URL(fileURLWithPath: "/private/tmp").appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let security = AdmissionMemorySecurity()
    let context = try WorkspaceCredentialAdmissionContext(denialDirectory: root, keychainService: "test.admission", security: security)
    let store = WorkspaceCredentialAdmissionStore(context: context)
    let scope = try WorkspaceCredentialScope(origin: WorkspaceOrigin("https://workspace.example"), profileID: "apple", accountID: UUID())
    let pending = try context.beginExplicitEnrollment(expected: context.capture(scope: scope))
    let active = try await store.saveIfAdmitted(admittedCandidate(scope), expected: pending)
    let denied = try context.commitDenial(expected: active, reason: .logoutAll)
    security.failRemove = true
    do { try await store.removeIfDenied(expected: denied); Issue.record("Removal failure hidden") }
    catch { #expect(error as? WorkspaceCredentialStoreError == .keychainStatus(-1)) }
    let restarted = try WorkspaceCredentialAdmissionContext(denialDirectory: root, keychainService: "test.admission", security: security)
    let restartedStore = WorkspaceCredentialAdmissionStore(context: restarted)
    do { _ = try await restartedStore.loadIfAdmitted(expected: restarted.capture(scope: scope)); Issue.record("Cold denial ignored") }
    catch { #expect(error as? WorkspaceCredentialAdmissionError == .denied) }
    #expect(try security.load(scope: scope) != nil)
}

@Test func credentialAdmissionSuccessfulRemoveAllowsOnlyExplicitFreshEnrollment() async throws {
    let root = URL(fileURLWithPath: "/private/tmp").appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let security = AdmissionMemorySecurity()
    let context = try WorkspaceCredentialAdmissionContext(denialDirectory: root, keychainService: "test.admission", security: security)
    let store = WorkspaceCredentialAdmissionStore(context: context)
    let scope = try WorkspaceCredentialScope(origin: WorkspaceOrigin("https://workspace.example"), profileID: "apple", accountID: UUID())
    let pending = try context.beginExplicitEnrollment(expected: context.capture(scope: scope))
    let active = try await store.saveIfAdmitted(admittedCandidate(scope), expected: pending)
    let denied = try context.commitDenial(expected: active, reason: .localLogout)
    try await store.removeIfDenied(expected: denied)
    try await store.removeIfDenied(expected: denied)
    #expect(try security.load(scope: scope) == nil)
    let fresh = try context.beginExplicitEnrollment(expected: context.capture(scope: scope))
    let saved = try await store.saveIfAdmitted(admittedCandidate(scope, token: String(repeating: "C", count: 43)), expected: fresh)
    #expect(try await store.loadIfAdmitted(expected: saved) != nil)
}
@Test func credentialAdmissionMarkerFailureAndClearFailureRemainClosed() async throws {
    let root = URL(fileURLWithPath: "/private/tmp").appendingPathComponent(UUID().uuidString)
    defer { chmod(root.path, 0o700); try? FileManager.default.removeItem(at: root) }
    let security = AdmissionMemorySecurity()
    let context = try WorkspaceCredentialAdmissionContext(denialDirectory: root, keychainService: "test.admission", security: security)
    let store = WorkspaceCredentialAdmissionStore(context: context)
    let scope = try WorkspaceCredentialScope(origin: WorkspaceOrigin("https://workspace.example"), profileID: "apple", accountID: UUID())
    let pending = try context.beginExplicitEnrollment(expected: context.capture(scope: scope))
    let active = try await store.saveIfAdmitted(admittedCandidate(scope), expected: pending)
    #expect(chmod(root.path, 0o500) == 0)
    #expect(throws: WorkspaceCredentialAdmissionError.persistenceUnavailable) { try context.commitDenial(expected: active, reason: .localLogout) }
    let failed = try context.capture(scope: scope)
    do { _ = try await store.loadIfAdmitted(expected: failed); Issue.record("Failed marker persistence admitted") }
    catch { #expect(error as? WorkspaceCredentialAdmissionError == .persistenceUnavailable) }
    #expect(chmod(root.path, 0o700) == 0)
    let denied = try context.commitDenial(expected: failed, reason: .localLogout)
    let file = root.appendingPathComponent(AdmissionDenialRepository.filename)
    let bytes = try Data(contentsOf: file)
    let next = try context.beginExplicitEnrollment(expected: denied)
    security.onSave = { _ = chmod(root.path, 0o500) }
    do { _ = try await store.saveIfAdmitted(admittedCandidate(scope, token: String(repeating: "C", count: 43)), expected: next); Issue.record("Failed clear published admission") }
    catch { #expect(error as? WorkspaceCredentialAdmissionError == .persistenceUnavailable) }
    #expect(try Data(contentsOf: file) == bytes)
    #expect(try security.load(scope: scope) == nil)
    #expect(chmod(root.path, 0o700) == 0)
    let restarted = try WorkspaceCredentialAdmissionContext(denialDirectory: root, keychainService: "test.admission", security: security)
    do { _ = try await WorkspaceCredentialAdmissionStore(context: restarted).loadIfAdmitted(expected: restarted.capture(scope: scope)); Issue.record("Cold denial after failed clear ignored") }
    catch { #expect(error as? WorkspaceCredentialAdmissionError == .denied) }
}
@Test func credentialAdmissionSharedServiceRejectsDifferentRootAndKeepsUnrelatedScope() async throws {
    let root = URL(fileURLWithPath: "/private/tmp").appendingPathComponent(UUID().uuidString)
    let other = URL(fileURLWithPath: "/private/tmp").appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: other) }
    let service = "test.shared." + UUID().uuidString
    let shared = try WorkspaceCredentialAdmissionContext.shared(denialDirectory: root, keychainService: service)
    #expect(try WorkspaceCredentialAdmissionContext.shared(denialDirectory: root, keychainService: service) === shared)
    #expect(throws: WorkspaceCredentialAdmissionError.conflictingContext) { try WorkspaceCredentialAdmissionContext.shared(denialDirectory: other, keychainService: service) }
    let security = AdmissionMemorySecurity()
    let context = try WorkspaceCredentialAdmissionContext(denialDirectory: root, keychainService: "test.fake", security: security)
    let store = WorkspaceCredentialAdmissionStore(context: context)
    let origin = try WorkspaceOrigin("https://workspace.example")
    let a = try WorkspaceCredentialScope(origin: origin, profileID: "apple", accountID: UUID())
    let b = try WorkspaceCredentialScope(origin: origin, profileID: "apple", accountID: UUID())
    let activeA = try await store.saveIfAdmitted(admittedCandidate(a), expected: context.beginExplicitEnrollment(expected: context.capture(scope: a)))
    let activeB = try await store.saveIfAdmitted(admittedCandidate(b), expected: context.beginExplicitEnrollment(expected: context.capture(scope: b)))
    _ = try context.commitDenial(expected: activeA, reason: .localLogout)
    #expect(try await store.loadIfAdmitted(expected: activeB)?.credential.accountID == b.accountID)
}
@Test func credentialAdmissionCorruptLinkedAndUnknownLedgersAreRetained() throws {
    let root = URL(fileURLWithPath: "/private/tmp").appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent(AdmissionDenialRepository.filename)
    for text in ["bad", #"{"schemaVersion":1,"schemaVersion":1,"revision":"00000000-0000-4000-8000-000000000001","denials":[]}"#, #"{"schemaVersion":2,"revision":"00000000-0000-4000-8000-000000000001","denials":[]}"#, String(repeating: "x", count: 262145)] {
        let bytes = Data(text.utf8); try bytes.write(to: file); #expect(chmod(file.path, 0o600) == 0)
        #expect(throws: WorkspaceCredentialAdmissionError.invalidDenialState) { try WorkspaceCredentialAdmissionContext(denialDirectory: root, keychainService: "test.fake", security: AdmissionMemorySecurity()) }
        #expect(try Data(contentsOf: file) == bytes)
    }
    try FileManager.default.removeItem(at: file)
    let target = root.appendingPathComponent("untouched")
    try Data("private".utf8).write(to: target)
    try FileManager.default.createSymbolicLink(at: file, withDestinationURL: target)
    #expect(throws: WorkspaceCredentialAdmissionError.invalidDenialState) { try WorkspaceCredentialAdmissionContext(denialDirectory: root, keychainService: "test.fake", security: AdmissionMemorySecurity()) }
    #expect(try Data(contentsOf: target) == Data("private".utf8))
}
#if os(macOS)
@Test func credentialAdmissionFIFORejectedWithinBoundedChildDeadline() async throws {
    let root = URL(fileURLWithPath: "/private/tmp").appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent(AdmissionDenialRepository.filename)
    #expect(mkfifo(file.path, 0o600) == 0)
    let module = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let sources = try FileManager.default.contentsOfDirectory(at: module.appendingPathComponent("Sources/SkriptumWorkspaceClient"), includingPropertiesForKeys: nil).filter { $0.pathExtension == "swift" }.map(\.path).sorted()
    let binary = root.appendingPathComponent("probe")
    let compile = Process(); compile.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    compile.arguments = ["swiftc", "-swift-version", "6", "-parse-as-library"] + sources + [module.appendingPathComponent("Verification/AdmissionFilesystemProbe.swift").path, "-o", binary.path]
    compile.standardOutput = FileHandle.nullDevice; compile.standardError = FileHandle.nullDevice
    try compile.run(); compile.waitUntilExit(); #expect(compile.terminationStatus == 0)
    let child = Process(); child.executableURL = binary; child.arguments = [root.path]
    child.standardOutput = FileHandle.nullDevice; child.standardError = FileHandle.nullDevice
    try child.run()
    for _ in 0..<100 { if !child.isRunning { break }; try await Task.sleep(for: .milliseconds(20)) }
    let timedOut = child.isRunning
    if timedOut { child.terminate() }; child.waitUntilExit()
    #expect(!timedOut)
    #expect(child.terminationStatus == 0)
}
#endif

@Test func credentialAdmissionExternalTokenReplacementCannotBeRemovedByOldDenial() async throws {
    let root = URL(fileURLWithPath: "/private/tmp").appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let security = AdmissionMemorySecurity()
    let context = try WorkspaceCredentialAdmissionContext(denialDirectory: root, keychainService: "test.fake", security: security)
    let store = WorkspaceCredentialAdmissionStore(context: context)
    let scope = try WorkspaceCredentialScope(origin: WorkspaceOrigin("https://workspace.example"), profileID: "apple", accountID: UUID())
    let saved = try await store.saveIfAdmitted(admittedCandidate(scope), expected: context.beginExplicitEnrollment(expected: context.capture(scope: scope)))
    let denied = try context.commitDenial(expected: saved, reason: .unauthorized)
    let file = root.appendingPathComponent(AdmissionDenialRepository.filename), before = try Data(contentsOf: file)
    let replacement = try admittedCandidate(scope, token: String(repeating: "C", count: 43))
    try security.save(replacement.credential, scope: scope)
    do { try await store.removeIfDenied(expected: denied); Issue.record("Old denial erased externally replaced token") }
    catch { #expect(error as? WorkspaceCredentialAdmissionError == .staleTicket) }
    #expect(try security.load(scope: scope)?.token == replacement.credential.token)
    #expect(try Data(contentsOf: file) == before)
}
@Test func credentialAdmissionCapacityDoesNotEvictDurableDenials() throws {
    let root = URL(fileURLWithPath: "/private/tmp").appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: root) }
    let origin = try WorkspaceOrigin("https://workspace.example")
    var ledger = AdmissionDenialLedger()
    for _ in 0..<1024 { ledger.denials.append(AdmissionDenialRecord(scope: try WorkspaceCredentialScope(origin: origin, profileID: "apple", accountID: UUID()), generation: UUID(), reason: .localLogout)) }
    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
    let bytes = try encoder.encode(ledger), file = root.appendingPathComponent(AdmissionDenialRepository.filename)
    try bytes.write(to: file); #expect(chmod(file.path, 0o600) == 0)
    let context = try WorkspaceCredentialAdmissionContext(denialDirectory: root, keychainService: "test.fake", security: AdmissionMemorySecurity())
    let scope = try WorkspaceCredentialScope(origin: origin, profileID: "apple", accountID: UUID())
    let expected = try context.capture(scope: scope)
    #expect(throws: WorkspaceCredentialAdmissionError.capacityExceeded) { try context.beginExplicitEnrollment(expected: expected) }
    #expect(try Data(contentsOf: file) == bytes)
}
@Test func credentialAdmissionSecuritySaveAndSynchronousDenialHaveOneSerialOrder() async throws {
    let root = URL(fileURLWithPath: "/private/tmp").appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let security = AdmissionMemorySecurity()
    let context = try WorkspaceCredentialAdmissionContext(denialDirectory: root, keychainService: "test.fake", security: security)
    let store = WorkspaceCredentialAdmissionStore(context: context)
    let scope = try WorkspaceCredentialScope(origin: WorkspaceOrigin("https://workspace.example"), profileID: "apple", accountID: UUID())
    let pending = try context.beginExplicitEnrollment(expected: context.capture(scope: scope))
    let entered = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0), denialStarted = DispatchSemaphore(value: 0)
    defer { release.signal() }
    security.onSave = { entered.signal(); _ = release.wait(timeout: .now() + 5) }
    let save = Task { try await store.saveIfAdmitted(admittedCandidate(scope), expected: pending) }
    let enteredResult = await admissionWait(entered)
    #expect(enteredResult == .success)
    let deny = Task.detached {
        denialStarted.signal()
        // A current user denial captures under this gate after the earlier
        // in-progress save; an old callback must use its retained old ticket.
        return try context.commitDenial(expected: context.capture(scope: scope), reason: .localLogout)
    }
    let denialResult = await admissionWait(denialStarted)
    #expect(denialResult == .success)
    release.signal()
    let saved = try await save.value, denied = try await deny.value
    do { _ = try await store.loadIfAdmitted(expected: saved); Issue.record("Save survived later denial") }
    catch { #expect(error as? WorkspaceCredentialAdmissionError == .staleTicket) }
    try await store.removeIfDenied(expected: denied)
    #expect(try security.load(scope: scope) == nil)
}

private func admissionWait(_ semaphore: DispatchSemaphore) async -> DispatchTimeoutResult {
    await withCheckedContinuation { continuation in
        DispatchQueue.global().async { continuation.resume(returning: semaphore.wait(timeout: .now() + 3)) }
    }
}
