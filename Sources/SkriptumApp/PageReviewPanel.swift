import SwiftUI

struct PageReviewPanel: View {
    let page: WritingPage
    let selection: NSRange
    let library: WritingLibrary
    let restored: (WritingPage) -> Void
    let beforeMutation: () -> Bool
    var performMutation: PageToolMutation = { $0() }
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
                    ForEach(library.comments.filter { $0.pageID == page.id && $0.parentCommentID == nil }) { comment in
                        CommentThreadRow(comment: comment,
                            replies: library.comments.filter { $0.parentCommentID == comment.id },
                            reply: { body in beforeMutation() && library.replyToComment(comment.id, body: body) },
                            resolve: { if beforeMutation() { library.resolveComment(comment.id, resolved: comment.resolvedAt == nil) } })
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
                        if let value = performMutation({ library.restore(revision, baseRevision: page.revision) }) { restored(value); selectedRevision = nil }
                    }
                }
            }
        }
    }
}

struct CommentThreadRow: View {
    let comment: Comment
    let replies: [Comment]
    let reply: (String) -> Bool
    let resolve: () -> Void
    var canWrite = true
    @State private var draft = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(comment.body).textSelection(.enabled)
            if !comment.quotedText.isEmpty { Text("„\(comment.quotedText)“").font(.caption).foregroundStyle(.secondary).lineLimit(3) }
            HStack {
                Text(comment.author).font(.caption)
                Text(comment.createdAt, format: .dateTime.day().month().hour().minute()).font(.caption2)
                if comment.resolvedAt != nil { Label("Erledigt", systemImage: "checkmark.circle").font(.caption) }
            }.foregroundStyle(.secondary)
            ForEach(replies) { answer in
                VStack(alignment: .leading, spacing: 4) {
                    Text(answer.body).textSelection(.enabled)
                    Text(answer.author).font(.caption).foregroundStyle(.secondary)
                }.padding(.leading, 16)
            }
            if canWrite {
            TextField("Antwort schreiben", text: $draft, axis: .vertical).lineLimit(1...6)
            HStack {
                Button("Antworten") {
                    let body = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !body.isEmpty, reply(body) { draft = "" }
                }.disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button(comment.resolvedAt == nil ? "Als erledigt markieren" : "Wieder öffnen", action: resolve)
            }.buttonStyle(.borderless)
            }
        }.padding(.vertical, 6)
    }
}
