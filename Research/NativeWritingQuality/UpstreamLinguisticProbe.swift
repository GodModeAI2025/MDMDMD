import Foundation
import CryptoKit
import SkriptumWritingQuality

/// Offline research. XML identity, full-engine parity and correction outcomes
/// remain separate; the initial strict-ID run is preserved without modification.
@main struct UpstreamLinguisticProbe {
    struct Corpus: Decodable { let records: [Record] }
    struct Record: Decodable {
        let language: String, ruleID: String, source: String, expect: String
        let sourceLine: Int, ruleLine: Int
        let offset: Int?, length: Int?
    }
    struct Annotations: Decodable {
        let selectionSHA256: String
        let records: [Annotation]
    }
    struct Annotation: Decodable { let corrections: [String]? }
    struct Match: Encodable {
        let ruleID: String, offset: Int, length: Int, kind: String
        let replacements: [String]
        init(_ value: QualityFinding) {
            ruleID = value.ruleID; offset = value.range.location; length = value.range.length
            kind = value.kind.rawValue; replacements = value.replacements
        }
    }
    struct Receipt: Encodable {
        let index: Int, language: String, ruleID: String, sourceLine: Int, expectation: String
        var passed = false, strictXMLIDPassed = false
        var selectedRuleID: String?, selectionBasis: String?
        var findings: [Match] = []
        var nativeCalls: [CapturedCall] = []
        var correctionAdmitted = false, staleRevisionRejected = false
        var correctionClearedTarget: Bool?
        var manualRequired = false, manualProtectionVerified = false
        var stage = "initialCheck"
        var error: String?
    }
    struct CapturedCall: Encodable, Sendable {
        let submittedTextSHA256: String, language: String, responseJSON: String
    }
    /// Fixture-only capture, never installed in the app.
    final class RecordingEngine: BundledGrammarEngine, @unchecked Sendable {
        let base: any BundledGrammarEngine
        private let lock = NSLock()
        private var calls: [CapturedCall] = []
        init(_ base: any BundledGrammarEngine) { self.base = base }
        var languages: Set<String> { base.languages }
        func check(text: String, language: String) throws -> Data {
            let data = try base.check(text: text, language: language)
            guard let json = String(data: data, encoding: .utf8) else { throw QualityError.invalidResponse }
            let value = CapturedCall(submittedTextSHA256: UpstreamLinguisticProbe.sha(Data(text.utf8)), language: language, responseJSON: json)
            lock.withLock { calls.append(value) }
            return data
        }
        func reset() { lock.withLock { calls.removeAll(keepingCapacity: true) } }
        func snapshot() -> [CapturedCall] { lock.withLock { calls } }
    }
    static func sha(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    static func main() async {
        do { try await run() }
        catch { FileHandle.standardError.write(Data((String(describing: error) + "\n").utf8)); exit(2) }
    }
    static func run() async throws {
        guard CommandLine.arguments.count == 4 else { throw QualityError.invalidConfiguration }
        let raw = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        let corpus = try JSONDecoder().decode(Corpus.self, from: raw)
        let annotations = try JSONDecoder().decode(Annotations.self,
            from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[3])))
        guard corpus.records.count <= 1000, corpus.records.count == annotations.records.count,
              sha(raw) == annotations.selectionSHA256 else { throw QualityError.invalidConfiguration }
        let engine = RecordingEngine(try await BundledGrammarRuntime.load(resourceBundleURL: URL(fileURLWithPath: CommandLine.arguments[2])))
        let reviewer = BundledRuleReviewer(engine: engine)
        var failures = 0, intentIDs: [String: Set<String>] = [:]
        for (index, record) in corpus.records.enumerated() {
            FileHandle.standardError.write(Data("\(index + 1)/\(corpus.records.count) \(record.language) \(record.ruleID) \(record.expect)\n".utf8))
            var receipt = Receipt(index: index, language: record.language, ruleID: record.ruleID,
                sourceLine: record.sourceLine, expectation: record.expect)
            engine.reset()
            do {
                let document = try await QualityDocument.prepare(source: record.source, revision: UUID())
                let findings = try await reviewer.check(document, language: record.language)
                receipt.findings = findings.map(Match.init)
                let strictMatches = findings.filter { $0.ruleID == record.ruleID }
                let identity = record.language + ":" + String(record.ruleLine)
                if record.expect == "absent" {
                    guard let ids = intentIDs[identity] else { throw QualityError.invalidConfiguration }
                    receipt.strictXMLIDPassed = strictMatches.isEmpty
                    receipt.passed = findings.allSatisfy { !ids.contains($0.ruleID) }
                    receipt.stage = "negativeControl"
                } else {
                    guard record.expect == "present", let offset = record.offset, let length = record.length else { throw QualityError.invalidConfiguration }
                    let expected = NSRange(location: offset, length: length)
                    let strict = strictMatches.first { $0.range == expected }
                    receipt.strictXMLIDPassed = strict != nil
                    // Alternatives require the original marker and literal XML correction.
                    // The external verifier additionally requires independent JVM parity.
                    let selected = strict ?? findings.first { finding in
                        finding.range == expected && finding.replacements.contains { replacement in
                            annotations.records[index].corrections?.contains(where: { $0.utf8.elementsEqual(replacement.utf8) }) == true
                        }
                    }
                    var ids: Set<String> = [record.ruleID]
                    if let selected { ids.insert(selected.ruleID) }
                    intentIDs[identity] = ids
                    receipt.selectedRuleID = selected?.ruleID
                    receipt.selectionBasis = selected.map { $0.ruleID == record.ruleID ? "exactXMLRuleID" : "maintainerCorrectionAtExactMarker" }
                    receipt.passed = selected != nil
                    receipt.stage = "detection"
                    if let selected, let replacement = selected.replacements.first {
                        receipt.manualRequired = selected.requiresManualEditing(replacement)
                        if receipt.manualRequired {
                            receipt.stage = "manualProtection"
                            do { _ = try await selected.prepareCorrection(replacement, source: document.source, revision: document.revision) }
                            catch QualityError.protectedSyntax { receipt.manualProtectionVerified = true }
                            receipt.passed = receipt.passed && receipt.manualProtectionVerified
                        } else {
                            receipt.stage = "correctionAdmission"
                            let correction = try await selected.prepareCorrection(replacement, source: document.source, revision: document.revision)
                            let changed = try correction.admitting(source: document.source, revision: document.revision)
                            receipt.correctionAdmitted = changed.utf8.elementsEqual((document.source as NSString).replacingCharacters(in: selected.range, with: replacement).utf8)
                            do { _ = try correction.admitting(source: document.source, revision: UUID()) }
                            catch QualityError.staleSource { receipt.staleRevisionRejected = true }
                            receipt.stage = "correctionRecheck"
                            let corrected = try await QualityDocument.prepare(source: changed, revision: UUID())
                            let after = try await reviewer.check(corrected, language: record.language)
                            receipt.correctionClearedTarget = after.filter { ids.contains($0.ruleID) }.count < findings.filter { ids.contains($0.ruleID) }.count
                            receipt.passed = receipt.passed && receipt.correctionAdmitted && receipt.staleRevisionRejected && receipt.correctionClearedTarget == true
                        }
                    }
                }
            } catch { receipt.passed = false; receipt.error = String(describing: error) }
            receipt.nativeCalls = engine.snapshot()
            if !receipt.passed { failures += 1 }
            FileHandle.standardOutput.write(try JSONEncoder().encode(receipt))
            FileHandle.standardOutput.write(Data("\n".utf8))
        }
        if failures > 0 { exit(1) }
    }
}
