import Foundation
import Testing
import SkriptumCore
import SkriptumWorkspaceClient
@testable import SkriptumWorkspaceModel

#if SWIFT_PACKAGE && DEBUG
/// This integration spec is opt-in because its owned HTTPS certificate is not
/// platform trusted. A skipped invocation is not bridge execution evidence.
@Test(.enabled(if: ProcessInfo.processInfo.environment["SCRIPTUM_PICKER_BRIDGE_FIXTURE"] != nil))
@MainActor func pickerProductionBridgeFactoryPreservesExactRegistryAndOwnedDocuments() throws {
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
    let context = try WorkspaceCredentialAdmissionContext.shared(
        denialDirectory: support.appendingPathComponent("Admission"),
        keychainService: "test.productionbridge." + UUID().uuidString)
    var proofCalls = 0
    let kernel = try WorkspaceAccountCoordinator.configuredForVerification(
        deployment: deployment, context: context, connectionRegistry: registry,
        verificationTLSAnchor: anchor, proofForWindow: { _ in
            proofCalls += 1
            throw WorkspaceAccountRuntimeError.presentationUnavailable
        })
    let runtime = try WorkspaceAccountRuntime(deployment: deployment, coordinator: kernel,
        connectionRegistry: registry, proofForWindow: { _ in
            proofCalls += 1
            throw WorkspaceAccountRuntimeError.presentationUnavailable
        })
    #expect(runtime.connectionRegistry === registry)
    let window = UUID(), locator = try runtime.register(windowID: window, library: library)
    #expect(locator == (try library.ownedWindowLocator()))
    #expect(kernel.state(windowID: window) == .signedOut)
    #expect(proofCalls == 0)
    #expect(try Data(contentsOf: libraryFile) == original)
    #expect(try library.cloudBindingRepository().load() == nil)
    runtime.detach(windowID: window)
}

private struct ProductionBridgeFixture: Decodable {
    let origin: String
    let profileID: String
    let consentVersion: String
    let certificatePath: String
}
#endif
