import Foundation
import CloudKit

/// Per-scene network admission. Local mutations are durable before requesting
/// work; this helper neither opens documents nor owns CloudKit/AI credentials.
@MainActor final class ICloudForegroundRefresh {
    private(set) var isActive = false
    private var pending = false
    private var requestID = UUID()
    private var generation = UUID()
    private var task: Task<Void, Never>?
    private var workerID = UUID()
    private let pause: @MainActor (Duration) async throws -> Void
    private let refresh: @MainActor () async -> Void
    init(pause: @escaping @MainActor (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
         refresh: @escaping @MainActor () async -> Void) {
        self.pause = pause; self.refresh = refresh
    }
    func setActive(_ active: Bool) {
        guard active != isActive else { return }
        isActive = active
        if active { request() }
        else {
            generation = UUID(); task?.cancel(); pending = false
        }
    }
    func request() {
        guard isActive else { return }
        requestID = UUID(); pending = true
        guard task == nil else { return }
        let attempt = generation, worker = UUID(); workerID = worker
        task = Task { @MainActor [weak self] in await self?.run(attempt: attempt, worker: worker) }
    }
    private func run(attempt: UUID, worker: UUID) async {
        defer {
            if workerID == worker {
                task = nil
                // A canceled CloudKit operation can take time to finish. A
                // returning scene waits for that exact worker before replacing
                // it; cancellation never permits two refreshes to overlap.
                if isActive, pending { request() }
            }
        }
        while isActive, generation == attempt, pending, !Task.isCancelled {
            let request = requestID
            do { try await pause(.milliseconds(600)) } catch { return }
            guard isActive, generation == attempt, !Task.isCancelled else { return }
            // A newer edit restarts the quiet period without canceling an
            // already-running CloudKit write. There is only one worker.
            guard request == requestID else { continue }
            pending = false
            await refresh()
        }
    }
}

/// Cancellation is a lifecycle pause only when this caller was canceled and
/// the exact transport/account session remains reusable. Never hide real errors.
enum ICloudRefreshCancellation {
    static func isExpectedPause(_ error: any Error, callerCancelled: Bool, transportCurrent: Bool) -> Bool {
        guard callerCancelled, transportCurrent else { return false }
        return error is CancellationError || (error as? CKError)?.code == .operationCancelled
    }
}
