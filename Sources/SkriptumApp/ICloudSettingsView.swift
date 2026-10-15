import SwiftUI

struct ICloudSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var session: ICloudLibrarySession
    @State private var reviewingConflicts = false
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
                        Label("iCloud in dieser Version nicht verfügbar", systemImage: "icloud.slash")
                        Text("Die Synchronisation wird mit einem App-Update freigeschaltet. Du musst dafür jetzt nichts einrichten. Deine Texte bleiben lokal verfügbar.")
                    case .inactive:
                        Button("iCloud aktivieren") { Task { await session.activate() } }
                        Text("Deine Bibliothek wird deinem iCloud-Konto zugeordnet.")
                    case .checking:
                        ProgressView("iCloud wird geprüft …")
                    case .ready:
                        Label("iCloud-Zugang eingerichtet", systemImage: "icloud")
                        if session.pendingCount > 0 { Text("\(session.pendingCount) Änderungen warten auf Übertragung.") }
                        if session.incomingCount > 0 { Text("\(session.incomingCount) empfangene Änderungen warten auf Übernahme.") }
                        if session.conflictCount > 0 { Label("\(session.conflictCount) Konflikte müssen geklärt werden.", systemImage: "exclamationmark.triangle") }
                        if let date = session.lastSynchronized { Text("Zuletzt synchronisiert: \(date.formatted(date: .abbreviated, time: .shortened))") }
                        Button("Jetzt synchronisieren") { Task { await session.synchronize() } }
                        Button("iCloud-Verbindung trennen") { Task { await session.stop() } }
                    case .syncing:
                        ProgressView("Synchronisation läuft …")
                    case .failed:
                        Label("iCloud derzeit nicht verfügbar", systemImage: "exclamationmark.icloud")
                        Text(session.connectionError ?? "Die Synchronisation konnte nicht abgeschlossen werden. Versuche es erneut; deine lokalen Texte bleiben erhalten.")
                        if let code = session.failureCode {
                            LabeledContent("Fehlercode", value: code).font(.caption.monospaced()).textSelection(.enabled)
                        }
                        Button("Erneut versuchen") { Task { await session.stop(rememberDisconnect: false); await session.activate() } }
                    case .accountChanged:
                        Label("iCloud-Konto geändert", systemImage: "person.crop.circle.badge.exclamationmark")
                        Text("Deine lokale Bibliothek bleibt erhalten. Die Verbindung muss für das neue Konto erneut eingerichtet werden.")
                        Button("iCloud-Verbindung erneuern") { Task { await session.stop(rememberDisconnect: false); await session.activate(allowAccountChange: true) } }
                    }
                }
                if let error = session.connectionError, session.status != .failed {
                    Section {
                        Text(error).foregroundStyle(.secondary)
                        Button("Gespeicherte iCloud-Auswahl zurücksetzen") { Task { await session.stop() } }
                        Text("Deine lokalen Texte und ausstehenden Änderungen bleiben erhalten. Danach kannst du iCloud neu einrichten.").font(.caption)
                    }
                }
                Section("Fassungen") {
                    Button("Seitenkonflikte prüfen", systemImage: "doc.on.doc") { reviewingConflicts = true }
                }
                ICloudDiagnosticsSection(report: session.diagnosticReport)
            }
            #if os(macOS)
            .formStyle(.grouped)
            .scrollBounceBehavior(.basedOnSize)
            #endif
            .scrollContentBackground(.hidden)
            .background { PaperSurface().ignoresSafeArea() }
            .navigationTitle("iCloud")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } } }
            .sheet(isPresented: $reviewingConflicts) { ICloudConflictsSheet(session: session) }
        }
    }
}

private struct ICloudDiagnosticsSection: View {
    let report: String
    var body: some View {
        Section {
            DisclosureGroup("Diagnose") {
                Text(verbatim: report).font(.caption.monospaced()).textSelection(.enabled)
                ShareLink(item: report) { Label("Diagnose teilen", systemImage: "square.and.arrow.up") }
                Text("Enthält keine Texte, Dateinamen oder Kontoangaben.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
