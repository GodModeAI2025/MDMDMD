import Foundation
import SwiftUI

struct DraftRecoveryView: View {
    let library: WritingLibrary
    let recovered: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var sharedMarkdown: SharedMarkdown?
    @State private var actionError: String?
    @State private var backupTask: Task<Void, Never>?
    @State private var backingUp = false
    var body: some View {
        NavigationStack {
            List {
                if library.isReadOnlyRecovery {
                    Section("Originaldateien") {
                        Text("Sichern Sie Bibliothek, Journale und Bilder vor einer Reparatur. Das ZIP enthält unveränderte Dateien und Prüfsummen; es wird nicht automatisch als Bibliothek importiert.").font(.caption).foregroundStyle(.secondary)
                        Button("Originaldateien als ZIP sichern", systemImage: "archivebox") {
                            backingUp = true; actionError = nil
                            backupTask = Task {
                                defer { backingUp = false; backupTask = nil }
                                sharedMarkdown = await library.exportRecoveryOriginals()
                                if sharedMarkdown == nil { actionError = library.saveError }
                            }
                        }.disabled(backingUp)
                        if backingUp {
                            ProgressView("Originaldateien werden gesichert …")
                            Button("Sicherung stoppen") { backupTask?.cancel() }
                        }
                    }
                }
                ForEach(library.recoveries) { record in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(record.page.title).font(.headline)
                        Text(record.capturedAt, format: .dateTime.day().month().hour().minute()).font(.caption).foregroundStyle(.secondary)
                        Text(record.page.markdown).lineLimit(5).font(.system(.caption, design: .monospaced))
                        if !record.isComplete {
                            Text("Text gesichert; die Sicherung ist noch nicht vollständig abgeschlossen.")
                                .font(.caption).foregroundStyle(.secondary)
                            Button("Textkopie ohne Bilder öffnen", systemImage: "doc.text") {
                                if let id = library.recoverTextAsCopy(record) { recovered(id); dismiss() }
                                else { actionError = library.saveError ?? "Die Textkopie konnte nicht geöffnet werden." }
                            }.disabled(library.isReadOnlyRecovery)
                            Text("Bildverweise bleiben im Markdown. Die ursprüngliche Sicherung bleibt für eine vollständige Wiederherstellung erhalten.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Button("Text als Markdown sichern", systemImage: "square.and.arrow.up") {
                            sharedMarkdown = library.exportMarkdown(record.page)
                            actionError = sharedMarkdown == nil ? library.saveError : nil
                        }
                        Button("Als neue Seite wiederherstellen", systemImage: "doc.badge.plus") {
                            if let id = library.recoverAsCopy(record) { recovered(id); dismiss() }
                            else { actionError = library.saveError ?? "Die Wiederherstellung konnte nicht abgeschlossen werden." }
                        }.disabled(library.isReadOnlyRecovery)
                    }.padding(.vertical, 6)
                }
                if !library.pendingJournalDrafts.isEmpty {
                    Section("Lesbare Schreibentwürfe") {
                        ForEach(library.pendingJournalDrafts) { draft in
                            VStack(alignment: .leading, spacing: 10) {
                                Text(draft.page.title).font(.headline)
                                Text(draft.page.markdown).lineLimit(5).font(.system(.caption, design: .monospaced))
                                Button("Entwurf als Markdown sichern", systemImage: "square.and.arrow.up") {
                                    sharedMarkdown = library.exportPendingJournal(draft)
                                    actionError = sharedMarkdown == nil ? library.saveError : nil
                                }
                            }.padding(.vertical, 6)
                        }
                    }
                }
            }
            .overlay { if library.recoveries.isEmpty && library.pendingJournalDrafts.isEmpty { ContentUnavailableView("Keine Konfliktentwürfe", systemImage: "checkmark.shield", description: Text("Gesicherte Entwürfe aus parallelen Änderungen erscheinen hier.")) } }
            .safeAreaInset(edge: .bottom) {
                if library.isReadOnlyRecovery || library.unreadableRecoveryCount > 0 || actionError != nil {
                    VStack(alignment: .leading, spacing: 8) {
                        if library.isReadOnlyRecovery { Text(library.recoveryNotice) }
                        if library.unreadableRecoveryCount > 0 {
                            Text("Nicht lesbare Sicherungen: \(library.unreadableRecoveryCount). Die Dateien bleiben erhalten.")
                        }
                        if let actionError { Text(actionError) }
                    }.font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding()
                }
            }
            .onDisappear { backupTask?.cancel() }
            .sheet(item: $sharedMarkdown) { item in MarkdownShareSheet(url: item.url) }
            .navigationTitle("Wiederherstellungen")
            .toolbar { Button("Schließen") { dismiss() } }
        }
    }
}
