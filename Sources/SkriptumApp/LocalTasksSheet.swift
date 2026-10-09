import SwiftUI

struct LocalTasksSheet: View {
    let library: WritingLibrary
    var pageID: UUID?
    @State private var session: LocalScheduleSession
    @State private var creating = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss
    init(library: WritingLibrary, pageID: UUID? = nil) {
        self.library = library; self.pageID = pageID
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
                            if task.lifecycle == .active { Button("Pausieren") { change { try await session.pause(task) } } }
                            if task.lifecycle != .cancelled { Button("Abbrechen", role: .destructive) { change { try await session.cancel(task) } } }
                        }.padding(.vertical, 6)
                    }
                }
                LocalTaskResultsSection(state: session.state, library: library, pageID: pageID)
                if let error = error ?? session.error { Section { Text(error).foregroundStyle(.red).textSelection(.enabled) } }
            }.scrollContentBackground(.hidden).background { PaperSurface().ignoresSafeArea() }
            .navigationTitle("Geplante Aufgaben")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Schließen") { dismiss() } } }
            .task { await session.load() }
            .sheet(isPresented: $creating) { LocalTaskCreationSheet(library: library, pageID: pageID, session: session) }
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
    var body: some View {
        Section("Ergebnisse") {
            let summaries = state.summaries.values.filter { pageID == nil || $0.pageID == pageID }.sorted { $0.createdAt > $1.createdAt }
            if summaries.isEmpty && state.proposals.isEmpty { Text("Noch keine Ergebnisse.").foregroundStyle(.secondary) }
            ForEach(summaries) { summary in
                DisclosureGroup(library.currentPage(summary.pageID)?.title ?? "Zusammenfassung") {
                    Text(summary.text).textSelection(.enabled)
                    Text(summary.providerID + " · " + summary.modelID).font(.caption).foregroundStyle(.secondary)
                    ShareLink("Ergebnis sichern", item: summary.text)
                }
            }
            ForEach(state.proposals.values.filter { pageID == nil || $0.pageID == pageID }.sorted { $0.id.uuidString < $1.id.uuidString }) { proposal in
                DisclosureGroup(library.currentPage(proposal.pageID)?.title ?? "Vorschlag") {
                    ForEach(proposal.replacementBlocks.keys.sorted { $0.uuidString < $1.uuidString }, id: \.self) { id in Text(proposal.replacementBlocks[id] ?? "").textSelection(.enabled) }
                    Text("Dieser Vorschlag verändert deinen Text erst nach einer gesonderten Übernahmeprüfung.").font(.caption).foregroundStyle(.secondary)
                }
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
