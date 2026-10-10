#if DEBUG
import SwiftUI

/// Unprovisioned real shared view: scene lifecycle must not create CloudKit
/// state or start any account lookup, document write, or AI provider.
struct ICloudSharedForegroundQAHost: View {
    @State private var session = ICloudSharedSession(directory: FileManager.default.temporaryDirectory.appendingPathComponent("ScriptumSharedForegroundQA-" + UUID().uuidString))
    var body: some View {
        ICloudSharedWritingView(session: session, retry: { await session.synchronize() })
    }
}
#endif
