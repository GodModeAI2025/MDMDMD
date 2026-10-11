import Foundation
import Testing
@testable import SkriptumWritingQuality

private actor ManuscriptTransport {
    private(set) var texts: [String] = []
    private(set) var catalogs = 0
    let failAt: Int?
    init(failAt: Int? = nil) { self.failAt = failAt }
    func response(_ request: URLRequest) throws -> Data {
        if request.url?.lastPathComponent == "languages" {
            catalogs += 1
            return Data(#"[{"name":"English","code":"en","longCode":"en-US"}]"#.utf8)
        }
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded; charset=utf-8")
        let body = try #require(request.httpBody)
        var parts = URLComponents(); parts.percentEncodedQuery = String(decoding: body, as: UTF8.self).replacingOccurrences(of: "+", with: "%20")
        let text = try #require(parts.queryItems?.first { $0.name == "text" }?.value)
        #expect(parts.queryItems?.first { $0.name == "language" }?.value == "en-US")
        texts.append(text)
        if texts.count == failAt { throw QualityError.http(503) }
        let range = (text as NSString).range(of: "misspell")
        let matches: [[String: Any]] = range.location == NSNotFound ? [] : [["offset":range.location,"length":range.length,"message":"Witness",
            "replacements":[["value":"correct"]],"rule":["id":"WITNESS","issueType":"misspelling","category":["id":"SPELL","name":"Spelling"]]]]
        return try JSONSerialization.data(withJSONObject: ["matches":matches])
    }
}

@Test func remoteManuscriptCoversExactProjectionAndMapsEveryChunkToOriginalUnicode() async throws {
    let source = String(repeating: "Café e\u{301} 🦊 misspell Plus+sign. `protected secret`\r\n\r\n", count: 8000)
    #expect(source.utf8.count > 100_000)
    let document = try await QualityDocument.prepare(source: source, revision: UUID())
    let transport = ManuscriptTransport()
    let client = LanguageToolClient(configuration: try LanguageToolConfiguration(endpoint: URL(string: "https://fixture.invalid/v2")!),
        transport: { try await transport.response($0) })
    let submission = try client.prepare(document, language: "en-US")
    let findings = try await client.check(submission, consentID: submission.id)
    let texts = await transport.texts
    #expect(texts.count > 1 && findings.count == texts.count)
    #expect(await transport.catalogs == 1)
    #expect(texts.joined().utf8.elementsEqual(document.projection.text.utf8))
    #expect(!texts.joined().contains("protected secret"))
    #expect(texts.allSatisfy { $0.utf16.count <= 16_384 && $0.utf8.count <= 100_000 })
    var offset = 0
    for (index, pair) in zip(texts, findings).enumerated() {
        let (text, finding) = pair
        let local = (text as NSString).range(of: "misspell")
        #expect(finding.range.location == offset + local.location)
        #expect((source as NSString).substring(with: finding.range) == "misspell")
        if [0, texts.count / 2, texts.count - 1].contains(index) {
            let changed = try finding.applying("correct", to: document)
            #expect(changed.utf8.elementsEqual((source as NSString).replacingCharacters(in: finding.range, with: "correct").utf8))
        }
        offset += text.utf16.count
    }
}

@MainActor private final class RemoteReviewCancellation { var task: Task<[QualityFinding], Error>? }
@Test @MainActor func cancellationAfterFirstRemoteChunkStopsFurtherTransmission() async throws {
    let document = try await QualityDocument.prepare(source: String(repeating: "A misspell sentence.\n\n", count: 5000), revision: UUID())
    let transport = ManuscriptTransport()
    let client = LanguageToolClient(configuration: try LanguageToolConfiguration(endpoint: URL(string: "https://fixture.invalid/v2")!),
        transport: { try await transport.response($0) })
    let submission = try client.prepare(document, language: "en-US"), cancellation = RemoteReviewCancellation()
    let task = Task {
        try await client.check(submission, consentID: submission.id, progress: { completed, _ in
            if completed == 1 { cancellation.task?.cancel() }
        })
    }
    cancellation.task = task
    do { _ = try await task.value; Issue.record("Canceled manuscript returned partial results") }
    catch is CancellationError {} catch { Issue.record("Unexpected error: \(error)") }
    #expect(await transport.texts.count == 1)
}

@Test func remoteManuscriptFailureDoesNotReturnPartialFindingsOrPermitReplay() async throws {
    let source = String(repeating: "A misspell sentence.\n\n", count: 5000)
    let document = try await QualityDocument.prepare(source: source, revision: UUID())
    let transport = ManuscriptTransport(failAt: 2)
    let client = LanguageToolClient(configuration: try LanguageToolConfiguration(endpoint: URL(string: "https://fixture.invalid/v2")!),
        transport: { try await transport.response($0) })
    let submission = try client.prepare(document, language: "en-US")
    await #expect(throws: QualityError.http(503)) { try await client.check(submission, consentID: submission.id) }
    #expect(await transport.texts.count == 2)
    await #expect(throws: QualityError.contentPermissionRequired) { try await client.check(submission, consentID: submission.id) }
    #expect(await transport.texts.count == 2)
}

@Test func remoteChunkBoundsRejectFindingsOutsideSubmittedTextEvenWithinFullDocument() throws {
    let document = QualityDocument(source: "Before 🦊\n\nmisspell\n\nAfter", revision: UUID())
    let range = (document.source as NSString).range(of: "misspell")
    let response = Data(#"{"matches":[{"offset":7,"length":2,"message":"bad","replacements":[],"rule":{"id":"x","issueType":"grammar","category":{"id":"g","name":"Grammar"}}}]}"#.utf8)
    #expect(throws: QualityError.invalidRange) { try LanguageToolClient.decode(response, document: document, submittedRange: range) }
}

@Test func sentenceChunksKeepChineseAndParagraphBoundariesLossless() throws {
    let source = String(repeating: "这是完整的句子。下一句也要保留！", count: 3000)
    let chunks = try QualityTextChunks.make(source, maximumUTF16: 200, preferSentences: true)
    #expect(chunks.count > 1 && chunks.map(\.text).joined().utf8.elementsEqual(source.utf8))
    #expect(chunks.dropLast().allSatisfy { "。！？".contains($0.text.last!) })
    let paragraphs = try QualityTextChunks.make("First paragraph.\r\n\r\nSecond paragraph.\r\n\r\nThird paragraph.", maximumUTF16: 43, preferSentences: true)
    #expect(paragraphs.first?.text == "First paragraph.\r\n\r\nSecond paragraph.\r\n\r\n")
}
