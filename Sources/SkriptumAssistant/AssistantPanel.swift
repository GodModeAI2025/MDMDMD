import SwiftUI
import UIKit

enum WritingAIAction: String, Identifiable {
    case proofread, rewrite, summarize
    var id: String { rawValue }
    var title: String { switch self { case .proofread: "Lektorat"; case .rewrite: "Überarbeiten"; case .summarize: "Zusammenfassen" } }
    var prompt: String { switch self {
        case .proofread: "Korrigiere Rechtschreibung, Grammatik und sprachliche Fehler. Erhalte Bedeutung, Quellen, Ton und Markdown. Ändere nur, was für die Korrektur nötig ist."
        case .rewrite: "Überarbeite den Text sprachlich für klare, flüssige Formulierungen. Erhalte Bedeutung, Quellen und Markdown."
        case .summarize: "Fasse den Text präzise zusammen. Erfinde keine Fakten oder Quellen. Kennzeichne offene Punkte."
    } }
    var revisesText: Bool { self != .summarize }
}

struct AssistantPanel: View {
    let page: WritingPage
    private let operation: WritingAIAction?
    let library: WritingLibrary?
    var selection: NSRange = NSRange(location: 0, length: 0)
    var activeBlock: NSRange?
    let apply: (AssistantTextTarget, String) -> Bool
    @State private var assistant: PageAssistant
    @State private var provider: AIProviderID = .applePCC
    private let credentials = ScriptumAccountSession.credentials
    @State private var account: ChatGPTAccount?
    @State private var window: UIWindow?
    @State private var loginCoordinator: NativeChatGPTSignInCoordinator?
    @State private var loginTask: Task<Void, Never>?
    @State private var signingIn = false
    @State private var models: [AIModelChoice] = []
    @State private var loadingModels = false
    @State private var contextIDs: Set<UUID> = []
    @State private var choosingContext = false
    @State private var includeHistory = true
    @State private var prompt = ""
    @State private var model = ""
    @State private var secret = ""
    @State private var settings = false
    @State private var revise = false
    @State private var widenToPage = false
    @State private var currentScope: AssistantScope?
    @State private var started = false
    @State private var compare = false
    @State private var submittedTarget: AssistantTextTarget?
    @State private var submittedRevisionMode = false
    @State private var submittedHybrid = false
    @State private var submittedOriginal = ""
    @State private var submittedPrefix = ""
    private struct AppliedChange {
        let range: NSRange
        let original: String
        let messageID: UUID?
        let expectedSource: String
        let scopeKind: AssistantScopeKind
    }
    @State private var applied: AppliedChange?
    @State private var keyStatus = ""
    @Environment(\.dismiss) private var dismiss
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    private var compactHeight: Bool { verticalSizeClass == .compact }
    init(page: WritingPage, selection: NSRange = NSRange(location: 0, length: 0), library: WritingLibrary? = nil, initialPrompt: String = "", initialRevisionMode: Bool = false, initialAction: WritingAIAction? = nil, activeBlock: NSRange? = nil, apply: @escaping (AssistantTextTarget, String) -> Bool) {
        self.page = page; self.operation = initialAction; self.selection = selection; self.activeBlock = activeBlock; self.library = library; self.apply = apply
        _prompt = State(initialValue: initialAction?.prompt ?? initialPrompt); _revise = State(initialValue: initialAction?.revisesText ?? initialRevisionMode)
        _includeHistory = State(initialValue: initialAction == nil)
        if let library {
            do { _assistant = State(initialValue: PageAssistant(pageID: page.id, directory: try library.assistantHistoryDirectory())) }
            catch { _assistant = State(initialValue: PageAssistant(unavailableError: "Der private Chat-Speicher dieser Bibliothek ist nicht verfügbar. Es wird kein anderer Verlauf geöffnet.")) }
        } else {
            _assistant = State(initialValue: PageAssistant(pageID: page.id))
        }
        let saved = AIProviderID(rawValue: UserDefaults.standard.string(forKey: "Scriptum.ai.provider") ?? "") ?? .applePCC
        _provider = State(initialValue: saved)
        _model = State(initialValue: UserDefaults.standard.string(forKey: "Scriptum.ai.model." + saved.rawValue) ?? "")
    }
    private func admissible(_ range: NSRange?) -> NSRange? {
        guard let range, range.length > 0, (try? AssistantTextTarget(page: page, selection: range)) != nil else { return nil }
        return range
    }
    private var naturalScope: AssistantScope { AssistantScope.resolve(markdown: page.markdown, selection: admissible(selection), activeBlock: admissible(activeBlock)) }
    private var scope: AssistantScope { widenToPage ? .page : currentScope ?? naturalScope }
    private var scopeText: String { scope.kind.label + (contextIDs.isEmpty ? "" : " + \(contextIDs.count) Seiten") }
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                contextCard
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        if let operation {
                            if assistant.response.isEmpty && !assistant.running {
                                ContentUnavailableView(operation.title, systemImage: "text.badge.checkmark", description: Text("Bereich: \(scope.kind.label). Dein Original bleibt erhalten, bis du einen Vorschlag übernimmst."))
                            }
                            if !assistant.response.isEmpty { AssistantMarkdown(text: assistant.response) }
                            if assistant.running { ProgressView("Text wird bearbeitet …") }
                        } else {
                        if assistant.entries.isEmpty {
                            ContentUnavailableView("Mit dieser Seite arbeiten", systemImage: "text.bubble", description: Text("Besprechen Sie Ideen oder lassen Sie eine überprüfbare Überarbeitung erstellen. Der gewählte Kontext wird an den angezeigten Anbieter gesendet."))
                        }
                        ForEach(assistant.entries) { entry in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(entry.role == "user" ? "Sie" : "Assistent").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                AssistantMarkdown(text: entry.role == "assistant" ? AssistantReply.display(entry.text, status: entry.applicationStatus) : entry.text)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if assistant.running { if assistant.response.isEmpty { Text("Antwort wird vorbereitet …") } else { AssistantMarkdown(text: AssistantReply.display(assistant.response)) } }
                        }
                        if let error = assistant.error { Text(error).foregroundStyle(.red).font(.callout) }
                    }.padding()
                }
                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    if operation == nil, let applied {
                        HStack {
                            Label("Änderung übernommen", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                            Spacer()
                            Button("Rückgängig", systemImage: "arrow.uturn.backward") { undo(applied) }.buttonStyle(.bordered)
                        }.font(.subheadline)
                    } else if submittedRevisionMode && assistant.completed && !assistant.running {
                        if operation != nil {
                            DisclosureGroup("Original anzeigen") { Text(submittedOriginal).textSelection(.enabled) }
                            if !submittedPrefix.isEmpty { Text("Die Zusammenfassung wird unter dem Bereich eingefügt.").font(.caption).foregroundStyle(.secondary) }
                            HStack {
                                Button("Übernehmen", action: applyResponse).buttonStyle(.borderedProminent)
                                Button("Verwerfen") { assistant.stop(); dismiss() }.buttonStyle(.bordered)
                            }
                        } else { Button("Änderung vergleichen", systemImage: "arrow.left.arrow.right") { compare = true } }
                    }
                    if operation == .summarize && assistant.completed && !assistant.running { ShareLink("Ergebnis sichern", item: assistant.response) }
                    if operation == nil {
                    if !compactHeight {
                    HStack {
                        if library != nil { Button("Kontextseiten", systemImage: "doc.on.doc") { choosingContext = true }.disabled(assistant.running) }
                        Menu("Prompts", systemImage: "text.bubble") {
                            Button("Zusammenfassen") { prompt = "Fasse den ausgewählten Kontext präzise zusammen. Kennzeichne offene Punkte."; revise = false }
                            Button("Sprachlich überarbeiten") { prompt = "Überarbeite den Zielbereich sprachlich. Erhalte Aussage, Quellen und alle übrigen Passagen."; revise = true }
                            ForEach(savedPrompts) { saved in Button(saved.title) { prompt = saved.text } }
                        }.disabled(assistant.running)
                    }
                    }
                    commandField
                    } else {
                    HStack {
                        Text("Der Bereich \(scope.kind.label) wird an deinen gewählten KI-Zugang gesendet.").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        if assistant.running { Button("Stoppen", systemImage: "stop.fill") { assistant.stop() } }
                        else { Button("Starten", systemImage: "arrow.up.circle.fill", action: send).buttonStyle(.borderedProminent).disabled(!assistant.isAvailable) }
                    }
                    }
                }.padding()
            }
            .navigationTitle(operation?.title ?? page.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Schließen") { assistant.stop(); loginCoordinator?.cancel(); loginTask?.cancel(); dismiss() } }
                ToolbarItem(placement: .primaryAction) { Button("KI-Zugang", systemImage: "slider.horizontal.3") { settings = true } }
            }
            .sheet(isPresented: $settings) { configuration }
            .sheet(isPresented: $compare) { comparison }
            .sheet(isPresented: $choosingContext) { contextChooser }
            .onChange(of: assistant.completed) { _, done in if done { applyChatEdit() } }
            .task {
                do { account = try await ScriptumAccountSession.restoredAccount() } catch { keyStatus = error.localizedDescription }
                if operation != nil, !started { started = true; send() }
            }
            .onChange(of: provider) { _, next in
                secret = ""; models = []; model = UserDefaults.standard.string(forKey: "Scriptum.ai.model." + next.rawValue) ?? ""
                UserDefaults.standard.set(next.rawValue, forKey: "Scriptum.ai.provider")
            }
            .onChange(of: model) { _, next in UserDefaults.standard.set(next, forKey: "Scriptum.ai.model." + provider.rawValue) }
            .interactiveDismissDisabled(signingIn)
            .onDisappear { assistant.stop(); if !signingIn { loginCoordinator?.cancel(); loginTask?.cancel() } }
        }
    }
    private var configuration: some View {
        NavigationStack {
            Form {
                Section("Anbieter") {
                    Picker("KI-Zugang", selection: $provider) { ForEach(AIProviderID.allCases, id: \.self) { Text(label($0)).tag($0) } }.disabled(assistant.running || signingIn)
                    if provider == .openAIKey || provider == .anthropicKey {
                        modelPicker
                        SecureField("API-Schlüssel", text: $secret).textInputAutocapitalization(.never).autocorrectionDisabled()
                        Button("Schlüssel im Keychain speichern") {
                            do { try KeychainCredentialStore().save(secret, for: provider); secret = ""; keyStatus = "Schlüssel sicher auf diesem Gerät gespeichert." }
                            catch { keyStatus = error.localizedDescription }
                        }.disabled(secret.isEmpty)
                        Text(keyStatus).font(.caption)
                        Text("API-Nutzung wird durch Ihren Anbieter separat abgerechnet. Schlüssel werden nicht in Dokumenten oder iCloud gespeichert.").font(.caption).foregroundStyle(.secondary)
                    } else if provider == .applePCC {
                        Text(ApplePCCProvider().availabilityDescription ?? "Private Cloud Compute verfügbar")
                        Text("Ohne ChatGPT-Konto und ohne API-Schlüssel. Apple hat das PCC-Entitlement für Scriptum bereitgestellt. Die Verfügbarkeit hängt zusätzlich von Ihrem Gerät und den Apple-Diensten ab. Es gibt keinen automatischen Wechsel zu einem anderen KI-Anbieter.").font(.caption).foregroundStyle(.secondary)
                    } else {
                        if let account {
                            Label(account.identity.email ?? "Mit ChatGPT verbunden", systemImage: "person.crop.circle.badge.checkmark")
                            modelPicker
                            Button("Abmelden") {
                                Task { do { try await credentials.signOut(); self.account = nil; models = []; model = "" } catch { keyStatus = error.localizedDescription } }
                            }.disabled(signingIn || assistant.running)
                        } else {
                            Button("Continue with ChatGPT", action: signIn).disabled(signingIn || window == nil)
                            if signingIn { ProgressView("Anmeldung im Systembrowser …") }
                            Text("Sie geben die Nutzung Ihres berechtigten ChatGPT-Abos im OpenAI-Anmeldefenster frei. Scriptum erhält dadurch keinen Zugriff auf Ihre bisherigen ChatGPT-Chats.").font(.caption).foregroundStyle(.secondary)
                        }
                        if !keyStatus.isEmpty { Text(keyStatus).font(.caption) }
                    }
                }
            }.navigationTitle("KI-Zugang").toolbar { Button("Fertig") { settings = false } }
                .background(AssistantWindowReader { window = $0 }.frame(width: 0, height: 0))
        }
    }
    private func applyResponse() {
        guard let submittedTarget else { assistant.error = "Für diesen Vorschlag fehlt die ursprüngliche Textfassung."; return }
        guard apply(submittedTarget, submittedPrefix + assistant.response) else {
            assistant.error = library?.saveError ?? "Der Vorschlag konnte nicht gespeichert werden. Ihr Ergebnis bleibt hier erhalten."
            return
        }
        assistant.stop(); compare = false; dismiss()
    }
    private var comparison: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Original").font(.headline)
                    Text(submittedOriginal).textSelection(.enabled)
                    Divider()
                    Text("Vorschlag").font(.headline)
                    AssistantMarkdown(text: assistant.response)
                    if let error = assistant.error { Text(error).foregroundStyle(.red) }
                }.padding()
            }.navigationTitle("Überarbeitung prüfen")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Zurück") { compare = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Übernehmen") {
                            applyResponse()
                        }
                    }
                }
        }
    }
    private func send() {
        do {
            var adapter: any AIProvider
            if provider == .applePCC { adapter = ApplePCCProvider() }
            else if provider == .chatGPTSubscription { adapter = ChatGPTPlanProvider(credentials: credentials) }
            else {
                let key = try KeychainCredentialStore().read(for: provider) ?? ""
                adapter = RemoteAIProvider(id: provider, credential: key)
            }
            #if DEBUG
            if DebugFakeProvider.enabled { adapter = DebugFakeProvider(id: provider) }
            #endif
            let scope = scope
            let editing = operation != nil || AssistantIntent.classify(prompt) == .edit
            let hybrid = operation == nil && !editing
            let task = try AssistantTextTarget(page: page, selection: scope.range)
            var target = task, prefix = ""
            if operation == .summarize {
                let end = scope.range.map { NSMaxRange($0) } ?? page.markdown.utf16.count
                target = try AssistantTextTarget(page: page, selection: NSRange(location: end, length: 0))
                prefix = scope.kind == .page && page.markdown.hasSuffix("\n") ? "\n" : "\n\n"
            }
            let references = library?.pages.filter { contextIDs.contains($0.id) && !$0.trashed && $0.id != page.id }.map { AssistantReference(title: $0.title, markdown: $0.markdown) } ?? []
            let submission = try assistant.prepare(providerID: adapter.id, model: model,
                prompt: operation?.prompt ?? prompt, context: (editing || hybrid) ? task.original : AssistantScope.chatContext(markdown: page.markdown, scope: scope), revisionMode: editing,
                rules: writingRules, references: references, includeHistory: includeHistory, hybrid: hybrid)
            applied = nil
            if assistant.run(provider: adapter, submission: submission, consentID: submission.id) {
                submittedTarget = target; submittedRevisionMode = editing; submittedHybrid = hybrid
                submittedOriginal = task.original; submittedPrefix = prefix
                prompt = ""
                if editing { revise = true }
            }
        } catch { assistant.error = error.localizedDescription }
    }
    private var scopePreview: String {
        let text: String
        if let scoped = scope.range {
            guard let range = Range(scoped, in: page.markdown) else { return "Der Bereich wurde verändert. Öffne den Assistenten erneut für den aktuellen Text." }
            text = String(page.markdown[range])
        } else { text = page.markdown }
        let trimmed = AssistantMedia.stripLinks(text).trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "(leer)" : String(trimmed.prefix(400))
    }
    private var contextCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Kontext: " + scopeText, systemImage: "doc.text.magnifyingglass").font(.subheadline.weight(.semibold))
                Spacer()
                if naturalScope.kind != .page {
                    Button(widenToPage ? "Nur \(naturalScope.kind.label)" : "Ganze Seite") { widenToPage.toggle() }.font(.caption).disabled(assistant.running)
                }
            }
            if !compactHeight { Text(scopePreview).font(.footnote).foregroundStyle(.secondary).lineLimit(3) }
            Label("Wird an \(label(provider)) gesendet", systemImage: "sparkles").font(.caption2).foregroundStyle(.secondary)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal).padding(.vertical, 8)
    }
    private var commandField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Dein Auftrag").font(.subheadline.weight(.semibold))
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Was soll mit \(scope.kind.label == "Seite" ? "der Seite" : "dem Bereich") geschehen?", text: $prompt, axis: .vertical).lineLimit(compactHeight ? 1...2 : 2...5)
                if assistant.running {
                    Button { assistant.stop() } label: { Image(systemName: "stop.circle.fill").font(.title) }.accessibilityLabel("Stoppen")
                } else {
                    Button(action: send) { Image(systemName: "arrow.up.circle.fill").font(.title) }.accessibilityLabel("Senden")
                        .disabled(!assistant.isAvailable || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(10)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.accentColor, lineWidth: 1.5))
            if !compactHeight {
                Text("Fragen werden beantwortet. Änderungswünsche führt der Chat sofort im Text aus, mit „Rückgängig“.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    /// Ein Chat-Auftrag mit Änderungswunsch gilt als Freigabe: Das Ergebnis ersetzt den Bereich sofort, das Original bleibt über „Rückgängig“ erreichbar.
    private func applyChatEdit() {
        guard operation == nil, submittedRevisionMode || submittedHybrid, applied == nil, let target = submittedTarget,
              !assistant.response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        var text = submittedPrefix + assistant.response
        if submittedHybrid {
            guard let replacement = AssistantReply.parse(assistant.response, original: submittedOriginal).replacement else { return }
            text = replacement
        }
        if apply(target, text) {
            applied = AppliedChange(range: NSRange(location: target.selection?.location ?? 0, length: text.utf16.count), original: submittedOriginal, messageID: assistant.entries.last?.id, expectedSource: target.replacing(with: text), scopeKind: scope.kind)
            currentScope = target.selection.map { AssistantScope(kind: scope.kind, range: NSRange(location: $0.location, length: text.utf16.count)) } ?? .page
            recordApplication(.applied, messageID: applied?.messageID)
        } else {
            recordApplication(.rejected, messageID: assistant.entries.last?.id)
            assistant.error = library?.saveError ?? "Die Änderung konnte nicht angewendet werden. Das Ergebnis bleibt im Chat erhalten."
        }
    }
    private func recordApplication(_ status: AssistantApplicationStatus, messageID: UUID?) {
        guard let messageID else { return }
        do { try assistant.recordApplication(status, messageID: messageID) }
        catch { assistant.error = "Der Änderungsstatus konnte nicht im Chat gespeichert werden. Prüfe den aktuellen Text in der Schreibansicht." }
    }
    private func undo(_ change: AppliedChange) {
        do {
            guard page.markdown.utf8.elementsEqual(change.expectedSource.utf8) else {
                assistant.error = "Der Text wurde inzwischen weiter bearbeitet. Nutze die Fassungen, um das Original wiederherzustellen."; return
            }
            let target = try AssistantTextTarget(page: page, selection: change.range)
            if apply(target, change.original) {
                applied = nil; assistant.error = nil
                currentScope = change.scopeKind == .page ? .page : AssistantScope(kind: change.scopeKind, range: NSRange(location: change.range.location, length: change.original.utf16.count))
                recordApplication(.undone, messageID: change.messageID)
            }
            else { assistant.error = library?.saveError ?? "Die Änderung konnte nicht zurückgenommen werden." }
        } catch { assistant.error = error.localizedDescription }
    }
    private var savedPrompts: [ReusablePrompt] {
        let space = library?.spaces.first { $0.id == page.spaceID }
        return (space?.reusablePrompts ?? []) + (page.reusablePrompts ?? [])
    }
    private var writingRules: String {
        [library?.spaces.first { $0.id == page.spaceID }?.assistantRules ?? "", page.assistantRules ?? ""].filter { !$0.isEmpty }.joined(separator: "\n\n")
    }
    private var contextChooser: some View {
        NavigationStack {
            List {
                Toggle("Letzte Nachrichten dieses Anbieters mitsenden", isOn: $includeHistory)
                Text("Nur die markierten Seiten werden zusätzlich an den gewählten Anbieter gesendet.").font(.caption).foregroundStyle(.secondary)
                ForEach(library?.pages.filter { !$0.trashed && $0.id != page.id } ?? []) { source in
                    Button {
                        if contextIDs.contains(source.id) { contextIDs.remove(source.id) } else { contextIDs.insert(source.id) }
                    } label: { HStack { Text(source.title); Spacer(); if contextIDs.contains(source.id) { Image(systemName: "checkmark") } } }
                }
            }.navigationTitle("KI-Kontext").toolbar { Button("Fertig") { choosingContext = false } }
        }
    }
    private var modelPicker: some View {
        Group {
            if !models.isEmpty {
                Picker("Modell", selection: $model) {
                    Text("Bitte auswählen").tag("")
                    ForEach(models) { choice in Text(choice.displayName + (choice.deprecated ? " (veraltet)" : "")).tag(choice.id) }
                }
            }
            Button("Verfügbare Modelle laden", action: loadModels).disabled(loadingModels || signingIn)
            if loadingModels { ProgressView() }
            TextField("Modell-ID (erweitert)", text: $model).textInputAutocapitalization(.never).autocorrectionDisabled()
        }
    }
    private func loadModels() {
        guard !loadingModels else { return }
        let selected = provider; loadingModels = true; keyStatus = ""
        Task {
            defer { loadingModels = false }
            do {
                let key = selected == .chatGPTSubscription ? "" : try KeychainCredentialStore().read(for: selected) ?? ""
                let choices = try await AIModelCatalog().list(provider: selected, credential: key, account: credentials)
                guard selected == provider else { return }
                models = choices
                if !choices.contains(where: { $0.id == model }) { model = "" }
                if choices.isEmpty { keyStatus = "Für diesen Zugang wurden keine Modelle zurückgegeben." }
            } catch { keyStatus = error.localizedDescription }
        }
    }
    private func signIn() {
        guard let window, !signingIn else { return }
        signingIn = true; keyStatus = ""
        let coordinator = NativeChatGPTSignInCoordinator(credentials: credentials, anchor: window)
        loginCoordinator = coordinator
        loginTask = Task {
            defer { signingIn = false; loginCoordinator = nil; loginTask = nil }
            do { account = try await coordinator.signIn(); loadModels() }
            catch { keyStatus = error.localizedDescription }
        }
    }
    private func label(_ id: AIProviderID) -> String {
        switch id { case .openAIKey: "OpenAI API"; case .anthropicKey: "Anthropic API"; case .applePCC: "Apple Private Cloud Compute"; case .chatGPTSubscription: "ChatGPT-Abo" }
    }
}


private struct AssistantMarkdown: View {
    let text: String
    private var lines: [String] { AssistantMedia.stripLinks(text).components(separatedBy: "\n") }
    private func inline(_ line: String) -> Text {
        let parsed = try? AttributedString(markdown: line, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
        return parsed.map { Text($0) } ?? Text(line)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty { Color.clear.frame(height: 2) }
                else if let hashes = trimmed.firstIndex(where: { $0 != "#" }), hashes > trimmed.startIndex, trimmed[hashes] == " " {
                    inline(String(trimmed[hashes...]).trimmingCharacters(in: .whitespaces)).font(.headline)
                } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") { inline("• " + trimmed.dropFirst(2)) }
                else { inline(line) }
            }
        }.frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
    }
}

private struct AssistantWindowReader: UIViewRepresentable {
    let changed: (UIWindow?) -> Void
    func makeUIView(context: Context) -> AssistantAnchorView { let view = AssistantAnchorView(); view.changed = changed; return view }
    func updateUIView(_ view: AssistantAnchorView, context: Context) { view.changed = changed }
}
private final class AssistantAnchorView: UIView {
    var changed: ((UIWindow?) -> Void)?
    override func didMoveToWindow() { super.didMoveToWindow(); let window = window; Task { @MainActor [weak self] in self?.changed?(window) } }
}

private enum ScriptumAccountSession {
    static let credentials = ChatGPTCredentials()
    private static let restoration = Task<ChatGPTAccount?, Error> { try await credentials.restore() }
    static func restoredAccount() async throws -> ChatGPTAccount? {
        _ = try await restoration.value
        return await credentials.account()
    }
}
