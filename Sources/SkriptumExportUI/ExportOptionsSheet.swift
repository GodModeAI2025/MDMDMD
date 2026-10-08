import SwiftUI
import UIKit
#if canImport(SkriptumExport)
import SkriptumExport
#endif

struct ExportOptionsSheet: View {
    let page: WritingPage
    var assets: [String: ExportAsset] = [:]
    var chapters: [ExportInput] = []
    @Environment(\.dismiss) private var dismiss
    @State private var format = Format.pdf
    @State private var profile = ExportProfile.standard
    @State private var author = ""
    @State private var language = "de"
    @State private var busy = false
    @State private var exportTask: Task<Void, Never>?
    @State private var error: String?
    @State private var warnings: [String] = []
    @State private var shared: ExportShareItem?
    private enum Format: String, CaseIterable { case md, html, docx, epub, pdf }
    var body: some View {
        NavigationStack {
            Form {
                Section("Dokument") {
                    Text(page.title).font(.headline)
                    Picker("Format", selection: $format) {
                        ForEach(Format.allCases.filter { chapters.isEmpty || $0 != .md }, id: \.self) { value in Text(value.rawValue.uppercased()).tag(value) }
                    }
                    Picker("Satzprofil", selection: $profile) {
                        Text("Standard").tag(ExportProfile.standard)
                        Text("Manuskript").tag(ExportProfile.manuscript)
                        Text("E-Book").tag(ExportProfile.ebook)
                    }.disabled(format == .md)
                }
                Section("Metadaten") {
                    TextField("Autor oder Autorin", text: $author)
                    TextField("Sprache (z. B. de oder en)", text: $language).textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                Section {
                    Text(chapters.isEmpty ? "PDF verwendet A4-Seiten. Markdown bleibt im Original erhalten. Eingefügte Bilder werden mit dem Dokument exportiert." : "\(chapters.count) Kapitel werden in der gewählten Reihenfolge zusammengestellt. Seitenüberschriften, Fußnoten und Bilder bleiben pro Kapitel erhalten. Die Originalseiten bleiben unverändert.").font(.footnote).foregroundStyle(.secondary)
                }
                if let error { Section("Export fehlgeschlagen") { Text(error).foregroundStyle(.red).textSelection(.enabled) } }
                if !warnings.isEmpty { Section("Hinweise des Renderers") { ForEach(Array(warnings.enumerated()), id: \.offset) { _, warning in Text(warning).font(.footnote) } } }
                Section {
                    Button(action: { startExport() }) {
                        HStack { if busy { ProgressView() }; Text(busy ? "Dokument wird erstellt …" : "Exportieren und teilen"); Spacer(); Image(systemName: "square.and.arrow.up") }
                    }.disabled(busy)
                }
            }
            .navigationTitle("Exportieren")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(busy ? "Abbrechen" : "Schließen") { if busy { exportTask?.cancel() } else { dismiss() } } } }
            .interactiveDismissDisabled(busy)
            .onDisappear { exportTask?.cancel() }
            .sheet(item: $shared, onDismiss: cleanup) { item in ExportNativeShareSheet(url: item.url) }
        }
    }
    @MainActor private func startExport() {
        guard !busy else { return }
        busy = true
        exportTask = Task { await export() }
    }
    @MainActor private func export() async {
        busy = true; error = nil; warnings = []
        defer { busy = false; exportTask = nil }
        let input = ExportInput(title: page.title, markdown: page.markdown, author: author, language: language, assets: assets)
        let chosenFormat = format, chosenProfile = profile
        let chosenChapters = chapters
        do {
            let result: (Data, [String])
            if chosenFormat == .md { result = (Data(page.markdown.utf8), []) }
            else {
                let artifact = try await Task.detached(priority: .userInitiated) {
                    let output: ExportFormat = chosenFormat == .pdf ? .html : (ExportFormat(rawValue: chosenFormat.rawValue) ?? .html)
                    if !chosenChapters.isEmpty { return try ExportEngine.exportManuscript(title: input.title, chapters: chosenChapters, author: input.author, language: input.language, format: output, profile: chosenProfile) }
                    return try ExportEngine.export(input, format: output, profile: chosenProfile)
                }.value
                try Task.checkCancellation()
                if chosenFormat == .pdf {
                    guard let html = String(data: artifact.data, encoding: .utf8) else { throw ExportUIError.invalidHTML }
                    let pdf = try await PaginatedPDF().render(html: html, title: input.title, author: input.author, profile: chosenProfile)
                    result = (pdf, artifact.warnings)
                } else { result = (artifact.data, artifact.warnings) }
            }
            try Task.checkCancellation()
            let directory = URL.temporaryDirectory.appending(path: "Scriptum-Export-" + UUID().uuidString, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let safeName = page.title.components(separatedBy: CharacterSet(charactersIn: "/\\:\n\r").union(.controlCharacters)).joined(separator: "-")
            let url = directory.appending(path: String(safeName.prefix(100)).isEmpty ? "Scriptum.\(chosenFormat.rawValue)" : "\(String(safeName.prefix(100))).\(chosenFormat.rawValue)")
            do { try result.0.write(to: url, options: .atomic) } catch { try? FileManager.default.removeItem(at: directory); throw error }
            warnings = result.1; shared = ExportShareItem(url: url)
        } catch is CancellationError { self.error = "Export abgebrochen." } catch { self.error = exportMessage(error) }
    }
    private func cleanup() {
        // Share controllers may hand the URL to another process. Retain the file in
        // OS-managed temporary storage instead of racing the recipient's read.
        shared = nil
    }
}

struct ManuscriptExportSheet: View {
    let library: WritingLibrary
    let spaceID: UUID?
    @Environment(\.dismiss) private var dismiss
    @State private var title = "Mein Manuskript"
    @State private var chosen: [UUID] = []
    @State private var prepared: [ExportInput] = []
    @State private var preparedPage: WritingPage?
    @State private var showingExport = false
    @State private var error: String?
    private var available: [WritingPage] { library.pages.filter { !$0.trashed && (spaceID == nil || $0.spaceID == spaceID) }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending } }
    var body: some View {
        NavigationStack {
            List {
                Section("Manuskript") { TextField("Titel", text: $title) }
                Section("Kapitelreihenfolge") {
                    if chosen.isEmpty { Text("Wählen Sie unten die Seiten Ihres Manuskripts.").foregroundStyle(.secondary) }
                    ForEach(chosen, id: \.self) { id in
                        if let page = library.currentPage(id) { Text(page.title) }
                    }.onMove { chosen.move(fromOffsets: $0, toOffset: $1) }
                        .onDelete { chosen.remove(atOffsets: $0) }
                }
                Section("Seiten auswählen") {
                    ForEach(available) { page in
                        Button {
                            if chosen.contains(page.id) { chosen.removeAll { $0 == page.id } } else { chosen.append(page.id) }
                        } label: { HStack { Text(page.title); Spacer(); if chosen.contains(page.id) { Image(systemName: "checkmark") } } }
                    }
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
                Section {
                    Button("Export vorbereiten") { prepare() }
                        .disabled(chosen.isEmpty || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }.navigationTitle("Manuskript zusammenstellen")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Schließen") { dismiss() } }
                    ToolbarItem(placement: .primaryAction) { EditButton() }
                }
                .navigationDestination(isPresented: $showingExport) {
                    if let preparedPage { ExportOptionsSheet(page: preparedPage, chapters: prepared) }
                }
        }
    }
    private func prepare() {
        do {
            guard !chosen.isEmpty else { return }
            prepared = try chosen.map { id in
                guard let page = library.currentPage(id), !page.trashed else { throw ExportError.invalidMetadata("Eine gewählte Seite ist nicht mehr verfügbar.") }
                return ExportInput(title: page.title, markdown: page.markdown, assets: try library.exportAssets(for: page))
            }
            guard var first = library.currentPage(chosen[0]) else { return }
            first.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            first.markdown = ""; preparedPage = first
            error = nil; showingExport = true
        } catch { self.error = exportMessage(error) }
    }
}
private struct ExportShareItem: Identifiable { let id = UUID(); let url: URL }
private struct ExportNativeShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: [url], applicationActivities: nil) }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
