import Foundation
import Testing
@testable import SkriptumWritingQuality

private let incompleteReviewMessage = "Die Prüfung wurde nicht vollständig abgeschlossen. Es werden keine Teilvorschläge angezeigt. Bitte erneut prüfen."

private func completenessResponse(text: String = "baad text", warnings: String? = nil,
                                  includingMatch: Bool = true) throws -> Data {
    let range = (text as NSString).range(of: "baad")
    let matches: [[String: Any]] = includingMatch && range.location != NSNotFound ? [[
        "offset": range.location, "length": range.length, "message": "Witness",
        "replacements": [["value": "good"]],
        "rule": ["id": "WITNESS", "issueType": "grammar", "category": ["id": "GRAMMAR", "name": "Grammar"]]
    ]] : []
    let encoded = String(decoding: try JSONSerialization.data(withJSONObject: matches), as: UTF8.self)
    return Data(("{\"matches\":" + encoded + (warnings.map { ",\"warnings\":" + $0 } ?? "") + "}").utf8)
}

// Keep these assertions usable against the old decoder so the regression's
// failing run checks behavior, rather than failing to compile a new error case.
private func expectIncompleteReview(_ error: any Error) {
    #expect(error is QualityError)
    #expect(String(describing: error) == "incompleteResults")
    #expect(error.localizedDescription == incompleteReviewMessage)
}

private final class IncompleteChunkEngine: BundledGrammarEngine, @unchecked Sendable {
    let languages: Set<String> = ["en-US"]
    private let lock = NSLock()
    private var calls = 0
    var callCount: Int { lock.withLock { calls } }
    func check(text: String, language: String) throws -> Data {
        let call = lock.withLock { calls += 1; return calls }
        return try completenessResponse(text: text, warnings: "{\"incompleteResults\":\(call == 2)}")
    }
}

private actor IncompleteChunkTransport {
    private(set) var checks = 0
    private(set) var catalogs = 0
    func response(_ request: URLRequest) throws -> Data {
        if request.url?.lastPathComponent == "languages" {
            catalogs += 1
            return Data(#"[{"name":"English","code":"en","longCode":"en-US"}]"#.utf8)
        }
        #expect(request.url?.lastPathComponent == "check")
        #expect(request.httpMethod == "POST")
        let body = try #require(request.httpBody)
        var parts = URLComponents()
        parts.percentEncodedQuery = String(decoding: body, as: UTF8.self).replacingOccurrences(of: "+", with: "%20")
        let text = try #require(parts.queryItems?.first { $0.name == "text" }?.value)
        checks += 1
        return try completenessResponse(text: text, warnings: "{\"incompleteResults\":\(checks == 2)}")
    }
}

@MainActor private final class CompletenessProgress {
    var values: [[Int]] = []
    func record(_ completed: Int, _ total: Int) { values.append([completed, total]) }
}

@Suite(.serialized, .timeLimit(.minutes(1))) struct RuleResponseCompletenessTests {
    @Test(arguments: [RuleResponseEngine.ownServer, .bundledNative])
    func incompleteResponsesNeverPublishCleanOrActionableResults(_ engine: RuleResponseEngine) throws {
        let document = QualityDocument(source: "baad text", revision: UUID())
        for includingMatch in [false, true] {
            let data = try completenessResponse(warnings: #"{"incompleteResults":true}"#, includingMatch: includingMatch)
            do {
                _ = try RuleResponseDecoder.decode(data, document: document,
                    submittedRange: NSRange(location: 0, length: document.source.utf16.count), engine: engine)
                Issue.record("An explicitly incomplete response must not return findings, including an empty result.")
            } catch { expectIncompleteReview(error) }
        }
    }

    @Test(arguments: [RuleResponseEngine.ownServer, .bundledNative])
    func completeAndLegacyResponsesStillReturnValidatedFindings(_ engine: RuleResponseEngine) throws {
        let document = QualityDocument(source: "baad text", revision: UUID())
        for warnings: String? in [nil, #"{"incompleteResults":false}"#] {
            for includingMatch in [false, true] {
                let findings = try RuleResponseDecoder.decode(
                    completenessResponse(warnings: warnings, includingMatch: includingMatch), document: document,
                    submittedRange: NSRange(location: 0, length: document.source.utf16.count), engine: engine)
                #expect(findings.count == (includingMatch ? 1 : 0))
                if let finding = findings.first {
                    #expect(finding.engine == engine.rawValue)
                    #expect(try finding.applying("good", to: document) == "good text")
                }
            }
        }
    }

    @Test(arguments: [RuleResponseEngine.ownServer, .bundledNative])
    func presentWarningsRequireAnActualBooleanStatus(_ engine: RuleResponseEngine) throws {
        let document = QualityDocument(source: "baad text", revision: UUID())
        for warnings in ["null", "[]", "true", "{}", #"{"incompleteResults":null}"#,
                         #"{"incompleteResults":"false"}"#, #"{"incompleteResults":0}"#,
                         #"{"incompleteResults":1}"#, #"{"incompleteResults":[]}"#,
                         #"{"incompleteResults":{}}"#] {
            #expect(throws: QualityError.invalidResponse) {
                try RuleResponseDecoder.decode(completenessResponse(warnings: warnings), document: document,
                    submittedRange: NSRange(location: 0, length: document.source.utf16.count), engine: engine)
            }
        }
    }

    @Test @MainActor func laterNativeIncompleteChunkDiscardsAllFindingsAndStopsWork() async throws {
        let document = try await QualityDocument.prepare(source: String(repeating: "A baad sentence.\n\n", count: 3000), revision: UUID())
        let chunks = try QualityTextChunks.make(document.projection.text, preferSentences: true)
        #expect(chunks.count > 2)
        let engine = IncompleteChunkEngine(), progress = CompletenessProgress()
        do {
            _ = try await BundledRuleReviewer(engine: engine).check(document, language: "en-US",
                progress: { progress.record($0, $1) })
            Issue.record("An incomplete later native chunk must fail the whole review instead of returning partial findings.")
        } catch { expectIncompleteReview(error) }
        #expect(engine.callCount == 2)
        #expect(progress.values == [[0, chunks.count], [1, chunks.count]])
    }

    @Test @MainActor func laterRemoteIncompleteChunkDiscardsAllFindingsAndStopsTransmission() async throws {
        let document = try await QualityDocument.prepare(source: String(repeating: "A baad sentence.\n\n", count: 3000), revision: UUID())
        let chunks = try QualityTextChunks.make(document.projection.text, preferSentences: true)
        #expect(chunks.count > 2)
        let transport = IncompleteChunkTransport(), progress = CompletenessProgress()
        let client = LanguageToolClient(configuration: try LanguageToolConfiguration(endpoint: URL(string: "https://fixture.invalid/v2")!),
            transport: { try await transport.response($0) })
        let submission = try client.prepare(document, language: "en-US")
        do {
            _ = try await client.check(submission, consentID: submission.id, progress: { progress.record($0, $1) })
            Issue.record("An incomplete later server chunk must fail the whole review instead of returning partial findings.")
        } catch { expectIncompleteReview(error) }
        #expect(await transport.catalogs == 1)
        #expect(await transport.checks == 2)
        #expect(progress.values == [[0, chunks.count], [1, chunks.count]])
    }
}
