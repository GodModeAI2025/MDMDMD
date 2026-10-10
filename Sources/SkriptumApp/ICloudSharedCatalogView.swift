import SwiftUI
import CloudKit
#if canImport(SkriptumCore)
import SkriptumCore
#endif

struct ICloudSharedCatalogView: View {
    let directory: URL
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow
    @Environment(\.supportsMultipleWindows) private var supportsMultipleWindows
    @Environment(\.scenePhase) private var scenePhase
    @State private var entries: [ICloudSharedCatalog.Entry] = []
    @State private var opened: ICloudSharedCatalog.Entry?
    @State private var loading = false
    @State private var error: String?
    @State private var generation = UUID()
    private var provisioned: Bool { Bundle.main.object(forInfoDictionaryKey: "ScriptumICloudProvisioned") as? Bool == true }
    var body: some View {
        NavigationStack {
            Group {
                if !provisioned {
                    ContentUnavailableView("iCloud-Freigaben noch nicht verfügbar", systemImage: "icloud.slash", description: Text("Die iCloud-Einrichtung dieser App ist noch nicht abgeschlossen."))
                } else if loading { ProgressView("Freigaben werden geladen …") }
                else if let error { ContentUnavailableView("Übersicht nicht erreichbar", systemImage: "exclamationmark.icloud", description: Text(error)) }
                else if entries.isEmpty {
                    ContentUnavailableView("Noch keine Freigaben", systemImage: "person.2", description: Text("Angenommene iCloud-Einladungen erscheinen hier. Beim Öffnen werden die aktuellen Rechte geprüft."))
                } else {
                    List(entries) { entry in
                        Button {
                            if supportsMultipleWindows { openWindow(id: "shared-document", value: entry.identity); dismiss() }
                            else { opened = entry }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Label(entry.titlePreview.isEmpty ? "Ohne Titel" : entry.titlePreview,
                                      systemImage: entry.identity.root.kind == .space ? "folder.badge.person.crop" : "doc.text")
                                Text(entry.lastOpened, format: .dateTime.day().month().year()).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .swipeActions { Button("Aus Übersicht entfernen", role: .destructive) { remove(entry) } }
                    }.scrollContentBackground(.hidden).refreshable { await reload() }
                }
            }.background { PaperSurface().ignoresSafeArea() }
            .navigationTitle("Geteilte Dokumente")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Schließen") { dismiss() } }
                ToolbarItem(placement: .primaryAction) { Button("Aktualisieren", systemImage: "arrow.clockwise") { Task { await reload() } }.disabled(!provisioned || loading) }
            }
        }
        .task { await reload() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await reload() } } }
        .onReceive(NotificationCenter.default.publisher(for: .CKAccountChanged)) { _ in Task { await reload() } }
        .onDisappear { generation = UUID() }
        .fullScreenCover(item: $opened) { entry in
            ICloudSharedWindowHost(identity: entry.identity, directory: directory, close: { opened = nil })
        }
    }
    private func reload() async {
        guard provisioned else { return }
        let attempt = UUID(); generation = attempt; loading = true; entries = []; error = nil
        do {
            let container = CKContainer(identifier: "iCloud.com.mobilebox.Skriptum")
            guard try await container.accountStatus() == .available else { throw ICloudSharedSessionError.unavailable }
            let account = try await container.userRecordID().recordName
            try Task.checkCancellation()
            let values = try ICloudSharedCatalog(directory: directory).entries(accountID: account)
            guard generation == attempt else { return }
            entries = values; loading = false
        } catch {
            guard generation == attempt else { return }
            loading = false; self.error = "Prüfe dein iCloud-Konto und versuche es erneut. Gespeicherte Inhalte bleiben erhalten."
        }
    }
    private func remove(_ entry: ICloudSharedCatalog.Entry) {
        do { try ICloudSharedCatalog(directory: directory).remove(entry.identity); entries.removeAll { $0.id == entry.id } }
        catch { self.error = "Der Eintrag konnte nicht entfernt werden. Deine Dokumente bleiben erhalten." }
    }
}
