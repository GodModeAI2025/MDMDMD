import Foundation
import Testing
@testable import SkriptumWritingQuality
@Test func r14_projectionProtectsMarkdownAndUTF16() throws {
    let source = "# Grüße 🦊\n\nNormal **Wort** [Text](https://example.org/a) `coode`\n\n```swift\nwrong wrong\n```\n"
    let projection = MarkdownProjection(source)
    #expect((projection.text as NSString).length == (source as NSString).length)
    #expect(projection.text.contains("Grüße 🦊"))
    #expect(!projection.text.contains("https://"))
    #expect(!projection.text.contains("coode"))
    #expect(!projection.text.contains("wrong wrong"))
    #expect(!projection.text.contains("**"))
    let doc = QualityDocument(source: source, revision: UUID())
    let url = (source as NSString).range(of: "https://example.org/a")
    #expect(throws: QualityError.self) { try QualityFinding.make(document: doc, range: url, message: "x", replacements: ["new"], ruleID: "x", kind: .grammar, engine: "test") }
    let normal = (source as NSString).range(of: "Normal")
    let finding = try QualityFinding.make(document: doc, range: normal, message: "x", replacements: ["Gut"], ruleID: "x", kind: .style, engine: "test")
    #expect(try finding.applying("Gut", to: doc).contains("Gut **Wort**"))
    #expect(throws: QualityError.self) { try finding.applying("Gut", to: QualityDocument(source: source, revision: UUID())) }
    #expect(throws: QualityError.self) { try finding.applying("unoffered", to: doc) }
    let emoji = (source as NSString).range(of: "🦊")
    #expect(throws: QualityError.self) { try QualityFinding.make(document: doc, range: NSRange(location: emoji.location + 1, length: 1), message: "x", replacements: ["x"], ruleID: "x", kind: .grammar, engine: "test") }
}
@Test func r14_basicStyleOnlyAndProtectedCorrection() throws {
    let doc = QualityDocument(source: "Das ist ist gut.\n\n`bad bad`\n", revision: UUID())
    let findings = LocalStyleReviewer.check(doc)
    #expect(findings.count == 1)
    #expect(findings.allSatisfy { $0.engine == "Lokale Basis-Stilregeln" && $0.kind == .style })
    #expect(try findings[0].applying("", to: doc) == "Das ist gut.\n\n`bad bad`\n")
}
@Test func r14_engineCatalogDistinctLanguages() throws {
    let languages = [QualityLanguage(name: "English", code: "en", longCode: "en-US"), QualityLanguage(name: "English", code: "en", longCode: "en-GB"), QualityLanguage(name: "German", code: "de", longCode: "de-DE")]
    #expect(LanguageCatalog(languages).distinctLanguageCount == 2)
    #expect(throws: QualityError.self) { try LanguageToolConfiguration(endpoint: URL(string: "http://example.org/v2")!) }
    #expect(throws: QualityError.self) { try LanguageToolConfiguration(endpoint: URL(string: "https://user:pass@example.org/v2")!) }
}
@Test func r14_languageToolOffsetsAndRulesValidated() throws {
    let doc = QualityDocument(source: "A 🦊 an test.", revision: UUID())
    let good = Data("{\"matches\":[{\"offset\":5,\"length\":2,\"message\":\"Article\",\"replacements\":[{\"value\":\"a\"}],\"rule\":{\"id\":\"ARTICLE\",\"issueType\":\"grammar\",\"category\":{\"id\":\"GRAMMAR\",\"name\":\"Grammar\"}}}]}".utf8)
    let findings = try LanguageToolClient.decode(good, document: doc)
    #expect(findings.count == 1)
    #expect(try findings[0].applying("a", to: doc) == "A 🦊 a test.")
    let bad = Data("{\"matches\":[{\"offset\":999,\"length\":2,\"message\":\"x\",\"replacements\":[],\"rule\":{\"id\":\"X\",\"issueType\":\"grammar\",\"category\":{\"id\":\"G\",\"name\":\"G\"}}}]}".utf8)
    #expect(throws: QualityError.self) { try LanguageToolClient.decode(bad, document: doc) }
}
@Test func r14_variantsNeverInflateCoverage() {
    #expect(LanguageCatalog([QualityLanguage(name: "German", code: "de", longCode: "de-DE"), QualityLanguage(name: "Simplified German", code: "de-DE-x-simple-language", longCode: "de-DE-x-simple-language")]).distinctLanguageCount == 1)
}
@Test func r14_bytesAndMarkupInsertionRemainSafe() throws {
    let doc = QualityDocument(source: "é safe", revision: UUID())
    let finding = try QualityFinding.make(document: doc, range: NSRange(location: 2, length: 4), message: "x", replacements: ["**bad**", "good"], ruleID: "TEST", kind: .grammar, engine: "test")
    #expect(throws: QualityError.protectedSyntax) { try finding.applying("**bad**", to: doc) }
    #expect(throws: QualityError.staleSource) { try finding.applying("good", to: QualityDocument(source: "e\u{301} safe", revision: doc.revision)) }
}
@Test func r14_oversizedTextFailsBeforeTransmission() async throws {
    let client = LanguageToolClient(configuration: try LanguageToolConfiguration(endpoint: URL(string: "https://unused.invalid/v2")!))
    await #expect(throws: QualityError.inputTooLarge) { try await client.check(QualityDocument(source: String(repeating: "x", count: 100_001), revision: UUID()), language: "en-US") }
}
