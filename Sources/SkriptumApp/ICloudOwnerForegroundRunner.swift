import SwiftUI

/// Uses the UIWindowScene actually hosting the document view, rather than the
/// potentially inactive SwiftUI phase of its DocumentGroupLaunchScene ancestor.
struct ICloudOwnerForegroundRunner: ViewModifier {
    let library: WritingLibrary
    @State private var registration = ICloudOwnerForegroundRegistration()
    func body(content: Content) -> some View {
        content.background {
            WorkspaceSceneActivityReader(changed: { active in
                registration.update(library: library, active: active)
            }, detached: { registration.close(ifBoundTo: library) })
            .frame(width: 0, height: 0)
            .id(library.libraryIdentity)
        }
    }
}
