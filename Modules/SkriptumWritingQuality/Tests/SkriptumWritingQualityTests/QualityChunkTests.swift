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
