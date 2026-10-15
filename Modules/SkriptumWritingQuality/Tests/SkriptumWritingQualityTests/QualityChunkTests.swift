import Foundation
import Testing
@testable import SkriptumWritingQuality

@Test func manuscriptChunksCoverEveryByteAndKeepAbsoluteRanges() throws {
    let source = String(repeating: "Eine Aussage e\u{301} und 🦊 bleibt erhalten.\r\n", count: 20_000)
    let chunks = try QualityTextChunks.make(source)
    #expect(source.utf8.count > 579_000)
    #expect(chunks.count > 1)
    #expect(chunks.map(\.text).joined().utf8.elementsEqual(source.utf8))
    var offset = 0
    for chunk in chunks {
        #expect(chunk.range.location == offset)
        #expect(chunk.range.length == chunk.text.utf16.count)
        #expect(chunk.range.length <= 16_384)
        #expect(Range(chunk.range, in: source) != nil)
        offset += chunk.range.length
    }
    #expect(offset == source.utf16.count)
}

@Test func chunkingNeverSilentlyTruncatesAnUnbreakableToken() throws {
    #expect(throws: QualityError.inputTooLarge) { try QualityTextChunks.make("abcdefgh", maximumUTF16: 4) }
    #expect(try QualityTextChunks.make("").isEmpty)
}

@Test @MainActor func chunkGrammarCorrectionsOnlyChangeTheirAbsoluteSourceRange() async throws {
    let source = "Vorwort 🦊\r\nan test"
    let doc = QualityDocument(source: source, revision: UUID())
    let offset = (source as NSString).range(of: "an test").location
    let gate = GrammarContinuationGate(timeoutNanoseconds: 1_000_000_000)
    let callback = NativeGrammarResultMapper.completion(document: doc, gate: gate, offset: offset, length: 7)
    let findings: [QualityFinding] = try await withCheckedThrowingContinuation { continuation in
        gate.install(continuation)
        callback([NSTextCheckingResult.correctionCheckingResult(range: NSRange(location: 0, length: 2), replacementString: "a")])
    }
    #expect(findings.count == 1)
    #expect(findings[0].range.location == offset)
    #expect(try findings[0].applying("a", to: doc) == "Vorwort 🦊\r\na test")
}


@Test func grammarContextWindowsKeepUnicodeSourceOwnershipAndCompleteWords() throws {
    let source = String(repeating: "café e\u{301} 👩🏽‍💻 ", count: 4000)
    let windows = try QualityTextChunks.reviewWindows(source)
    #expect(windows.count > 2)
    var offset = 0
    for window in windows {
        #expect(window.ownedRange.location == offset)
        #expect(window.request.range.location <= offset)
        #expect(NSMaxRange(window.request.range) >= NSMaxRange(window.ownedRange))
        #expect(window.request.range.length <= 16_384)
        #expect(window.request.text.utf8.elementsEqual(String(source[try #require(Range(window.request.range, in: source))]).utf8))
        #expect(window.request.text.first?.isWhitespace == true || window.request.text.hasPrefix("café"))
        #expect(window.request.text.last?.isWhitespace == true || window.request.text.hasSuffix("👩🏽‍💻") || window.request.text.hasSuffix("café") || window.request.text.hasSuffix("e\u{301}"))
        offset += window.ownedRange.length
    }
    #expect(offset == source.utf16.count)
    let natural = try QualityTextChunks.reviewWindows(String(repeating: "A full sentence.\r\n\r\n", count: 2000))
    #expect(natural.allSatisfy { $0.request.range == $0.ownedRange })
}


@Test func contextReservationDoesNotReduceExistingWholeWordLimit() throws {
    let source = "Prefix " + String(repeating: "a", count: 16_000) + " " + String(repeating: "suffix ", count: 3000)
    let windows = try QualityTextChunks.reviewWindows(source)
    #expect(windows.allSatisfy { $0.request.range.length <= 16_384 })
    #expect(windows.map { (source as NSString).substring(with: $0.ownedRange) }.joined().utf8.elementsEqual(source.utf8))
    #expect(windows.contains { $0.request.text.contains(String(repeating: "a", count: 16_000)) })
    #expect(throws: QualityError.inputTooLarge) { try QualityTextChunks.reviewWindows(String(repeating: "a", count: 16_385)) }
}
