import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct LocalTasksSheet: View {
    let library: WritingLibrary
    var pageID: UUID?
    @State private var session: LocalScheduleSession
    @State private var creating = false
    @State private var showingBudget = false
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
            LocalTaskList {
                Section {
                    Text("Aufgaben bleiben auf diesem Gerät. Eine gespeicherte Planung wird erst nach Prüfung von KI-Zugang, Ausführungsmodus und Budget aktiviert.").font(.callout).foregroundStyle(.secondary)
                    Button { creating = true } label: {
                        Label("Neue Aufgabe", systemImage: "plus")
                            .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }.localTaskRowButtonStyle().disabled(library.pages.filter { !$0.trashed }.isEmpty || session.error != nil)
                    Button { showingBudget = true } label: {
                        Label("Gemeinsames Monatsbudget", systemImage: "banknote")
                            .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }.localTaskRowButtonStyle().disabled(session.error != nil)
                }
                Section("Aufgaben") {
                    if tasks.isEmpty { Text("Noch keine Aufgaben gespeichert.").foregroundStyle(.secondary) }
                    let runsByTask = Dictionary(grouping: session.state.runs.values, by: { $0.occurrence.taskID })
                    ForEach(tasks) { task in
                        let progress = try? ScheduledTaskProgress(task: task, runs: runsByTask[task.id] ?? [])
                        VStack(alignment: .leading, spacing: 8) {
                            Text(library.currentPage(task.pageID)?.title ?? "Seite nicht verfügbar").font(.headline)
                            Text(task.prompt).lineLimit(3)
                            if let progress {
                                Text(status(progress.phase)).font(.caption).foregroundStyle(.secondary)
                                if let run = progress.latestRunState {
                                    Text(runStatus(run)).font(.caption).foregroundStyle(.secondary)
                                }
                            } else {
                                Text("Aufgabenstatus nicht verfügbar").font(.caption).foregroundStyle(.secondary)
                            }
#if canImport(UIKit)
                            Text(task.executionPolicy == .backgroundAllowed ? "Vordergrund und iOS-Hintergrundzeiten" : "Nur geöffnete App").font(.caption).foregroundStyle(.secondary)
#else
                            Text("Nur geöffnete App im Vordergrund").font(.caption).foregroundStyle(.secondary)
#endif
                            if let message = session.executionMessages[task.providerBindingID] { Text(message).font(.caption).foregroundStyle(.secondary) }
                            if let date = progress?.nextOccurrence {
                                Text("Nächster Termin: \(date, format: .dateTime.day().month().year().hour().minute())").font(.caption)
                            }
                            if let binding = try? session.binding(task) { Text(localProviderTitle(binding.provider) + " · " + binding.model).font(.caption).foregroundStyle(.secondary) }
                            if task.lifecycle == .paused && task.contentPermissionVersion == nil {
                                Text("Für neue Übermittlungen muss die Inhaltsfreigabe erneut bestätigt werden.").font(.caption).foregroundStyle(.secondary)
                            }
                            if [.draft, .awaitingActivation, .paused].contains(task.lifecycle) { Button(task.lifecycle == .paused ? "Fortsetzen prüfen" : "Aktivierung prüfen") { selectedActivation = .init(id: task.id) } }
                            if progress?.canPause == true { Button("Pausieren") { change { try await session.pause(task) } } }
                            if progress?.canCancel == true { Button("Abbrechen", role: .destructive) { change { try await session.cancel(task) } } }
                        }
                        .localTaskLifecycleButtonStyle()
                        .accessibilityElement(children: .contain)
                        .padding(.vertical, 6)
                    }
                }
                LocalTaskResultsSection(state: session.state, library: library, pageID: pageID) { selectedProposal = $0 }
                if let error = error ?? session.error { Section { Text(error).foregroundStyle(.red).textSelection(.enabled) } }
                if let error = session.runtimeError { Section { Text(error).foregroundStyle(.secondary).textSelection(.enabled) } }
#if canImport(UIKit)
                if let error = ScriptumBackgroundTaskCoordinator.shared.error { Section { Text(error).foregroundStyle(.secondary).textSelection(.enabled) } }
#endif
            }.localTaskFormStyle().scrollContentBackground(.hidden).background { PaperSurface().ignoresSafeArea() }
            .navigationTitle("Geplante Aufgaben")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Schließen") { dismiss() } } }
            .task { await session.load() }
            .sheet(isPresented: $creating) { LocalTaskCreationSheet(library: library, pageID: pageID, session: session).localTaskSheetSize() }
            .sheet(isPresented: $showingBudget) { LocalOwnerBudgetSheet(session: session).localTaskSheetSize() }
            .sheet(item: $selectedActivation) { selected in
                LocalTaskActivationSheet(library: library, session: session, taskID: selected.id, executorFactory: activationExecutor).localTaskSheetSize()
            }
            .sheet(item: $selectedProposal) { selected in
                LocalTaskProposalSheet(library: library, session: session, selection: selected).localTaskSheetSize()
            }
        }
    }
    private func change(_ operation: @escaping () async throws -> Void) {
        Task {
            do {
                try await operation(); error = nil
#if canImport(UIKit)
                await ScriptumBackgroundTaskCoordinator.shared.submitNext()
#endif
            } catch { self.error = "Die Änderung konnte nicht gespeichert werden. Die Aufgabe bleibt erhalten." }
        }
    }
    private func status(_ value: ScheduledTaskProgress.Phase) -> LocalizedStringResource {
        switch value {
        case .draft: "Entwurf · noch nicht aktiviert"
        case .awaitingActivation: "Aktivierung ausstehend"
        case .scheduled: "Aktiv"
        case .queued: "Ausführung ausstehend"
        case .running: "Wird ausgeführt"
        case .finished: "Planung beendet"
        case .paused: "Pausiert"
        case .cancelled: "Abgebrochen"
        }
    }
    private func runStatus(_ value: RunState) -> LocalizedStringResource {
        switch value {
        case .queued: "Letzter Lauf: Ausstehend"
        case .leased, .authorized, .reserved: "Letzter Lauf: Wird vorbereitet"
        case .dispatching, .running: "Letzter Lauf: Wird ausgeführt"
        case .completed: "Letzter Lauf: Abgeschlossen"
        case .proposalReady: "Letzter Lauf: Vorschlag verfügbar"
        case .cancelled: "Letzter Lauf: Abgebrochen"
        case .denied: "Letzter Lauf: Nicht freigegeben"
        case .budgetDenied: "Letzter Lauf: Budget reicht nicht aus"
        case .failed: "Letzter Lauf: Fehlgeschlagen"
        case .executionUncertain: "Letzter Lauf: Ergebnis ungewiss"
        }
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
                    Text((AIProviderID(rawValue: summary.providerID).map(localProviderTitle) ?? "Anbieter nicht verfügbar") + " · " + summary.modelID).font(.caption).foregroundStyle(.secondary)
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
    @State private var backgroundAllowed = false
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
#if canImport(UIKit)
                    if provider == .openAIKey || provider == .anthropicKey {
                        Toggle("Auch im Hintergrund versuchen", isOn: $backgroundAllowed)
                        Text("iOS bestimmt Zeitpunkt und Laufzeit. Bei gesperrtem Gerät können Schlüssel oder Dateien unzugänglich sein; die Aufgabe bleibt dann offen.").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("Dieser Zugang wird für geplante Aufgaben nur in der geöffneten App geprüft.").font(.caption).foregroundStyle(.secondary)
                    }
#else
                    Text("Auf dem Mac werden geplante Aufgaben nur bei geöffneter App im Vordergrund ausgeführt. Verpasste Termine werden beim nächsten Öffnen geprüft.").font(.caption).foregroundStyle(.secondary)
#endif
                    Text("Zugang und Preisfreigabe werden vor der Aktivierung geprüft. Ein Entwurf löst keinen KI-Aufruf aus.").font(.caption).foregroundStyle(.secondary)
                    if provider == .applePCC {
                        Text("Bei berechtigtem PCC-Zugriff berechnet Apple keine Cloud-API-Gebühren. Zugang, Textfreigabe und Tokenlimits werden vor der Ausführung geprüft.")
                            .font(.caption).foregroundStyle(.secondary)
                        Link("PCC-Bedingungen von Apple", destination: ScheduledPCCAPIPricePolicy.source).font(.caption)
                    } else if provider == .chatGPTSubscription {
                        Text("Dieser ChatGPT-Zugang unterstützt derzeit kein verbindliches Ausgabetokenlimit für geplante Aufgaben. Du kannst einen Entwurf speichern; die automatische Aktivierung ist noch nicht verfügbar.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section("Grenzen") {
                    Stepper("Pro Lauf: \(perRunCents) USD-Cent", value: $perRunCents, in: 0...10000)
                    Stepper("Pro Monat: \(monthlyCents) USD-Cent", value: $monthlyCents, in: perRunCents...100000)
                    Stepper("Input: \(inputTokens) Tokens", value: $inputTokens, in: 1024...200000, step: 1024)
                    Stepper("Output: \(outputTokens) Tokens", value: $outputTokens, in: 256...65536, step: 256)
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
            }.localTaskFormStyle().scrollContentBackground(.hidden).background { PaperSurface().ignoresSafeArea() }
            .navigationTitle("Neue Aufgabe")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Schließen") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) { Button("Entwurf speichern", action: save).disabled(saving || selectedPage == nil || prompt.isEmpty || model.isEmpty) }
            }
            .onChange(of: perRunCents) { _, value in monthlyCents = max(monthlyCents, value) }
            .onChange(of: provider) { _, value in model = value == .applePCC ? "Apple Private Cloud Compute" : ""; backgroundAllowed = false }
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
                    end: endEnabled ? end : nil, count: limitCount ? count : nil, executionPolicy: backgroundAllowed && (provider == .openAIKey || provider == .anthropicKey) ? .backgroundAllowed : .foregroundOnly)
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
            .navigationTitle("Vorschlag prüfen").localTaskNavigationTitle()
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Schließen") { dismiss() }.disabled(saving) } }
            .safeAreaBar(edge: .bottom) {
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


#if DEBUG && canImport(UIKit)
/// Isolated device-verification surface, never included in Release. It exercises
/// durable proposal recording and the real review/acceptance path without keys,
/// network requests, access-gate overrides or writes to existing libraries.
struct LocalProposalQALaunchGate: View {
    @State private var presented = ProcessInfo.processInfo.arguments.contains("--scriptum-markdown-package-ui-qa") || ProcessInfo.processInfo.arguments.contains("--scriptum-image-preview-ui-qa") || ProcessInfo.processInfo.arguments.contains("--scriptum-owner-foreground-ui-qa") || ProcessInfo.processInfo.arguments.contains("--scriptum-shared-foreground-ui-qa") || ProcessInfo.processInfo.arguments.contains("--scriptum-native-grammar-coverage-ui-qa") || ProcessInfo.processInfo.arguments.contains("--scriptum-composite-writing-ui-qa") || ProcessInfo.processInfo.arguments.contains("--scriptum-conflict-review-ui-qa") || ProcessInfo.processInfo.arguments.contains("--scriptum-local-proposal-ui-qa") || ProcessInfo.processInfo.arguments.contains("--scriptum-local-activation-ui-qa") || ProcessInfo.processInfo.arguments.contains("--scriptum-local-foreground-ui-qa")
    var body: some View {
        LaunchLibraryAccess().fullScreenCover(isPresented: $presented) {
            Group {
                if ProcessInfo.processInfo.arguments.contains("--scriptum-markdown-package-ui-qa") { CompositeWritingQAHost() }
                else if ProcessInfo.processInfo.arguments.contains("--scriptum-image-preview-ui-qa") { CompositeWritingQAHost() }
                else if ProcessInfo.processInfo.arguments.contains("--scriptum-owner-foreground-ui-qa") { CompositeWritingQAHost() }
                else if ProcessInfo.processInfo.arguments.contains("--scriptum-shared-foreground-ui-qa") { ICloudSharedForegroundQAHost() }
                else if ProcessInfo.processInfo.arguments.contains("--scriptum-native-grammar-coverage-ui-qa") { NativeGrammarCoverageQAHost() }
                else if ProcessInfo.processInfo.arguments.contains("--scriptum-composite-writing-ui-qa") { CompositeWritingQAHost() }
                else if ProcessInfo.processInfo.arguments.contains("--scriptum-conflict-review-ui-qa") { ConflictReviewQAHost() }
                else { LocalProposalQAHost() }
            }.interactiveDismissDisabled()
        }
    }
}
struct LocalProposalQAHost: View {
    @State private var library: WritingLibrary?
    @State private var error: String?
    var body: some View {
        VStack {
            if let library {
                if ProcessInfo.processInfo.arguments.contains("--scriptum-local-foreground-ui-qa") {
                    LocalTasksSheet(library: library).modifier(LocalScheduleForegroundRunner(library: library, executorFactory: { id in
                        guard let session = library.scheduleSession, let task = session.state.tasks[id] else { throw SchedulingError.denied }
                        if task.prompt == "QA – fehlender Zugang" { throw AIError.missingCredential }
                        let binding = try session.binding(task)
                        return LocalForegroundQAExecutor(bindingID: binding.id, modelID: binding.model)
                    }))
                } else if ProcessInfo.processInfo.arguments.contains("--scriptum-local-activation-ui-qa") {
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
                if ProcessInfo.processInfo.arguments.contains("--scriptum-local-foreground-ui-qa") { library = try await LocalProposalQAFixture.makeForeground() }
                else { library = try await (ProcessInfo.processInfo.arguments.contains("--scriptum-local-activation-ui-qa") ? LocalProposalQAFixture.makeActivation() : LocalProposalQAFixture.make()) }
            }
            catch { self.error = "Prüfdaten konnten nicht vorbereitet werden: " + error.localizedDescription }
        }
    }
}
@MainActor private enum LocalProposalQAFixture {
    static func makeForeground() async throws -> WritingLibrary {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ScriptumForegroundUIQA-" + UUID().uuidString)
        let documents = root.appendingPathComponent("Documents"), store = try LibraryStore(directory: documents.appendingPathComponent("Skriptum"))
        let space = try store.createSpace(title: "Isolierte Vordergrundprüfung")
        let page = try store.createPage(spaceID: space.id, title: "QA – fällige Aufgaben", markdown: "Original der automatischen Prüfung: e\u{301} und 🦊.")
        guard let preferences = UserDefaults(suiteName: "Scriptum.ForegroundUIQA." + UUID().uuidString) else { throw LocalScheduleSessionError.unavailable }
        let library = try WritingLibrary(store: store, documentRoot: documents, supportRoot: root.appendingPathComponent("Support"), preferences: preferences)
        let session = LocalScheduleSession(library: library); await session.load()
        let date = Date().addingTimeInterval(5)
        for (prompt, action, model) in [("QA – automatische Zusammenfassung", ScheduledAction.summary, "QA controlled result"), ("QA – automatischer Vorschlag", ScheduledAction.proposal, "QA controlled result"), ("QA – fehlender Zugang", ScheduledAction.summary, "QA missing access")] {
            try await session.create(pageID: page.id, prompt: prompt, provider: .openAIKey, model: model,
                rule: .oneShot(date), action: action, budget: BudgetPolicy(currency: "USD", perRunMicros: 0, monthlyMicros: 0, inputTokens: 32000, outputTokens: 2048), end: nil, count: 1)
            guard let task = session.state.tasks.values.first(where: { $0.prompt == prompt }) else { throw SchedulingError.denied }
            let executor = LocalForegroundQAExecutor(bindingID: task.providerBindingID, modelID: model)
            let review = try await session.prepareActivation(taskID: task.id, executor: executor, accountMonthlyMicros: 0, mode: .foreground)
            try await session.activate(reviewID: review.id, contentPermissionID: review.id)
        }
        library.scheduleSession = session; return library
    }
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
        try await session.create(pageID: page.id, prompt: "QA – ausdrückliche Hintergrundfreigabe", provider: .openAIKey, model: "QA controlled result",
            rule: .oneShot(Date().addingTimeInterval(3600)), action: .summary,
            budget: BudgetPolicy(currency: "USD", perRunMicros: 0, monthlyMicros: 0, inputTokens: 32000, outputTokens: 2048), end: nil, count: 1, executionPolicy: .backgroundAllowed)
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
            try await queue.activate(taskID: value.id, contentPermissionVersion: ScheduledTask.currentContentPermissionVersion,
                grant: authority.capture(value, now: now).grant, now: now, expectedVersion: state.version)
        }
        try await LocalScheduleDispatcher(store: queue, authority: authority,
            executor: LocalProposalQAExecutor(bindingID: task.providerBindingID), clock: { now }).runDue(mode: .foreground)
        try store.renamePage(stale.id, title: "QA – Seite inzwischen geändert")
        library.reload()
        let loaded = LocalScheduleSession(library: library); await loaded.load(); library.scheduleSession = loaded
        return library
    }
}
private struct LocalForegroundQAExecutor: LocalScheduledExecutor {
    let bindingID: UUID, modelID: String
    let providerID = AIProviderID.openAIKey.rawValue, pricingVersion = "foreground-qa-zero"
    func preflight(task: ScheduledTask, capture: LocalScheduledCapture, mode: LocalScheduledMode, now: Date) async throws -> BudgetQuote {
        BudgetQuote(currency: "USD", maximumMicros: 0, inputTokens: 1024, outputTokens: 2048, version: pricingVersion, expiresAt: now.addingTimeInterval(60))
    }
    func execute(task: ScheduledTask, capture: LocalScheduledCapture, requestReference: String) async throws -> LocalScheduledResult {
        let output: LocalScheduledOutput
        if task.action == .summary { output = .summary("Automatisch gespeicherte QA-Zusammenfassung: e\u{301} und 🦊.") }
        else {
            guard let block = capture.page.blocks.first else { throw SchedulingError.denied }
            output = .proposal([block.id: "Kontrollierter automatischer Vorschlag: e\u{301} und 🦊."])
        }
        return LocalScheduledResult(output: output, providerID: providerID, modelID: modelID, confirmedCostMicros: 0)
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
    @State private var contentPermission = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            LocalTaskList {
                Section {
                    Text("Diese Freigabe speichert die Planung. Sie startet jetzt keine KI-Anfrage.").font(.callout).foregroundStyle(.secondary)
                    if checking { ProgressView("Zugang und Preise werden geprüft") }
                    if activated { Label("Planung aktiviert", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                    if let message { Text(message).foregroundStyle(.secondary).textSelection(.enabled) }
                }
                if let review {
                    LocalTaskActivationDetails(review: review)
                    LocalTaskContentDisclosure(review: review, permission: $contentPermission)
                }
            }.localTaskFormStyle().scrollContentBackground(.hidden).background { PaperSurface().ignoresSafeArea() }
            .navigationTitle("Aufgabe aktivieren").localTaskNavigationTitle()
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Schließen") { dismiss() }.disabled(saving) } }
            .safeAreaBar(edge: .bottom) {
                if !activated {
                    LocalTaskActivationFooter(expiresAt: review?.expiresAt, busy: checking || saving, contentPermission: contentPermission,
                        activate: activate, recheck: { Task { await prepare() } })
                }
            }
            .interactiveDismissDisabled(saving)
            .task { await prepare() }
        }
    }
    @MainActor private func prepare() async {
        checking = true; review = nil; message = nil; contentPermission = false
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
        guard !checking, !saving, contentPermission, let review, review.expiresAt > Date() else { return }
        saving = true
        Task {
            do {
                try await session.activate(reviewID: review.id, contentPermissionID: review.id); activated = true; self.review = nil
                dismiss()
#if canImport(UIKit)
                await ScriptumBackgroundTaskCoordinator.shared.submitNext()
#endif
            }
            catch { self.review = nil; message = explanation(error) }
            saving = false
        }
    }
    private func explanation(_ error: any Error) -> String {
        if error is ScheduledPricePolicyError {
            return "Für diesen KI-Zugang fehlt eine bestätigte Preisrichtlinie für geplante Aufgaben. Der Entwurf bleibt erhalten. Es wurde kein Auftrag gestartet."
        }
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
                Text("Nächster Termin (Gerätezeit)").font(.caption).foregroundStyle(.secondary)
                Text(review.nextOccurrence, format: .dateTime.day().month().year().hour().minute())
            }
            LocalTaskActivationValue(title: "Auftrag", value: review.prompt)
            LocalTaskRecurrenceDetails(review: review)
            Text(review.action == .summary ? "Ergebnis: Zusammenfassung" : "Ergebnis: Änderungsvorschlag")
            Text(review.executionPolicy == .backgroundAllowed ? "Freigegeben für die geöffnete App und von iOS gewährte Hintergrundzeiten. Zeitpunkt und Laufzeit sind nicht garantiert." : "Freigegeben für die geöffnete App. Eine genaue Ausführung bei geschlossener App ist nicht zugesichert.").font(.callout).foregroundStyle(.secondary)
        }
        Section("Budgets · \(review.budget.currency) netto") {
            if review.provider == .applePCC {
                Text("Bei berechtigtem PCC-Zugriff fallen keine Cloud-API-Gebühren an. Die unten aufgeführten Grenzen ändern weder Apples Zugangsbedingungen noch dessen Verfügbarkeit.")
                    .font(.caption).foregroundStyle(.secondary)
                Link("PCC-Bedingungen von Apple", destination: ScheduledPCCAPIPricePolicy.source).font(.caption)
            }
            LocalTaskActivationMoney(title: "Berechnete Preisobergrenze pro Lauf", micros: review.quote.maximumMicros, currency: review.budget.currency)
            LocalTaskActivationMoney(title: "Höchstbetrag pro Lauf", micros: review.budget.perRunMicros, currency: review.budget.currency)
            LocalTaskActivationMoney(title: "Monatsgrenze dieser Aufgabe", micros: review.budget.monthlyMicros, currency: review.budget.currency)
            LocalTaskActivationMoney(title: "Gemeinsame Monatsgrenze auf diesem Gerät", micros: review.accountMonthlyMicros, currency: review.budget.currency)
            Text("Die gemeinsame Grenze gilt über deine eigenen Bibliotheken hinweg, je UTC-Monat. Reservierungen bleiben bei unklarem Ausgang erhalten.").font(.caption).foregroundStyle(.secondary)
            if review.provider != .applePCC {
                Text("Berechnung unter den abgerufenen Standard-Tokenpreisen. Die Anbieterabrechnung erfolgt separat; Steuern und andere Leistungen sind nicht enthalten.").font(.caption).foregroundStyle(.secondary)
            }
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
private struct LocalTaskRecurrenceDetails: View {
    let review: LocalScheduleActivationReview
    private func clock(_ hour: Int, _ minute: Int) -> String { String(format: "%02d:%02d", hour, minute) }
    var body: some View {
        switch review.rule {
        case .oneShot: Text("Einmalige Ausführung")
        case .daily(let zone, let hour, let minute): Text("Täglich um \(clock(hour, minute)) · \(zone)")
        case .weekly(let zone, let hour, let minute, let weekdays):
            Text("Wöchentlich um \(clock(hour, minute)) · \(zone)")
            Text(weekdays.sorted().map { Calendar.current.weekdaySymbols[$0 - 1] }.formatted(.list(type: .and)))
        case .monthly(let zone, let hour, let minute, let day): Text("Monatlich am Tag \(day) um \(clock(hour, minute)) · \(zone)")
        }
        if let end = review.scheduleEndUTC {
            VStack(alignment: .leading) {
                Text("Spätester Termin (Gerätezeit)").font(.caption).foregroundStyle(.secondary)
                Text(end, format: .dateTime.day().month().year().hour().minute())
            }
        } else { Text("Kein Enddatum festgelegt").font(.caption).foregroundStyle(.secondary) }
        if let count = review.remainingOccurrences { Text("Noch höchstens \(count) geplante Termine") }
        else { Text("Keine Anzahlgrenze festgelegt").font(.caption).foregroundStyle(.secondary) }
    }
}
private struct LocalTaskContentDisclosure: View {
    let review: LocalScheduleActivationReview
    @Binding var permission: Bool
    private var recipient: String { review.provider == .chatGPTSubscription ? "OpenAI (ChatGPT)" : localProviderTitle(review.provider) }
    private var privacyURL: URL {
        switch review.provider {
        case .openAIKey, .chatGPTSubscription: URL(string: "https://openai.com/policies/privacy-policy/")!
        case .anthropicKey: URL(string: "https://www.anthropic.com/legal/privacy")!
        case .applePCC: URL(string: "https://www.apple.com/legal/privacy/data/en/intelligence-engine/")!
        }
    }
    var body: some View {
        Section("Spätere Textübermittlung") {
            Text("Empfänger: \(recipient)").font(.headline)
            Text("Bei jedem erlaubten Lauf werden der Auftrag und der freigegebene Markdown-Text mit seinen Blockkennungen an diesen Anbieter gesendet. Die Inhalte können personenbezogene Daten enthalten.")
            Text(review.wholePage ? "Die Freigabe umfasst die ganze Seite einschließlich späterer Änderungen." : "Die Freigabe umfasst die ausgewählten Blöcke einschließlich späterer Änderungen ihres Textes.")
            Text("Chatverlauf, zusätzliche Kontextseiten und Bilddateien werden nicht zusätzlich mitgesendet. Pausieren oder Abbrechen verhindert neue Aufträge; eine bereits versendete Anfrage lässt sich damit nicht zurückholen.").font(.caption).foregroundStyle(.secondary)
            Link("Datenschutz beim Anbieter", destination: privacyURL)
            Toggle("Diese späteren Übermittlungen erlauben", isOn: $permission)
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
    let contentPermission: Bool
    let activate: () -> Void, recheck: () -> Void
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(spacing: 10) {
                if let expiresAt, expiresAt <= context.date { Text("Freigabe abgelaufen. Bitte neu prüfen.").font(.caption).foregroundStyle(.secondary) }
                Button("Aufgabe aktivieren", systemImage: "checkmark") { activate() }
                    .buttonStyle(.borderedProminent).disabled(busy || !contentPermission || expiresAt == nil || (expiresAt ?? .distantPast) <= context.date)
                Button("Neu prüfen") { recheck() }.disabled(busy)
            }.frame(maxWidth: .infinity).padding().background(.regularMaterial)
        }
    }
}

/// SwiftUI cancels this task when its scene becomes inactive or its owned
/// library changes. Other windows share the same serial session via registry.
struct LocalScheduleForegroundRunner: ViewModifier {
    let library: WritingLibrary
    var executorFactory: (@MainActor (UUID) async throws -> any LocalScheduledExecutor)? = nil
    @State private var active = false
    @Environment(\.scenePhase) private var scenePhase
    private var foregroundActive: Bool {
#if canImport(UIKit)
        active
#else
        scenePhase == .active
#endif
    }
    private struct Identity: Hashable { let libraryID: UUID; let active: Bool }
    func body(content: Content) -> some View {
        content.background {
#if canImport(UIKit)
            WorkspaceSceneActivityReader(changed: { active = $0 }).frame(width: 0, height: 0)
#endif
        }
        .task(id: Identity(libraryID: library.libraryIdentity, active: foregroundActive)) {
#if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--scriptum-local-foreground-ui-qa") { print("Foreground QA runner started active=\(foregroundActive)") }
#endif
            guard foregroundActive else { return }
            let session = library.scheduleSession ?? LocalScheduleSession(library: library)
            library.scheduleSession = session
            while !Task.isCancelled {
#if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--scriptum-local-foreground-ui-qa") { print("Foreground QA checking due tasks") }
#endif
                do {
                    try await session.runNativeDue(executorFactory: executorFactory)
#if canImport(UIKit)
                    if executorFactory == nil { await ScriptumBackgroundTaskCoordinator.shared.submitNext() }
#endif
                }
                catch is CancellationError { return }
                catch { session.reportRuntimeFailure() }
                do { try await Task.sleep(for: .seconds(30)) }
                catch { return }
            }
        }
    }
}

#if canImport(UIKit)
/// Reads only the UIWindowScene actually hosting this view. The document
/// launch host can report an inactive SwiftUI phase while its window is active.
struct WorkspaceSceneActivityReader: UIViewRepresentable {
    let changed: @MainActor (Bool) -> Void
    var detached: (@MainActor () -> Void)? = nil
    final class ActivityView: UIView {
        var changed: (@MainActor (Bool) -> Void)?
        var detached: (@MainActor () -> Void)?
        private weak var scene: UIWindowScene?
        private var generation: UInt64 = 0
        private var stopped = false
        override func didMoveToWindow() {
            super.didMoveToWindow()
            NotificationCenter.default.removeObserver(self)
            scene = window?.windowScene
            guard !stopped else { return }
            if let scene {
                let center = NotificationCenter.default
                center.addObserver(self, selector: #selector(activated), name: UIScene.didActivateNotification, object: scene)
                for name in [UIScene.willDeactivateNotification, UIScene.didEnterBackgroundNotification, UIScene.didDisconnectNotification] {
                    center.addObserver(self, selector: #selector(deactivated), name: name, object: scene)
                }
            }
            publish(scene?.activationState == .foregroundActive)
        }
        @objc private func activated(_ notification: Notification) { publish(scene?.activationState == .foregroundActive) }
        @objc private func deactivated(_ notification: Notification) { publish(false) }
        private func publish(_ active: Bool) {
            generation &+= 1
            let current = generation
            // Leave the UIKit/SwiftUI update before mutating State; a later
            // detach/inactive event invalidates any queued active callback.
            Task { @MainActor [weak self] in
                guard let self, !self.stopped, self.generation == current else { return }
                self.changed?(active)
            }
        }
        func stop() {
            guard !stopped else { return }
            stopped = true; generation &+= 1
            NotificationCenter.default.removeObserver(self)
            changed = nil; scene = nil
            detached?(); detached = nil
        }
        deinit { NotificationCenter.default.removeObserver(self) }
    }
    func makeUIView(context: Context) -> ActivityView {
        let view = ActivityView()
        view.isUserInteractionEnabled = false; view.isAccessibilityElement = false
        view.changed = changed; view.detached = detached
        return view
    }
    func updateUIView(_ view: ActivityView, context: Context) { view.changed = changed; view.detached = detached }
    static func dismantleUIView(_ view: ActivityView, coordinator: ()) { view.stop() }
}
#endif

private struct LocalOwnerBudgetSheet: View {
    let session: LocalScheduleSession
    @State private var snapshot: LocalOwnerBudgetSnapshot?
    @State private var review: LocalOwnerBudgetReview?
    @State private var cents = 0
    @State private var busy = false
    @State private var message: String?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Dieser USD-Rahmen gilt für deine eigenen Bibliotheken auf diesem Gerät, je UTC-Monat. Er ersetzt weder die Grenzen einzelner Aufgaben noch eine Anbieterabrechnung.").font(.callout)
                    if let snapshot { LocalOwnerBudgetValues(snapshot: snapshot) }
                }
                Section("Neuer Rahmen") {
                    Stepper(value: $cents, in: 0...100_000) {
                        Text(Decimal(cents) / 100, format: .currency(code: "USD"))
                    }.disabled(busy)
                    Text("Eine Grenze unter den Monatsgrenzen bestehender Aufgaben sperrt deren nächste Aufnahme. Bereits reservierte oder unklare Beträge bleiben erhalten.").font(.caption).foregroundStyle(.secondary)
                    Button("Änderung prüfen", action: prepare).disabled(busy || snapshot == nil)
                }
                if let review { LocalOwnerBudgetConfirmation(review: review, busy: busy, confirm: confirm) }
                if let message { Section { Text(message).foregroundStyle(.secondary).textSelection(.enabled) } }
            }.localTaskFormStyle().scrollContentBackground(.hidden).background { PaperSurface().ignoresSafeArea() }
            .navigationTitle("Monatsbudget").localTaskNavigationTitle()
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Schließen") { dismiss() }.disabled(busy) } }
            .interactiveDismissDisabled(busy)
            .onChange(of: cents) { _, _ in review = nil }
            .task {
                busy = true; defer { busy = false }
                do {
                    await session.load()
                    let value = try await session.ownerBudget()
                    snapshot = value; cents = min(100_000, max(0, Int((value.ceiling ?? 0) / 10_000)))
                } catch { message = explanation(error) }
            }
        }
    }
    private func prepare() {
        guard !busy else { return }; busy = true; message = nil; review = nil
        let amount = Int64(cents) * 10_000
        Task {
            defer { busy = false }
            do {
                let value = try await session.prepareBudgetChange(currency: "USD", monthlyMicros: amount)
                snapshot = value.previous; review = value
            }
            catch { message = explanation(error) }
        }
    }
    private func confirm() {
        guard !busy, let review else { return }; busy = true
        Task {
            defer { busy = false }
            do {
                try await session.confirmBudgetChange(id: review.id)
                self.review = nil; snapshot = try await session.ownerBudget()
                message = "Monatsrahmen gespeichert. Bestehende Reservierungen bleiben erhalten."
            } catch { self.review = nil; message = explanation(error) }
        }
    }
    private func explanation(_ error: any Error) -> String {
        if error as? SchedulingError == .budgetDenied { return "Der Rahmen darf nicht unter bereits bestätigten oder reservierten Beträgen dieses UTC-Monats liegen." }
        return "Die Budgetänderung konnte nicht sicher bestätigt werden. Prüfe sie erneut; bestehende Beträge bleiben erhalten."
    }
}
private struct LocalOwnerBudgetValues: View {
    let snapshot: LocalOwnerBudgetSnapshot
    var body: some View {
        if let ceiling = snapshot.ceiling { LocalTaskActivationMoney(title: "Aktueller Monatsrahmen", micros: ceiling, currency: snapshot.currency) }
        else { Text("Noch kein gemeinsamer Rahmen festgelegt.") }
        LocalTaskActivationMoney(title: "Bestätigt oder reserviert", micros: snapshot.committed, currency: snapshot.currency)
        Text("UTC-Monat: \(snapshot.period)").font(.caption).foregroundStyle(.secondary)
    }
}
private struct LocalOwnerBudgetConfirmation: View {
    let review: LocalOwnerBudgetReview
    let busy: Bool
    let confirm: () -> Void
    var body: some View {
        Section("Bestätigung") {
            LocalTaskActivationMoney(title: "Neuer Monatsrahmen", micros: review.monthlyMicros, currency: review.previous.currency)
            Text("Eine Erhöhung gibt bestehenden Aufgaben mehr gemeinsamen Spielraum innerhalb ihrer eigenen Grenzen. Sie startet selbst keine KI-Anfrage.").font(.caption).foregroundStyle(.secondary)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                if context.date >= review.expiresAt { Text("Freigabe abgelaufen. Bitte erneut prüfen.").font(.caption) }
                Button("Änderung bestätigen", action: confirm).disabled(busy || context.date >= review.expiresAt)
            }
        }
    }
}

/// Mac list rows merge several task actions into one accessibility element.
/// A scrollable stack preserves individual native buttons and text selection.
private struct LocalTaskList<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
#if os(macOS)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) { content }
                .padding(20).frame(maxWidth: .infinity, alignment: .leading)
        }
#else
        List { content }
#endif
    }
}

private extension View {
    @ViewBuilder func localTaskLifecycleButtonStyle() -> some View {
#if os(macOS)
        buttonStyle(.bordered)
#else
        buttonStyle(.borderless)
#endif
    }
    @ViewBuilder func localTaskFormStyle() -> some View {
#if os(macOS)
        formStyle(.grouped)
#else
        self
#endif
    }
    @ViewBuilder func localTaskRowButtonStyle() -> some View {
#if os(macOS)
        buttonStyle(.plain)
#else
        self
#endif
    }
    @ViewBuilder func localTaskNavigationTitle() -> some View {
#if canImport(UIKit)
        navigationBarTitleDisplayMode(.inline)
#else
        self
#endif
    }
    @ViewBuilder func localTaskSheetSize() -> some View {
#if os(macOS)
        frame(width: 620, height: 640)
#else
        self
#endif
    }
}
