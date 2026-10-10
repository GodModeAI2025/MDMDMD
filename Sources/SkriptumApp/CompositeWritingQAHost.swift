#if DEBUG
import SwiftUI
import CryptoKit
#if canImport(SkriptumCore)
import SkriptumCore
#endif

struct CompositeWritingQAHost: View {
    @State private var library: WritingLibrary?
    @State private var original: Page?
    @State private var showingEditor = false
    @State private var focus = false
    @State private var report = ""
    var body: some View {
        NavigationStack {
            List {
                Text("Neue temporäre Manuskriptbibliothek; kein iCloud- oder KI-Zugang.")
                if library != nil {
                    Button("Manuskript öffnen") { showingEditor = true }
                    Button("Gespeicherte Fassung prüfen", action: inspect)
                }
                Text(report).textSelection(.enabled)
            }.navigationTitle("Manuskriptprüfung")
                .sheet(isPresented: $showingEditor) {
                    if let library, let page = library.pages.first {
                        NavigationStack {
                            PageWritingView(page: page, library: library, focus: $focus, createSubpage: {})
                                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Prüfung schließen") { showingEditor = false } } }
                        }
                    }
                }
                .task {
                    guard library == nil else { return }
                    do {
                        let token = UUID().uuidString
                        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ScriptumCompositeWritingUIQA-" + token)
                        let documents = root.appendingPathComponent("Documents")
                        let store = try LibraryStore(directory: documents.appendingPathComponent("Skriptum"))
                        let space = try store.createSpace(title: "Manuskriptprüfung")
                        var text = "# Kapitel Eins\r\n\r\nFließtext mit **Fettdruck**, *Kursivschrift*, e\u{301} und 🦊.\r\n\r\n## Zweiter Abschnitt\r\n\r\nWeiterer Fließtext bleibt in normaler Größe.\r\n\r\n```swift\r\nlet code = 42\r\n```\r\n"
                        if ProcessInfo.processInfo.arguments.contains("--scriptum-composite-large-ui-qa") {
                            text += String(repeating: "\r\nAbsatz des langen Manuskripts: Quellen, Gedanken und eine präzise Frage. 🦊\r\n", count: 8000)
                        }
                        let created = try store.createPage(spaceID: space.id, title: "Mehrteiliger Import", markdown: text)
                        try store.setBlocks(pageID: created.id, blocks: [Block(markdown: text)], baseRevision: created.revision)
                        guard let single = store.snapshot.pages.first(where: { $0.id == created.id }), single.blocks.count == 1,
                              single.markdown.utf8.elementsEqual(text.utf8) else { throw CocoaError(.fileReadCorruptFile) }
                        original = single
                        guard let preferences = UserDefaults(suiteName: "Scriptum.CompositeWritingQA." + token) else { return }
                        library = try WritingLibrary(store: store, documentRoot: documents, supportRoot: root.appendingPathComponent("Support"), preferences: preferences)
                        inspect()
                    } catch { report = error.localizedDescription }
                }
        }
    }
    private func inspect() {
        do {
            guard let library, let store = library.store, let original,
                  let page = try LibraryStore(directory: store.directory).snapshot.pages.first else { return }
            let exact = page.markdown.utf8.elementsEqual(original.markdown.utf8)
            let ids = page.blocks.map(\.id) == original.blocks.map(\.id)
            report = "Gespeicherter Schluss: \(String(page.markdown.suffix(80)))\nGespeicherte Blöcke: \(page.blocks.count)\nUrsprüngliche Block-IDs: \(ids ? "unverändert" : "geändert")\nOriginalbytes: \(exact ? "unverändert" : "bearbeitet")\nUTF-8-Bytes: \(page.markdown.utf8.count)\nSHA256: \(SHA256.hash(data: Data(page.markdown.utf8)).map { String(format: "%02x", $0) }.joined())"
        } catch { report = error.localizedDescription }
    }
}
#endif
