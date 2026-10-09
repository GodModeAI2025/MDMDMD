import Foundation
#if canImport(SkriptumCore)
import SkriptumCore
#endif

@MainActor struct WorkspaceAccountSheetRequest: Identifiable {
    struct Identity: Hashable, Sendable {
        let windowID: UUID
        let locator: OwnedLibraryLocator
        let facadeID: UUID
    }
    struct LifecycleIdentity: Hashable, Sendable {
        let facadeID: UUID
        let locator: OwnedLibraryLocator?
    }
    let windowID: UUID
    let runtime: WorkspaceAccountRuntime
    let presentation: WorkspaceAccountPresentation
    let locator: OwnedLibraryLocator
    let facadeID: UUID
    let libraryTitle: String
    nonisolated var id: Identity { Identity(windowID: windowID, locator: locator, facadeID: facadeID) }
}
