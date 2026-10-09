import SwiftUI
#if canImport(SkriptumCore)
import SkriptumCore
#endif

struct ICloudConflictsSheet: View {
    let session: ICloudLibrarySession
    @Environment(\.dismiss) private var dismiss
    @State private var conflicts: [ICloudPageConflict] = []
    @State private var selected: ICloudPageConflict?
    @State private var loading = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            List {
                if session.status == .notConfigured {
                    ContentUnavailableView("iCloud nicht bereit", systemImage: "icloud.slash", description: Text("Die Konfliktprüfung wird mit der iCloud-Synchronisation verfügbar."))
                } else if session.status == .inactive || session.status == .checking || session.status == .accountChanged {
                    ContentUnavailableView("Mit iCloud verbinden", systemImage: "icloud", description: Text("Öffne deine iCloud-Verbindung, um gespeicherte Fassungen zu vergleichen."))
                } else if loading { ProgressView("Fassungen werden geladen …") }
                else if conflicts.isEmpty {
                    ContentUnavailableView("Keine Seitenkonflikte", systemImage: "doc.badge.checkmark", description: Text("Andere ausstehende Änderungen und Konflikte werden in den iCloud-Einstellungen angezeigt."))
                }
                ForEach(conflicts) { conflict in
                    Button { selected = conflict } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(conflict.local.title.isEmpty ? "Ohne Titel" : conflict.local.title)
                            Text("Lokale und iCloud-Fassung vergleichen").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if let error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            }.scrollContentBackground(.hidden).background { PaperSurface().ignoresSafeArea() }
            .navigationTitle("Seitenkonflikte")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Schließen") { dismiss() } }
                ToolbarItem(placement: .primaryAction) { Button("Neu laden", systemImage: "arrow.clockwise") { Task { await load() } }.disabled(loading || session.status == .syncing) }
            }
            .task { await load() }
            .sheet(item: $selected, onDismiss: { Task { await load() } }) { ICloudConflictReviewView(conflict: $0, session: session) }
        }
    }
    private func load() async {
        guard !loading else { return }; loading = true; defer { loading = false }
        do { conflicts = try await session.pageConflicts(); error = nil }
        catch { self.error = "Die Fassungen konnten noch nicht geladen werden. Deine gespeicherten Texte bleiben erhalten." }
    }
}

private enum ConflictReviewMode: String, CaseIterable, Identifiable {
    case local = "Lokal", remote = "iCloud", merged = "Zusammenführen"
    var id: Self { self }
}
private struct ICloudConflictReviewView: View {
    let conflict: ICloudPageConflict
    let session: ICloudLibrarySession
    @Environment(\.dismiss) private var dismiss
    @State private var mode = ConflictReviewMode.local
    @State private var draft: String
    @State private var selection = NSRange(location: 0, length: 0)
    @State private var recovery: ICloudConflictReviewStore?
    @State private var recoveryFailed = false
    @State private var savedDraftExists = false
    @State private var savedDrafts: [ICloudConflictReviewStore.Summary] = []
    @State private var confirmClose = false
    @State private var working = false
    @State private var task: Task<Void, Never>?
    @State private var failedAttempt = false
    @State private var error: String?
    init(conflict: ICloudPageConflict, session: ICloudLibrarySession) {
        self.conflict = conflict; self.session = session; _draft = State(initialValue: conflict.local.markdown)
    }
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ConflictReviewHeader(mode: $mode)
                if mode == .merged {
                    MarkdownTextEditor(text: Binding(get: { draft }, set: capture), selection: $selection,
                        isEditable: !working, jumpTo: nil, onCommandHandled: {}, onJumpHandled: {})
                } else {
                    ConflictSourcePane(page: mode == .local ? conflict.local : conflict.remote, session: session).id(mode)
                }
                ConflictReviewFooter(working: working, canApply: session.canResolve(conflict) && !failedAttempt,
                    error: error, draft: draft, apply: apply)
            }.background { PaperSurface().ignoresSafeArea() }
            .navigationTitle("Fassungen vergleichen")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Schließen") { if persist() { task?.cancel(); dismiss() } else { confirmClose = true } }.disabled(working) }
                ToolbarItem(placement: .primaryAction) {
                    Menu("Entwürfe", systemImage: "clock.arrow.circlepath") {
                        ForEach(savedDrafts) { saved in
                            Button { restore(saved) } label: {
                                Text(saved.updatedAt, format: .dateTime.day().month().hour().minute())
                                Text(saved.preview).lineLimit(2)
                                if !saved.matchesCurrentComparison { Text("Aus einem älteren Vergleich") }
                            }
                        }
                        Button("Entwürfe neu laden", systemImage: "arrow.clockwise") { reloadDrafts() }
                    }.disabled(working)
                }
            }
            .interactiveDismissDisabled(working || recoveryFailed)
            .confirmationDialog("Ungesicherten Entwurf schließen?", isPresented: $confirmClose) {
                Button("Trotzdem schließen", role: .destructive) { task?.cancel(); dismiss() }
            } message: { Text("Dein aktueller Text konnte nicht als Entwurf gespeichert werden. Sichere ihn über „Entwurf sichern“, bevor du ihn schließt.") }
            .task {
                do {
                    let store = try session.reviewStore(for: conflict); recovery = store
                    reloadDrafts()
                    if let latest = savedDrafts.first(where: { $0.matchesCurrentComparison }), let saved = try store.load(latest) { draft = saved; mode = .merged; savedDraftExists = true }
                } catch { self.error = "Die Entwurfssicherung konnte nicht geladen werden. Du kannst deinen Text über „Entwurf sichern“ exportieren." }
            }
            .onDisappear { task?.cancel() }
        }
    }
    private func capture(_ text: String) { draft = text; _ = persist() }
    private func reloadDrafts() {
        do {
            guard let recovery else { return }
            let listing = try recovery.listing()
            savedDrafts = listing.drafts.filter { !$0.matchesCurrentComparison || $0.draftID != recovery.draftID }
            if listing.unreadableCount > 0 { error = "Einige Entwürfe konnten nicht geladen werden. Ihre Dateien bleiben erhalten." }
        } catch { self.error = "Die gesicherten Entwürfe konnten nicht geladen werden. Dein geöffneter Text bleibt erhalten." }
    }
    private func restore(_ saved: ICloudConflictReviewStore.Summary) {
        guard persist(), let recovery else { return }
        do {
            guard let text = try recovery.load(saved) else { return }
            draft = text; mode = .merged; savedDraftExists = true; _ = persist()
        } catch { self.error = "Dieser Entwurf konnte nicht geladen werden. Dein geöffneter Text bleibt erhalten." }
    }
    @discardableResult private func persist() -> Bool {
        guard savedDraftExists || !draft.utf8.elementsEqual(conflict.local.markdown.utf8) else { return true }
        do {
            guard let recovery else { throw ICloudPageConflictError.unavailable }
            try recovery.save(draft); if recoveryFailed { error = nil }; recoveryFailed = false; savedDraftExists = true; return true
        } catch {
            recoveryFailed = true; self.error = "Die Entwurfssicherung ist fehlgeschlagen. Bitte sichere deinen Text vor dem Schließen."; return false
        }
    }
    private func apply() {
        guard !working, persist() else { return }
        let choice: ICloudPageResolutionChoice
        switch mode { case .local: choice = .local; case .remote: choice = .remote; case .merged: choice = .mergedMarkdown(draft) }
        working = true; error = nil
        task = Task { @MainActor in
            defer { working = false }
            do { try await session.resolve(conflict, choice: choice); dismiss() }
            catch { failedAttempt = true; self.error = "Die Fassungen haben sich geändert oder sind noch nicht verfügbar. Dein Entwurf bleibt gesichert. Lade den Vergleich erneut, bevor du ihn übernimmst." }
        }
    }
}
private struct ConflictReviewHeader: View {
    @Binding var mode: ConflictReviewMode
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Vergleiche beide Fassungen oder bearbeite deine neue Fassung. Die Ausgangsfassungen bleiben im Versionsverlauf erhalten.").font(.caption).foregroundStyle(.secondary)
            if mode == .merged { Text("Die Zusammenführung behält deine lokalen Seiteneigenschaften und die Bilder beider Fassungen.").font(.caption).foregroundStyle(.secondary) }
            if typeSize.isAccessibilitySize {
                Picker("Fassung", selection: $mode) { ForEach(ConflictReviewMode.allCases) { Text(LocalizedStringKey($0.rawValue)).tag($0) } }.pickerStyle(.menu)
            } else {
                Picker("Fassung", selection: $mode) { ForEach(ConflictReviewMode.allCases) { Text(LocalizedStringKey($0.rawValue)).tag($0) } }.pickerStyle(.segmented)
            }
        }.padding()
    }
}
private struct ConflictSourcePane: View {
    let page: Page
    let session: ICloudLibrarySession
    @State private var selection = NSRange(location: 0, length: 0)
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(page.title.isEmpty ? "Ohne Titel" : page.title).font(.headline).padding(.horizontal)
            Text("Diese Fassung umfasst Text und Seiteneigenschaften.").font(.caption).foregroundStyle(.secondary).padding(.horizontal)
            DisclosureGroup("Seiteneigenschaften") {
                ConflictPageProperties(page: page, spaceTitle: session.spaceTitle(page.spaceID),
                    parentTitle: page.parentID.flatMap { session.pageTitle($0) })
            }.padding(.horizontal)
            MarkdownTextEditor(text: .constant(page.markdown), selection: $selection, isEditable: false,
                jumpTo: nil, onCommandHandled: {}, onJumpHandled: {})
        }
    }
}
private struct ConflictPageProperties: View {
    let page: Page
    let spaceTitle: String?, parentTitle: String?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Space: \(spaceTitle ?? "Noch nicht verfügbar")")
                if page.parentID != nil { Text("Übergeordnete Seite: \(parentTitle ?? "Noch nicht verfügbar")") }
                else { Text("Keine übergeordnete Seite") }
                Text("Schlagwörter: \(page.tags.isEmpty ? "Keine" : page.tags.formatted(.list(type: .and)))")
                Label(page.isFavorite ? "Favorit" : "Kein Favorit", systemImage: page.isFavorite ? "star.fill" : "star")
                if let goal = page.wordGoal { Text("Schreibziel: \(goal) Wörter") }
                if page.trashedAt != nil { Label("Im Papierkorb", systemImage: "trash") }
                Text(page.effectivePurpose == .material ? "Recherchematerial" : page.effectivePurpose == .template ? "Vorlage" : "Manuskripttext")
                if let rules = page.assistantRules, !rules.isEmpty { Text("Seitenregeln").font(.headline); Text(rules).textSelection(.enabled) }
                ForEach(page.reusablePrompts ?? []) { prompt in
                    Text(prompt.title).font(.headline); Text(prompt.text).textSelection(.enabled)
                }
                ForEach(page.attachments ?? []) { image in Label(image.filename, systemImage: "photo") }
            }.frame(maxWidth: .infinity, alignment: .leading).font(.caption).padding(.vertical, 8)
        }.frame(maxHeight: 240)
    }
}
private struct ConflictReviewFooter: View {
    let working: Bool, canApply: Bool
    let error: String?, draft: String
    let apply: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let error { Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
            if working { ProgressView("Fassung wird gespeichert …") }
            ViewThatFits(in: .horizontal) {
                HStack {
                    ShareLink("Entwurf sichern", item: draft).fixedSize()
                    Spacer()
                    Button("Diese Fassung verwenden", action: apply).buttonStyle(.borderedProminent).disabled(working || !canApply).fixedSize()
                }
                VStack(alignment: .leading, spacing: 12) {
                    ShareLink("Entwurf sichern", item: draft)
                    Button("Diese Fassung verwenden", action: apply).buttonStyle(.borderedProminent).disabled(working || !canApply)
                }
            }
        }.padding()
    }
}
