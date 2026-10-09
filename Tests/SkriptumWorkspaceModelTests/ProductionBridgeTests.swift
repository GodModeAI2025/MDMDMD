import Foundation
import Security
import LocalAuthentication
import Testing
import SkriptumCore
import SkriptumWorkspaceClient
@testable import SkriptumWorkspaceModel

#if SWIFT_PACKAGE && DEBUG
/// This integration spec is opt-in because its owned HTTPS certificate is not
/// platform trusted. A skipped invocation is not bridge execution evidence.
@Test(.enabled(if: ProcessInfo.processInfo.environment["SCRIPTUM_PICKER_BRIDGE_FIXTURE"] != nil))
@MainActor func pickerProductionBridgeFactoryPreservesExactRegistryAndOwnedDocuments() async throws {
    let path = try #require(ProcessInfo.processInfo.environment["SCRIPTUM_PICKER_BRIDGE_FIXTURE"])
    let url = URL(fileURLWithPath: path)
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    let mode = try #require(attributes[.posixPermissions] as? NSNumber).intValue
    try #require(mode & 0o077 == 0, "Owned fixture configuration must be private")
    try #require(attributes[.type] as? FileAttributeType == .typeRegular)
    let fixtureSize = try #require(attributes[.size] as? NSNumber).intValue
    try #require((1...16_384).contains(fixtureSize))
    let data = try Data(contentsOf: url)
    try #require(data.count <= 16_384)
    let fixture = try JSONDecoder().decode(ProductionBridgeFixture.self, from: data)
    let deployment = try WorkspaceDeploymentConfiguration(origin: fixture.origin,
        profileID: fixture.profileID, consentVersion: fixture.consentVersion,
        operatorName: "Owned bridge verification", privacyURL: fixture.origin + "/privacy",
        serviceURL: fixture.origin + "/service", consentDisclosure: "Owned verification only; no document upload.")
    let certificateURL = URL(fileURLWithPath: fixture.certificatePath)
    let certificateAttributes = try FileManager.default.attributesOfItem(atPath: certificateURL.path)
    try #require(certificateAttributes[.type] as? FileAttributeType == .typeRegular)
    let certificateSize = try #require(certificateAttributes[.size] as? NSNumber).intValue
    try #require((1...65_536).contains(certificateSize))
    let anchor = try WorkspaceVerificationTLSAnchor(origin: deployment.origin,
        certificateDER: Data(contentsOf: certificateURL))
    let root = URL(fileURLWithPath: "/private/tmp/ScriptumProductionBridge-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700])
    defer { try? FileManager.default.removeItem(at: root) }
    let documents = root.appendingPathComponent("Documents"), support = root.appendingPathComponent("Support")
    try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: false)
    try FileManager.default.createDirectory(at: support, withIntermediateDirectories: false)
    let store = try LibraryStore(directory: documents.appendingPathComponent("Skriptum"))
    let space = try store.createSpace(title: "Local source")
    _ = try store.createPage(spaceID: space.id, title: "Preserved source", markdown: "e\u{301}\r\n🦊")
    let suite = "test.productionbridge." + UUID().uuidString
    defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
    let library = try WritingLibrary(store: store, documentRoot: documents, supportRoot: support,
        preferences: #require(UserDefaults(suiteName: suite)))
    let libraryFile = store.directory.appendingPathComponent("library.json")
    let original = try Data(contentsOf: libraryFile)
    let registry = try CloudConnectionRegistry()
    // No credential is injected or synthesized: this is the actual Security-backed
    // shared admission context, still signed out until the later signed flow.
    let keychainService = "test.productionbridge." + UUID().uuidString
    defer {
        // A fresh, exclusive service namespace belongs only to this invocation.
        // Cleanup does not enumerate accounts or touch the shipping namespace.
        let authentication = LAContext(); authentication.interactionNotAllowed = true
        let status = SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrSynchronizable as String: false,
            kSecUseDataProtectionKeychain as String: true,
            kSecUseAuthenticationContext as String: authentication
        ] as CFDictionary)
        #expect(status == errSecSuccess || status == errSecItemNotFound)
        if status != errSecSuccess && status != errSecItemNotFound {
            Issue.record("Owned Keychain cleanup status: \(status)")
        }
    }
    let context = try WorkspaceCredentialAdmissionContext.shared(
        denialDirectory: support.appendingPathComponent("Admission"),
        keychainService: keychainService)
    var proofCalls = 0
    let proof = WorkspaceAccountProofAcquisition(authorize: { challenge in
        let result = try await fixture.control("/authorize", body: ["account": "owner", "nonce": challenge.nonce])
        guard let token = result["identityToken"], let code = result["authorizationCode"] else {
            throw WorkspaceClientError.invalidResponse
        }
        return try WorkspaceIdentityProof(identityToken: token, authorizationCode: code, state: challenge.state)
    }, cancel: {})
    let kernel = try WorkspaceAccountCoordinator.configuredForVerification(
        deployment: deployment, context: context, connectionRegistry: registry,
        verificationTLSAnchor: anchor, proofForWindow: { _ in
            proofCalls += 1
            return proof
        })
    let runtime = try WorkspaceAccountRuntime(deployment: deployment, coordinator: kernel,
        connectionRegistry: registry, proofForWindow: { _ in
            proofCalls += 1
            return proof
        })
    #expect(runtime.connectionRegistry === registry)
    let window = UUID(), locator = try runtime.register(windowID: window, library: library)
    #expect(locator == (try library.ownedWindowLocator()))
    #expect(kernel.state(windowID: window) == .signedOut)
    #expect(proofCalls == 0)
    #expect(try Data(contentsOf: libraryFile) == original)
    #expect(try library.cloudBindingRepository().load() == nil)
    try runtime.acknowledgeOperator(windowID: window)
    #expect(await runtime.signIn(windowID: window, expectedLocator: locator) == .completed)
    guard case .active(let scope, _, _) = kernel.state(windowID: window) else {
        Issue.record("Actual signed enrollment did not activate the account: \(kernel.state(windowID: window))"); return
    }
    let credentialScope = try WorkspaceCredentialScope(origin: deployment.origin,
        profileID: deployment.profileID, accountID: scope.accountID)
    let ticket = try context.capture(scope: credentialScope)
    let stored = try await WorkspaceCredentialAdmissionStore(context: context).loadIfAdmitted(expected: ticket)
    #expect(stored != nil)
    let seeded = try await fixture.control("/bootstrap", body: ["accountID": scope.accountID.uuidString.lowercased()])
    let remoteString = try #require(seeded["libraryID"])
    let remoteID = try #require(UUID(uuidString: remoteString))
    let facade = library.libraryIdentity, consumer = UUID()
    try runtime.beginLibraryConsumer(windowID: window, expectedLocator: locator, expectedFacadeID: facade, consumerID: consumer)
    let pickerValue = try runtime.pickerPresentation(windowID: window, expectedLocator: locator, expectedFacadeID: facade)
    let picker = try #require(pickerValue)
    await runtime.loadLibraries(windowID: window, expectedLocator: locator, expectedFacadeID: facade, consumerID: consumer)
    #expect(picker.rows.map(\.libraryID) == [remoteID])
    #expect(await runtime.associateLibrary(id: remoteID, windowID: window, expectedLocator: locator,
        expectedFacadeID: facade, consumerID: consumer) == .associated)
    let bindingValue = try library.cloudBindingRepository().load()
    let binding = try #require(bindingValue)
    #expect(binding.remoteLibraryID == remoteID && binding.accountID == scope.accountID)
    #expect(binding.origin == fixture.origin && binding.profileID == fixture.profileID)
    #expect(try Data(contentsOf: libraryFile) == original)
    #expect(await runtime.logout(windowID: window, expectedLocator: locator, allSessions: true) == .completed)
    #expect(await runtime.associateLibrary(id: remoteID, windowID: window, expectedLocator: locator,
        expectedFacadeID: facade, consumerID: consumer) == .unavailable)
    #expect(try Data(contentsOf: libraryFile) == original)
    runtime.detach(windowID: window)
}

private struct ProductionBridgeFixture: Decodable {
    let origin: String
    let profileID: String
    let consentVersion: String
    let certificatePath: String
    let controlOrigin: String
    let controlSecret: String

    func control(_ path: String, body: [String: String]) async throws -> [String: String] {
        let origin = try WorkspaceOrigin.loopbackForTesting(controlOrigin)
        let components = try #require(URLComponents(url: origin.url, resolvingAgainstBaseURL: false))
        try #require(components.scheme == "http" && components.host == "127.0.0.1" && components.port != nil)
        var request = URLRequest(url: try #require(URL(string: origin.url.absoluteString + path)))
        request.httpMethod = "POST"; request.timeoutInterval = 5
        request.setValue("Bearer " + controlSecret, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCredentialStorage = nil; configuration.httpCookieStorage = nil
        let session = URLSession(configuration: configuration, delegate: ProductionBridgeControlDelegate(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request)
        try #require((response as? HTTPURLResponse)?.statusCode == 200 && data.count <= 16_384)
        return try JSONDecoder().decode([String: String].self, from: data)
    }
}

private final class ProductionBridgeControlDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        completionHandler(.cancelAuthenticationChallenge, nil)
    }
}
#endif
