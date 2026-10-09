import Foundation

/// Only Foundation-provided app-container roots are resolved. No caller-supplied
/// library, import URL or interior directory can be normalized through this API.
enum WorkspaceSystemContainerRoots {
    static let documents = URL.documentsDirectory.resolvingSymlinksInPath()
    static let applicationSupport = URL.applicationSupportDirectory.resolvingSymlinksInPath()
}
