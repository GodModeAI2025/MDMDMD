import Foundation
import Testing
@testable import SkriptumWritingQuality

private final class RecordedGrammarEngine: BundledGrammarEngine, @unchecked Sendable {
    let languages: Set<String> = ["en-US"]
    private let lock = NSLock()
    private var recorded: [String] = []
    private var mainThread = false
    let failAt: Int?
    init(failAt: Int? = nil) { self.failAt = failAt }
    var texts: [String] { lock.withLock { recorded } }
    var usedMainThread: Bool { lock.withLock { mainThread } }
    func check(text: String, language: String) throws -> Data {
        let count = lock.withLock {
            recorded.append(text); mainThread = mainThread || Thread.isMainThread; return recorded.count
        }
        if count == failAt { throw QualityError.invalidResponse }
        let range = (text as NSString).range(of: "baad")
        let matches: [[String: Any]] = range.location == NSNotFound ? [] : [[
            "offset": range.location, "length": range.length, "message": "Witness",
            "replacements": [["value": "good"]],
            "rule": ["id": "WITNESS", "issueType": "grammar", "category": ["id": "GRAMMAR", "name": "Grammar"]]
        ]]
        return try JSONSerialization.data(withJSONObject: ["matches": matches])
    }
}

private final class BlockingGrammarEngine: BundledGrammarEngine, @unchecked Sendable {
    let languages: Set<String> = ["en-US"]
    let started = AsyncStream<Void>.makeStream()
    let release = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var calls = 0, active = 0, peak = 0
    var counts: (Int, Int) { lock.withLock { (calls, peak) } }
    func check(text: String, language: String) throws -> Data {
        let index = lock.withLock { calls += 1; active += 1; peak = max(peak, active); return calls }
        defer { lock.withLock { active -= 1 } }
        if index == 1 { started.continuation.yield(); release.wait() }
        return Data(#"{"matches":[]}"#.utf8)
    }
}

@Suite(.serialized, .timeLimit(.minutes(1))) struct BundledRuleReviewerTests {
    @Test @MainActor func nativeWorkerMapsManuscriptAndKeepsMarkdownAndRevisionProtection() async throws {
        let source = String(repeating: "Café e\u{301} 🦊 baad prose. `private code`\r\n\r\n", count: 1200)
        let document = try await QualityDocument.prepare(source: source, revision: UUID())
        let engine = RecordedGrammarEngine()
        let findings = try await BundledRuleReviewer(engine: engine).check(document, language: "en-US")
        #expect(engine.texts.count > 1 && findings.count == engine.texts.count)
        #expect(!engine.usedMainThread)
        #expect(engine.texts.joined().utf8.elementsEqual(document.projection.text.utf8))
        #expect(!engine.texts.joined().contains("private code"))
        var offset = 0
        for (text, finding) in zip(engine.texts, findings) {
            #expect(finding.range.location == offset + (text as NSString).range(of: "baad").location)
            #expect(finding.engine == "LanguageTool 6.6 · lokal" && finding.kind == .grammar)
            #expect(try finding.applying("good", to: document) == (source as NSString).replacingCharacters(in: finding.range, with: "good"))
            #expect(throws: QualityError.staleSource) {
                try finding.applying("good", to: QualityDocument(source: source, revision: UUID()))
            }
            offset += text.utf16.count
        }
    }

    @Test func laterChunkFailureDiscardsAllFindings() async throws {
        let document = QualityDocument(source: String(repeating: "A baad sentence.\n\n", count: 2000), revision: UUID())
        let engine = RecordedGrammarEngine(failAt: 2)
        await #expect(throws: QualityError.invalidResponse) {
            try await BundledRuleReviewer(engine: engine).check(document, language: "en-US")
        }
        #expect(engine.texts.count == 2)
    }

    @Test func unsupportedLanguageDoesNotInvokeOrFallback() async throws {
        let engine = RecordedGrammarEngine()
        await #expect(throws: QualityError.unsupportedLanguage) {
            try await BundledRuleReviewer(engine: engine).check(QualityDocument(source: "baad", revision: UUID()), language: "de")
        }
        #expect(engine.texts.isEmpty)
    }

    @Test func cancellationReturnsWhileActiveIsolateCleansUpAndNextReviewerWaits() async throws {
        let engine = BlockingGrammarEngine()
        defer { engine.release.signal() }
        let document = QualityDocument(source: "Text.", revision: UUID())
        let first = Task { try await BundledRuleReviewer(engine: engine).check(document, language: "en-US") }
        for await _ in engine.started.stream { break }
        first.cancel()
        do { _ = try await first.value; Issue.record("Canceled work returned results") } catch is CancellationError {}
        // Cancellation must return before releasing the synchronous native call.
        #expect(engine.counts.0 == 1)
        let queued = Task { try await BundledRuleReviewer(engine: engine).check(document, language: "en-US") }
        queued.cancel()
        do { _ = try await queued.value; Issue.record("Queued cancellation returned results") } catch is CancellationError {}
        let next = Task { try await BundledRuleReviewer(engine: engine).check(document, language: "en-US") }
        engine.release.signal()
        #expect(try await next.value.isEmpty)
        #expect(engine.counts.0 == 2 && engine.counts.1 == 1)
    }
}
