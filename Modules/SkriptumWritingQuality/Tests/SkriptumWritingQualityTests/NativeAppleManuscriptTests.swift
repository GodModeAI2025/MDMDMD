import Foundation
import Testing
@testable import SkriptumWritingQuality

@Test @MainActor func nativeGrammarOwnershipUsesIssueRangeInsideContextSentence() async throws {
    let sentence = "Wir geht nach Hause.", source = "Vorwort 🦊 e\u{301}\r\n" + sentence
    let document = QualityDocument(source: source, revision: UUID())
    let offset = (source as NSString).range(of: sentence).location
    let issue = (sentence as NSString).range(of: "geht")
    let parent = NSRange(location: 0, length: sentence.utf16.count)
    let owners = [NSRange(location: offset, length: issue.location),
                  NSRange(location: offset + issue.location, length: sentence.utf16.count - issue.location)]
    for result in [NSTextCheckingResult.correctionCheckingResult(range: issue, replacementString: "gehen"),
                   NSTextCheckingResult.grammarCheckingResult(range: parent, details: [["NSGrammarRange": NSValue(range: issue), "NSGrammarCorrections": ["gehen"]]])] {
        var findings: [QualityFinding] = []
        for owner in owners {
            let gate = GrammarContinuationGate(timeoutNanoseconds: 1_000_000_000)
            let completion = NativeGrammarResultMapper.completion(document: document, gate: gate, offset: offset, length: sentence.utf16.count, ownedRange: owner)
            let mapped: [QualityFinding] = try await withCheckedThrowingContinuation { continuation in
                gate.install(continuation); completion([result])
            }
            findings += mapped
        }
        #expect(findings.count == 1)
        let finding = try #require(findings.first)
        #expect(finding.range == NSRange(location: offset + issue.location, length: issue.length))
        #expect(try finding.applying("gehen", to: document).utf8.elementsEqual(source.replacingOccurrences(of: "geht", with: "gehen").utf8))
    }
}

#if canImport(AppKit)
/// Opt in on a host with Apple grammar available; ordinary unit tests need no language service.
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["SCRIPTUM_APPLE_GRAMMAR_WITNESS"] == "1"))
@MainActor struct NativeAppleManuscriptTests {
    @Test func nativeGrammarSurvivesManuscriptCutsExactlyOnce() async throws {
        let sentence = "Wir geht nach Hause."
        let reference = try await NativeWritingReviewer.check(QualityDocument(source: sentence, revision: UUID()))
        let offered = try #require(reference.first { $0.kind == .grammar && $0.original == "geht" && $0.replacements.contains("gehen") })
        #expect(offered.engine.hasPrefix("Apple"))

        for sentenceOffset in [16_380, 15_868, 15_854] {
            let source = paddedSource(sentence: sentence, at: sentenceOffset)
            let document = try await QualityDocument.prepare(source: source, revision: UUID())
            let expectedRange = (source as NSString).range(of: "geht")
            let result = try await NativeWritingReviewer.check(document)
            let target = result.filter { $0.kind == .grammar && $0.range == expectedRange && $0.replacements.contains("gehen") }
            print("APPLE_GRAMMAR_BOUNDARY sentenceOffset=\(sentenceOffset) reference=1 actual=\(target.count)")
            #expect(target.count == 1, "The reference Apple correction must survive the manuscript cut exactly once.")
            if let finding = target.first {
                let expected = (source as NSString).replacingCharacters(in: expectedRange, with: "gehen")
                #expect(try finding.applying("gehen", to: document).utf8.elementsEqual(expected.utf8))
                #expect(throws: QualityError.staleSource) {
                    try finding.applying("gehen", to: QualityDocument(source: source, revision: UUID()))
                }
            }
        }
    }

    @Test func nativeSpellingOverlapHasOneOwner() async throws {
        let dictionary = try #require(NativeWritingReviewer.spellingLanguages.first { $0.split(whereSeparator: { $0 == "_" || $0 == "-" }).first == "de" })
        let source = paddedSource(sentence: "Das Wort qzxqzx steht hier.", at: 15_850)
        let document = try await QualityDocument.prepare(source: source, revision: UUID())
        let expectedRange = (source as NSString).range(of: "qzxqzx")
        let findings = try await NativeWritingReviewer.check(document, spellingLanguage: dictionary, includingGrammarAndStyle: false)
        #expect(findings.filter { $0.kind == .spelling && $0.range == expectedRange }.count == 1)
    }

    private func paddedSource(sentence: String, at offset: Int) -> String {
        let before = "```text\r\n🦊 e\u{301} ", after = "\r\n```\r\n\r\n"
        return before + String(repeating: "x", count: offset - before.utf16.count - after.utf16.count) + after + sentence
    }
}
#endif
