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
    let apply: (String, UUID) -> Void
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
    @State private var useSelection = true
    @State private var compare = false
    @State private var submittedSelection: NSRange?
    @State private var submittedRevisionMode = false
    @State private var keyStatus = ""
    @Environment(\.dismiss) private var dismiss
    init(page: WritingPage, selection: NSRange = NSRange(location: 0, length: 0), library: WritingLibrary? = nil, initialPrompt: String = "", initialRevisionMode: Bool = false, initialAction: WritingAIAction? = nil, apply: @escaping (String, UUID) -> Void) {
        self.page = page; self.operation = initialAction; self.selection = selection; self.library = library; self.apply = apply
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
    private var validSelection: Bool { selection.length > 0 && selection.location >= 0 && NSMaxRange(selection) <= (page.markdown as NSString).length }
    private var context: String {
        useSelection && validSelection ? (page.markdown as NSString).substring(with: selection) : page.markdown
    }
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Label(label(provider), systemImage: "sparkles")
                    Spacer()
                    Text((useSelection && validSelection ? "Textauswahl" : "Ganze Seite") + (contextIDs.isEmpty ? "" : " + \(contextIDs.count) Seiten")).foregroundStyle(.secondary)
                }.font(.caption).padding()
                Divider()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        if let operation {
                            if assistant.response.isEmpty && !assistant.running {
                                ContentUnavailableView(operation.title, systemImage: "text.badge.checkmark", description: Text("Starte mit deinem gewählten KI-Zugang. Dein Original bleibt erhalten, bis du einen Vorschlag übernimmst."))
                            }
                            if !assistant.response.isEmpty { Text(assistant.response).textSelection(.enabled) }
                            if assistant.running { ProgressView("Text wird bearbeitet …") }
                        } else {
                        if assistant.entries.isEmpty {
                            ContentUnavailableView("Mit dieser Seite arbeiten", systemImage: "text.bubble", description: Text("Besprechen Sie Ideen oder lassen Sie eine überprüfbare Überarbeitung erstellen. Der gewählte Kontext wird an den angezeigten Anbieter gesendet."))
                        }
                        ForEach(assistant.entries) { entry in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(entry.role == "user" ? "Sie" : "Assistent").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                Text(entry.text).textSelection(.enabled)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if assistant.running { Text(assistant.response.isEmpty ? "Antwort wird vorbereitet …" : assistant.response).textSelection(.enabled) }
                        }
                        if let error = assistant.error { Text(error).foregroundStyle(.red).font(.callout) }
                    }.padding()
                }
                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    if operation == nil {
                    Toggle("Überarbeitung vorschlagen", isOn: $revise).disabled(assistant.running)
                    if validSelection { Toggle("Auswahl als Zielbereich verwenden", isOn: $useSelection).disabled(assistant.running) }
                    } else if validSelection {
                        Picker("Textbereich", selection: $useSelection) { Text("Auswahl").tag(true); Text("Ganze Seite").tag(false) }
                            .pickerStyle(.segmented).disabled(assistant.running)
                    }
                    if submittedRevisionMode && assistant.completed && !assistant.running {
                        if operation != nil {
                            DisclosureGroup("Original anzeigen") { Text(context).textSelection(.enabled) }
                            HStack {
                                Button("Übernehmen", action: applyResponse).buttonStyle(.borderedProminent)
                                Button("Verwerfen") { assistant.stop(); dismiss() }.buttonStyle(.bordered)
                            }
                        } else { Button("Änderung vergleichen", systemImage: "arrow.left.arrow.right") { compare = true } }
                    }
                    if operation == .summarize && assistant.completed && !assistant.running { ShareLink("Ergebnis sichern", item: assistant.response) }
                    if operation == nil {
                    HStack {
                        if library != nil { Button("Kontextseiten", systemImage: "doc.on.doc") { choosingContext = true }.disabled(assistant.running) }
                        Menu("Prompts", systemImage: "text.bubble") {
                            Button("Zusammenfassen") { prompt = "Fasse den ausgewählten Kontext präzise zusammen. Kennzeichne offene Punkte."; revise = false }
                            Button("Sprachlich überarbeiten") { prompt = "Überarbeite den Zielbereich sprachlich. Erhalte Aussage, Quellen und alle übrigen Passagen."; revise = true }
                            ForEach(savedPrompts) { saved in Button(saved.title) { prompt = saved.text } }
                        }.disabled(assistant.running)
                    }
                    TextField("Mit dieser Seite arbeiten …", text: $prompt, axis: .vertical).lineLimit(2...5)
                    }
                    HStack {
                        Text(operation == nil ? "Kontext: gewählter Text und bis zu 8 Chatnachrichten desselben Anbieters. Der Originaltext bleibt bis zur Übernahme erhalten." : "Der angezeigte Textbereich wird an deinen gewählten KI-Zugang gesendet.").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        if assistant.running { Button("Stoppen", systemImage: "stop.fill") { assistant.stop() } }
                        else { Button(operation == nil ? "Senden" : "Starten", systemImage: "arrow.up.circle.fill", action: send).buttonStyle(.borderedProminent).disabled(!assistant.isAvailable || (operation == nil && prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)) }
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
            .task { do { account = try await ScriptumAccountSession.restoredAccount() } catch { keyStatus = error.localizedDescription } }
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
        let replacement = submittedSelection.map { (page.markdown as NSString).replacingCharacters(in: $0, with: assistant.response) } ?? assistant.response
        apply(replacement, page.revision); assistant.stop(); dismiss()
    }
    private var comparison: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Original").font(.headline)
                    Text(submittedSelection.map { (page.markdown as NSString).substring(with: $0) } ?? page.markdown).textSelection(.enabled)
                    Divider()
                    Text("Vorschlag").font(.headline)
                    Text(assistant.response).textSelection(.enabled)
                }.padding()
            }.navigationTitle("Überarbeitung prüfen")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Zurück") { compare = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Übernehmen") {
                            let replacement: String
                            if let target = submittedSelection { replacement = (page.markdown as NSString).replacingCharacters(in: target, with: assistant.response) }
                            else { replacement = assistant.response }
                            apply(replacement, page.revision); compare = false; dismiss()
                        }
                    }
                }
        }
    }
    private func send() {
        do {
            let adapter: any AIProvider
            if provider == .applePCC { adapter = ApplePCCProvider() }
            else if provider == .chatGPTSubscription { adapter = ChatGPTPlanProvider(credentials: credentials) }
            else {
                let key = try KeychainCredentialStore().read(for: provider) ?? ""
                adapter = RemoteAIProvider(id: provider, credential: key)
            }
            submittedSelection = useSelection && validSelection ? selection : nil
            submittedRevisionMode = revise
            let references = library?.pages.filter { contextIDs.contains($0.id) && !$0.trashed && $0.id != page.id }.map { AssistantReference(title: $0.title, markdown: $0.markdown) } ?? []
            assistant.run(provider: adapter, model: model, prompt: operation?.prompt ?? prompt, context: context, revisionMode: revise, rules: writingRules, references: references, includeHistory: includeHistory)
            prompt = ""
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
