import SwiftUI

struct AssistantPanel: View {
    let page: WritingPage
    var selection: NSRange = NSRange(location: 0, length: 0)
    let apply: (String, UUID) -> Void
    @State private var assistant: PageAssistant
    @State private var provider: AIProviderID = .openAIKey
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
                ToolbarItem(placement: .cancellationAction) { Button("Schließen") { assistant.stop(); dismiss() } }
                ToolbarItem(placement: .primaryAction) { Button("KI-Zugang", systemImage: "slider.horizontal.3") { settings = true } }
            }
            .sheet(isPresented: $settings) { configuration }
            .sheet(isPresented: $compare) { comparison }
            .onDisappear { assistant.stop() }
        }
    }
    private var configuration: some View {
        NavigationStack {
            Form {
                Section("Anbieter") {
                    Picker("KI-Zugang", selection: $provider) { ForEach(AIProviderID.allCases, id: \.self) { Text(label($0)).tag($0) } }
                    if provider == .openAIKey || provider == .anthropicKey {
                        TextField("Modell-ID Ihres Anbieters", text: $model).textInputAutocapitalization(.never).autocorrectionDisabled()
                        SecureField("API-Schlüssel", text: $secret).textInputAutocapitalization(.never).autocorrectionDisabled()
                        Button("Schlüssel im Keychain speichern") {
                            do { try KeychainCredentialStore().save(secret, for: provider); secret = ""; keyStatus = "Schlüssel sicher auf diesem Gerät gespeichert." }
                            catch { keyStatus = error.localizedDescription }
                        }.disabled(secret.isEmpty)
                        Text(keyStatus).font(.caption)
                        Text("API-Nutzung wird durch Ihren Anbieter separat abgerechnet. Schlüssel werden nicht in Dokumenten oder iCloud gespeichert.").font(.caption).foregroundStyle(.secondary)
                    } else if provider == .applePCC {
                        Text(ApplePCCProvider().availabilityDescription ?? "Private Cloud Compute verfügbar")
                    } else {
                        Text("Der kommerzielle mobile Zugang mit ChatGPT-Abo muss für diese App von OpenAI bereitgestellt werden. Ein vorhandenes ChatGPT-Abo allein aktiviert ihn noch nicht.")
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
    private func label(_ id: AIProviderID) -> String {
        switch id { case .openAIKey: "OpenAI API"; case .anthropicKey: "Anthropic API"; case .applePCC: "Apple Private Cloud Compute"; case .chatGPTSubscription: "ChatGPT-Abo" }
    }
}
