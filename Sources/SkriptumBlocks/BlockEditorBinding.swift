import SwiftUI

@MainActor enum BlockEditorBinding {
    static func text(readSource: @escaping () -> String, writeText: @escaping (String) -> Void) -> Binding<String> {
        // Read the current canonical block for every synchronization; the row
        // value may have been constructed before a successful native keystroke.
        return Binding(get: { BlockProjection(readSource()).text }, set: writeText)
    }
}
