import SwiftUI
import UIKit
import PDFKit
#if canImport(SkriptumExport)
import SkriptumExport
#endif

struct ExportOptionsSheet: View {
    let page: WritingPage
    var assets: [String: ExportAsset] = [:]
    var chapters: [ExportInput] = []
    var preferenceKey: String? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var format = Format.pdf
    @State private var profile = ExportProfile.standard
    @State private var theme = ExportTheme.preset(for: .standard)
    @State private var livePreview = false
    @State private var preferencesLoaded = false
    @State private var author = ""
    @State private var language = "de"
    @State private var busy = false
    @State private var exportTask: Task<Void, Never>?
    @State private var error: String?
    @State private var warnings: [String] = []
    @State private var shared: ExportShareItem?
    private enum Format: String, CaseIterable { case md, mdPackage, html, docx, epub, pdf, blog }
    private struct Preferences: Codable { let format: String; let profile: String; let theme: ExportTheme; let author: String; let language: String }
    var body: some View {
        NavigationStack {
            Form {
                Section("Dokument") {
                    Text(page.title).font(.headline)
                    Picker("Format", selection: $format) {
                        ForEach(Format.allCases.filter { chapters.isEmpty || $0 != .md }, id: \.self) { value in Text(value == .blog ? "Blogpaket" : (value == .mdPackage ? "Markdown mit Bildern (ZIP)" : value.rawValue.uppercased())).tag(value) }
                    }
                    Picker("Satzprofil", selection: Binding(get: { profile }, set: { profile = $0; theme = .preset(for: $0); savePreferences() })) {
                        Text("Standard").tag(ExportProfile.standard)
                        Text("Manuskript").tag(ExportProfile.manuscript)
                        Text("E-Book").tag(ExportProfile.ebook)
                    }.disabled(format == .md || format == .mdPackage)
                }
                if format != .md && format != .mdPackage {
                    Section("Export-Theme") {
                        Picker("Schrift", selection: $theme.bodyFont) { ForEach(ExportFont.allCases, id: \.self) { Text($0.displayName).tag($0) } }
                        Stepper("Schriftgröße: \(theme.bodySizePoints.formatted()) pt", value: $theme.bodySizePoints, in: 8...36, step: 0.5)
                        Stepper("Zeilenabstand: \(theme.lineHeight.formatted())", value: $theme.lineHeight, in: 1...3, step: 0.05)
                        Stepper("Absatzabstand: \(theme.paragraphSpacingPoints.formatted()) pt", value: $theme.paragraphSpacingPoints, in: 0...36, step: 1)
                        Stepper("Seitenrand: \(theme.marginsMM.formatted()) mm", value: $theme.marginsMM, in: 5...45, step: 1)
                        Picker("Papier", selection: $theme.paperSize) { Text("A4").tag(ExportPaperSize.a4); Text("US Letter").tag(ExportPaperSize.letter) }
                        TextField("Überschriftenfarbe (Hex)", text: $theme.headingColorHex).textInputAutocapitalization(.never).autocorrectionDisabled()
                        Toggle("Dokumenttitel ausgeben", isOn: $theme.includeTitle)
                        Toggle("Inhaltsverzeichnis", isOn: $theme.includeTOC)
                    }
                }
                Section("Metadaten") {
                    TextField("Autor oder Autorin", text: $author)
                    TextField("Sprache (z. B. de oder en)", text: $language).textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                if livePreview {
                    Section("Live-Vorschau") {
                        if format == .md || format == .mdPackage { ScrollView { Text(page.markdown).font(.system(.body, design: .monospaced)).textSelection(.enabled).padding() }.frame(height: 340) }
                        else { ExportLivePreview(input: previewInput, chapters: chapters, profile: profile, pdf: format == .pdf).frame(height: 480) }
                        if format == .docx { Text("Satzvorschau mit demselben Theme. Word kann den Seitenumbruch abweichend berechnen.").font(.caption) }
                        Button("Vorschau ausblenden") { livePreview = false }
                    }
                }
                Section {
                    Text(format == .md ? "MD enthält den unveränderten Quelltext. Für verwendete Bilder wähle Markdown mit Bildern (ZIP)." : (format == .mdPackage ? "Das ZIP enthält den unveränderten Markdown-Quelltext und die verwendeten Originalbilder. Manuskriptkapitel bleiben getrennte Dateien." : (chapters.isEmpty ? "PDF verwendet das gewählte Papierformat. Eingefügte Bilder werden mit dem Dokument exportiert." : "\(chapters.count) Kapitel werden in der gewählten Reihenfolge zusammengestellt. Seitenüberschriften, Fußnoten und Bilder bleiben pro Kapitel erhalten. Die Originalseiten bleiben unverändert."))).font(.footnote).foregroundStyle(.secondary)
                }
                if let error { Section("Export fehlgeschlagen") { Text(error).foregroundStyle(.red).textSelection(.enabled) } }
                if !warnings.isEmpty { Section("Hinweise des Renderers") { ForEach(Array(warnings.enumerated()), id: \.offset) { _, warning in Text(warning).font(.footnote) } } }
                Section {
                    Button(action: { startExport() }) {
                        HStack { if busy { ProgressView() }; Text(busy ? "Dokument wird erstellt …" : "Exportieren und teilen"); Spacer(); Image(systemName: "square.and.arrow.up") }
                    }.disabled(busy)
                    Button("Live-Vorschau", systemImage: "eye") { livePreview.toggle() }
                    if format == .blog { Button("Blogtext formatiert kopieren", systemImage: "doc.on.doc", action: copyBlog).disabled(busy) }
                }
            }
            .navigationTitle("Exportieren")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(busy ? "Abbrechen" : "Schließen") { if busy { exportTask?.cancel() } else { dismiss() } } } }
            .interactiveDismissDisabled(busy)
            .onDisappear { exportTask?.cancel() }
            .sheet(item: $shared, onDismiss: cleanup) { item in ExportNativeShareSheet(url: item.url) }
            .onAppear(perform: restorePreferences)
            .onChange(of: theme) { _, _ in savePreferences() }
            .onChange(of: format) { _, _ in savePreferences() }
            .onChange(of: author) { _, _ in savePreferences() }
            .onChange(of: language) { _, _ in savePreferences() }
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
        let input = previewInput
        let chosenFormat = format, chosenProfile = profile
        let chosenChapters = chapters
        do {
            let result: (Data, [String])
            if chosenFormat == .md { result = (Data(page.markdown.utf8), assets.isEmpty ? [] : ["Die MD-Datei enthält keine Bilddateien. Markdown mit Bildern (ZIP) enthält die verwendeten Bilder."]) }
            else if chosenFormat == .mdPackage {
                let artifact = try await Task.detached(priority: .userInitiated) {
                    if chosenChapters.isEmpty { return try ExportEngine.markdownPackage(input) }
                    return try ExportEngine.markdownManuscriptPackage(title: input.title, chapters: chosenChapters, author: input.author, language: input.language)
                }.value
                result = (artifact.data, artifact.warnings)
            }
            else {
                let artifact = try await Task.detached(priority: .userInitiated) {
                    let output: ExportFormat = chosenFormat == .pdf ? .html : (ExportFormat(rawValue: chosenFormat.rawValue) ?? .html)
                    if !chosenChapters.isEmpty { return try ExportEngine.exportManuscript(title: input.title, chapters: chosenChapters, author: input.author, language: input.language, format: output, profile: chosenProfile, theme: input.theme) }
                    return try ExportEngine.export(input, format: output, profile: chosenProfile)
                }.value
                try Task.checkCancellation()
                if chosenFormat == .pdf {
                    guard let html = String(data: artifact.data, encoding: .utf8) else { throw ExportUIError.invalidHTML }
                    let pdf = try await PaginatedPDF().render(html: html, title: input.title, author: input.author, profile: chosenProfile, theme: input.theme)
                    result = (pdf, artifact.warnings)
                } else { result = (artifact.data, artifact.warnings) }
            }
            try Task.checkCancellation()
            let directory = URL.temporaryDirectory.appending(path: "Scriptum-Export-" + UUID().uuidString, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let safeName = page.title.components(separatedBy: CharacterSet(charactersIn: "/\\:\n\r").union(.controlCharacters)).joined(separator: "-")
            let ext = chosenFormat == .blog || chosenFormat == .mdPackage ? "zip" : chosenFormat.rawValue
            let url = directory.appending(path: String(safeName.prefix(100)).isEmpty ? "Scriptum.\(ext)" : "\(String(safeName.prefix(100))).\(ext)")
            do { try result.0.write(to: url, options: .atomic) } catch { try? FileManager.default.removeItem(at: directory); throw error }
            warnings = result.1; shared = ExportShareItem(url: url)
        } catch is CancellationError { self.error = "Export abgebrochen." } catch { self.error = exportMessage(error) }
    }
    private func cleanup() {
        // Share controllers may hand the URL to another process. Retain the file in
        // OS-managed temporary storage instead of racing the recipient's read.
        shared = nil
    }
    private var previewInput: ExportInput { ExportInput(title: page.title, markdown: page.markdown, author: author, language: language, assets: assets, theme: theme) }
    private func restorePreferences() {
        guard !preferencesLoaded else { return }
        preferencesLoaded = true
        guard let preferenceKey, let data = UserDefaults.standard.data(forKey: preferenceKey), let saved = try? JSONDecoder().decode(Preferences.self, from: data) else { return }
        profile = ExportProfile(rawValue: saved.profile) ?? .standard
        theme = saved.theme; author = saved.author; language = saved.language
        format = Format(rawValue: saved.format) ?? .pdf
        if !chapters.isEmpty, format == .md { format = .pdf }
    }
    private func savePreferences() {
        guard preferencesLoaded, let preferenceKey, (try? theme.validate()) != nil,
              let data = try? JSONEncoder().encode(Preferences(format: format.rawValue, profile: profile.rawValue, theme: theme, author: author, language: language)) else { return }
        UserDefaults.standard.set(data, forKey: preferenceKey)
    }
    private func copyBlog() {
        do {
            guard chapters.isEmpty else { error = "Zusammengestellte Manuskripte bitte als Blogpaket exportieren."; return }
            let content = try ExportEngine.blogContent(previewInput, profile: profile)
            UIPasteboard.general.items = [["public.html": Data(content.html.utf8), "public.utf8-plain-text": Data(content.plainText.utf8)]]
            warnings = content.warnings + ["Bilder müssen auf der Blogplattform separat hochgeladen werden. Das Blogpaket enthält die Bilddateien."]
        } catch { self.error = exportMessage(error) }
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
    private var available: [WritingPage] { library.pages.filter { !$0.trashed && $0.effectivePurpose == .writing && (spaceID == nil || $0.spaceID == spaceID) }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending } }
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
                    if let preparedPage { ExportOptionsSheet(page: preparedPage, chapters: prepared, preferenceKey: library.exportPreferenceKey(spaceID: preparedPage.spaceID)) }
                }
        }
    }
    private func prepare() {
        do {
            guard !chosen.isEmpty else { return }
            prepared = try chosen.map { id in
                guard let page = library.currentPage(id), !page.trashed, page.effectivePurpose == .writing else { throw ExportError.invalidMetadata("Eine gewählte Seite ist nicht mehr als Manuskripttext verfügbar.") }
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
