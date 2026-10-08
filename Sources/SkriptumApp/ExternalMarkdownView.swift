import SwiftUI
import UIKit

struct ExternalMarkdownView: View {
    let document: MarkdownDocument
    @Environment(\.undoManager) private var undoManager
    @Environment(\.openWindow) private var openWindow
    @State private var selection = NSRange(location: 0, length: 0)
    @State private var preview = false
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if preview {
                    ScrollView { Text(.init(document.text)).textSelection(.enabled).padding(28).frame(maxWidth: 800, alignment: .leading) }
                } else {
                    MarkdownTextEditor(text: Binding(get: { document.text }, set: { document.replaceText($0, undoManager: undoManager) }), selection: $selection, onCommandHandled: {})
                }
                WritingStatusBar(markdown: document.text, saved: nil, goal: 0)
            }
            .toolbar {
                Button("Bibliothek", systemImage: "books.vertical") { openWindow(id: "library") }
                Button("Rückgängig", systemImage: "arrow.uturn.backward") { undoManager?.undo() }.disabled(undoManager?.canUndo != true)
                Button("Wiederholen", systemImage: "arrow.uturn.forward") { undoManager?.redo() }.disabled(undoManager?.canRedo != true)
                Button(preview ? "Quelltext" : "Vorschau", systemImage: preview ? "chevron.left.forwardslash.chevron.right" : "eye") { preview.toggle() }
            }
        }
    }
}

struct MarkdownShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

struct SharedMarkdown: Identifiable {
    let id = UUID()
    let url: URL
}
