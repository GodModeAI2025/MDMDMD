import Foundation

/// A synchronous native driver. Each call owns and tears down its isolate on
/// the calling thread, including on failure. No network or automatic fallback.
public protocol BundledGrammarEngine: Sendable {
    var languages: Set<String> { get }
    func check(text: String, language: String) throws -> Data
}

/// Uses the app's source-bound correction decoder. Availability requires an
/// explicitly constructed, verified native driver; no engine is enabled here.
public struct BundledRuleReviewer: Sendable {
    private let engine: any BundledGrammarEngine
    public init(engine: any BundledGrammarEngine) { self.engine = engine }

    @concurrent public func check(_ document: QualityDocument, language: String,
        progress: @MainActor @Sendable (Int, Int) -> Void = { _, _ in }) async throws -> [QualityFinding] {
        try Task.checkCancellation()
        guard document.source.utf8.count <= 8 * 1024 * 1024 else { throw QualityError.inputTooLarge }
        guard !language.isEmpty, language.utf8.count <= 32, engine.languages.contains(language) else {
            throw QualityError.unsupportedLanguage
        }
        let chunks = try QualityTextChunks.reviewWindows(document.projection.text)
        await progress(0, chunks.count)
        var findings: [QualityFinding] = []
        for (index, window) in chunks.enumerated() {
            let chunk = window.request
            try Task.checkCancellation()
            guard chunk.text.utf8.count <= 100_000, !chunk.text.contains("\0") else { throw QualityError.inputTooLarge }
            let data = try await NativeRuleWorker.run(engine: engine, text: chunk.text, language: language)
            try Task.checkCancellation()
            let values = try RuleResponseDecoder.decode(data, document: document, submittedRange: chunk.range, engine: .bundledNative)
                .filter { NSLocationInRange($0.range.location, window.ownedRange) }
            guard values.count <= 5000 - findings.count else { throw QualityError.responseTooLarge }
            findings.append(contentsOf: values)
            await progress(index + 1, chunks.count)
        }
        try Task.checkCancellation()
        return findings
    }
}

private enum NativeRuleWorker {
    // Process-wide, across reviewers and windows. A canceled caller can return
    // promptly, but the next isolate waits until the current driver cleans up.
    static let queue = DispatchQueue(label: "com.mobilebox.Skriptum.grammar", qos: .userInitiated)
    static func run(engine: any BundledGrammarEngine, text: String, language: String) async throws -> Data {
        let request = NativeRuleRequest()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                request.install(continuation)
                queue.async {
                    guard request.begin() else { return }
                    request.finish(Result { try engine.check(text: text, language: language) })
                }
            }
        } onCancel: { request.cancel() }
    }
}

/// One continuation owner even when cancellation races installation, execution
/// or completion. An in-flight C call is allowed to finish and release memory;
/// its canceled result is discarded rather than published as partial findings.
private final class NativeRuleRequest: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Data, Error>?
    private var canceled = false
    func install(_ value: CheckedContinuation<Data, Error>) {
        let reject = lock.withLock {
            if canceled { return true }
            continuation = value; return false
        }
        if reject { value.resume(throwing: CancellationError()) }
    }
    func begin() -> Bool { lock.withLock { !canceled } }
    func finish(_ result: Result<Data, Error>) {
        let value = lock.withLock { let value = continuation; continuation = nil; return value }
        value?.resume(with: result)
    }
    func cancel() {
        let value = lock.withLock { canceled = true; let value = continuation; continuation = nil; return value }
        value?.resume(throwing: CancellationError())
    }
}
