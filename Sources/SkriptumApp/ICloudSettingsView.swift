import SwiftUI

struct ICloudSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section("Bibliothek") {
                    Label("Lokal verfügbar", systemImage: "checkmark.circle")
                    Text("Deine Texte bleiben auch ohne Internet verfügbar.")
                }
                Section("iCloud") {
                    Label("Synchronisation noch nicht aktiviert", systemImage: "icloud")
                    Text("Scriptum verwendet dein iCloud-Konto für die Synchronisation. Die Einrichtung dieser Version ist noch nicht abgeschlossen.")
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
