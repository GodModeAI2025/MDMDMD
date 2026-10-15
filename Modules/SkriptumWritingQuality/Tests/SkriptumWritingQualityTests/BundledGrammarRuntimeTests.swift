import Foundation
import Testing
@testable import SkriptumWritingQuality

private struct GrammarAssetFixture {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let resource = "org/languagetool/resource/test.txt"
    let content = Data("Grüße e\u{301} 🦊\r\n".utf8)
    init() throws {
        let file = root.appendingPathComponent(resource)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: file)
    }
    func remove() { try? FileManager.default.removeItem(at: root) }
    func manifest(paths: [String]? = nil, engine: String = "LanguageTool", version: String = "6.6") throws -> GrammarResourcePin {
        let paths = paths ?? [resource]
        let data = try JSONSerialization.data(withJSONObject: ["engine": engine, "version": version,
            "resources": paths.map { ["path": $0, "bytes": content.count, "sha256": GrammarResourceVerifier.digest(content)] as [String: Any] }])
        try data.write(to: root.appendingPathComponent("manifest.json"))
        return GrammarResourcePin(manifestSHA256: GrammarResourceVerifier.digest(data), files: paths.count, bytes: paths.count * content.count)
    }
}

struct BundledGrammarRuntimeTests {
    @Test func completeResourceBytesAndPinnedManifestAreRequired() throws {
        let fixture = try GrammarAssetFixture(); defer { fixture.remove() }
        let pin = try fixture.manifest()
        #expect(try GrammarResourceVerifier.verify(root: fixture.root, pin: pin) == fixture.root.resolvingSymlinksInPath())
        let file = fixture.root.appendingPathComponent(fixture.resource)
        var corrupt = fixture.content; corrupt[0] ^= 1
        try corrupt.write(to: file)
        #expect(throws: BundledGrammarError.invalidResources) { try GrammarResourceVerifier.verify(root: fixture.root, pin: pin) }
        try fixture.content.write(to: file)
        try Data("{}".utf8).write(to: fixture.root.appendingPathComponent("manifest.json"))
        #expect(throws: BundledGrammarError.invalidResources) { try GrammarResourceVerifier.verify(root: fixture.root, pin: pin) }
    }

    @Test func unsafeDuplicateAndAliasedPathsCannotBecomeVerifiedAssets() throws {
        let fixture = try GrammarAssetFixture(); defer { fixture.remove() }
        for paths in [["../outside"], ["org/languagetool/../outside"], ["/org/languagetool/file"],
                      ["org/languagetool//file"], ["org/languagetool/./file"],
                      [fixture.resource, fixture.resource], [fixture.resource, "org/languagetool/resource/TEST.txt"]] {
            let pin = try fixture.manifest(paths: paths)
            #expect(throws: BundledGrammarError.invalidResources) { try GrammarResourceVerifier.verify(root: fixture.root, pin: pin) }
        }
        let pin = try fixture.manifest()
        #expect(throws: BundledGrammarError.invalidResources) { try GrammarResourceVerifier.verify(root: URL(string: "https://example.invalid")!, pin: pin) }
    }

    @Test func resourceAndManifestSymlinksAreRejectedEvenWhenBytesMatch() throws {
        let fixture = try GrammarAssetFixture(); defer { fixture.remove() }
        let pin = try fixture.manifest()
        let file = fixture.root.appendingPathComponent(fixture.resource), target = fixture.root.appendingPathComponent("target")
        try FileManager.default.moveItem(at: file, to: target)
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: target)
        #expect(throws: BundledGrammarError.invalidResources) { try GrammarResourceVerifier.verify(root: fixture.root, pin: pin) }
        try FileManager.default.removeItem(at: file)
        try FileManager.default.moveItem(at: target, to: file)
        let manifest = fixture.root.appendingPathComponent("manifest.json"), actual = fixture.root.appendingPathComponent("actual-manifest.json")
        try FileManager.default.moveItem(at: manifest, to: actual)
        try FileManager.default.createSymbolicLink(at: manifest, withDestinationURL: actual)
        #expect(throws: BundledGrammarError.invalidResources) { try GrammarResourceVerifier.verify(root: fixture.root, pin: pin) }
    }

    @Test func engineIdentityResourceCountsAndTotalsMustMatch() throws {
        let fixture = try GrammarAssetFixture(); defer { fixture.remove() }
        for (engine, version) in [("Other", "6.6"), ("LanguageTool", "6.5")] {
            let pin = try fixture.manifest(engine: engine, version: version)
            #expect(throws: BundledGrammarError.invalidResources) { try GrammarResourceVerifier.verify(root: fixture.root, pin: pin) }
        }
        let pin = try fixture.manifest()
        for wrong in [GrammarResourcePin(manifestSHA256: pin.manifestSHA256, files: 2, bytes: pin.bytes),
                      GrammarResourcePin(manifestSHA256: pin.manifestSHA256, files: 1, bytes: pin.bytes - 1),
                      GrammarResourcePin(manifestSHA256: pin.manifestSHA256, files: 1, bytes: pin.bytes + 1)] {
            #expect(throws: BundledGrammarError.invalidResources) { try GrammarResourceVerifier.verify(root: fixture.root, pin: wrong) }
        }
    }

    @Test func unavailableRuntimeDoesNotStartAnotherEngine() async {
        #if canImport(ScriptumGrammar)
        await #expect(throws: BundledGrammarError.invalidResources) { try await BundledGrammarRuntime.load(resourceBundleURL: nil) }
        #else
        #expect(!BundledGrammarRuntime.isLinked)
        await #expect(throws: BundledGrammarError.notInstalled) { try await BundledGrammarRuntime.load(resourceBundleURL: nil) }
        #endif
    }

    @Test @MainActor func spellingOnlyDoesNotAddStyleOrRequestSystemGrammar() async throws {
        let document = QualityDocument(source: "Text Text.", revision: UUID())
        let findings = try await NativeWritingReviewer.check(document, includingGrammarAndStyle: false)
        #expect(findings.isEmpty)
    }
}
