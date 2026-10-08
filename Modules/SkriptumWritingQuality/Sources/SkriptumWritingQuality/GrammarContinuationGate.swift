import Foundation

/// State protected by one lock; only the winning completion resumes the continuation.
/// Lives outside UIKit so timeout, cancellation and stale callbacks are executable tests.
final class GrammarContinuationGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<[QualityFinding], Error>?
    private var terminal: Result<[QualityFinding], Error>?
    private var timeoutTask: Task<Void, Never>?
    private let timeoutNanoseconds: UInt64
    init(timeoutNanoseconds: UInt64 = 30_000_000_000) { self.timeoutNanoseconds = timeoutNanoseconds }
    func install(_ value: CheckedContinuation<[QualityFinding], Error>) {
        lock.lock()
        if let terminal { lock.unlock(); value.resume(with: terminal); return }
        continuation = value
        let interval = timeoutNanoseconds
        timeoutTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: interval); self?.resolve(.failure(QualityError.nativeGrammarTimeout)) }
            catch { /* Completion/cancellation stopped timeout. */ }
        }
        lock.unlock()
    }
    func finish(_ result: [QualityFinding]) { resolve(.success(result)) }
    func cancel() { resolve(.failure(CancellationError())) }
    private func resolve(_ result: Result<[QualityFinding], Error>) {
        lock.lock()
        guard terminal == nil else { lock.unlock(); return }
        terminal = result
        let value = continuation; continuation = nil
        let timer = timeoutTask; timeoutTask = nil
        lock.unlock()
        timer?.cancel()
        value?.resume(with: result)
    }
}
