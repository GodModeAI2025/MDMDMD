import SwiftUI

/// External files use Apple's document lifecycle, independent of library imports.
struct MacExternalMarkdownView: View {
    let document: MarkdownDocument
    @Environment(\.undoManager) private var undoManager
    @Environment(\.openWindow) private var openWindow
    @State private var selection = NSRange(location: 0, length: 0)
    @State private var preview = false

    var body: some View {
        MacManuscriptSurface {
            if preview {
                MarkdownPreview(title: "Markdown-Datei", markdown: document.text)
            } else {
                // Document.replaceText owns undo; AppKit must not register it again.
                MarkdownTextEditor(text: Binding(get: { document.text }, set: {
                    document.replaceText($0, undoManager: undoManager)
                }), selection: $selection, preferences: MacWritingAppearance.defaults,
                    registersNativeUndo: false, onCommandHandled: {})
            }
        }
        .toolbar {
            ToolbarItem {
                Button("Bibliothek öffnen", systemImage: "books.vertical") { openWindow(id: "library") }
                    .help("Spaces und Bibliothek öffnen").labelStyle(.iconOnly)
            }
            ToolbarItem {
                Toggle("Vorschau", systemImage: "eye", isOn: $preview)
                    .toggleStyle(.button).labelStyle(.iconOnly).help("Markdown-Vorschau ein- oder ausblenden")
            }
        }
    }
}
