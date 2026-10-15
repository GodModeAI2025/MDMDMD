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
    @Environment(\.locale) private var locale
    @State private var selectedFinding: QualityFinding?
    @State private var showingSettings = false
    private struct RemoteCheck: Identifiable {
        let client: LanguageToolClient
        let submission: LanguageToolCheckSubmission
        var id: UUID { submission.id }
    }
    @State private var remoteCheck: RemoteCheck?
    @State private var startedRemoteID: UUID?
    @State private var category = "all"
    @State private var findings: [QualityFinding] = []
    @State private var reviewCompleted = false
    @State private var reviewCancelled = false
    @State private var language = ""
    @State private var suggestedLanguageLoaded = false
    @State private var serverMode = false
    @State private var useBundledGrammar = true
    @State private var endpoint = ""
    @State private var languages: [QualityLanguage] = []
    @State private var checking = false
    @State private var applyingCorrection = false
    @State private var stopping = false
    @State private var checkedChunks = 0
    @State private var totalChunks = 0
    @State private var error: String?
    @State private var checkTask: Task<Void, Never>?
    @State private var generation = UUID()
    @State private var correctionHistory = WritingCorrectionHistory()
    var body: some View {
        NavigationStack {
            List {
                Section("Prüfung") {
                    Text("Prüfe den Text und öffne einen Hinweis, um die Korrektur zu übernehmen oder zu ignorieren.").font(.callout).foregroundStyle(.secondary)
                    if !language.isEmpty {
                        if serverMode || bundledMode { Text("Sprache: \(locale.localizedString(forIdentifier: language) ?? language)").font(.caption).foregroundStyle(.secondary) }
                        else { Text("Rechtschreibung: \(locale.localizedString(forIdentifier: language) ?? language)").font(.caption).foregroundStyle(.secondary) }
                    }
                    if language.isEmpty && !serverMode && !bundledMode {
                        Button("Rechtschreibsprache wählen") { showingSettings = true }
                        Text("Ohne ausgewähltes Wörterbuch prüft Apple Grammatik nach Systemverfügbarkeit. Grundlegende lokale Stilhinweise bleiben verfügbar; Rechtschreibung wird nicht geprüft.").font(.caption).foregroundStyle(.secondary)
                    }
                    if bundledMode {
                        Text("Grammatik und Stil werden auf diesem Gerät geprüft. Es wird kein Text an einen Server gesendet.").font(.caption).foregroundStyle(.secondary)
                        if !language.isEmpty {
                            if let dictionary = spellingLanguage(for: language) {
                                Text("Apple-Rechtschreibung: \(locale.localizedString(forIdentifier: dictionary) ?? dictionary)").font(.caption).foregroundStyle(.secondary)
                            } else {
                                Text("Für diese Textsprache ist kein passendes Apple-Rechtschreibwörterbuch verfügbar.").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        if language.isEmpty { Button("Textsprache wählen") { showingSettings = true } }
                    }
                    Button(action: check) { if checking { ProgressView(stopping ? "Vorgang wird beendet …" : (applyingCorrection ? "Korrektur wird vorbereitet …" : (totalChunks > 0 ? "Abschnitt \(checkedChunks) von \(totalChunks)" : "Text wird geprüft …"))) } else { Label("Text prüfen", systemImage: "text.badge.checkmark") } }.disabled(checking || (serverMode && (language.isEmpty || languages.isEmpty)) || (bundledMode && language.isEmpty))
                    if checking { Button("Stoppen") { stopping = true; checkTask?.cancel() }.disabled(stopping) }
                }
                if let error { Section { Text(error).foregroundStyle(.red).textSelection(.enabled) } }
                Section("Hinweise: \(findings.count)") {
                    if !findings.isEmpty {
                        Picker("Hinweise", selection: $category) {
                            Text("Alles (\(findings.count))").tag("all")
                            Text("Rechtschreibung (\(count(.spelling)))").tag("spelling")
                            Text("Grammatik (\(count(.grammar)))").tag("grammar")
                            Text("Stil (\(count(.style)))").tag("style")
                            Text("Sonstiges (\(count(.other)))").tag("other")
                        }
                    }
                    ForEach(visibleFindings) { finding in
                        Button { selectedFinding = finding } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(verbatim: finding.original).font(.headline).foregroundStyle(.primary)
                                Text(verbatim: finding.message).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }.padding(.vertical, 4)
                        }.disabled(checking)
                    }
                    if findings.isEmpty, !checking {
                        Text(reviewCompleted ? "Prüfung abgeschlossen: keine Hinweise gefunden. Das ist keine Garantie für einen fehlerfreien Text." : (reviewCancelled ? "Prüfung abgebrochen. Du kannst sie erneut starten." : "Starte die Prüfung. Du entscheidest über jede Korrektur."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if correctionHistory.canUndo || correctionHistory.canRedo || correctionHistory.isLimited {
                    Section("Korrekturverlauf") {
                        Button("Korrektur rückgängig", systemImage: "arrow.uturn.backward", action: undoCorrection)
                            .disabled(checking || !correctionHistory.canUndo)
                        Button("Korrektur wiederholen", systemImage: "arrow.uturn.forward", action: redoCorrection)
                            .disabled(checking || !correctionHistory.canRedo)
                        if correctionHistory.isLimited {
                            Text("Der Rückgängig-Verlauf ist begrenzt. Ältere Fassungen bleiben im Versionsverlauf der Seite verfügbar.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
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
                .onAppear { if !suggestedLanguageLoaded { suggestedLanguageLoaded = true; language = suggestedLanguage } }
                .onDisappear { generation = UUID(); checkTask?.cancel(); remoteCheck?.submission.discard() }
                .sheet(item: $remoteCheck) { pending in remotePermission(pending) }
                .onChange(of: endpoint) { _, _ in languages = []; if serverMode { language = "" } }
                .onChange(of: language) { _, _ in findings = []; reviewCompleted = false; reviewCancelled = false }
                .onChange(of: useBundledGrammar) { _, _ in findings = []; reviewCompleted = false; reviewCancelled = false; language = suggestedLanguage }
                .onChange(of: serverMode) { _, _ in findings = []; reviewCompleted = false; reviewCancelled = false; language = serverMode ? suggestedLanguage(in: languages.map(\.longCode)) : suggestedLanguage }
        }
    }
    private var bundledMode: Bool { !serverMode && BundledGrammarRuntime.isLinked && useBundledGrammar }
    private var suggestedLanguage: String {
        suggestedLanguage(in: bundledMode ? BundledGrammarRuntime.languageCodes : NativeWritingReviewer.spellingLanguages)
    }
    private func spellingLanguage(for textLanguage: String) -> String? {
        guard !textLanguage.isEmpty else { return nil }
        return SpellingLanguageChoice.suggested(detected: textLanguage, system: locale.identifier, dictionaries: NativeWritingReviewer.spellingLanguages)
    }
    private func suggestedLanguage(in dictionaries: [String]) -> String {
        let recognizer = NLLanguageRecognizer()
        let excerpt = QualityDocument(source: String(page.markdown.prefix(10_000)), revision: page.revision).projection.text
        recognizer.processString(excerpt)
        return SpellingLanguageChoice.suggested(detected: recognizer.dominantLanguage?.rawValue, system: locale.identifier, dictionaries: dictionaries) ?? ""
    }
    private var visibleFindings: [QualityFinding] { category == "all" ? findings : findings.filter { $0.kind.rawValue == category } }
    private func count(_ kind: QualityKind) -> Int { findings.filter { $0.kind == kind }.count }
    private var reviewSettings: some View {
        NavigationStack {
            Form {
                Section("Sprache und Prüfverfahren") {
                    Toggle("Eigenen Prüfserver verwenden", isOn: $serverMode).disabled(checking)
                    if serverMode {
                        TextField("HTTPS-Adresse Ihres LanguageTool-Servers", text: $endpoint).scriptumPlainTextInput()
                        Text("Nur nach Ihrem Start wird der Seiteninhalt an diesen Server geschickt. Es gibt keinen voreingestellten öffentlichen Dienst.").font(.caption).foregroundStyle(.secondary)
                        Button("Unterstützte Sprachen laden", action: loadLanguages).disabled(checking || endpoint.isEmpty)
                        if !languages.isEmpty {
                            Picker("Sprache", selection: $language) {
                                Text("Bitte wählen").tag("")
                                ForEach(languages, id: \.longCode) { Text($0.name + " · " + $0.longCode).tag($0.longCode) }
                            }
                        }
                    } else if bundledMode {
                        Toggle("Lokale Grammatik und Stil", isOn: $useBundledGrammar)
                        Picker("Textsprache", selection: $language) {
                            Text("Bitte wählen").tag("")
                            ForEach(BundledGrammarRuntime.languageCodes, id: \.self) { code in
                                Text(locale.localizedString(forIdentifier: code) ?? code).tag(code)
                            }
                        }
                        Text("LanguageTool 6.6 prüft Grammatik und Stil ohne Netzwerk. Apple ergänzt Rechtschreibung, wenn ein passendes Wörterbuch verfügbar ist. Die Prüftiefe unterscheidet sich nach Sprache.").font(.caption).foregroundStyle(.secondary)
                    } else {
                        if BundledGrammarRuntime.isLinked { Toggle("Lokale Grammatik und Stil", isOn: $useBundledGrammar) }
                        Picker("Rechtschreibsprache", selection: $language) {
                            Text("Ohne Rechtschreibprüfung").tag("")
                            ForEach(NativeWritingReviewer.spellingLanguages, id: \.self) { Text(Locale(identifier: "de").localizedString(forIdentifier: $0) ?? $0).tag($0) }
                        }
                        Text("Apple prüft Grammatik automatisch nach Systemverfügbarkeit. Die lokale Stilprüfung ergänzt grundlegende Hinweise; Code und Markdown-Syntax bleiben geschützt.").font(.caption).foregroundStyle(.secondary)
                    }
                }.disabled(checking)
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
                    QualityFindingContextView(original: finding.original, context: finding.context)
                    Text(verbatim: finding.message).font(.body)
                    ForEach(Array(finding.replacements.enumerated()), id: \.offset) { _, replacement in
                        QualityReplacementChoice(replacement: replacement, manual: finding.requiresManualEditing(replacement), disabled: checking) {
                            accept(finding, replacement: replacement); selectedFinding = nil
                        }
                    }
                    Button("Ignorieren") { findings.removeAll { $0.id == finding.id }; selectedFinding = nil }.buttonStyle(.bordered).disabled(checking)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(24)
            }.navigationTitle(kindName(finding.kind))
                .toolbar { Button("Schließen") { selectedFinding = nil } }
        }.presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
    }
    private func kindName(_ kind: QualityKind) -> String { switch kind { case .spelling: "Rechtschreibung"; case .grammar: "Grammatik"; case .style: "Stil"; case .other: "Sonstiges" } }
    private func client() throws -> LanguageToolClient {
        guard let url = URL(string: endpoint) else { throw QualityError.invalidConfiguration }
        return LanguageToolClient(configuration: try LanguageToolConfiguration(endpoint: url))
    }
    private func loadLanguages() {
        let token = UUID(); generation = token; checking = true; stopping = false; reviewCancelled = false; error = nil
        checkTask = Task {
            defer {
                if generation == token { checking = false; stopping = false; checkTask = nil }
            }
            do {
                let catalog = try await client().languages(); try Task.checkCancellation()
                guard generation == token else { return }
                languages = catalog.languages
                if !languages.contains(where: { $0.longCode == language }) { language = suggestedLanguage(in: languages.map(\.longCode)) }
            } catch {
                guard generation == token else { return }
                if Task.isCancelled { reviewCancelled = true; return }
                self.error = error.localizedDescription
            }
        }
    }
    private func check() {
        guard !checking, let current = library.currentPage(page.id) else { return }
        remoteCheck?.submission.discard(); remoteCheck = nil
        page = current
        let token = UUID(); generation = token; checking = true; stopping = false; reviewCompleted = false; reviewCancelled = false; findings = []; error = nil; checkedChunks = 0; totalChunks = 0
        let selectedLanguage = language, remote = serverMode, bundled = bundledMode
        let spelling = bundled ? spellingLanguage(for: selectedLanguage) : (selectedLanguage.isEmpty ? nil : selectedLanguage)
        let resourceBundle = bundled ? Bundle.main.url(forResource: "ScriptumGrammarResources", withExtension: "bundle") : nil
        let capturedClient: LanguageToolClient?
        do { capturedClient = remote ? try client() : nil }
        catch { self.error = error.localizedDescription; checking = false; return }
        checkTask = Task {
            defer {
                if generation == token { checking = false; stopping = false; checkTask = nil }
            }
            do {
                let document = try await QualityDocument.prepare(source: current.markdown, revision: current.revision)
                try Task.checkCancellation()
                guard generation == token else { return }
                if let capturedClient {
                    remoteCheck = RemoteCheck(client: capturedClient, submission: try capturedClient.prepare(document, language: selectedLanguage))
                    return
                }
                let result: [QualityFinding]
                if bundled {
                    let engine = try await BundledGrammarRuntime.load(resourceBundleURL: resourceBundle)
                    let rules = try await BundledRuleReviewer(engine: engine).check(document, language: selectedLanguage) { completed, total in
                        guard generation == token else { return }; checkedChunks = completed; totalChunks = total
                    }
                    let spellingFindings = try await NativeWritingReviewer.check(document, spellingLanguage: spelling, includingGrammarAndStyle: false)
                    guard rules.count <= 5000 - spellingFindings.count else { throw QualityError.responseTooLarge }
                    result = rules + spellingFindings
                } else {
                    result = try await NativeWritingReviewer.check(document, spellingLanguage: spelling, progress: { completed, total in
                        guard generation == token else { return }; checkedChunks = completed; totalChunks = total
                    })
                }
                try Task.checkCancellation()
                guard generation == token else { return }
                guard let latest = library.currentPage(page.id), latest.revision == document.revision, latest.markdown.utf8.elementsEqual(document.source.utf8) else { throw QualityError.staleSource }
                findings = result; reviewCompleted = true
            } catch {
                guard generation == token else { return }
                if Task.isCancelled { reviewCancelled = true; return }
                self.error = error.localizedDescription
            }
        }
    }
    private func remotePermission(_ pending: RemoteCheck) -> some View {
        NavigationStack {
            Form {
                Section("Empfänger") {
                    Text(pending.submission.endpoint.absoluteString).textSelection(.enabled)
                    Text("Der Prüftext und die gewählte Sprache werden an deinen eigenen LanguageTool-Server gesendet. Der Text kann personenbezogene Daten enthalten. Es gilt die Datenschutzregelung dieses Serverbetreibers.")
                }
                Section("Inhalt") {
                    LabeledContent("Seiteninhalt", value: "\(pending.submission.document.source.count) Zeichen")
                    LabeledContent("Sprache", value: pending.submission.language)
                    Text("Geschützte Markdown-Bereiche werden in der Textprojektion ausgelassen. Bilddateien und Chatverlauf werden nicht zusätzlich hochgeladen.").font(.caption)
                    Text("Lange Texte werden abschnittsweise geprüft. Diese Freigabe umfasst den angezeigten Textstand vollständig.").font(.caption)
                }
                Button("An diesen Server senden") { startRemote(pending); remoteCheck = nil }
                    .buttonStyle(.borderedProminent).disabled(checking)
            }.navigationTitle("Textübermittlung freigeben")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { pending.submission.discard(); remoteCheck = nil } } }
                .onDisappear { if startedRemoteID != pending.id { pending.submission.discard() } }
        }
    }
    private func startRemote(_ pending: RemoteCheck) {
        guard !checking, let current = library.currentPage(page.id),
              current.revision == pending.submission.document.revision,
              current.markdown.utf8.elementsEqual(pending.submission.document.source.utf8) else {
            pending.submission.discard(); error = QualityError.staleSource.localizedDescription; return
        }
        let token = UUID(); generation = token; checking = true; stopping = false; error = nil
        startedRemoteID = pending.id
        checkTask = Task {
            defer { if generation == token { checking = false; stopping = false; checkTask = nil } }
            do {
                let result = try await pending.client.check(pending.submission, consentID: pending.id, progress: { completed, total in
                    guard generation == token else { return }; checkedChunks = completed; totalChunks = total
                })
                try Task.checkCancellation()
                guard generation == token else { return }
                guard let latest = library.currentPage(page.id), latest.revision == pending.submission.document.revision,
                      latest.markdown.utf8.elementsEqual(pending.submission.document.source.utf8) else { throw QualityError.staleSource }
                findings = result; reviewCompleted = true
            } catch {
                guard generation == token else { return }
                if Task.isCancelled { reviewCancelled = true; return }
                self.error = error.localizedDescription
            }
        }
    }
    private func refreshAfterCorrection() {
        findings = []; reviewCompleted = false; reviewCancelled = false
        if !serverMode { check() }
    }
    private func accept(_ finding: QualityFinding, replacement: String) {
        guard !checking, let captured = library.currentPage(page.id) else { return }
        let token = UUID(); generation = token; checking = true; applyingCorrection = true; stopping = false; error = nil
        checkTask = Task {
            defer { if generation == token { checking = false; applyingCorrection = false; stopping = false; checkTask = nil } }
            do {
                let prepared = try await finding.prepareCorrection(replacement, source: captured.markdown, revision: captured.revision)
                try Task.checkCancellation()
                guard generation == token else { return }
                var before: Page?
                var admissionError: Error?
                let saved = performMutation {
                    do {
                        // The mutation wrapper may first flush an editor draft.
                        // Re-admit inside it, immediately before the durable write.
                        guard var current = library.currentPage(captured.id) else { throw QualityError.staleSource }
                        current.markdown = try prepared.admitting(source: current.markdown, revision: current.revision)
                        before = library.store?.snapshot.pages.first(where: { $0.id == current.id })
                        guard before != nil, let revision = library.update(current) else { return nil }
                        current.revision = revision; return library.currentPage(current.id)
                    } catch { admissionError = error; return nil }
                }
                guard let saved else { error = admissionError?.localizedDescription ?? library.saveError ?? "Die Korrektur konnte nicht gespeichert werden."; return }
                page = saved; updated(saved)
                if let before, let after = library.store?.snapshot.pages.first(where: { $0.id == saved.id }) {
                    correctionHistory.record(before: before, after: after)
                }
                checking = false; applyingCorrection = false; checkTask = nil
                refreshAfterCorrection()
            } catch {
                guard generation == token else { return }
                if Task.isCancelled { reviewCancelled = true; return }
                self.error = error.localizedDescription
            }
        }
    }
    private func undoCorrection() {
        if let saved = performMutation({ correctionHistory.undo(library: library) }) {
            page = saved; updated(saved); refreshAfterCorrection()
        } else { error = library.saveError }
    }
    private func redoCorrection() {
        if let saved = performMutation({ correctionHistory.redo(library: library) }) {
            page = saved; updated(saved); refreshAfterCorrection()
        } else { error = library.saveError }
    }
    private func openAI(_ action: WritingAIAction) { generation = UUID(); checkTask?.cancel(); aiAction(action); dismiss() }
}

private struct QualityReplacementChoice: View {
    let replacement: String
    let manual: Bool
    let disabled: Bool
    let apply: @MainActor () -> Void
    var body: some View {
        if manual {
            VStack(alignment: .leading, spacing: 8) {
                Text("Vorschlag zur manuellen Änderung").font(.caption).foregroundStyle(.secondary)
                Text(verbatim: replacement).font(.body).textSelection(.enabled)
                Text("Bitte im Editor ändern. Dieser Vorschlag wird nicht automatisch eingesetzt.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        } else {
            Button(action: apply) {
                if replacement.isEmpty { Text("Entfernen") }
                else { Text("Ersetzen durch „\(replacement)“") }
            }.buttonStyle(.borderedProminent).disabled(disabled)
        }
    }
}

private struct QualityFindingContextView: View {
    let original: String
    let context: QualityFindingContext

    private var highlightedText: AttributedString {
        var result = AttributedString((context.isTruncatedBefore ? "…" : "") + context.before)
        var marked = AttributedString(original)
        marked.font = .body.bold()
        marked.foregroundColor = .accentColor
        marked.underlineStyle = .single
        result.append(marked)
        result.append(AttributedString(context.after + (context.isTruncatedAfter ? "…" : "")))
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Textstelle", comment: "Heading above the literal source excerpt for a proofreading suggestion.")
                .font(.caption).foregroundStyle(.secondary)
            Text(highlightedText)
                .font(.body).textSelection(.enabled)
            Text("Markierte Stelle: \(original)", comment: "Accessible identification of the exact text a proofreading suggestion changes.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
