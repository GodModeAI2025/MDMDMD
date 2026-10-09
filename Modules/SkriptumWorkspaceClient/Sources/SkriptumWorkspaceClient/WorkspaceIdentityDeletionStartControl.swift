import Foundation

/// One-way, synchronous authorization-start fence shared across the caller's
/// executor and identity actor. Started is not a server-deletion confirmation.
public final class WorkspaceIdentityDeletionStartControl: @unchecked Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public enum State: Equatable, Sendable { case pending, cancelled, started }
    private let lock = NSLock()
    private var value: State = .pending
    public init() {}
    public var state: State { lock.withLock { value } }
    public func cancel() { lock.withLock { if value == .pending { value = .cancelled } } }
    func claimStart() throws {
        try lock.withLock {
            switch value {
            case .pending: value = .started
            case .cancelled: throw CancellationError()
            case .started: throw WorkspaceClientError.invalidRequest
            }
        }
    }
    public var description: String { "WorkspaceIdentityDeletionStartControl(<opaque>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: ["control": "<opaque>"]) }
}
