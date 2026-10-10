import Foundation
#if canImport(UIKit)
import UIKit
@available(iOS 27.0, *)
@MainActor public enum NativeWritingReviewer {
    /// These are spelling dictionaries; this property makes no grammar-language promise.
    public static var spellingLanguages: [String] { UITextChecker.availableLanguages }
    public static func check(_ document: QualityDocument, spellingLanguage: String? = nil,
                             progress: ((Int, Int) -> Void)? = nil) async throws -> [QualityFinding] {
        guard document.source.utf8.count <= 8 * 1024 * 1024 else { throw QualityError.inputTooLarge }
        if let spellingLanguage, !spellingLanguages.contains(spellingLanguage) { throw QualityError.unsupportedLanguage }
        let checker = UITextChecker()
        let chunks = try QualityTextChunks.make(document.projection.text)
        var findings: [QualityFinding] = []
        for (index, chunk) in chunks.enumerated() {
            try Task.checkCancellation()
            progress?(index, chunks.count)
            var position = 0
            while let spellingLanguage, position < chunk.range.length {
                try Task.checkCancellation()
                let misspelled = checker.rangeOfMisspelledWord(in: chunk.text,
                    range: NSRange(location: position, length: chunk.range.length - position), startingAt: position,
                    wrap: false, language: spellingLanguage)
                guard misspelled.location != NSNotFound, misspelled.length > 0 else { break }
                guard misspelled.location >= position, NSMaxRange(misspelled) <= chunk.range.length else { throw QualityError.invalidResponse }
                let absolute = NSRange(location: chunk.range.location + misspelled.location, length: misspelled.length)
                if let finding = try? QualityFinding.make(document: document, range: absolute,
                    message: "Möglicher Rechtschreibfehler", replacements: Array((checker.guesses(forWordRange: misspelled, in: chunk.text, language: spellingLanguage) ?? []).prefix(50)),
                    ruleID: "APPLE_SPELLING", kind: .spelling, engine: "Apple Rechtschreibung") { findings.append(finding) }
                position = NSMaxRange(misspelled)
                await Task.yield()
            }
            let gate = GrammarContinuationGate()
            let grammar: [QualityFinding] = try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    gate.install(continuation)
                    let completion = NativeGrammarResultMapper.completion(document: document, gate: gate,
                        offset: chunk.range.location, length: chunk.range.length)
                    checker.requestGrammarChecking(of: chunk.text, range: NSRange(location: 0, length: chunk.range.length),
                        waitForAllResults: true, completionHandler: completion)
                }
            } onCancel: { gate.cancel() }
            try Task.checkCancellation()
            findings += grammar
            progress?(index + 1, chunks.count)
            await Task.yield()
        }
        return findings + LocalStyleReviewer.check(document)
    }

}
#endif

/// NSTextCheckingResult objects are consumed synchronously on the SDK's calling queue.
/// Only immutable Sendable findings cross back through the continuation gate.
/// Explicit Sendable/nonisolated callback avoids inheriting NativeWritingReviewer MainActor.
enum NativeGrammarResultMapper {
    nonisolated static func completion(document: QualityDocument, gate: GrammarContinuationGate, offset: Int = 0, length: Int? = nil) -> @Sendable ([NSTextCheckingResult]) -> Void {
        return { @Sendable results in
            var converted: [QualityFinding] = []
            let documentLength = document.source.utf16.count
            let checkedLength = length ?? documentLength
            guard offset >= 0, offset <= documentLength, checkedLength >= 0,
                  checkedLength <= documentLength - offset else { gate.finish([]); return }
            for result in results {
                let totalLength = length ?? (document.source as NSString).length
                guard result.range.location >= 0, result.range.length > 0, result.range.location <= totalLength, result.range.length <= totalLength - result.range.location else { continue }
                if result.resultType == .correction, let replacement = result.replacementString {
                    if let finding = try? QualityFinding.make(document: document, range: NSRange(location: offset + result.range.location, length: result.range.length), message: "Apple Korrekturvorschlag", replacements: [replacement], ruleID: "APPLE_CORRECTION", kind: .grammar, engine: "Apple Grammatik (Systemverfügbarkeit)") { converted.append(finding) }
                } else if result.resultType == .grammar {
                    for detail in result.grammarDetails ?? [] {
                        guard let relative = detail["NSGrammarRange"] as? NSValue else { continue }
                        let local = relative.rangeValue
                        guard local.location >= 0, local.length > 0, local.location <= result.range.length, local.length <= result.range.length - local.location else { continue }
                        let absolute = NSRange(location: offset + result.range.location + local.location, length: local.length)
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
