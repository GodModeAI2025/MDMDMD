import SwiftUI
#if canImport(SkriptumCore)
import SkriptumCore
#endif
#if canImport(SkriptumWorkspaceClient)
import SkriptumWorkspaceClient
#endif

struct WorkspaceLibraryPickerView: View {
    let runtime: WorkspaceAccountRuntime
    let presentation: WorkspaceLibraryPickerPresentation
    let windowID: UUID
    let locator: OwnedLibraryLocator
    let expectedFacadeID: UUID
    let consumerID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var choice: WorkspaceLibraryPickerChoice?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    WorkspaceLibraryAssociationSection(associated: presentation.association != nil)
                    WorkspaceLibraryPickerStatus(outcome: presentation.outcome, busy: presentation.isBusy)
                    if presentation.rows.isEmpty && !presentation.isBusy {
                        Text("Keine auswählbare Bibliothek angezeigt. Laden Sie die Liste erneut; falls sie leer bleibt, ist für dieses Konto noch keine Bibliothek verfügbar.")
                    }
                    VStack(spacing: 12) {
                        ForEach(presentation.rows, id: \.libraryID) { row in
                            WorkspaceLibraryPickerRow(title: row.title, role: row.role, disabled: presentation.isBusy) {
                                choice = WorkspaceLibraryPickerChoice(id: row.libraryID, title: row.title)
                            }
                        }
                    }
                    WorkspaceLibraryPaginationSection(busy: presentation.isBusy, previousAvailable: !presentation.previousCursors.isEmpty,
                        nextAvailable: presentation.nextAfter != nil, previous: previous, next: next, reload: reload)
                }.padding(20).frame(maxWidth: 640, alignment: .leading).frame(maxWidth: .infinity)
            }
            .background { PaperSurface().ignoresSafeArea() }
            .navigationTitle("Cloud-Bibliothek")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Fertig") { cancel(); dismiss() } }
                if presentation.isBusy { ToolbarItem(placement: .cancellationAction) { Button("Abbrechen", action: cancel) } }
            }
            .task { await runtime.loadLibraries(windowID: windowID, expectedLocator: locator, expectedFacadeID: expectedFacadeID, consumerID: consumerID) }
            .onDisappear(perform: cancel)
            .confirmationDialog("Bibliothek zuordnen?", item: $choice, titleVisibility: .visible) { selected in
                Button("Zuordnen") {
                    Task { _ = await runtime.associateLibrary(id: selected.id, windowID: windowID, expectedLocator: locator, expectedFacadeID: expectedFacadeID, consumerID: consumerID) }
                }
                Button("Abbrechen", role: .cancel) {}
            } message: { selected in
                Text("„\(selected.title)“ wird dieser lokalen Bibliothek zugeordnet. Eine bestehende Zuordnung wird ersetzt. Dokumente werden dadurch nicht hochgeladen oder synchronisiert.")
            }
        }.tint(Color("AccentColor"))
    }
    private func cancel() { runtime.cancelLibraryRequest(windowID: windowID, expectedLocator: locator, expectedFacadeID: expectedFacadeID, consumerID: consumerID) }
    private func reload() { Task { await runtime.loadLibraries(windowID: windowID, expectedLocator: locator, expectedFacadeID: expectedFacadeID, consumerID: consumerID) } }
    private func next() { Task { await runtime.nextLibraries(windowID: windowID, expectedLocator: locator, expectedFacadeID: expectedFacadeID, consumerID: consumerID) } }
    private func previous() { Task { await runtime.previousLibraries(windowID: windowID, expectedLocator: locator, expectedFacadeID: expectedFacadeID, consumerID: consumerID) } }
}

private struct WorkspaceLibraryPickerChoice: Identifiable {
    nonisolated let id: UUID
    let title: String
}
private struct WorkspaceLibraryAssociationSection: View {
    let associated: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(associated ? "Bibliothek zugeordnet" : "Bibliothek auswählen").font(.headline)
            Text("Die Zuordnung verbindet nur lokale Metadaten mit einer Cloud-Bibliothek. Sie aktiviert weder Dokumentübertragung noch Synchronisation und stellt keinen Verschlüsselungsschlüssel bereit.")
        }
    }
}
private struct WorkspaceLibraryPickerStatus: View {
    let outcome: WorkspaceLibraryPickerOutcome?
    let busy: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if busy { ProgressView("Bibliotheken werden geprüft …") }
            switch outcome {
            case .associated: Text("Zuordnung gespeichert. Ihre lokalen Dokumente bleiben unverändert.")
            case .conflict: Text("Die Zuordnung wurde zwischenzeitlich geändert. Laden Sie die Liste erneut und prüfen Sie Ihre Auswahl.")
            case .unavailable: Text("Bibliotheken konnten nicht geprüft oder zugeordnet werden. Prüfen Sie die Anmeldung und versuchen Sie es erneut.")
            case .superseded: Text("Die Anfrage ist nicht mehr aktuell oder wurde abgebrochen.")
            case nil: EmptyView()
            }
        }.foregroundStyle(Color.primary)
    }
}
private struct WorkspaceLibraryPickerRow: View {
    let title: String
    let role: WorkspaceRole
    let disabled: Bool
    let select: () -> Void
    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: 8) {
                Text(verbatim: title).font(.headline).lineLimit(4).multilineTextAlignment(.leading)
                Text(roleLabel).font(.subheadline)
                Text("Zuordnen").font(.body)
            }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).padding(12)
                .background(Color("PaperBase"), in: RoundedRectangle(cornerRadius: 12))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).foregroundStyle(Color.primary).disabled(disabled)
            .accessibilityLabel(Text(verbatim: title))
            .accessibilityValue(Text(roleLabel))
            .accessibilityHint("Diese Cloud-Bibliothek für die Zuordnung auswählen")
    }
    private var roleLabel: LocalizedStringResource {
        switch role {
        case .owner: "Berechtigung: Verwaltung"
        case .editor: "Berechtigung: Bearbeiten"
        case .viewer: "Berechtigung: Lesen"
        case .none: "Keine Berechtigung"
        }
    }
}
private struct WorkspaceLibraryPaginationSection: View {
    let busy: Bool
    let previousAvailable: Bool
    let nextAvailable: Bool
    let previous: () -> Void
    let next: () -> Void
    let reload: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button("Vorherige Seite", action: previous).frame(minHeight: 44).disabled(busy || !previousAvailable)
            Button("Nächste Seite", action: next).frame(minHeight: 44).disabled(busy || !nextAvailable)
            Button("Erneut laden", action: reload).frame(minHeight: 44).disabled(busy)
        }
    }
}
