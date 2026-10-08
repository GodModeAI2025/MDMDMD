import SwiftUI
#if canImport(SkriptumWritingQuality)
import SkriptumWritingQuality
#endif

struct WritingQualitySheet: View {
    @State var page: WritingPage
    let library: WritingLibrary
    let updated: (WritingPage) -> Void
    let aiAction: (String, Bool) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var findings: [QualityFinding] = []
    @State private var language = ""
    @State private var serverMode = false
    @State private var endpoint = ""
    @State private var languages: [QualityLanguage] = []
    @State private var checking = false
    @State private var error: String?
    @State private var checkTask: Task<Void, Never>?
    @State private var generation = UUID()
    @State private var undo: CorrectionUndo?
    private struct CorrectionUndo { let before: String; let after: String; let revision: UUID }
    var body: some View {
        NavigationStack {
            List {
                Section("Prüfung") {
                    Toggle("Eigenen Prüfserver verwenden", isOn: $serverMode).disabled(checking)
                    if serverMode {
                        TextField("HTTPS-Adresse Ihres LanguageTool-Servers", text: $endpoint).textInputAutocapitalization(.never).autocorrectionDisabled()
                        Text("Nur nach Ihrem Start wird der Seiteninhalt an diesen Server geschickt. Es gibt keinen voreingestellten öffentlichen Dienst.").font(.caption).foregroundStyle(.secondary)
                        Button("Unterstützte Sprachen laden", action: loadLanguages).disabled(checking || endpoint.isEmpty)
                        if !languages.isEmpty {
                            Picker("Sprache", selection: $language) { ForEach(languages, id: \.longCode) { Text($0.name + " · " + $0.longCode).tag($0.longCode) } }
                        }
                    } else {
                        Picker("Rechtschreibsprache", selection: $language) {
                            ForEach(NativeWritingReviewer.spellingLanguages, id: \.self) { Text(Locale.current.localizedString(forIdentifier: $0) ?? $0).tag($0) }
                        }
                        Text("Apple prüft Grammatik automatisch nach Systemverfügbarkeit. Die lokale Stilprüfung ergänzt grundlegende Hinweise; Code und Markdown-Syntax bleiben geschützt.").font(.caption).foregroundStyle(.secondary)
                    }
                    Button(action: check) { if checking { ProgressView("Text wird geprüft …") } else { Label("Text prüfen", systemImage: "text.badge.checkmark") } }.disabled(checking || language.isEmpty || (serverMode && languages.isEmpty))
                    if checking { Button("Stoppen") { generation = UUID(); checkTask?.cancel(); checking = false } }
                }
                if let error { Section { Text(error).foregroundStyle(.red).textSelection(.enabled) } }
                Section("Hinweise: \(findings.count)") {
                    ForEach(findings) { finding in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(finding.message).font(.headline)
                            Text(finding.original).textSelection(.enabled)
                            Text(kindName(finding.kind) + " · " + finding.engine).font(.caption).foregroundStyle(.secondary)
                            ForEach(Array(finding.replacements.enumerated()), id: \.offset) { _, replacement in
                                Button(replacement.isEmpty ? "Entfernen" : replacement) { accept(finding, replacement: replacement) }.disabled(checking)
                            }
                            Button("Hinweis ausblenden") { findings.removeAll { $0.id == finding.id } }.font(.caption)
                        }.padding(.vertical, 6)
                    }
                    if findings.isEmpty, !checking { Text("Starten Sie die Prüfung. Keine Hinweise bedeuten keine Garantie für fehlerfreien Text.").font(.caption).foregroundStyle(.secondary) }
                }
                if undo != nil { Section { Button("Letzte Korrektur rückgängig", action: undoCorrection).disabled(checking) } }
                Section("KI-Lektorat") {
                    Button("Korrektur lesen") { openAI("Prüfe Rechtschreibung, Grammatik und Stil. Erhalte Bedeutung, Quellen und Markdown. Erläutere die wichtigsten Korrekturen und kennzeichne Unsicherheit.") }
                    Button("Überarbeiten") { openAI("Überarbeite den Text sprachlich. Erhalte Bedeutung, Quellen und Markdown. Gib eine prüfbare Überarbeitung zurück.", revisionMode: true) }
                    Button("Zusammenfassen") { openAI("Fasse den Text präzise zusammen. Erfinde keine Fakten oder Quellen. Kennzeichne offene Punkte.") }
                    Text("Öffnet den Assistenten mit Ihrem gewählten KI-Zugang. Apple-Verfügbarkeit, Sprache und Region werden separat geprüft; kein automatischer Anbieterwechsel.").font(.caption).foregroundStyle(.secondary)
                }
            }.navigationTitle("Textprüfung")
                .toolbar { Button("Schließen") { dismiss() } }
                .onAppear { if language.isEmpty { language = NativeWritingReviewer.spellingLanguages.first(where: { $0.hasPrefix(Locale.current.language.languageCode?.identifier ?? "de") }) ?? NativeWritingReviewer.spellingLanguages.first ?? "" } }
                .onDisappear { generation = UUID(); checkTask?.cancel() }
                .onChange(of: serverMode) { _, _ in findings = []; language = serverMode ? languages.first?.longCode ?? "" : NativeWritingReviewer.spellingLanguages.first ?? "" }
        }
    }
    private func kindName(_ kind: QualityKind) -> String { switch kind { case .spelling: "Rechtschreibung"; case .grammar: "Grammatik"; case .style: "Stil" } }
    private func client() throws -> LanguageToolClient {
        guard let url = URL(string: endpoint) else { throw QualityError.invalidConfiguration }
        return LanguageToolClient(configuration: try LanguageToolConfiguration(endpoint: url))
    }
    private func loadLanguages() {
        let token = UUID(); generation = token; checking = true; error = nil
        checkTask = Task {
            do {
                let catalog = try await client().languages(); try Task.checkCancellation()
                guard generation == token else { return }
                languages = catalog.languages; language = languages.first?.longCode ?? ""
            } catch { guard generation == token else { return }; self.error = error.localizedDescription }
            if generation == token { checking = false; checkTask = nil }
        }
    }
    private func check() {
        guard !checking, let current = library.currentPage(page.id) else { return }
        page = current
        let document = QualityDocument(source: current.markdown, revision: current.revision)
        let token = UUID(); generation = token; checking = true; error = nil
        let selectedLanguage = language, remote = serverMode
        checkTask = Task {
            do {
                let result = remote ? try await client().check(document, language: selectedLanguage) : try await NativeWritingReviewer.check(document, spellingLanguage: selectedLanguage)
                try Task.checkCancellation()
                guard generation == token else { return }
                guard let latest = library.currentPage(page.id), latest.revision == document.revision, latest.markdown.utf8.elementsEqual(document.source.utf8) else { throw QualityError.staleSource }
                findings = result
            } catch { guard generation == token else { return }; self.error = error.localizedDescription }
            if generation == token { checking = false; checkTask = nil }
        }
    }
    private func accept(_ finding: QualityFinding, replacement: String) {
        do {
            guard var current = library.currentPage(page.id) else { return }
            let before = current.markdown
            current.markdown = try finding.applying(replacement, to: QualityDocument(source: current.markdown, revision: current.revision))
            guard let revision = library.update(current) else { error = library.saveError; return }
            current.revision = revision; page = current; updated(current)
            undo = CorrectionUndo(before: before, after: current.markdown, revision: revision)
            findings = []; check()
        } catch { self.error = error.localizedDescription }
    }
    private func undoCorrection() {
        guard let undo, var current = library.currentPage(page.id), current.revision == undo.revision, current.markdown.utf8.elementsEqual(undo.after.utf8) else { error = "Der Text wurde inzwischen geändert. Die Korrektur wird nicht überschrieben."; return }
        current.markdown = undo.before
        if let revision = library.update(current) { current.revision = revision; page = current; updated(current); self.undo = nil; findings = []; check() }
        else { error = library.saveError }
    }
    private func openAI(_ prompt: String, revisionMode: Bool = false) { generation = UUID(); checkTask?.cancel(); aiAction(prompt + (language.isEmpty ? "" : "\nGewählte Prüfsprache: " + language), revisionMode); dismiss() }
}
