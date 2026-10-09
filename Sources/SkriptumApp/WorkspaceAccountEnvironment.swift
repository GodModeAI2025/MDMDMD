import SwiftUI

extension EnvironmentValues {
    /// Injected once by the app. Absence never constructs another account runtime.
    @Entry var workspaceAccountRuntime: WorkspaceAccountRuntime?
    @Entry var workspacePresentationAnchors: WorkspacePresentationAnchors?
}
