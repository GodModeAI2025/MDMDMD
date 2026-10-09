import Foundation
import Observation
#if canImport(SkriptumWorkspaceClient)
import SkriptumWorkspaceClient
#endif

enum WorkspaceAccountOperationOutcome: Equatable, Sendable {
    case signedIn, cancelled, authenticationUnavailable
    case unavailable(WorkspaceAccountUnavailableReason)
    case logout(WorkspaceAccountRemoteOutcome)
    case deletion(WorkspaceAccountDeletionResult)
}

/// Per-window view data only. Tokens, proof, receipts, clients and admission
/// tickets remain in their owners and are never properties on this model.
@MainActor @Observable final class WorkspaceAccountPresentation {
    let windowID: UUID
    private(set) var state: WorkspaceAccountState
    private(set) var operationOutcome: WorkspaceAccountOperationOutcome?
    private(set) var cleanupOutcome: WorkspaceLogoutOutcome?
    private(set) var canRetryDeletionLocalCleanup = false

    init(windowID: UUID, state: WorkspaceAccountState = .signedOut) {
        self.windowID = windowID
        self.state = state
    }

    var isBusy: Bool {
        switch state {
        case .signingIn, .restoring, .signingOut, .reauthenticatingForDeletion, .deleting: true
        default: false
        }
    }

    func publish(state: WorkspaceAccountState, outcome: WorkspaceAccountOperationOutcome?, cleanup: WorkspaceLogoutOutcome?, canRetryDeletionLocalCleanup: Bool = false) {
        self.state = state
        operationOutcome = outcome
        cleanupOutcome = cleanup
        self.canRetryDeletionLocalCleanup = canRetryDeletionLocalCleanup
    }
}
