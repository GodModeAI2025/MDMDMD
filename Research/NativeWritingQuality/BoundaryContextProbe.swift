import Foundation
import CryptoKit
@testable import SkriptumWritingQuality

/// Synthetic manuscript only. The pinned native runtime is exercised offline;
/// this is not a language-coverage or iOS execution claim.
@main struct BoundaryContextProbe {
    enum Failure: Error { case arguments, missingReference, missingFinding, incorrectCorrection, staleAdmitted, leakedCode }
    struct Receipt: Encodable {
        let boundary: Int, utf16: Int, referenceMatches: Int, reviewedMatches: Int
        let sourceSHA256: String
        let correctionVerified: Bool, staleRejected: Bool, negativeControlClear: Bool
    }
    static func main() async {
        do {
            guard CommandLine.arguments.count == 2 else { throw Failure.arguments }
            let engine = try await BundledGrammarRuntime.load(resourceBundleURL: URL(fileURLWithPath: CommandLine.arguments[1]))
            var receipts: [Receipt] = []
            for limit in [16_384, 15_872] {
                let prefix = "Intro `" + String(repeating: "x", count: limit - 13) + "` "
                let source = prefix + "an test remains here.\r\n\r\n`an test private` e\u{301} 👩🏽‍💻"
                let document = try await QualityDocument.prepare(source: source, revision: UUID())
                let expectedRange = (source as NSString).range(of: "an test")
                let full = try await Task.detached { try engine.check(text: document.projection.text, language: "en") }.value
                let response = try JSONSerialization.jsonObject(with: full) as! [String: Any]
                let raw = response["matches"] as! [[String: Any]]
                let reference = raw.filter { item in
                    let rule = item["rule"] as? [String: Any]
                    return rule?["id"] as? String == "EN_A_VS_AN" && item["offset"] as? Int == expectedRange.location
                }
                guard reference.count == 1 else { throw Failure.missingReference }
                let findings = try await BundledRuleReviewer(engine: engine).check(document, language: "en")
                let selected = findings.filter { $0.ruleID == "EN_A_VS_AN" && $0.range.location == expectedRange.location }
                guard selected.count == 1, let finding = selected.first else { throw Failure.missingFinding }
                let prepared = try await finding.prepareCorrection("a", source: source, revision: document.revision)
                let corrected = try prepared.admitting(source: source, revision: document.revision)
                guard corrected.utf8.elementsEqual((prefix + "a test remains here.\r\n\r\n`an test private` e\u{301} 👩🏽‍💻").utf8) else { throw Failure.incorrectCorrection }
                do {
                    _ = try prepared.admitting(source: source, revision: UUID())
                    throw Failure.staleAdmitted
                } catch QualityError.staleSource { }
                let control = try await QualityDocument.prepare(source: corrected, revision: UUID())
                let rechecked = try await BundledRuleReviewer(engine: engine).check(control, language: "en")
                guard !rechecked.contains(where: { $0.ruleID == "EN_A_VS_AN" }) else { throw Failure.incorrectCorrection }
                let privateRange = (source as NSString).range(of: "an test private")
                guard !findings.contains(where: { NSIntersectionRange($0.range, privateRange).length > 0 }) else { throw Failure.leakedCode }
                receipts.append(Receipt(boundary: limit, utf16: source.utf16.count, referenceMatches: reference.count,
                    reviewedMatches: selected.count, sourceSHA256: SHA256.hash(data: Data(source.utf8)).map { String(format: "%02x", $0) }.joined(),
                    correctionVerified: true, staleRejected: true, negativeControlClear: true))
            }
            FileHandle.standardOutput.write(try JSONEncoder().encode(receipts))
            FileHandle.standardOutput.write(Data("\n".utf8))
        } catch {
            FileHandle.standardError.write(Data((String(describing: error) + "\n").utf8))
            exit(1)
        }
    }
}
