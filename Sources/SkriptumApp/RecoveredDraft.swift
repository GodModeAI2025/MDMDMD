import Foundation
import SwiftUI

typealias RecoveredDraft = RecoveryRecord<WritingPage>

extension RecoveryRecord where Value == WritingPage {
    var page: WritingPage { value }
}

struct DraftRecoveryView: View {
    let library: WritingLibrary
    let recovered: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List(library.recoveries) { record in
                VStack(alignment: .leading, spacing: 12) {
                    Text(record.page.title).font(.headline)
                    Text(record.capturedAt, format: .dateTime.day().month().hour().minute()).font(.caption).foregroundStyle(.secondary)
                    Text(record.page.markdown).lineLimit(5).font(.system(.caption, design: .monospaced))
                    Button("Als neue Seite wiederherstellen", systemImage: "doc.badge.plus") {
                        if let id = library.recoverAsCopy(record) { recovered(id); dismiss() }
                    }
                }.padding(.vertical, 6)
            }
            .overlay { if library.recoveries.isEmpty { ContentUnavailableView("Keine Konfliktentwürfe", systemImage: "checkmark.shield", description: Text("Gesicherte Entwürfe aus parallelen Änderungen erscheinen hier.")) } }
            .navigationTitle("Wiederherstellungen")
            .toolbar { Button("Schließen") { dismiss() } }
        }
    }
}
