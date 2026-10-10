import Foundation

/// Owns submission lifetimes and serializes OS request changes through their
/// asynchronous confirmations, including cancellation after a pending submit.
public actor BackgroundRequestQueue {
    private var tail: Task<Void, Never>?
    private var tailID: UUID?
    public init() {}
    public func perform(_ operation: @escaping @Sendable () async -> Void) async {
        let (id, next) = enqueue(operation)
        await next.value
        if tailID == id { tail = nil; tailID = nil }
    }
    func enqueue(_ operation: @escaping @Sendable () async -> Void) -> (UUID, Task<Void, Never>) {
        let previous = tail
        let id = UUID()
        let next = Task { await previous?.value; await operation() }
        tail = next; tailID = id
        return (id, next)
    }
}
