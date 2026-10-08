import SwiftUI

struct PageReviewPanel: View {
    let page: WritingPage
    let selection: NSRange
    let library: WritingLibrary
    let restored: (WritingPage) -> Void
    let beforeMutation: () -> Bool
    @State private var tab = "Kommentare"
    @State private var draft = ""
    @State private var selectedRevision: Revision?
    var body: some View {
        VStack(spacing: 0) {
            Picker("Seitenprüfung", selection: $tab) {
                Text("Kommentare").tag("Kommentare")
                Text("Verlauf").tag("Verlauf")
            }.pickerStyle(.segmented).padding()
            List {
                if tab == "Kommentare" {
                    ForEach(library.comments.filter { $0.pageID == page.id }) { comment in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(comment.body)
                            if !comment.quotedText.isEmpty { Text("„\(comment.quotedText)“").font(.caption).foregroundStyle(.secondary).lineLimit(3) }
                            Text(comment.createdAt, format: .dateTime.day().month().hour().minute()).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    TextField("Kommentar zur Auswahl", text: $draft, axis: .vertical)
                    Button("Kommentar hinzufügen", systemImage: "plus.bubble") {
                        let body = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !body.isEmpty else { return }
                        guard beforeMutation() else { return }
                        library.addComment(page: page, selection: selection, body: body); draft = ""
                    }.disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } else {
                    ForEach(library.revisions.filter { $0.page.id == page.id }.reversed()) { revision in
                        Button { selectedRevision = revision } label: {
                            VStack(alignment: .leading) {
                                Text(revision.capturedAt, format: .dateTime.day().month().hour().minute().second())
                                Text("\(revision.author) · \(revision.page.markdown.count) Zeichen").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }.frame(minHeight: 200, maxHeight: 360)
        .sheet(item: $selectedRevision) { revision in
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Historische Fassung").font(.headline)
                        Text(revision.page.markdown).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                        Divider()
                        Text("Aktuelle Fassung").font(.headline)
                        Text(page.markdown).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                    }.padding()
                }
                .navigationTitle("Fassungen vergleichen")
                .toolbar {
                    Button("Schließen") { selectedRevision = nil }
                    Button("Wiederherstellen") {
                        guard beforeMutation() else { return }
                        if let value = library.restore(revision, baseRevision: page.revision) { restored(value); selectedRevision = nil }
                    }
                }
            }
        }
    }
}
