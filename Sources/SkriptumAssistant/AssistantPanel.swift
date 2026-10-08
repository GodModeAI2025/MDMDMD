import SwiftUI
import UIKit

struct AssistantPanel: View {
    let page: WritingPage
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
    init(page: WritingPage, selection: NSRange = NSRange(location: 0, length: 0), apply: @escaping (String, UUID) -> Void) {
        self.page = page; self.selection = selection; self.apply = apply
        _assistant = State(initialValue: PageAssistant(pageID: page.id))
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
                    Text(useSelection && validSelection ? "Textauswahl" : "Ganze Seite").foregroundStyle(.secondary)
                }.font(.caption).padding()
                Divider()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
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
                        if let error = assistant.error { Text(error).foregroundStyle(.red).font(.callout) }
                    }.padding()
                }
                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Überarbeitung vorschlagen", isOn: $revise).disabled(assistant.running)
                    if validSelection { Toggle("Nur ausgewählten Text verwenden", isOn: $useSelection).disabled(assistant.running) }
                    if submittedRevisionMode && assistant.completed {
                        Button("Änderung vergleichen", systemImage: "arrow.left.arrow.right") { compare = true }
                    }
                    TextField("Mit dieser Seite arbeiten …", text: $prompt, axis: .vertical).lineLimit(2...5)
                    HStack {
                        Text("Kontext: gewählter Text und bis zu 8 Chatnachrichten desselben Anbieters. Der Originaltext bleibt bis zur Übernahme erhalten.").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        if assistant.running { Button("Stoppen", systemImage: "stop.fill") { assistant.stop() } }
                        else { Button("Senden", systemImage: "arrow.up.circle.fill", action: send).disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
                    }
                }.padding()
            }
            .navigationTitle(page.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Schließen") { assistant.stop(); loginCoordinator?.cancel(); loginTask?.cancel(); dismiss() } }
                ToolbarItem(placement: .primaryAction) { Button("KI-Zugang", systemImage: "slider.horizontal.3") { settings = true } }
            }
            .sheet(isPresented: $settings) { configuration }
            .sheet(isPresented: $compare) { comparison }
            .background(AssistantWindowReader { window = $0 }.frame(width: 0, height: 0))
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
                        Text("Ohne ChatGPT-Konto und ohne API-Schlüssel. Die Apple-Freigabe für diese App ist beantragt. Es gibt keinen automatischen Wechsel zu einem anderen KI-Anbieter.").font(.caption).foregroundStyle(.secondary)
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
        }
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
            assistant.run(provider: adapter, model: model, prompt: prompt, context: context, revisionMode: revise)
            prompt = ""
        } catch { assistant.error = error.localizedDescription }
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
