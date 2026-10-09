import Foundation
#if canImport(SkriptumWorkspaceClient)
import SkriptumWorkspaceClient
#endif

struct WorkspaceAccountScope: Hashable, Sendable {
    let origin: WorkspaceOrigin
    let profileID: String
    let accountID: UUID

    init(origin: WorkspaceOrigin, profileID: String, accountID: UUID) throws {
        guard origin.url.scheme == "https" else { throw WorkspaceDeploymentError.invalidOrigin }
        guard WorkspaceDeploymentConfiguration.validProfile(profileID) else {
            throw WorkspaceDeploymentError.invalidProfile
        }
        self.origin = origin
        self.profileID = profileID
        self.accountID = accountID
    }
}

enum WorkspaceAccountUnavailableReason: Equatable, Sendable {
    case deploymentNotConfigured, invalidBinding, credentialUnavailable, networkUnavailable
    case localSignOutPersistenceUnavailable, localDenialUnavailable
}

enum WorkspaceAccountRemoteOutcome: Equatable, Sendable {
    case confirmedRevocation, revocationUnknown, confirmedAccountTombstone, deletionUnknown
}

/// Presentation state only; never stores credentials, proofs or receipts.
enum WorkspaceAccountState: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    case unavailable(WorkspaceAccountUnavailableReason)
    case signedOut
    case signingIn(attemptID: UUID)
    case restoring(scope: WorkspaceAccountScope)
    case active(scope: WorkspaceAccountScope, sessionID: UUID, expiresAt: Date)
    case signingOut(scope: WorkspaceAccountScope)
    case localDenied(scope: WorkspaceAccountScope, remoteOutcome: WorkspaceAccountRemoteOutcome)

    var description: String {
        switch self {
        case .unavailable: "WorkspaceAccountState.unavailable"
        case .signedOut: "WorkspaceAccountState.signedOut"
        case .signingIn: "WorkspaceAccountState.signingIn"
        case .restoring: "WorkspaceAccountState.restoring"
        case .active: "WorkspaceAccountState.active"
        case .signingOut: "WorkspaceAccountState.signingOut"
        case .localDenied: "WorkspaceAccountState.localDenied"
        }
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: ["state": description]) }
}
