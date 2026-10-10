import SwiftUI
import NaturalLanguage
#if canImport(SkriptumWritingQuality)
import SkriptumWritingQuality
#endif

struct WritingQualitySheet: View {
    @State var page: WritingPage
    let library: WritingLibrary
    let updated: (WritingPage) -> Void
    let aiAction: (WritingAIAction) -> Void
    var performMutation: PageToolMutation = { $0() }
    @Environment(\.dismiss) private var dismiss
    @State private var selectedFinding: QualityFinding?
    @State private var showingSettings = false
    @State private var category = "all"
    @State private var findings: [QualityFinding] = []
    @State private var language = ""
    @State private var serverMode = false
    @State private var endpoint = ""
    @State private var languages: [QualityLanguage] = []
    @State private var checking = false
    @State private var checkedChunks = 0
    @State private var totalChunks = 0
    @State private var error: String?
    @State private var checkTask: Task<Void, Never>?
    @State private var generation = UUID()
    @State private var undo: CorrectionUndo?
    private struct CorrectionUndo { let before: String; let after: String; let revision: UUID }
    var body: some View {
        NavigationStack {
            List {
                Section("Prüfung") {
                    Text("Prüfe den Text und öffne einen Hinweis, um die Korrektur zu übernehmen oder zu ignorieren.").font(.callout).foregroundStyle(.secondary)
                    if !language.isEmpty { Text("Sprache: " + (Locale(identifier: "de").localizedString(forIdentifier: language) ?? language)).font(.caption).foregroundStyle(.secondary) }
                    Button(action: check) { if checking { ProgressView(totalChunks > 0 ? "Abschnitt \(checkedChunks) von \(totalChunks)" : "Text wird geprüft …") } else { Label("Text prüfen", systemImage: "text.badge.checkmark") } }.disabled(checking || language.isEmpty || (serverMode && languages.isEmpty))
                    if checking { Button("Stoppen") { generation = UUID(); checkTask?.cancel(); checking = false } }
                }
                if let error { Section { Text(error).foregroundStyle(.red).textSelection(.enabled) } }
                Section("Hinweise: \(findings.count)") {
                    if !findings.isEmpty {
                        Picker("Hinweise", selection: $category) {
                            Text("Alles (\(findings.count))").tag("all")
                            Text("Rechtschreibung (\(count(.spelling)))").tag("spelling")
                            Text("Grammatik (\(count(.grammar)))").tag("grammar")
                            Text("Stil (\(count(.style)))").tag("style")
                        }
                    }
                    ForEach(visibleFindings) { finding in
                        Button { selectedFinding = finding } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(finding.original).font(.headline).foregroundStyle(.primary)
                                Text(finding.message).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }.padding(.vertical, 4)
                        }
                    }
                    if findings.isEmpty, !checking { Text("Starte die Prüfung. Du entscheidest über jede Korrektur.").font(.caption).foregroundStyle(.secondary) }
                }
                if undo != nil { Section { Button("Letzte Korrektur rückgängig", action: undoCorrection).disabled(checking) } }
                Section("KI-Lektorat") {
                    Button("Lektorat", systemImage: "text.badge.checkmark") { openAI(.proofread) }
                    Button("Überarbeiten", systemImage: "pencil.line") { openAI(.rewrite) }
                    Button("Zusammenfassen", systemImage: "text.alignleft") { openAI(.summarize) }

                }
            }.navigationTitle("Textprüfung")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Schließen") { dismiss() } }
                    ToolbarItem(placement: .primaryAction) { Button("Prüfeinstellungen", systemImage: "gearshape") { showingSettings = true }.disabled(checking) }
                }
                .sheet(isPresented: $showingSettings) { reviewSettings }
                .sheet(item: $selectedFinding) { finding in correctionDialog(finding) }
                .onAppear { if language.isEmpty { language = suggestedLanguage } }
                .onDisappear { generation = UUID(); checkTask?.cancel() }
                .onChange(of: serverMode) { _, _ in findings = []; language = serverMode ? languages.first?.longCode ?? "" : NativeWritingReviewer.spellingLanguages.first ?? "" }
        }
    }
    private var suggestedLanguage: String {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(String(page.markdown.prefix(10_000)))
        let detected = recognizer.dominantLanguage?.rawValue ?? Locale.current.language.languageCode?.identifier ?? "de"
        return NativeWritingReviewer.spellingLanguages.first { $0.replacingOccurrences(of: "_", with: "-").hasPrefix(detected) }
            ?? NativeWritingReviewer.spellingLanguages.first ?? ""
    }
    private var visibleFindings: [QualityFinding] { category == "all" ? findings : findings.filter { $0.kind.rawValue == category } }
    private func count(_ kind: QualityKind) -> Int { findings.filter { $0.kind == kind }.count }
    private var reviewSettings: some View {
        NavigationStack {
            Form {
                Section("Sprache und Prüfverfahren") {
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
                            ForEach(NativeWritingReviewer.spellingLanguages, id: \.self) { Text(Locale(identifier: "de").localizedString(forIdentifier: $0) ?? $0).tag($0) }
                        }
                        Text("Apple prüft Grammatik automatisch nach Systemverfügbarkeit. Die lokale Stilprüfung ergänzt grundlegende Hinweise; Code und Markdown-Syntax bleiben geschützt.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
                if checking { Section { ProgressView("Prüfung wird vorbereitet …") } }
            }.navigationTitle("Prüfeinstellungen")
                .toolbar { Button("Fertig") { showingSettings = false } }
        }
    }
    private func correctionDialog(_ finding: QualityFinding) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(finding.original).font(.title3.weight(.semibold)).foregroundStyle(.tint).textSelection(.enabled)
                    Text(finding.message).font(.body)
                    ForEach(Array(finding.replacements.enumerated()), id: \.offset) { _, replacement in
                        Button(replacement.isEmpty ? "Entfernen" : "Ersetzen durch „\(replacement)“") {
                            accept(finding, replacement: replacement); selectedFinding = nil
                        }.buttonStyle(.borderedProminent).disabled(checking)
                    }
                    Button("Ignorieren") { findings.removeAll { $0.id == finding.id }; selectedFinding = nil }.buttonStyle(.bordered)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(24)
            }.navigationTitle(kindName(finding.kind))
                .toolbar { Button("Schließen") { selectedFinding = nil } }
        }.presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
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
        let token = UUID(); generation = token; checking = true; error = nil; checkedChunks = 0; totalChunks = 0
        let selectedLanguage = language, remote = serverMode
        checkTask = Task {
            do {
                let result = remote ? try await client().check(document, language: selectedLanguage) : try await NativeWritingReviewer.check(document, spellingLanguage: selectedLanguage, progress: { completed, total in
                    guard generation == token else { return }; checkedChunks = completed; totalChunks = total
                })
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
            guard let saved = performMutation({
                guard let revision = library.update(current) else { return nil }
                current.revision = revision; return library.currentPage(current.id)
            }) else { error = library.saveError; return }
            page = saved; updated(saved)
            undo = CorrectionUndo(before: before, after: saved.markdown, revision: saved.revision)
            findings = []; check()
        } catch { self.error = error.localizedDescription }
    }
    private func undoCorrection() {
        guard let undo, var current = library.currentPage(page.id), current.revision == undo.revision, current.markdown.utf8.elementsEqual(undo.after.utf8) else { error = "Der Text wurde inzwischen geändert. Die Korrektur wird nicht überschrieben."; return }
        current.markdown = undo.before
        if let saved = performMutation({
            guard let revision = library.update(current) else { return nil }
            current.revision = revision; return library.currentPage(current.id)
        }) { page = saved; updated(saved); self.undo = nil; findings = []; check() }
        else { error = library.saveError }
    }
    private func openAI(_ action: WritingAIAction) { generation = UUID(); checkTask?.cancel(); aiAction(action); dismiss() }
}
