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

@Test func r14_metadataReferencesAndURIsProtected() throws {
let protectedCases: [(String,String,String,String)] = [
("foot-ref", "Some note[^wrod].\r\n\r\n[^wrod]: A useful explanation.\r\n", "wrod", "word"),
("quote-id", "> [label]: relative-url\n", "label", "word"),
("list-id", "- [label]: relative-url\n", "label", "word"),
("quote-uri", "> [label]: relative-url\n", "relative-url", "other-url"),
("list-uri", "- [label]: relative-url\n", "relative-url", "other-url"),
("nested-uri", "> - [label]: relative-url\n", "relative-url", "other-url"),
("multi-destination", "[label]:\n  relative-url\n", "relative-url", "other-url"),
("multi-title", "[label]: relative-url\n  \"wrod title\"\n", "wrod", "word"),
("multi-title-body", "[label]: relative-url\n  \"some\n  wrod\n  title\"\n", "wrod", "word"),
("multi-destination-title-body", "[label]:\n  relative-url \"some\n  wrod\n  title\"\n", "wrod", "word"),
("escaped-title-body", "[label]: relative-url \"some \\\" escaped\n  wrod\n  title\"\n", "wrod", "word"),
("quote-multi-uri", "> [label]:\r\n>   relative-url\r\n>   \"Title\"\r\n", "relative-url", "other-url"),
("quote-multi-title", "> [label]:\r\n>   relative-url\r\n>   \"wrod title\"\r\n", "wrod", "word"),
("list-multi-uri", "- [label]:\n  relative-url\n  \"Title\"\n", "relative-url", "other-url"),
("custom-uri", "Open scriptum://pages/wrod now.", "wrod", "word"),
("mail-uri", "Contact mailto:wrod@example.org now.", "wrod", "word"),
("doi-uri", "See doi:10.1234/wrod for detail.", "wrod", "word"),
("unicode-ref", "> [🦊wrod]: relative-url\r\n", "wrod", "word")]
for (_,source,target,replacement) in protectedCases {
 let document = QualityDocument(source: source, revision: UUID())
 #expect(throws: QualityError.protectedSyntax) {
  let finding = try QualityFinding.make(document: document, range: (source as NSString).range(of: target), message: "synthetic", replacements: [replacement], ruleID: "METADATA", kind: .spelling, engine: "test")
  _ = try finding.applying(replacement, to: document)
 }
}
for source in ["> ordinary wrod text\r\n", "- ordinary wrod text\n", "> > 🦊 ordinary wrod e\u{301}\r\n", "[label]: relative-url\n\nprose wrod\n", "[label]: relative-url\n  \"title\"\n\nprose wrod\n"] {
 let document = QualityDocument(source: source, revision: UUID())
 let finding = try QualityFinding.make(document: document, range: (source as NSString).range(of: "wrod"), message: "synthetic", replacements: ["word"], ruleID: "PROSE", kind: .spelling, engine: "test")
 #expect(try Array(finding.applying("word", to: document).utf8) == Array(source.replacingOccurrences(of: "wrod", with: "word").utf8))
}
}

@Test func r14_realLanguageToolCatalogAndValidation() throws {
    // Actual /v2/languages payload captured from the verified own LanguageTool6.6 engine.
    let actualResponse = Data(#"""
[{"name":"Arabic","code":"ar","longCode":"ar"},{"name":"Asturian","code":"ast","longCode":"ast-ES"},{"name":"Belarusian","code":"be","longCode":"be-BY"},{"name":"Breton","code":"br","longCode":"br-FR"},{"name":"Catalan","code":"ca","longCode":"ca-ES"},{"name":"Catalan (Valencian)","code":"ca","longCode":"ca-ES-valencia"},{"name":"Catalan (Balearic)","code":"ca","longCode":"ca-ES-balear"},{"name":"Danish","code":"da","longCode":"da-DK"},{"name":"German","code":"de","longCode":"de"},{"name":"German (Germany)","code":"de","longCode":"de-DE"},{"name":"German (Austria)","code":"de","longCode":"de-AT"},{"name":"German (Swiss)","code":"de","longCode":"de-CH"},{"name":"Simple German","code":"de-DE-x-simple-language","longCode":"de-DE-x-simple-language"},{"name":"Greek","code":"el","longCode":"el-GR"},{"name":"English","code":"en","longCode":"en"},{"name":"English (US)","code":"en","longCode":"en-US"},{"name":"English (GB)","code":"en","longCode":"en-GB"},{"name":"English (Australian)","code":"en","longCode":"en-AU"},{"name":"English (Canadian)","code":"en","longCode":"en-CA"},{"name":"English (New Zealand)","code":"en","longCode":"en-NZ"},{"name":"English (South African)","code":"en","longCode":"en-ZA"},{"name":"Esperanto","code":"eo","longCode":"eo"},{"name":"Spanish","code":"es","longCode":"es"},{"name":"Spanish (voseo)","code":"es","longCode":"es-AR"},{"name":"Persian","code":"fa","longCode":"fa"},{"name":"French","code":"fr","longCode":"fr"},{"name":"French (Canada)","code":"fr","longCode":"fr-CA"},{"name":"French (Switzerland)","code":"fr","longCode":"fr-CH"},{"name":"French (Belgium)","code":"fr","longCode":"fr-BE"},{"name":"Irish","code":"ga","longCode":"ga-IE"},{"name":"Galician","code":"gl","longCode":"gl-ES"},{"name":"Italian","code":"it","longCode":"it"},{"name":"Japanese","code":"ja","longCode":"ja-JP"},{"name":"Khmer","code":"km","longCode":"km-KH"},{"name":"Dutch","code":"nl","longCode":"nl"},{"name":"Dutch (Belgium)","code":"nl","longCode":"nl-BE"},{"name":"Polish","code":"pl","longCode":"pl-PL"},{"name":"Portuguese","code":"pt","longCode":"pt"},{"name":"Portuguese (Portugal)","code":"pt","longCode":"pt-PT"},{"name":"Portuguese (Brazil)","code":"pt","longCode":"pt-BR"},{"name":"Portuguese (Angola preAO)","code":"pt","longCode":"pt-AO"},{"name":"Portuguese (Moçambique preAO)","code":"pt","longCode":"pt-MZ"},{"name":"Romanian","code":"ro","longCode":"ro-RO"},{"name":"Russian","code":"ru","longCode":"ru-RU"},{"name":"Slovak","code":"sk","longCode":"sk-SK"},{"name":"Slovenian","code":"sl","longCode":"sl-SI"},{"name":"Swedish","code":"sv","longCode":"sv"},{"name":"Tamil","code":"ta","longCode":"ta-IN"},{"name":"Tagalog","code":"tl","longCode":"tl-PH"},{"name":"Ukrainian","code":"uk","longCode":"uk-UA"},{"name":"Chinese","code":"zh","longCode":"zh-CN"},{"name":"Crimean Tatar","code":"crh","longCode":"crh-UA"},{"name":"Dutch","code":"nl","longCode":"nl-NL"},{"name":"Simple German","code":"de-DE-x-simple-language","longCode":"de-DE-x-simple-language-DE"},{"name":"Spanish","code":"es","longCode":"es-ES"},{"name":"Italian","code":"it","longCode":"it-IT"},{"name":"Persian","code":"fa","longCode":"fa-IR"},{"name":"Swedish","code":"sv","longCode":"sv-SE"},{"name":"German","code":"de","longCode":"de-LU"},{"name":"French","code":"fr","longCode":"fr-FR"}]
"""#.utf8)
    let catalog = try LanguageToolClient.decodeLanguages(actualResponse)
    #expect(catalog.languages.count == 60)
    #expect(catalog.distinctLanguageCount == 31)
    #expect(catalog.languages.contains { $0.code == "de-DE-x-simple-language" })
    for (code,longCode) in [("", "en-US"), (String(repeating: "x", count: 33), "en-US"), ("en", ""), ("en", String(repeating: "x", count: 33))] {
        let data = try JSONEncoder().encode([QualityLanguage(name: "Example", code: code, longCode: longCode)])
        #expect(throws: QualityError.invalidResponse) { try LanguageToolClient.decodeLanguages(data) }
    }
    #expect(throws: QualityError.invalidResponse) { try LanguageToolClient.decodeLanguages(Data("[]".utf8)) }
    #expect(throws: QualityError.invalidResponse) { try LanguageToolClient.decodeLanguages(Data("not-json".utf8)) }
    let tooMany = try JSONEncoder().encode(Array(repeating: QualityLanguage(name: "Example", code: "en", longCode: "en-US"), count: 301))
    #expect(throws: QualityError.invalidResponse) { try LanguageToolClient.decodeLanguages(tooMany) }
    #expect(throws: QualityError.responseTooLarge) { try LanguageToolClient.decodeLanguages(Data(repeating: 32, count: 2_000_001)) }
}
@Test func r14_onlyASTProseRangesAllowCorrections() throws {
    for source in ["[la\\]bel]: relative-url\n", "> [la\\]bel]: relative-url\n", "> [multi\n> line]: relative-url\n", "- [multi\n  line]: relative-url\n"] {
        let document = QualityDocument(source: source, revision: UUID())
        #expect(throws: QualityError.protectedSyntax) {
            let finding = try QualityFinding.make(document: document, range: (source as NSString).range(of: "relative-url"), message: "synthetic", replacements: ["other-url"], ruleID: "PROSE_BOUNDARY", kind: .spelling, engine: "test")
            _ = try finding.applying("other-url", to: document)
        }
    }
    for source in ["> prose wrod\r\n", "- prose wrod\n", "🦊 e\u{301} wrod\r\nnext line\r\n", "# prose wrod\n", "prose wrod  \nnext line\n"] {
        let document = QualityDocument(source: source, revision: UUID())
        let finding = try QualityFinding.make(document: document, range: (source as NSString).range(of: "wrod"), message: "synthetic", replacements: ["word"], ruleID: "PROSE", kind: .spelling, engine: "test")
        #expect(try Array(finding.applying("word", to: document).utf8) == Array(source.replacingOccurrences(of: "wrod", with: "word").utf8))
    }
}
@Test func r14_standaloneTOCIdentifierIsProtected() throws {
    for source in ["(toc)\n", "   (toc)\r\n"] {
        let document = QualityDocument(source: source, revision: UUID())
        #expect(throws: QualityError.protectedSyntax) {
            let finding = try QualityFinding.make(document: document, range: (source as NSString).range(of: "toc"), message: "synthetic", replacements: ["TOC"], ruleID: "TOC", kind: .spelling, engine: "test")
            _ = try finding.applying("TOC", to: document)
        }
    }
    let source = "A prose mention (toc) beside wrod.\n"
    let document = QualityDocument(source: source, revision: UUID())
    let finding = try QualityFinding.make(document: document, range: (source as NSString).range(of: "wrod"), message: "synthetic", replacements: ["word"], ruleID: "PROSE", kind: .spelling, engine: "test")
    #expect(try finding.applying("word", to: document) == source.replacingOccurrences(of: "wrod", with: "word"))
}
@Test func r14_nestedExportTOCDirectiveRoleIsProtected() throws {
    for source in ["> (toc)\n", "- (toc)\n", "> > (toc)\n", "> \\(toc\\)\n", "- \\(toc\\)\n"] {
        let document = QualityDocument(source: source, revision: UUID())
        #expect(throws: QualityError.protectedSyntax) {
            let finding = try QualityFinding.make(document: document, range: (source as NSString).range(of: "toc"), message: "synthetic", replacements: ["TOC"], ruleID: "EXPORT_DIRECTIVE", kind: .spelling, engine: "test")
            _ = try finding.applying("TOC", to: document)
        }
    }
    for source in ["> plain\n", "- plain\n", "> > plain\n"] {
        let document = QualityDocument(source: source, revision: UUID())
        let finding = try QualityFinding.make(document: document, range: (source as NSString).range(of: "plain"), message: "synthetic", replacements: ["(toc)"], ruleID: "EXPORT_DIRECTIVE_CREATION", kind: .grammar, engine: "test")
        #expect(throws: QualityError.protectedSyntax) { try finding.applying("(toc)", to: document) }
    }
    for source in ["A prose (toc) mention\n", "*(toc)*\n", "# (toc)\n"] {
        let document = QualityDocument(source: source, revision: UUID())
        let finding = try QualityFinding.make(document: document, range: (source as NSString).range(of: "toc"), message: "synthetic", replacements: ["TOC"], ruleID: "LITERAL", kind: .spelling, engine: "test")
        #expect(try finding.applying("TOC", to: document) == source.replacingOccurrences(of: "toc", with: "TOC"))
    }
}
#if canImport(SkriptumExport)
import SkriptumExport
@Test func r14_actualExporterTOCRoleConformance() throws {
    let cases: [(String, Bool, Bool)] = [("(toc)\n", true, false), ("> (toc)\n", true, false), ("- (toc)\n", true, false), ("> > (toc)\n", true, false), ("> \\(toc\\)\n", true, false), ("A prose (toc) mention\n", false, true), ("*(toc)*\n", false, true), ("# (toc)\n", false, true), ("`(toc)`\n", false, false)]
    for (source, expectedDirective, expectedCorrection) in cases {
        let theme = try ExportTheme(includeTOC: false)
        let artifact = try ExportEngine.renderHTML(ExportInput(title: "Role fixture", markdown: source, theme: theme))
        let html = try #require(String(data: artifact.data, encoding: .utf8))
        #expect(html.contains("<nav aria-label=\"Contents\">") == expectedDirective)
        let document = QualityDocument(source: source, revision: UUID())
        do {
            let finding = try QualityFinding.make(document: document, range: (source as NSString).range(of: "toc"), message: "synthetic", replacements: ["TOC"], ruleID: "CONFORMANCE", kind: .spelling, engine: "test")
            _ = try finding.applying("TOC", to: document)
            #expect(expectedCorrection)
        } catch QualityError.protectedSyntax { #expect(!expectedCorrection) }
    }
}
#endif
