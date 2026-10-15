import Foundation
import SkriptumWritingQuality

/// Runs a preselected upstream corpus through the actual app runtime, retaining
/// failures rather than stopping early or weakening the selection afterward.
@main struct UpstreamLinguisticProbe {
    struct Corpus: Decodable { let records: [Record] }
    struct Record: Decodable {
        let language: String, ruleID: String, source: String, expect: String
        let sourceLine: Int
        let offset: Int?, length: Int?
    }
    struct Match: Encodable { let offset: Int, length: Int, kind: String }
    struct Receipt: Encodable {
        let index: Int, language: String, ruleID: String, sourceLine: Int, expectation: String
        let passed: Bool, targetMatches: [Match], findings: Int
        let correctionAdmitted: Bool, correctionClearedTarget: Bool?, staleRevisionRejected: Bool
        let error: String?
    }

    static func main() async {
        do { try await run() }
        catch { FileHandle.standardError.write(Data((String(describing: error) + "\n").utf8)); exit(2) }
    }

    static func run() async throws {
        guard CommandLine.arguments.count == 3 else { throw QualityError.invalidConfiguration }
        let input = URL(fileURLWithPath: CommandLine.arguments[1])
        let corpus = try JSONDecoder().decode(Corpus.self, from: Data(contentsOf: input))
        guard corpus.records.count <= 1000 else { throw QualityError.inputTooLarge }
        let engine = try await BundledGrammarRuntime.load(resourceBundleURL: URL(fileURLWithPath: CommandLine.arguments[2]))
        let reviewer = BundledRuleReviewer(engine: engine)
        var failures = 0
        for (index, record) in corpus.records.enumerated() {
            let progress = "\(index + 1)/\(corpus.records.count) \(record.language) \(record.ruleID) \(record.expect)\n"
            FileHandle.standardError.write(Data(progress.utf8))
            let receipt: Receipt
            do {
                let document = try await QualityDocument.prepare(source: record.source, revision: UUID())
                let findings = try await reviewer.check(document, language: record.language)
                let matches = findings.filter { $0.ruleID == record.ruleID }
                let expectedRange = record.offset.flatMap { offset in record.length.map { NSRange(location: offset, length: $0) } }
                let selected = matches.first { $0.range == expectedRange }
                var passed = record.expect == "absent" ? matches.isEmpty : selected != nil
                var admitted = false, staleRejected = false
                var cleared: Bool?
                if let selected, let replacement = selected.replacements.first {
                    let correction = try await selected.prepareCorrection(replacement, source: document.source, revision: document.revision)
                    let changed = try correction.admitting(source: document.source, revision: document.revision)
                    admitted = changed == (document.source as NSString).replacingCharacters(in: selected.range, with: replacement)
                    do { _ = try correction.admitting(source: document.source, revision: UUID()) }
                    catch QualityError.staleSource { staleRejected = true }
                    let corrected = try await QualityDocument.prepare(source: changed, revision: UUID())
                    let after = try await reviewer.check(corrected, language: record.language)
                    cleared = after.filter { $0.ruleID == record.ruleID }.count < matches.count
                    passed = passed && admitted && staleRejected && cleared == true
                }
                receipt = Receipt(index: index, language: record.language, ruleID: record.ruleID,
                    sourceLine: record.sourceLine, expectation: record.expect, passed: passed,
                    targetMatches: matches.map { Match(offset: $0.range.location, length: $0.range.length, kind: $0.kind.rawValue) },
                    findings: findings.count, correctionAdmitted: admitted, correctionClearedTarget: cleared,
                    staleRevisionRejected: staleRejected, error: nil)
            } catch {
                receipt = Receipt(index: index, language: record.language, ruleID: record.ruleID,
                    sourceLine: record.sourceLine, expectation: record.expect, passed: false, targetMatches: [],
                    findings: 0, correctionAdmitted: false, correctionClearedTarget: nil, staleRevisionRejected: false,
                    error: String(describing: error))
            }
            if !receipt.passed { failures += 1 }
            FileHandle.standardOutput.write(try JSONEncoder().encode(receipt))
            FileHandle.standardOutput.write(Data("\n".utf8))
        }
        if failures > 0 { exit(1) }
    }
}
