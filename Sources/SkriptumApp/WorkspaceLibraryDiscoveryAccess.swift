import Foundation
#if canImport(SkriptumWorkspaceClient)
import SkriptumWorkspaceClient
#endif

@MainActor protocol WorkspaceLibraryDiscoveryDriver: AnyObject {
    func adopt(_ loaded: WorkspaceAccountLoadedCredential) throws
    func listLibraries(after: UUID?) async throws -> WorkspaceLibraryMetadataPage
    func libraryMetadata(id: UUID) async throws -> WorkspaceLibraryMetadata
    func validateAdmission() throws
    func withAdmittedCredential<T>(_ body: () throws -> T) throws -> T
}

/// Kernel incarnation only. Credential checks remain inside the real driver.
/// In particular, validation here never reenters the admission gate.
@MainActor final class WorkspaceLibraryDiscoveryAccess {
    let scope: WorkspaceAccountScope
    let driver: any WorkspaceLibraryDiscoveryDriver
    private let validate: @MainActor (UUID) throws -> Void
    init(scope: WorkspaceAccountScope, driver: any WorkspaceLibraryDiscoveryDriver,
         validate: @escaping @MainActor (UUID) throws -> Void) {
        self.scope = scope; self.driver = driver; self.validate = validate
    }
    func validateCurrent(windowID: UUID) throws { try validate(windowID) }
}
