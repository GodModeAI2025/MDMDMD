import SwiftUI

struct ICloudSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var session: ICloudLibrarySession
    init(library: WritingLibrary) {
        let current = library.iCloudSession ?? ICloudLibrarySession(library: library)
        library.iCloudSession = current
        _session = State(initialValue: current)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Bibliothek") {
                    Label("Lokal verfügbar", systemImage: "checkmark.circle")
                    Text("Deine Texte bleiben auch ohne Internet verfügbar.")
                }
                Section("iCloud") {
                    switch session.status {
                    case .notConfigured:
                        Label("Einrichtung noch nicht abgeschlossen", systemImage: "icloud")
                        Text("Die iCloud-Synchronisation ist in dieser Version noch nicht freigeschaltet.")
                    case .inactive:
                        Button("iCloud aktivieren") { Task { await session.activate() } }
                        Text("Deine Bibliothek wird deinem iCloud-Konto zugeordnet.")
                    case .checking:
                        ProgressView("iCloud wird geprüft …")
                    case .ready:
                        Label("iCloud-Zugang eingerichtet", systemImage: "icloud")
                        Text("Die vollständige Dokumentübertragung wird noch eingerichtet.")
                    case .syncing:
                        ProgressView("Synchronisation läuft …")
                    case .failed:
                        Label("iCloud derzeit nicht verfügbar", systemImage: "exclamationmark.icloud")
                        Text("Prüfe dein iCloud-Konto und die Internetverbindung. Deine lokalen Texte bleiben erhalten.")
                        Button("Erneut versuchen") { Task { await session.activate() } }
                    case .accountChanged:
                        Label("iCloud-Konto geändert", systemImage: "person.crop.circle.badge.exclamationmark")
                        Text("Deine lokale Bibliothek bleibt erhalten. Die Verbindung muss für das neue Konto erneut eingerichtet werden.")
                    }
                }
                Section("KI-Zugänge") {
                    Text("OpenAI, Anthropic und Apple Private Cloud Compute werden unabhängig von der Bibliothek eingerichtet. API-Schlüssel werden nicht mit deinen Dokumenten synchronisiert.")
                }
            }
            .scrollContentBackground(.hidden)
            .background { PaperSurface().ignoresSafeArea() }
            .navigationTitle("iCloud")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } } }
        }
    }
}
