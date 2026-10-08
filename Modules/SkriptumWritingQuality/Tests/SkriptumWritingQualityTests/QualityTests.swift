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
@Test func r14_correctionsCannotCreateMarkdownStructure() throws {
    let source = "Before 🦊\n\nplain line\n\nAfter e\u{301} **kept**\n"
    let doc = QualityDocument(source: source, revision: UUID())
    let range = (source as NSString).range(of: "plain line")
    for replacement in ["# Title", "- word", "+ word", "1. word", "2) word", "---", "===", "    code", "\tcode", " \tcode"] {
        let finding = try QualityFinding.make(document: doc, range: range, message: "x", replacements: [replacement], ruleID: "STRUCTURE", kind: .grammar, engine: "test")
        #expect(throws: QualityError.protectedSyntax) { try finding.applying(replacement, to: doc) }
    }
    for replacement in ["well-written line", "plain line!", "A title: yes."] {
        let finding = try QualityFinding.make(document: doc, range: range, message: "x", replacements: [replacement], ruleID: "PROSE", kind: .grammar, engine: "test")
        let expected = "Before 🦊\n\n" + replacement + "\n\nAfter e\u{301} **kept**\n"
        #expect(try Array(finding.applying(replacement, to: doc).utf8) == Array(expected.utf8))
    }
}
@Test func r14_boundaryDeletionCannotActivateExistingMarker() throws {
    let doc = QualityDocument(source: "prefix - word", revision: UUID())
    let finding = try QualityFinding.make(document: doc, range: NSRange(location: 0, length: 7), message: "x", replacements: [""], ruleID: "BOUNDARY", kind: .grammar, engine: "test")
    #expect(throws: QualityError.protectedSyntax) { try finding.applying("", to: doc) }
}
@Test func r14_setextStructureCannotBeChangedByDeletingTitle() throws {
    let doc = QualityDocument(source: "Title\n---\n", revision: UUID())
    let finding = try QualityFinding.make(document: doc, range: NSRange(location: 0, length: 5), message: "x", replacements: [""], ruleID: "SETEXT", kind: .grammar, engine: "test")
    #expect(throws: QualityError.protectedSyntax) { try finding.applying("", to: doc) }
}
@Test func r14_singleCharacterSetextPrefixCannotBeCreated() throws {
    let doc = QualityDocument(source: "Paragraph\nplain", revision: UUID())
    let finding = try QualityFinding.make(document: doc, range: NSRange(location: 10, length: 5), message: "x", replacements: ["=", "-"], ruleID: "SETEXT", kind: .grammar, engine: "test")
    #expect(throws: QualityError.protectedSyntax) { try finding.applying("=", to: doc) }
    #expect(throws: QualityError.protectedSyntax) { try finding.applying("-", to: doc) }
}
@Test func r14_nativeCallbackTimeoutIsErrorAndLateCompletionIgnored() async throws {
    let gate = GrammarContinuationGate(timeoutNanoseconds: 1_000_000)
    await #expect(throws: QualityError.nativeGrammarTimeout) {
        let _: [QualityFinding] = try await withCheckedThrowingContinuation { gate.install($0) }
    }
    gate.finish([])
    gate.cancel()
}
@Test func r14_nativeCallbackCancelBeforeInstallAndCompletionOnce() async throws {
    let cancelled = GrammarContinuationGate(timeoutNanoseconds: 1_000_000)
    cancelled.cancel()
    await #expect(throws: CancellationError.self) {
        let _: [QualityFinding] = try await withCheckedThrowingContinuation { cancelled.install($0) }
    }
    let gate = GrammarContinuationGate(timeoutNanoseconds: 1_000_000)
    let result: [QualityFinding] = try await withCheckedThrowingContinuation { continuation in
        gate.install(continuation); gate.finish([]); gate.finish([]); gate.cancel()
    }
    #expect(result.isEmpty)
    try await Task.sleep(nanoseconds: 2_000_000)
}
@Test func r14_boundaryWhitespaceCannotActivateInlineMarkup() throws {
    let doc = QualityDocument(source: "Before * bold * after", revision: UUID())
    let finding = try QualityFinding.make(document: doc, range: NSRange(location: 8, length: 6), message: "x", replacements: ["bold"], ruleID: "INLINE", kind: .grammar, engine: "test")
    #expect(throws: QualityError.protectedSyntax) { try finding.applying("bold", to: doc) }
}
@Test func r14_emptyMarkdownListMarkersCannotBeCreated() throws {
    let doc = QualityDocument(source: "plain", revision: UUID())
    for replacement in ["+", "1.", "2)", "#"] {
        let finding = try QualityFinding.make(document: doc, range: NSRange(location: 0, length: 5), message: "x", replacements: [replacement], ruleID: "EMPTY_LIST", kind: .grammar, engine: "test")
        #expect(throws: QualityError.protectedSyntax) { try finding.applying(replacement, to: doc) }
    }
}
@Test func r14_containerFencesProtectCode() throws {
    for source in ["> ~~~\n> teh\n> ~~~\n", "- ~~~\n  teh\n  ~~~\n", "> - ```swift\n>   teh\n>   ```\n", "1. ~~~\n   teh\n   ~~~\n", "> ~~~\n> teh\n", "- ```\n  teh\n"] {
        let doc = QualityDocument(source: source, revision: UUID())
        let range = (source as NSString).range(of: "teh")
        #expect(!MarkdownProjection(source).text.contains("teh"))
        #expect(throws: QualityError.protectedSyntax) { try QualityFinding.make(document: doc, range: range, message: "spelling", replacements: ["the"], ruleID: "CONTAINER_CODE", kind: .spelling, engine: "test") }
    }
}
@Test func r14_containerIndentedCodeRemainsProtected() throws {
    for source in [">     teh\n", "> \tteh\n", "> -     teh\n", "-     teh\n", "> >     teh\n", "> - prose\n>     teh\n"] {
        let doc = QualityDocument(source: source, revision: UUID())
        #expect(!MarkdownProjection(source).text.contains("teh"))
        #expect(throws: QualityError.protectedSyntax) { try QualityFinding.make(document: doc, range: (source as NSString).range(of: "teh"), message: "x", replacements: ["the"], ruleID: "INDENTED", kind: .spelling, engine: "test") }
    }
    for source in ["> teh\n", "> - teh\n", "- teh\n", "> > teh\n"] {
        let doc = QualityDocument(source: source, revision: UUID())
        let finding = try QualityFinding.make(document: doc, range: (source as NSString).range(of: "teh"), message: "x", replacements: ["the"], ruleID: "PROSE", kind: .spelling, engine: "test")
        #expect(try finding.applying("the", to: doc).contains("the"))
    }
}
@Test func r14_astCodeRangesPreserveUnicodeAndContainerProse() throws {
    for source in ["> Grüße 🦊\r\n>\r\n>     teh\r\n>\r\n> prose\r\n", "- Grüße 🦊\r\n\r\n      teh\r\n\r\n- prose\r\n", "Quote 🦊 `teh` prose e\u{301}\r\n", "> Quote\n>\n> ```\n> teh\n> ```\n>\n> prose\n", "- item\n\n      teh\n\n  prose\n"] {
        let document = QualityDocument(source: source, revision: UUID())
        let code = (source as NSString).range(of: "teh")
        #expect(throws: QualityError.protectedSyntax) { try QualityFinding.make(document: document, range: code, message: "x", replacements: ["the"], ruleID: "AST", kind: .spelling, engine: "test") }
        let prose = (source as NSString).range(of: "prose")
        let finding = try QualityFinding.make(document: document, range: prose, message: "x", replacements: ["text"], ruleID: "PROSE", kind: .spelling, engine: "test")
        let expected = (source as NSString).replacingCharacters(in: prose, with: "text")
        #expect(try Array(finding.applying("text", to: document).utf8) == Array(expected.utf8))
    }
}
@Test func r14_completeASTStructurePreventsNestedActivation() throws {
    for (source, replacements) in [("> plain\n", ["# Title", "---"]), ("- plain\n", ["# Title", "- nested", "1. nested", "---"]), ("> > plain\n", ["# Title", "- nested"]), ("> - plain\n", ["# Title", "- nested", "---"])] {
        let doc = QualityDocument(source: source, revision: UUID())
        let range = (source as NSString).range(of: "plain")
        for replacement in replacements {
            let finding = try QualityFinding.make(document: doc, range: range, message: "x", replacements: [replacement], ruleID: "NESTED_AST", kind: .grammar, engine: "test")
            #expect(throws: QualityError.protectedSyntax) { try finding.applying(replacement, to: doc) }
        }
        let ordinary = try QualityFinding.make(document: doc, range: range, message: "x", replacements: ["well-written prose!"], ruleID: "PROSE", kind: .grammar, engine: "test")
        #expect(try ordinary.applying("well-written prose!", to: doc) == (source as NSString).replacingCharacters(in: range, with: "well-written prose!"))
    }
}
@Test @MainActor func r14_nativeGrammarCompletionCanRunOnBackgroundQueue() async throws {
    let doc = QualityDocument(source: "an test", revision: UUID())
    let gate = GrammarContinuationGate(timeoutNanoseconds: 1_000_000_000)
    let callback = NativeGrammarResultMapper.completion(document: doc, gate: gate)
    let findings: [QualityFinding] = try await withCheckedThrowingContinuation { continuation in
        gate.install(continuation)
        DispatchQueue.global().async {
            let result = NSTextCheckingResult.correctionCheckingResult(range: NSRange(location: 0, length: 2), replacementString: "a")
            callback([result])
            callback([result]) // Real SDK may deliver a stale/duplicate callback; only one resume.
        }
    }
    #expect(findings.count == 1)
    #expect(try findings[0].applying("a", to: doc) == "a test")
}
