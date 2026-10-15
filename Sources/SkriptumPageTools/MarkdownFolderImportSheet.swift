import SwiftUI
import UniformTypeIdentifiers

/// A folder is an explicit read boundary, not a replacement library. Selecting
/// files inside it imports only those documents and their referenced images.
struct MarkdownFolderImportSheet: View {
    let library: WritingLibrary
    let spaceID: UUID?
    let prepare: () -> Bool
    let imported: ([UUID]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var choosingFolder = false
    @State private var directory: URL?
    @State private var catalogRequest = UUID()
    @State private var paths: [String] = []
    @State private var selected: Set<String> = []
    @State private var loading = false
    @State private var importing = false
    @State private var error: String?
    @State private var importTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Wählen Sie den Ordner mit Ihren Markdown-Dateien und Bildern. Danach wählen Sie die Texte für den Import aus.")
                    Button(directory == nil ? "Ordner auswählen" : "Anderen Ordner auswählen", systemImage: "folder") { choosingFolder = true }
                        .disabled(loading || importing)
                    if let directory { Text(directory.lastPathComponent).foregroundStyle(.secondary) }
                } footer: {
                    Text("Die Originaltexte bleiben unverändert. PNG- und JPEG-Bilder werden in Ihre Bibliothek kopiert. Internetbilder und Bilder außerhalb des Ordners werden nicht geladen. HTML-Bildverweise und Verknüpfungen auf andere Dokumente bleiben im Quelltext.")
                }
                if loading { ProgressView("Texte suchen …") }
                if !paths.isEmpty {
                    Section("Texte auswählen") {
                        ForEach(paths, id: \.self) { path in
                            Toggle(isOn: Binding(get: { selected.contains(path) }, set: { enabled in
                                if enabled { selected.insert(path) } else { selected.remove(path) }
                            })) { Text(verbatim: path) }
                            .disabled(importing)
                        }
                    }
                } else if directory != nil && !loading && error == nil {
                    Text("Dieser Ordner enthält keine Markdown- oder Textdateien.").foregroundStyle(.secondary)
                }
                if let error { Text(error).foregroundStyle(.red).accessibilityIdentifier("markdownImportError") }
                if importing { ProgressView("Texte und Bilder importieren …") }
            }
            .navigationTitle("Markdown mit Bildern")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { importTask?.cancel(); dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Importieren") { startImport() }
                        .disabled(selected.isEmpty || loading || importing)
                }
            }
            .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder]) { result in
                do { directory = try result.get(); error = nil; catalogRequest = UUID() }
                catch { self.error = error.localizedDescription }
            }
            .task(id: catalogRequest) {
                let request = catalogRequest
                paths = []; selected = []
                guard let directory else { return }
                loading = true
                defer { if request == catalogRequest { loading = false } }
                do {
                    let catalog = try await MarkdownImportWork.catalog(directory: directory)
                    try Task.checkCancellation()
                    guard request == catalogRequest else { return }
                    paths = catalog
                    // Choosing a folder never implicitly chooses all documents.
                    if catalog.count == 1 { selected = Set(catalog) }
                } catch is CancellationError { }
                catch { if !Task.isCancelled && request == catalogRequest { self.error = error.localizedDescription } }
            }
            .onDisappear { importTask?.cancel() }
        }
        #if os(macOS)
        .frame(minWidth: 480, idealWidth: 620, minHeight: 420, idealHeight: 600)
        #endif
    }
    private func startImport() {
        guard let directory, prepare() else { return }
        let files = paths.filter { selected.contains($0) }.map { directory.appendingPathComponent($0) }
        importing = true; error = nil
        importTask = Task {
            defer { importing = false; importTask = nil }
            if let ids = await library.importMarkdown(files: files, sourceDirectory: directory, spaceID: spaceID) {
                imported(ids); dismiss()
            } else if !Task.isCancelled { error = library.saveError ?? "Der Import konnte nicht abgeschlossen werden." }
        }
    }
}
