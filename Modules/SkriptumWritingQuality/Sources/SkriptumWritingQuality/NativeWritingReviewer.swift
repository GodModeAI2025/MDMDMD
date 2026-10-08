import Foundation
#if canImport(UIKit)
import UIKit
@available(iOS 27.0, *)
@MainActor public enum NativeWritingReviewer {
    /// These are spelling dictionaries; this property makes no grammar-language promise.
    public static var spellingLanguages: [String] { UITextChecker.availableLanguages }
    public static func check(_ document: QualityDocument, spellingLanguage: String) async throws -> [QualityFinding] {
        guard document.source.utf8.count <= 100_000 else { throw QualityError.inputTooLarge }
        guard spellingLanguages.contains(spellingLanguage) else { throw QualityError.unsupportedLanguage }
        let checker = UITextChecker()
        let projection = MarkdownProjection(document.source)
        let range = NSRange(location: 0, length: (projection.text as NSString).length)
        var findings: [QualityFinding] = []
        var position = 0
        while position < range.length {
            try Task.checkCancellation()
            let misspelled = checker.rangeOfMisspelledWord(in: projection.text, range: NSRange(location: position, length: range.length - position), startingAt: position, wrap: false, language: spellingLanguage)
            guard misspelled.location != NSNotFound, misspelled.length > 0 else { break }
            guard misspelled.location >= position, NSMaxRange(misspelled) <= range.length else { throw QualityError.invalidResponse }
            if let finding = try? QualityFinding.make(document: document, range: misspelled, message: "Möglicher Rechtschreibfehler", replacements: Array((checker.guesses(forWordRange: misspelled, in: projection.text, language: spellingLanguage) ?? []).prefix(50)), ruleID: "APPLE_SPELLING", kind: .spelling, engine: "Apple Rechtschreibung") { findings.append(finding) }
            position = NSMaxRange(misspelled)
        }
        let gate = GrammarContinuationGate()
        let grammar: [QualityFinding] = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                gate.install(continuation)
                let completion = NativeGrammarResultMapper.completion(document: document, gate: gate)
                checker.requestGrammarChecking(of: projection.text, range: range, waitForAllResults: true, completionHandler: completion)
            }
        } onCancel: { gate.cancel() }
        try Task.checkCancellation()
        findings += grammar
        return findings + LocalStyleReviewer.check(document)
    }
}
#endif

/// NSTextCheckingResult objects are consumed synchronously on the SDK's calling queue.
/// Only immutable Sendable findings cross back through the continuation gate.
/// Explicit Sendable/nonisolated callback avoids inheriting NativeWritingReviewer MainActor.
enum NativeGrammarResultMapper {
    nonisolated static func completion(document: QualityDocument, gate: GrammarContinuationGate) -> @Sendable ([NSTextCheckingResult]) -> Void {
        return { @Sendable results in
            var converted: [QualityFinding] = []
            for result in results {
                let totalLength = (document.source as NSString).length
                guard result.range.location >= 0, result.range.length > 0, result.range.location <= totalLength, result.range.length <= totalLength - result.range.location else { continue }
                if result.resultType == .correction, let replacement = result.replacementString {
                    if let finding = try? QualityFinding.make(document: document, range: result.range, message: "Apple Korrekturvorschlag", replacements: [replacement], ruleID: "APPLE_CORRECTION", kind: .grammar, engine: "Apple Grammatik (Systemverfügbarkeit)") { converted.append(finding) }
                } else if result.resultType == .grammar {
                    for detail in result.grammarDetails ?? [] {
                        guard let relative = detail["NSGrammarRange"] as? NSValue else { continue }
                        let local = relative.rangeValue
                        guard local.location >= 0, local.length > 0, local.location <= result.range.length, local.length <= result.range.length - local.location else { continue }
                        let absolute = NSRange(location: result.range.location + local.location, length: local.length)
                        let message = detail["NSGrammarUserDescription"] as? String ?? "Apple Grammatikhinweis"
                        let corrections = detail["NSGrammarCorrections"] as? [String] ?? []
                        if let finding = try? QualityFinding.make(document: document, range: absolute, message: message, replacements: Array(corrections.prefix(50)), ruleID: "APPLE_GRAMMAR", kind: .grammar, engine: "Apple Grammatik (Systemverfügbarkeit)") { converted.append(finding) }
                    }
                }
            }
            gate.finish(converted)
        }
    }
}
