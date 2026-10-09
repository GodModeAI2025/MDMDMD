import Foundation
import Testing
import SkriptumCore
import SkriptumWorkspaceClient
@testable import SkriptumWorkspaceModel

private func runtimeInfo(version: String = "v1") -> [String: Any] {
    ["ScriptumWorkspaceDeployment": ["configured": true, "origin": "https://workspace.example", "profileID": "apple", "consentVersion": version, "operatorName": "Owned operator", "privacyURL": "https://workspace.example/privacy", "serviceURL": "https://workspace.example/service", "consentDisclosure": "Cloud use requires explicit consent."]]
}
@Test func workspaceRuntimeLoaderDistinguishesMissingMalformedAndExplicitConfig() throws {
    if case .notConfigured = WorkspaceDeploymentBundleLoader.load(infoDictionary: [:]) {} else { Issue.record("Missing deployment inferred") }
    if case .notConfigured = WorkspaceDeploymentBundleLoader.load(infoDictionary: ["ScriptumWorkspaceDeployment": ["configured": false]]) {} else { Issue.record("Disabled deployment inferred") }
    if case .configured(let value) = WorkspaceDeploymentBundleLoader.load(infoDictionary: runtimeInfo()) { #expect(value.profileID == "apple") } else { Issue.record("Valid exact configuration rejected") }
    var info = runtimeInfo(), values = try #require(info["ScriptumWorkspaceDeployment"] as? [String: Any])
    values["debugToken"] = "not-allowed"; info["ScriptumWorkspaceDeployment"] = values
    if case .unavailable = WorkspaceDeploymentBundleLoader.load(infoDictionary: info) {} else { Issue.record("Unknown config fields accepted") }
    values.removeValue(forKey: "debugToken"); values["configured"] = 1; info["ScriptumWorkspaceDeployment"] = values
    if case .unavailable = WorkspaceDeploymentBundleLoader.load(infoDictionary: info) {} else { Issue.record("Numeric boolean accepted") }
}
@Test @MainActor func workspaceRuntimeUnconfiguredCreatesNoRootOrProofAndPreservesLibrary() throws {
    let root = URL(fileURLWithPath: "/private/tmp").appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let support = root.appendingPathComponent("UnusedSupport")
    var proofCalls = 0
    let runtime = WorkspaceAccountRuntime(configuration: .notConfigured, systemSupportRoot: support, keychainService: "test.runtime." + UUID().uuidString, proofForWindow: { _ in proofCalls += 1; throw WorkspaceAccountRuntimeError.presentationUnavailable })
    #expect(runtime.availability == .notConfigured)
    #expect(!FileManager.default.fileExists(atPath: support.path))
    #expect(proofCalls == 0)
}
private struct RuntimeLibraryFixture {
    let library: WritingLibrary; let documents: URL; let support: URL; let suite: String
    @MainActor init(root: URL) throws {
        documents = root.appendingPathComponent("Documents"); support = root.appendingPathComponent("Support")
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let store = try LibraryStore(directory: documents.appendingPathComponent("Skriptum"))
        let space = try store.createSpace(title: "Local"); _ = try store.createPage(spaceID: space.id, title: "Unchanged", markdown: "e\u{301}\r\n🦊")
        suite = "test.runtime." + UUID().uuidString
        library = try WritingLibrary(store: store, documentRoot: documents, supportRoot: support, preferences: #require(UserDefaults(suiteName: suite)))
    }
}
@Test @MainActor func workspaceRuntimeRestorationRequiresExactOperatorAcknowledgement() async throws {
    let root = URL(fileURLWithPath: "/private/tmp").appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let fixture = try RuntimeLibraryFixture(root: root); defer { UserDefaults.standard.removePersistentDomain(forName: fixture.suite) }
    let repository = try fixture.library.cloudBindingRepository()
    let binding = try CloudLibraryBinding(locator: repository.locator, origin: "https://workspace.example", profileID: "apple", accountID: UUID(), remoteLibraryID: UUID())
    try repository.save(binding, replacing: nil)
    let bytes = try Data(contentsOf: fixture.library.store!.directory.appendingPathComponent("library.json"))
    let runtime = WorkspaceAccountRuntime(configuration: WorkspaceDeploymentBundleLoader.load(infoDictionary: runtimeInfo()), systemSupportRoot: fixture.support, keychainService: "test.runtime." + UUID().uuidString, proofForWindow: { _ in throw WorkspaceAccountRuntimeError.presentationUnavailable })
    let window = UUID(); try runtime.register(windowID: window, library: fixture.library)
    #expect(await runtime.restore(windowID: window) == .consentRequired)
    #expect(runtime.isOperatorAcknowledged(windowID: window) == false)
    try runtime.acknowledgeOperator(windowID: window)
    #expect(runtime.isOperatorAcknowledged(windowID: window))
    let changed = WorkspaceAccountRuntime(configuration: WorkspaceDeploymentBundleLoader.load(infoDictionary: runtimeInfo(version: "v2")), systemSupportRoot: fixture.support, keychainService: "test.runtime." + UUID().uuidString, proofForWindow: { _ in throw WorkspaceAccountRuntimeError.presentationUnavailable })
    try changed.register(windowID: window, library: fixture.library)
    #expect(await changed.restore(windowID: window) == .consentRequired)
    #expect(try Data(contentsOf: fixture.library.store!.directory.appendingPathComponent("library.json")) == bytes)
}
@Test @MainActor func workspaceRuntimePrivateSupportParentsRejectLinkedInteriors() throws {
    let root = URL(fileURLWithPath: "/private/tmp").appendingPathComponent(UUID().uuidString)
    let outside = URL(fileURLWithPath: "/private/tmp").appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: outside) }
    let linked = root.appendingPathComponent("LinkedSupport")
    try FileManager.default.createSymbolicLink(at: linked, withDestinationURL: outside)
    let runtime = WorkspaceAccountRuntime(configuration: WorkspaceDeploymentBundleLoader.load(infoDictionary: runtimeInfo()), systemSupportRoot: linked, keychainService: "test.runtime." + UUID().uuidString, proofForWindow: { _ in throw WorkspaceAccountRuntimeError.presentationUnavailable })
    #expect(runtime.availability == .storageUnavailable)
    #expect(try FileManager.default.contentsOfDirectory(atPath: outside.path).isEmpty)
}

@Test func workspaceRuntimeMalformedTopLevelAndRowsFailClosed() throws {
    for supplied: Any in ["not-a-dictionary", [true], ["configured": "true"], ["configured": false, "origin": "https://hidden.example"], ["configured": true], ["configured": NSNull()]] {
        if case .unavailable = WorkspaceDeploymentBundleLoader.load(infoDictionary: ["ScriptumWorkspaceDeployment": supplied]) {} else { Issue.record("Malformed deployment became configured") }
    }
}
@Test @MainActor func workspaceRuntimeFacadeReplacementFencesOldInspectorActions() async throws {
    let root = URL(fileURLWithPath: "/private/tmp").appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let fixture = try RuntimeLibraryFixture(root: root); defer { UserDefaults.standard.removePersistentDomain(forName: fixture.suite) }
    let store = try #require(fixture.library.store)
    let replacement = try WritingLibrary(store: store, documentRoot: fixture.documents, supportRoot: fixture.support, preferences: #require(UserDefaults(suiteName: fixture.suite)))
    var proofCalls = 0
    let runtime = WorkspaceAccountRuntime(configuration: WorkspaceDeploymentBundleLoader.load(infoDictionary: runtimeInfo()), systemSupportRoot: fixture.support, keychainService: "test.runtime." + UUID().uuidString, proofForWindow: { _ in proofCalls += 1; throw WorkspaceAccountRuntimeError.presentationUnavailable })
    let window = UUID(), locator = try runtime.register(windowID: window, library: fixture.library), oldID = fixture.library.libraryIdentity
    try runtime.acknowledgeOperator(windowID: window, expectedLocator: locator, expectedFacadeID: oldID)
    _ = try runtime.register(windowID: window, library: replacement)
    #expect(try replacement.ownedWindowLocator() == locator)
    #expect(runtime.isOperatorAcknowledged(windowID: window, expectedLocator: locator, expectedFacadeID: oldID) == false)
    #expect(throws: WorkspaceAccountRuntimeError.staleRegistration) { try runtime.acknowledgeOperator(windowID: window, expectedLocator: locator, expectedFacadeID: oldID) }
    #expect(await runtime.signIn(windowID: window, expectedLocator: locator, expectedFacadeID: oldID) == .consentRequired)
    #expect(await runtime.restore(windowID: window, expectedLocator: locator, expectedFacadeID: oldID) == .consentRequired)
    #expect(proofCalls == 0)
}
@Test @MainActor func workspaceRuntimeChangedOriginAndProfileNeedNewAcknowledgementAndWrongBindingDoesNotRegister() async throws {
    let root = URL(fileURLWithPath: "/private/tmp").appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let fixture = try RuntimeLibraryFixture(root: root); defer { UserDefaults.standard.removePersistentDomain(forName: fixture.suite) }
    let repository = try fixture.library.cloudBindingRepository()
    let wrong = try CloudLibraryBinding(locator: repository.locator, origin: "https://other.example", profileID: "different", accountID: UUID(), remoteLibraryID: UUID())
    try repository.save(wrong, replacing: nil)
    let runtime = WorkspaceAccountRuntime(configuration: WorkspaceDeploymentBundleLoader.load(infoDictionary: runtimeInfo()), systemSupportRoot: fixture.support, keychainService: "test.runtime." + UUID().uuidString, proofForWindow: { _ in throw WorkspaceAccountRuntimeError.presentationUnavailable })
    let window = UUID(); try runtime.register(windowID: window, library: fixture.library)
    try runtime.acknowledgeOperator(windowID: window)
    #expect(await runtime.restore(windowID: window) == .unavailable)
    #expect(try runtime.presentation(windowID: window).state == .signedOut)
    for field in ["origin", "profileID"] {
        var info = runtimeInfo(), row = try #require(info["ScriptumWorkspaceDeployment"] as? [String: Any])
        row[field] = field == "origin" ? "https://other.example" : "other-profile"; info["ScriptumWorkspaceDeployment"] = row
        let changed = WorkspaceAccountRuntime(configuration: WorkspaceDeploymentBundleLoader.load(infoDictionary: info), systemSupportRoot: fixture.support, keychainService: "test.runtime." + UUID().uuidString, proofForWindow: { _ in throw WorkspaceAccountRuntimeError.presentationUnavailable })
        try changed.register(windowID: window, library: fixture.library)
        #expect(await changed.restore(windowID: window) == .consentRequired)
    }
}

#if SWIFT_PACKAGE && DEBUG
private struct RuntimeCleanupTicket: WorkspaceAccountAdmissionTicket {}
@MainActor private final class RuntimeCleanupAdmission: WorkspaceAccountAdmission {
    var failRemove = true; var removals = 0
    let credential: WorkspaceCredential
    init(credential: WorkspaceCredential) { self.credential = credential }
    func capture(scope: WorkspaceAccountScope) throws -> any WorkspaceAccountAdmissionTicket { RuntimeCleanupTicket() }
    func beginEnrollment(expected: any WorkspaceAccountAdmissionTicket) throws -> any WorkspaceAccountAdmissionTicket { expected }
    func deny(expected: any WorkspaceAccountAdmissionTicket, reason: WorkspaceAccountDenialReason) throws -> any WorkspaceAccountAdmissionTicket { expected }
    func load(expected: any WorkspaceAccountAdmissionTicket) async throws -> WorkspaceAccountLoadedCredential? { .init(credential: credential, ticket: expected) }
    func remove(expected: any WorkspaceAccountAdmissionTicket) async throws { removals += 1; if failRemove { throw WorkspaceAccountAdmissionFailure.unavailable } }
}
@MainActor private final class RuntimeCleanupDriver: WorkspaceAccountIdentityDriver {
    let session: WorkspaceAccountVerifiedSession
    var deletes = 0
    init(account: UUID) { session = .init(accountID: account, sessionID: UUID(), expiresAt: Date().addingTimeInterval(3600)) }
    func restore() async throws -> WorkspaceAccountVerifiedSession { session }
    func enroll() async throws -> WorkspaceAccountVerifiedSession { session }
    func save(expected: any WorkspaceAccountAdmissionTicket) async throws -> any WorkspaceAccountAdmissionTicket { expected }
    func discardEnrollment() async -> WorkspaceLogoutOutcome { .confirmedRemoteRevocation }
    func logout(allSessions: Bool) async -> WorkspaceLogoutOutcome { .confirmedRemoteRevocation }
    func deleteFreshEnrollment() async throws -> WorkspaceAccountDeletionOutcome { deletes += 1; return .confirmedAccountTombstone }
    func invalidate() async {}
    func cancelProof() {}
}
@Test @MainActor func workspaceRuntimeRetriesActualPendingDeletionCleanupWithoutAnotherDelete() async throws {
    let root = URL(fileURLWithPath: "/private/tmp").appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let fixture = try RuntimeLibraryFixture(root: root); defer { UserDefaults.standard.removePersistentDomain(forName: fixture.suite) }
    guard case .configured(let deployment) = WorkspaceDeploymentBundleLoader.load(infoDictionary: runtimeInfo()) else { throw WorkspaceAccountRuntimeError.wrongDeployment }
    let account = UUID(), scope = try WorkspaceAccountScope(origin: deployment.origin, profileID: deployment.profileID, accountID: account)
    let credential = try WorkspaceCredential(origin: deployment.origin, accountID: account, token: String(repeating: "A", count: 43), profileID: deployment.profileID)
    let admission = RuntimeCleanupAdmission(credential: credential), driver = RuntimeCleanupDriver(account: account)
    let coordinator = try WorkspaceAccountCoordinator(deployment: deployment, admission: admission, makeIdentity: { _, _ in driver })
    let runtime = try WorkspaceAccountRuntime(deployment: deployment, coordinator: coordinator, proofForWindow: { _ in .init(authorize: { _ in throw WorkspaceAccountRuntimeError.presentationUnavailable }, cancel: {}) })
    let window = UUID(), locator = try runtime.register(windowID: window, library: fixture.library), facade = fixture.library.libraryIdentity
    try runtime.acknowledgeOperator(windowID: window, expectedLocator: locator, expectedFacadeID: facade)
    try coordinator.attach(windowID: window, scope: scope); await coordinator.restore(windowID: window)
    _ = await runtime.deleteAccount(windowID: window, expectedLocator: locator, expectedFacadeID: facade)
    #expect(coordinator.state(windowID: window) == .unavailable(.localSignOutPersistenceUnavailable))
    #expect(driver.deletes == 1)
    let before = admission.removals
    admission.failRemove = false
    #expect(await runtime.retryDeletionLocalCleanup(windowID: window, expectedLocator: locator, expectedFacadeID: facade) == .completed)
    #expect(admission.removals == before + 1)
    #expect(driver.deletes == 1)
}
#endif
