import Foundation
import SkriptumWritingQuality

@main struct ReviewerIntegrationProbe {
    struct Corpus: Decodable { let records: [Record] }
    struct Record: Decodable {
        let language: String, source: String, response: Expected
    }
    struct Expected: Decodable { let matches: [Match] }
    struct Match: Decodable {
        let offset: Int, length: Int, rule: Rule
    }
    struct Rule: Decodable { let id: String }
    struct Receipt: Encodable { let language: String, findings: Int, corrections: Int }
    enum Failure: Error { case arguments, missingWitness(String, String), incorrectOrigin, lostProtection, staleAdmitted }

    static func main() async {
        do { try await run() }
        catch {
            let data = try? JSONSerialization.data(withJSONObject: ["passed": false, "error": String(describing: error)], options: [.sortedKeys])
            if let data { FileHandle.standardError.write(data); FileHandle.standardError.write(Data("\n".utf8)) }
            exit(1)
        }
    }

    static func run() async throws {
        guard CommandLine.arguments.count == 3 else { throw Failure.arguments }
        let corpus = try JSONDecoder().decode(Corpus.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
        let engine = GraalBundledGrammarEngine(resourceRoot: URL(fileURLWithPath: CommandLine.arguments[2]),
            languages: Set(corpus.records.map(\.language)))
        let reviewer = BundledRuleReviewer(engine: engine)
        // Real configuration failure must release its isolate before the next
        // request. The valid corpus immediately follows on the same worker.
        let bad = GraalBundledGrammarEngine(resourceRoot: engine.resourceRoot.appendingPathComponent("missing-fixture-root"), languages: engine.languages)
        do {
            _ = try await BundledRuleReviewer(engine: bad).check(QualityDocument(source: "Text.", revision: UUID()), language: "en")
            throw Failure.arguments
        } catch GraalGrammarError.resources { }
        var receipts: [Receipt] = []
        for record in corpus.records {
            let progress = try JSONSerialization.data(withJSONObject: ["language": record.language, "phase": "native-review"])
            FileHandle.standardError.write(progress); FileHandle.standardError.write(Data("\n".utf8))
            // Code is deliberately appended; production projection must mask it
            // while preserving the exact original witness offsets and source.
            let source = record.source + "\n\n`private code baad`\n"
            let document = try await QualityDocument.prepare(source: source, revision: UUID())
            let findings = try await reviewer.check(document, language: record.language)
            for expected in record.response.matches {
                guard findings.contains(where: { $0.ruleID == expected.rule.id && $0.range == NSRange(location: expected.offset, length: expected.length) }) else {
                    throw Failure.missingWitness(record.language, expected.rule.id)
                }
            }
            var corrections = 0
            for finding in findings {
                guard finding.engine == "LanguageTool 6.6 · lokal" else { throw Failure.incorrectOrigin }
                if let replacement = finding.replacements.first {
                    let result = try await finding.prepareCorrection(replacement, source: source, revision: document.revision)
                    let changed = try result.admitting(source: source, revision: document.revision)
                    guard changed.hasSuffix("\n\n`private code baad`\n") else { throw Failure.lostProtection }
                    do {
                        _ = try result.admitting(source: source, revision: UUID())
                        throw Failure.staleAdmitted
                    } catch QualityError.staleSource { }
                    corrections += 1
                }
            }
            receipts.append(Receipt(language: record.language, findings: findings.count, corrections: corrections))
        }
        let output = try JSONEncoder().encode(receipts)
        FileHandle.standardOutput.write(output)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }
}
