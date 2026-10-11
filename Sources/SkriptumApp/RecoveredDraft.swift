import Foundation
import SwiftUI

struct DraftRecoveryView: View {
    let library: WritingLibrary
    let recovered: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var sharedMarkdown: SharedMarkdown?
    @State private var actionError: String?
    var body: some View {
        NavigationStack {
            List(library.recoveries) { record in
                VStack(alignment: .leading, spacing: 12) {
                    Text(record.page.title).font(.headline)
                    Text(record.capturedAt, format: .dateTime.day().month().hour().minute()).font(.caption).foregroundStyle(.secondary)
                    Text(record.page.markdown).lineLimit(5).font(.system(.caption, design: .monospaced))
                    if !record.isComplete {
                        Text("Text gesichert; die Sicherung ist noch nicht vollständig abgeschlossen.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Button("Text als Markdown sichern", systemImage: "square.and.arrow.up") {
                        sharedMarkdown = library.exportMarkdown(record.page)
                        actionError = sharedMarkdown == nil ? library.saveError : nil
                    }
                    Button("Als neue Seite wiederherstellen", systemImage: "doc.badge.plus") {
                        if let id = library.recoverAsCopy(record) { recovered(id); dismiss() }
                        else { actionError = library.saveError ?? "Die Wiederherstellung konnte nicht abgeschlossen werden." }
                    }
                }.padding(.vertical, 6)
            }
            .overlay { if library.recoveries.isEmpty { ContentUnavailableView("Keine Konfliktentwürfe", systemImage: "checkmark.shield", description: Text("Gesicherte Entwürfe aus parallelen Änderungen erscheinen hier.")) } }
            .safeAreaInset(edge: .bottom) {
                if library.unreadableRecoveryCount > 0 || actionError != nil {
                VStack(alignment: .leading, spacing: 8) {
                    if library.unreadableRecoveryCount > 0 {
                        Text("Nicht lesbare Sicherungen: \(library.unreadableRecoveryCount). Die Dateien bleiben erhalten.")
                    }
                    if let actionError { Text(actionError) }
                }.font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding()
                }
            }
            .sheet(item: $sharedMarkdown) { item in MarkdownShareSheet(url: item.url) }
            .navigationTitle("Wiederherstellungen")
            .toolbar { Button("Schließen") { dismiss() } }
        }
    }
}
