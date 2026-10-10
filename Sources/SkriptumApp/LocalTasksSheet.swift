import SwiftUI

struct LocalTasksSheet: View {
    let library: WritingLibrary
    var pageID: UUID?
    @State private var session: LocalScheduleSession
    @State private var creating = false
    @State private var selectedProposal: LocalTaskProposalSelection?
    @State private var selectedActivation: LocalTaskActivationSelection?
    private let activationExecutor: (@MainActor (UUID) async throws -> any LocalScheduledExecutor)?
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss
    init(library: WritingLibrary, pageID: UUID? = nil, activationExecutor: (@MainActor (UUID) async throws -> any LocalScheduledExecutor)? = nil) {
        self.library = library; self.pageID = pageID; self.activationExecutor = activationExecutor
        let session = library.scheduleSession ?? LocalScheduleSession(library: library)
        library.scheduleSession = session; _session = State(initialValue: session)
    }
    private var tasks: [ScheduledTask] {
        session.state.tasks.values.filter { pageID == nil || $0.pageID == pageID }.sorted { $0.createdAt > $1.createdAt }
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Aufgaben bleiben auf diesem Gerät. Eine gespeicherte Planung wird erst nach Prüfung von KI-Zugang, Ausführungsmodus und Budget aktiviert.").font(.callout).foregroundStyle(.secondary)
                    Button("Neue Aufgabe", systemImage: "plus") { creating = true }.disabled(library.pages.filter { !$0.trashed }.isEmpty || session.error != nil)
                }
                Section("Aufgaben") {
                    if tasks.isEmpty { Text("Noch keine Aufgaben gespeichert.").foregroundStyle(.secondary) }
                    ForEach(tasks) { task in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(library.currentPage(task.pageID)?.title ?? "Seite nicht verfügbar").font(.headline)
                            Text(task.prompt).lineLimit(3)
                            Text(status(task.lifecycle)).font(.caption).foregroundStyle(.secondary)
                            if let date = try? task.rule.next(after: task.lastOccurrence ?? task.scheduleAnchor.addingTimeInterval(-0.001)) {
                                Text(date, format: .dateTime.day().month().year().hour().minute()).font(.caption)
                            }
                            if let binding = try? session.binding(task) { Text(localProviderTitle(binding.provider) + " · " + binding.model).font(.caption).foregroundStyle(.secondary) }
                            if [.draft, .awaitingActivation, .paused].contains(task.lifecycle) { Button(task.lifecycle == .paused ? "Fortsetzen prüfen" : "Aktivierung prüfen") { selectedActivation = .init(id: task.id) } }
                            if task.lifecycle == .active { Button("Pausieren") { change { try await session.pause(task) } } }
                            if task.lifecycle != .cancelled { Button("Abbrechen", role: .destructive) { change { try await session.cancel(task) } } }
                        }.buttonStyle(.borderless).padding(.vertical, 6)
                    }
                }
                LocalTaskResultsSection(state: session.state, library: library, pageID: pageID) { selectedProposal = $0 }
                if let error = error ?? session.error { Section { Text(error).foregroundStyle(.red).textSelection(.enabled) } }
            }.scrollContentBackground(.hidden).background { PaperSurface().ignoresSafeArea() }
            .navigationTitle("Geplante Aufgaben")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Schließen") { dismiss() } } }
            .task { await session.load() }
            .sheet(isPresented: $creating) { LocalTaskCreationSheet(library: library, pageID: pageID, session: session) }
            .sheet(item: $selectedActivation) { selected in
                LocalTaskActivationSheet(library: library, session: session, taskID: selected.id, executorFactory: activationExecutor)
            }
            .sheet(item: $selectedProposal) { selected in
                LocalTaskProposalSheet(library: library, session: session, selection: selected)
            }
        }
    }
    private func change(_ operation: @escaping () async throws -> Void) {
        Task { do { try await operation(); error = nil } catch { self.error = "Die Änderung konnte nicht gespeichert werden. Die Aufgabe bleibt erhalten." } }
    }
    private func status(_ value: TaskLifecycle) -> String {
        switch value { case .draft: "Entwurf · noch nicht aktiviert"; case .awaitingActivation: "Aktivierung ausstehend"; case .active: "Aktiv"; case .paused: "Pausiert"; case .cancelled: "Abgebrochen" }
    }
}
private struct LocalTaskResultsSection: View {
    let state: SchedulingState, library: WritingLibrary
    let pageID: UUID?
    let openProposal: (LocalTaskProposalSelection) -> Void
    private let summaries: [ScheduledSummary]
    private let proposals: [ScheduledProposal]
    init(state: SchedulingState, library: WritingLibrary, pageID: UUID?, openProposal: @escaping (LocalTaskProposalSelection) -> Void) {
        self.state = state; self.library = library; self.pageID = pageID; self.openProposal = openProposal
        summaries = state.summaries.values.filter { pageID == nil || $0.pageID == pageID }.sorted { $0.createdAt > $1.createdAt }
        proposals = state.proposals.values.filter { pageID == nil || $0.pageID == pageID }.sorted { $0.id.uuidString < $1.id.uuidString }
    }
    var body: some View {
        Section("Ergebnisse") {
            if summaries.isEmpty && proposals.isEmpty { Text("Noch keine Ergebnisse.").foregroundStyle(.secondary) }
            ForEach(summaries) { summary in
                DisclosureGroup(library.currentPage(summary.pageID)?.title ?? "Zusammenfassung") {
                    Text(summary.text).textSelection(.enabled)
                    Text(summary.providerID + " · " + summary.modelID).font(.caption).foregroundStyle(.secondary)
                    ShareLink("Ergebnis sichern", item: summary.text)
                }
            }
            ForEach(proposals) { proposal in
                Button { openProposal(LocalTaskProposalSelection(id: proposal.id, pageID: proposal.pageID)) } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(library.currentPage(proposal.pageID)?.title ?? "Vorschlag").font(.headline)
                        Label("Vorschlag vergleichen", systemImage: "doc.on.doc")
                        Text("Original und neue Fassung prüfen, bevor du Änderungen übernimmst.").font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.plain)
            }
        }
    }
}
private enum LocalRecurrence: String, CaseIterable, Identifiable { case once = "Einmalig", daily = "Täglich", weekly = "Wöchentlich", monthly = "Monatlich"; var id: Self { self } }
private struct LocalTaskCreationSheet: View {
    let library: WritingLibrary, session: LocalScheduleSession
    @State private var selectedPage: UUID?
    @State private var prompt = ""
    @State private var provider = AIProviderID.applePCC
    @State private var model = "Apple Private Cloud Compute"
    @State private var action = ScheduledAction.summary
    @State private var recurrence = LocalRecurrence.once
    @State private var date = Date().addingTimeInterval(3600)
    @State private var weekdays: Set<Int> = [2]
    @State private var monthDay = 1
    @State private var limitCount = false
    @State private var count = 1
    @State private var endEnabled = false
    @State private var end = Date().addingTimeInterval(30 * 86400)
    @State private var perRunCents = 0
    @State private var monthlyCents = 0
    @State private var inputTokens = 32000
    @State private var outputTokens = 2048
    @State private var saving = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss
    init(library: WritingLibrary, pageID: UUID?, session: LocalScheduleSession) {
        self.library = library; self.session = session
        _selectedPage = State(initialValue: pageID ?? library.pages.first(where: { !$0.trashed })?.id)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Inhalt") {
                    Picker("Seite", selection: $selectedPage) { ForEach(library.pages.filter { !$0.trashed }) { Text($0.title).tag(Optional($0.id)) } }
                    TextField("Auftrag", text: $prompt, axis: .vertical)
                    Picker("Ergebnis", selection: $action) { Text("Zusammenfassung").tag(ScheduledAction.summary); Text("Änderungsvorschlag").tag(ScheduledAction.proposal) }
                    Text("Kontext ist die gesamte gewählte Seite. Die Aufgabe erhält keinen Zugriff auf andere Seiten.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Termin") {
                    Picker("Wiederholung", selection: $recurrence) { ForEach(LocalRecurrence.allCases) { Text(LocalizedStringKey($0.rawValue)).tag($0) } }
                    DatePicker(recurrence == .once ? "Ausführen ab" : "Uhrzeit", selection: $date, displayedComponents: recurrence == .once ? [.date, .hourAndMinute] : [.hourAndMinute])
                    Text("Zeitzone: " + TimeZone.current.identifier).font(.caption)
                    if recurrence == .weekly {
                        ForEach(1...7, id: \.self) { day in Toggle(Calendar.current.weekdaySymbols[day - 1], isOn: Binding(get: { weekdays.contains(day) }, set: { if $0 { weekdays.insert(day) } else { weekdays.remove(day) } })) }
                    }
                    if recurrence == .monthly { Stepper("Tag im Monat: \(monthDay)", value: $monthDay, in: 1...31) }
                    Toggle("Anzahl begrenzen", isOn: $limitCount)
                    if limitCount { Stepper("\(count) Ausführungen", value: $count, in: 1...1000) }
                    Toggle("Enddatum", isOn: $endEnabled)
                    if endEnabled { DatePicker("Endet am", selection: $end) }
                }
                Section("KI-Zugang") {
                    Picker("Anbieter", selection: $provider) { ForEach(AIProviderID.allCases, id: \.self) { Text(localProviderTitle($0)).tag($0) } }
                    TextField("Modell", text: $model)
                    Text("Zugang und Preisfreigabe werden vor der Aktivierung geprüft. Ein Entwurf löst keinen KI-Aufruf aus.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Grenzen") {
                    Stepper("Pro Lauf: \(perRunCents) USD-Cent", value: $perRunCents, in: 0...10000)
                    Stepper("Pro Monat: \(monthlyCents) USD-Cent", value: $monthlyCents, in: perRunCents...100000)
                    Stepper("Input: \(inputTokens) Tokens", value: $inputTokens, in: 1024...200000, step: 1024)
                    Stepper("Output: \(outputTokens) Tokens", value: $outputTokens, in: 256...65536, step: 256)
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
            }.scrollContentBackground(.hidden).background { PaperSurface().ignoresSafeArea() }
            .navigationTitle("Neue Aufgabe")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Schließen") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) { Button("Entwurf speichern", action: save).disabled(saving || selectedPage == nil || prompt.isEmpty || model.isEmpty) }
            }
            .onChange(of: perRunCents) { _, value in monthlyCents = max(monthlyCents, value) }
            .onChange(of: provider) { _, value in model = value == .applePCC ? "Apple Private Cloud Compute" : "" }
            .interactiveDismissDisabled(saving)
        }
    }
    private func save() {
        guard !saving, let selectedPage else { return }; saving = true
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date), zone = TimeZone.current.identifier
        let rule: ScheduleRule
        switch recurrence {
        case .once: rule = .oneShot(date)
        case .daily: rule = .daily(timeZone: zone, hour: parts.hour ?? 0, minute: parts.minute ?? 0)
        case .weekly: rule = .weekly(timeZone: zone, hour: parts.hour ?? 0, minute: parts.minute ?? 0, weekdays: weekdays)
        case .monthly: rule = .monthly(timeZone: zone, hour: parts.hour ?? 0, minute: parts.minute ?? 0, day: monthDay)
        }
        Task {
            defer { saving = false }
            do {
                try await session.create(pageID: selectedPage, prompt: prompt, provider: provider, model: model, rule: rule, action: action,
                    budget: BudgetPolicy(currency: "USD", perRunMicros: Int64(perRunCents) * 10000, monthlyMicros: Int64(monthlyCents) * 10000, inputTokens: inputTokens, outputTokens: outputTokens),
                    end: endEnabled ? end : nil, count: limitCount ? count : nil)
                dismiss()
            } catch { self.error = "Die Aufgabe konnte nicht gespeichert werden. Prüfe Seite, Termin und Grenzen." }
        }
    }
}

private func localProviderTitle(_ id: AIProviderID) -> String {
    switch id { case .openAIKey: "OpenAI · API-Schlüssel"; case .anthropicKey: "Anthropic · API-Schlüssel"; case .applePCC: "Apple Private Cloud Compute"; case .chatGPTSubscription: "ChatGPT-Abo" }
}


private struct LocalTaskProposalSelection: Identifiable {
    let id: UUID, pageID: UUID
}
private struct LocalTaskProposalSheet: View {
    let library: WritingLibrary, session: LocalScheduleSession
    let selection: LocalTaskProposalSelection
    @State private var review: LocalScheduledProposalReview?
    @State private var loading = true
    @State private var saving = false
    @State private var error: LocalizedStringResource?
    @Environment(\.dismiss) private var dismiss
    private var pageRevision: UUID? { library.currentPage(selection.pageID)?.revision }
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    Text(library.currentPage(selection.pageID)?.title ?? "Seite nicht verfügbar").font(.title2.bold())
                    if loading { ProgressView("Vorschlag wird geprüft") }
                    if let error {
                        Label { Text(error) } icon: { Image(systemName: "exclamationmark.triangle") }
                            .foregroundStyle(.secondary)
                    }
                    if let review {
                        if let receipt = review.receipt {
                            Label("Bereits übernommen", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                            Text(receipt.acceptedAt, format: .dateTime.day().month().year().hour().minute())
                            Text("Spätere Änderungen an deiner Seite bleiben erhalten.").foregroundStyle(.secondary)
                        } else {
                            Text("Nur die gezeigten Blöcke werden ersetzt. Die bisherige Fassung bleibt im Versionsverlauf erhalten.").font(.callout).foregroundStyle(.secondary)
                            ForEach(review.changes) { change in LocalTaskProposalChange(change: change) }
                        }
                    }
                }.padding(20).frame(maxWidth: 900, alignment: .leading).frame(maxWidth: .infinity)
            }.background { PaperSurface().ignoresSafeArea() }
            .navigationTitle("Vorschlag prüfen").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Schließen") { dismiss() }.disabled(saving) } }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 10) {
                    if review?.receipt == nil {
                        Button { accept() } label: {
                            if saving { ProgressView("Übernahme wird gespeichert") }
                            else { Label("Änderungen übernehmen", systemImage: "checkmark") }
                        }.buttonStyle(.borderedProminent).disabled(loading || saving || error != nil || review == nil || pageRevision != review?.baseRevision)
                    }
                    Button("Neu prüfen") { Task { await refresh() } }.disabled(saving || loading)
                }.frame(maxWidth: .infinity).padding().background(.regularMaterial)
            }
            .interactiveDismissDisabled(saving)
            .task { await refresh() }
            .onChange(of: pageRevision) { _, _ in if !saving { Task { await refresh() } } }
        }
    }
    @MainActor private func refresh() async {
        loading = true; review = nil; error = nil
        do { review = try await session.review(proposalID: selection.id) }
        catch { self.error = explanation(error) }
        loading = false
    }
    @MainActor private func accept() {
        guard !saving, !loading, error == nil, let review, review.receipt == nil,
              pageRevision == review.baseRevision else { return }
        saving = true
        Task {
            do { _ = try await session.accept(proposalID: selection.id); await refresh() }
            catch { self.review = nil; self.error = explanation(error) }
            saving = false
        }
    }
    private func explanation(_ error: any Error) -> LocalizedStringResource {
        if let value = error as? SchedulingError, value == .staleProposal {
            return "Die Seite hat sich seit der Erstellung dieses Vorschlags geändert. Er wird nicht übernommen. Erstelle einen neuen Vorschlag auf Grundlage der aktuellen Fassung."
        }
        if let value = error as? LibraryError, value == .editInProgress {
            return "Die Seite wird noch bearbeitet. Beende die Bearbeitung und prüfe den Vorschlag erneut."
        }
        return "Dieser Vorschlag kann derzeit nicht sicher übernommen werden. Prüfe Seite und Bibliothek erneut. Dein Text bleibt erhalten."
    }
}
private struct LocalTaskProposalChange: View {
    let change: LocalScheduledProposalReview.Change
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Label("Original", systemImage: "doc.text").font(.headline)
                Text(change.original).font(.body.monospaced()).textSelection(.enabled)
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Label("Vorschlag", systemImage: "pencil.and.outline").font(.headline)
                Text(change.replacement).font(.body.monospaced()).textSelection(.enabled)
            }
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.background, in: RoundedRectangle(cornerRadius: 18))
    }
}


#if DEBUG
/// Isolated device-verification surface, never included in Release. It exercises
/// durable proposal recording and the real review/acceptance path without keys,
/// network requests, access-gate overrides or writes to existing libraries.
struct LocalProposalQALaunchGate: View {
    let launch: LibraryLaunchCoordinator
    @State private var presented = ProcessInfo.processInfo.arguments.contains("--scriptum-local-proposal-ui-qa") || ProcessInfo.processInfo.arguments.contains("--scriptum-local-activation-ui-qa")
    var body: some View {
        LaunchLibraryAccess(launch: launch).fullScreenCover(isPresented: $presented) {
            LocalProposalQAHost().interactiveDismissDisabled()
        }
    }
}
struct LocalProposalQAHost: View {
    @State private var library: WritingLibrary?
    @State private var error: String?
    var body: some View {
        VStack {
            if let library {
                if ProcessInfo.processInfo.arguments.contains("--scriptum-local-activation-ui-qa") {
                    LocalTasksSheet(library: library, activationExecutor: { id in
                        guard let session = library.scheduleSession, let task = session.state.tasks[id] else { throw SchedulingError.denied }
                        if task.prompt == "QA – fehlender Zugang" { throw AIError.missingCredential }
                        return LocalProposalQAExecutor(bindingID: task.providerBindingID)
                    })
                } else { LocalTasksSheet(library: library) }
            }
            else if let error { Text(error).textSelection(.enabled) }
            else { ProgressView("Isolierte Prüfdaten werden vorbereitet") }
        }.task {
            guard library == nil, error == nil else { return }
            do {
                library = try await (ProcessInfo.processInfo.arguments.contains("--scriptum-local-activation-ui-qa") ? LocalProposalQAFixture.makeActivation() : LocalProposalQAFixture.make())
            }
            catch { self.error = "Prüfdaten konnten nicht vorbereitet werden: " + error.localizedDescription }
        }
    }
}
@MainActor private enum LocalProposalQAFixture {
    static func makeActivation() async throws -> WritingLibrary {
        let token = UUID().uuidString, root = FileManager.default.temporaryDirectory.appendingPathComponent("ScriptumActivationUIQA-" + UUID().uuidString)
        let documents = root.appendingPathComponent("Documents"), store = try LibraryStore(directory: documents.appendingPathComponent("Skriptum"))
        let space = try store.createSpace(title: "Isolierte Aktivierungsprüfung")
        let page = try store.createPage(spaceID: space.id, title: "QA – Aktivierung ohne Inferenz", markdown: "Kontrollierter Text, der nie an einen Anbieter gesendet wird.")
        guard let preferences = UserDefaults(suiteName: "Scriptum.ActivationUIQA." + token) else { throw LocalScheduleSessionError.unavailable }
        let library = try WritingLibrary(store: store, documentRoot: documents, supportRoot: root.appendingPathComponent("Support"), preferences: preferences)
        let session = LocalScheduleSession(library: library); await session.load()
        for prompt in ["QA – Freigabe ohne Inferenz", "QA – fehlender Zugang"] {
            try await session.create(pageID: page.id, prompt: prompt, provider: .openAIKey, model: "QA controlled result",
                rule: .oneShot(Date().addingTimeInterval(3600)), action: .summary,
                budget: BudgetPolicy(currency: "USD", perRunMicros: 0, monthlyMicros: 0, inputTokens: 32000, outputTokens: 2048), end: nil, count: 1)
        }
        library.scheduleSession = session; return library
    }
    static func make() async throws -> WritingLibrary {
        let token = UUID().uuidString
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ScriptumProposalUIQA-" + token)
        let documents = root.appendingPathComponent("Documents")
        let store = try LibraryStore(directory: documents.appendingPathComponent("Skriptum"))
        let space = try store.createSpace(title: "Isolierte UI-Prüfung")
        let valid = try store.createPage(spaceID: space.id, title: "QA – passender Vorschlag", markdown: "Original der UI-Prüfung: e\u{301} und 🦊.")
        let stale = try store.createPage(spaceID: space.id, title: "QA – veralteter Vorschlag", markdown: "Original der später geänderten Seite.")
        guard let preferences = UserDefaults(suiteName: "Scriptum.ProposalUIQA." + token) else { throw LocalScheduleSessionError.unavailable }
        let library = try WritingLibrary(store: store, documentRoot: documents, supportRoot: root.appendingPathComponent("Support"), preferences: preferences)
        let session = LocalScheduleSession(library: library); await session.load()
        let now = Date().addingTimeInterval(60)
        for page in [valid, stale] {
            try await session.create(pageID: page.id, prompt: "UI-Prüfung – kontrollierter Testvorschlag", provider: .openAIKey, model: "QA controlled result",
                rule: .oneShot(now), action: .proposal,
                budget: BudgetPolicy(currency: "USD", perRunMicros: 0, monthlyMicros: 0, inputTokens: 32000, outputTokens: 2048), end: nil, count: 1)
        }
        guard let folder = try FileManager.default.contentsOfDirectory(at: library.localSchedulingDirectory(), includingPropertiesForKeys: nil).first else { throw LocalScheduleSessionError.unavailable }
        let queue = try SchedulingStore(persistence: FileSchedulingPersistence(url: folder.appendingPathComponent("tasks-v1.json")))
        guard let task = session.state.tasks.values.first else { throw LocalScheduleSessionError.unavailable }
        let authority = try LocalScheduleAuthority(library: library, ownerID: task.scope.accountID, providerBindingID: task.providerBindingID, accountBudgets: ["USD": 0])
        for value in session.state.tasks.values {
            let state = await queue.snapshot()
            try await queue.activate(taskID: value.id, grant: authority.capture(value, now: now).grant, now: now, expectedVersion: state.version)
        }
        try await LocalScheduleDispatcher(store: queue, authority: authority,
            executor: LocalProposalQAExecutor(bindingID: task.providerBindingID), clock: { now }).runDue(mode: .foreground)
        try store.renamePage(stale.id, title: "QA – Seite inzwischen geändert")
        library.reload()
        let loaded = LocalScheduleSession(library: library); await loaded.load(); library.scheduleSession = loaded
        return library
    }
}
private struct LocalProposalQAExecutor: LocalScheduledExecutor {
    let bindingID: UUID
    let providerID = AIProviderID.openAIKey.rawValue, modelID = "QA controlled result", pricingVersion = "qa-zero-cost"
    func preflight(task: ScheduledTask, capture: LocalScheduledCapture, mode: LocalScheduledMode, now: Date) async throws -> BudgetQuote {
        BudgetQuote(currency: "USD", maximumMicros: 0, inputTokens: 1024, outputTokens: 2048, version: pricingVersion, expiresAt: now.addingTimeInterval(60))
    }
    func execute(task: ScheduledTask, capture: LocalScheduledCapture, requestReference: String) async throws -> LocalScheduledResult {
        guard let block = capture.page.blocks.first else { throw SchedulingError.denied }
        return LocalScheduledResult(output: .proposal([block.id: "Übernommener UI-Testvorschlag: e\u{301} und 🦊."]), providerID: providerID, modelID: modelID, confirmedCostMicros: 0)
    }
}
#endif


private struct LocalTaskActivationSelection: Identifiable { let id: UUID }
private struct LocalTaskActivationSheet: View {
    let library: WritingLibrary, session: LocalScheduleSession
    let taskID: UUID
    let executorFactory: (@MainActor (UUID) async throws -> any LocalScheduledExecutor)?
    @State private var review: LocalScheduleActivationReview?
    @State private var checking = true
    @State private var saving = false
    @State private var message: String?
    @State private var activated = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Diese Freigabe speichert die Planung. Sie startet jetzt keine KI-Anfrage.").font(.callout).foregroundStyle(.secondary)
                    if checking { ProgressView("Zugang und Preise werden geprüft") }
                    if activated { Label("Planung aktiviert", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                    if let message { Text(message).foregroundStyle(.secondary).textSelection(.enabled) }
                }
                if let review { LocalTaskActivationDetails(review: review) }
            }.scrollContentBackground(.hidden).background { PaperSurface().ignoresSafeArea() }
            .navigationTitle("Aufgabe aktivieren").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Schließen") { dismiss() }.disabled(saving) } }
            .safeAreaInset(edge: .bottom) {
                if !activated {
                    LocalTaskActivationFooter(expiresAt: review?.expiresAt, busy: checking || saving,
                        activate: activate, recheck: { Task { await prepare() } })
                }
            }
            .interactiveDismissDisabled(saving)
            .task { await prepare() }
        }
    }
    @MainActor private func prepare() async {
        checking = true; review = nil; message = nil
        do {
            let executor: any LocalScheduledExecutor
            if let executorFactory { executor = try await executorFactory(taskID) }
            else { executor = try await session.nativeExecutor(taskID: taskID) }
            let ceiling = try await session.activationAccountMonthly(taskID: taskID)
            review = try await session.prepareActivation(taskID: taskID, executor: executor,
                accountMonthlyMicros: ceiling, mode: .foreground)
        } catch { message = explanation(error) }
        checking = false
    }
    @MainActor private func activate() {
        guard !checking, !saving, let review, review.expiresAt > Date() else { return }
        saving = true
        Task {
            do { try await session.activate(reviewID: review.id); activated = true; self.review = nil }
            catch { self.review = nil; message = explanation(error) }
            saving = false
        }
    }
    private func explanation(_ error: any Error) -> String {
        if let error = error as? AIError { return error.localizedDescription }
        if let error = error as? SchedulingError, error == .budgetDenied {
            return "Preise oder Budgetgrenzen konnten nicht sicher bestätigt werden. Prüfe Modell, Zugriff und Budgets erneut. Der Entwurf bleibt erhalten."
        }
        return "Die Planung konnte nicht aktiviert werden. Seite oder Freigabe haben sich möglicherweise geändert. Prüfe sie erneut; dein Text bleibt erhalten."
    }
}
private struct LocalTaskActivationDetails: View {
    let review: LocalScheduleActivationReview
    var body: some View {
        Section("Planung") {
            LocalTaskActivationValue(title: "Seite", value: review.pageTitle)
            LocalTaskActivationValue(title: "KI-Zugang", value: localProviderTitle(review.provider))
            LocalTaskActivationValue(title: "Modell", value: review.model)
            VStack(alignment: .leading, spacing: 5) {
                Text("Nächster Termin").font(.caption).foregroundStyle(.secondary)
                Text(review.nextOccurrence, format: .dateTime.day().month().year().hour().minute())
            }
            LocalTaskActivationValue(title: "Auftrag", value: review.prompt)
            Text(review.action == .summary ? "Ergebnis: Zusammenfassung" : "Ergebnis: Änderungsvorschlag")
            Text("Freigegeben für die geöffnete App. Eine genaue Ausführung bei geschlossener App ist nicht zugesichert.").font(.callout).foregroundStyle(.secondary)
        }
        Section("Budgets · \(review.budget.currency) netto") {
            LocalTaskActivationMoney(title: "Berechnete Preisobergrenze pro Lauf", micros: review.quote.maximumMicros, currency: review.budget.currency)
            LocalTaskActivationMoney(title: "Höchstbetrag pro Lauf", micros: review.budget.perRunMicros, currency: review.budget.currency)
            LocalTaskActivationMoney(title: "Monatsgrenze dieser Aufgabe", micros: review.budget.monthlyMicros, currency: review.budget.currency)
            LocalTaskActivationMoney(title: "Gemeinsame Monatsgrenze auf diesem Gerät", micros: review.accountMonthlyMicros, currency: review.budget.currency)
            Text("Die gemeinsame Grenze gilt über deine eigenen Bibliotheken hinweg, je UTC-Monat. Reservierungen bleiben bei unklarem Ausgang erhalten.").font(.caption).foregroundStyle(.secondary)
            Text("Berechnung unter den abgerufenen Standard-Tokenpreisen. Die Anbieterabrechnung erfolgt separat; Steuern und andere Leistungen sind nicht enthalten.").font(.caption).foregroundStyle(.secondary)
        }
        Section("Textumfang") {
            if review.wholePage { Text("Ganze Seite, auch nach späteren Änderungen") }
            else { Text("Freigegebene Blöcke: \(review.readableBlockCount)") }
            Text("Input-Obergrenze: \(review.quote.inputTokens) · Output-Limit: \(review.quote.outputTokens)")
            Text("Die Inputzahl ist eine konservative Berechnung, keine gemessene Anbieterzählung.").font(.caption).foregroundStyle(.secondary)
            Text("Änderungsvorschläge ersetzen deinen Text erst nach gesonderter Übernahme.").font(.caption).foregroundStyle(.secondary)
        }
    }
}
private struct LocalTaskActivationValue: View {
    let title: LocalizedStringResource, value: String
    var body: some View { VStack(alignment: .leading, spacing: 5) { Text(title).font(.caption).foregroundStyle(.secondary); Text(value).textSelection(.enabled) } }
}
private struct LocalTaskActivationMoney: View {
    let title: LocalizedStringResource, micros: Int64
    let currency: String
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(Decimal(micros) / 1_000_000, format: .currency(code: currency).precision(.fractionLength(2...6))).font(.headline)
        }
    }
}
private struct LocalTaskActivationFooter: View {
    let expiresAt: Date?, busy: Bool
    let activate: () -> Void, recheck: () -> Void
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(spacing: 10) {
                if let expiresAt, expiresAt <= context.date { Text("Freigabe abgelaufen. Bitte neu prüfen.").font(.caption).foregroundStyle(.secondary) }
                Button("Aufgabe aktivieren", systemImage: "checkmark") { activate() }
                    .buttonStyle(.borderedProminent).disabled(busy || expiresAt == nil || (expiresAt ?? .distantPast) <= context.date)
                Button("Neu prüfen") { recheck() }.disabled(busy)
            }.frame(maxWidth: .infinity).padding().background(.regularMaterial)
        }
    }
}
