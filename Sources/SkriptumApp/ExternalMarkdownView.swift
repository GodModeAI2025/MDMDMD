import SwiftUI
import UIKit

struct ExternalMarkdownView: View {
    let document: MarkdownDocument
    @State var library: WritingLibrary
    var libraryActivated: ((WritingLibrary) -> Void)? = nil
    @Environment(\.undoManager) private var undoManager
    @State private var showingLibrary = false
    @State private var selection = NSRange(location: 0, length: 0)
    @State private var preview = false
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if preview {
                    MarkdownPreview(title: "Markdown-Datei", markdown: document.text)
                } else {
                    MarkdownTextEditor(text: Binding(get: { document.text }, set: { document.replaceText($0, undoManager: undoManager) }), selection: $selection, onCommandHandled: {})
                }
                WritingStatusBar(markdown: document.text, saved: nil, goal: 0)
            }
            .fullScreenCover(isPresented: $showingLibrary) { WritingWorkspace(library: library, closeLibrary: { showingLibrary = false }, libraryActivated: { library = $0; libraryActivated?($0) }) }
            .toolbar {
                Button("Bibliothek", systemImage: "books.vertical") { showingLibrary = true }
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


