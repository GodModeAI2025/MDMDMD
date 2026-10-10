import Foundation

/// Keeps CPU work off the caller's actor and forwards cancellation to its worker.
/// A late result is never admitted after caller cancellation. Synchronous parsers
/// and system decoders still need to reach their next cancellation checkpoint.
public enum ExportWorker {
    public static func run<Value: Sendable>(
        _ operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        try Task.checkCancellation()
        let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let result = try await operation()
            try Task.checkCancellation()
            return result
        }
        return try await withTaskCancellationHandler {
            let result = try await worker.value
            try Task.checkCancellation()
            return result
        } onCancel: { worker.cancel() }
    }
}
