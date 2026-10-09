import SwiftUI
#if canImport(SkriptumCore)
import SkriptumCore
#endif

struct ICloudSharedWindowHost: View {
    let identity: ICloudSharedStoreIdentity?
    @State private var session: ICloudSharedSession
    init(identity: ICloudSharedStoreIdentity?, directory: URL) {
        self.identity = identity; _session = State(initialValue: ICloudSharedSession(directory: directory))
    }
    var body: some View {
        ICloudSharedWritingView(session: session, retry: {
            if session.identity == nil, let identity { await session.restore(identity) }
            else { await session.synchronize() }
        })
        .task(id: identity) { if let identity { await session.restore(identity) } }
    }
}

struct ICloudSharedWritingView: View {
    let session: ICloudSharedSession
    let retry: () async -> Void
    var close: (() -> Void)? = nil
    @Environment(\.scenePhase) private var scenePhase
    @State private var selected: UUID?
    @State private var draftID = UUID()
    @State private var draft = ""
    @State private var baseline = ""
    @State private var revision: UUID?
    @State private var selection = NSRange(location: 0, length: 0)
    @State private var review = false
    @State private var reviewQuotation = ""
    @State private var reviewBlockID: UUID?
    @State private var jumpTo: Int?
    @State private var error: String?
    private var dirty: Bool { !draft.utf8.elementsEqual(baseline.utf8) }
    private var page: Page? { selected.flatMap { session.context?.page($0) } }
    private var canWrite: Bool { session.context?.permission == .readWrite && page?.trashedAt == nil }
    var body: some View {
        NavigationSplitView {
            List {
                if session.recoveredDrafts.contains(where: { $0.id != draftID }) {
                    Section("Gesicherte Entwürfe") {
                        ForEach(session.recoveredDrafts.filter { $0.id != draftID }) { saved in
                            Button { restore(saved) } label: {
                                VStack(alignment: .leading) {
                                    Text(session.context?.page(saved.pageID)?.title ?? "Lokaler Entwurf")
                                    Text(saved.updatedAt, format: .dateTime.day().month().hour().minute()).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                ForEach(session.context?.canonical.pages ?? []) { page in
                    Button { select(page.id) } label: {
                        Label(page.title.isEmpty ? "Ohne Titel" : page.title, systemImage: page.id == selected ? "doc.text.fill" : "doc.text")
                    }
                }
            }.scrollContentBackground(.hidden).background { PaperSurface() }
            .navigationTitle("Geteilte Dokumente")
        } detail: {
            VStack(spacing: 0) {
                if let page {
                    HStack {
                        Label(canWrite ? "Gemeinsam bearbeiten" : "Nur lesen", systemImage: canWrite ? "person.2" : "lock")
                        Spacer()
                        if session.pendingCount > 0 { Text("\(session.pendingCount) Änderungen ausstehend") }
                    }.font(.caption).foregroundStyle(.secondary).padding(.horizontal).padding(.top, 8)
                    MarkdownTextEditor(text: Binding(get: { draft }, set: capture), selection: $selection, isEditable: canWrite, jumpTo: jumpTo, onCommandHandled: {}, onJumpHandled: { jumpTo = nil })
                        .background { PaperSurface() }
                        .navigationTitle(page.title.isEmpty ? "Ohne Titel" : page.title)
                } else {
                    unavailable
                    if dirty {
                        Text("Dein lokaler Entwurf bleibt erhalten.").font(.callout)
                        ShareLink("Entwurf sichern", item: draft).padding()
                        ScrollView { Text(draft).font(.system(.body, design: .monospaced)).textSelection(.enabled).padding() }
                    }
                }
                if let error { Text(error).font(.caption).foregroundStyle(.red).padding().textSelection(.enabled) }
            }.background { PaperSurface() }
            .toolbar {
                if let close {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Schließen") {
                            if flush() { close() }
                            else if let selected, let revision {
                                do { try session.preserveDraft(ICloudSharedDraft(id: draftID, pageID: selected, baseRevision: revision, text: draft)); close() }
                                catch { self.error = "Bitte sichere deinen Entwurf vor dem Schließen." }
                            }
                        }
                    }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button("Synchronisieren", systemImage: "arrow.triangle.2.circlepath") {
                        guard flush() else { return }; Task { await retry() }
                    }.disabled(session.status == .accepting || session.status == .synchronizing || session.status == .notConfigured)
                    Button("Kommentare", systemImage: "text.bubble", action: showReview).disabled(page == nil)
                    if dirty { Button("Speichern", systemImage: "square.and.arrow.down") { _ = flush() } }
                }
            }
        }
        .sheet(isPresented: $review) {
            if let selected { SharedPageReviewView(session: session, pageID: selected, quotation: reviewQuotation, blockID: reviewBlockID, beforeMutation: flush) }
        }
        .interactiveDismissDisabled(dirty)
        .onChange(of: session.context?.canonical.pages) { _, _ in refresh() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { _ = flush() } }
        .onDisappear { _ = flush() }
        .task(id: Data(draft.utf8)) {
            guard dirty else { return }
            do { try await Task.sleep(for: .milliseconds(400)); _ = flush() } catch { }
        }
    }
    private var unavailable: some View {
        Group {
            if session.status == .accepting || session.status == .synchronizing { ProgressView("Geteiltes Dokument wird geladen …") }
            else if session.status == .notConfigured {
                ContentUnavailableView("iCloud-Freigaben noch nicht verfügbar", systemImage: "icloud.slash", description: Text("Die iCloud-Einrichtung dieser App ist noch nicht abgeschlossen."))
            } else if session.status == .failed {
                ContentUnavailableView("Freigabe nicht erreichbar", systemImage: "exclamationmark.icloud", description: Text("Prüfe deine Verbindung und die Freigaberechte. Gespeicherte Änderungen bleiben erhalten."))
            } else { ContentUnavailableView("Geteiltes Dokument auswählen", systemImage: "person.2") }
        }
    }
    private func capture(_ text: String) {
        if let selected, let revision {
            do {
                try session.preserveDraft(ICloudSharedDraft(id: draftID, pageID: selected, baseRevision: revision, text: text))
                if text.utf8.elementsEqual(baseline.utf8) { try session.clearDraft(draftID, matching: text) }
            } catch { self.error = "Die Entwurfssicherung ist fehlgeschlagen. Bitte sichere deinen Text vor dem Schließen." }
        }
        draft = text
    }
    private func restore(_ saved: ICloudSharedDraft) {
        guard flush() else { return }
        let current: ICloudSharedDraft
        do { guard let recovered = try session.recoveryDraft(saved.id) else { return }; current = recovered }
        catch { self.error = "Der gesicherte Entwurf konnte nicht geladen werden."; return }
        selected = current.pageID; draftID = current.id; revision = current.baseRevision
        baseline = page?.markdown ?? ""; draft = current.text
        if current.text.utf8.elementsEqual(baseline.utf8) { revision = page?.revision ?? current.baseRevision }
        selection = NSRange(location: 0, length: 0); jumpTo = 0
        // Retain original ancestry: stale drafts never silently overwrite a newer revision.
    }
    private func select(_ id: UUID) {
        guard flush() else { return }
        selected = id; selection = NSRange(location: 0, length: 0); jumpTo = 0; refresh()
    }
    private func refresh() {
        guard !dirty else { return }
        if selected == nil { selected = session.context?.canonical.pages.first?.id }
        guard let page else { return }
        draft = page.markdown; baseline = page.markdown; revision = page.revision
    }
    private func showReview() {
        guard flush() else { return }
        reviewQuotation = selection.length > 0 ? Range(selection, in: draft).map { String(draft[$0]) } ?? "" : ""
        reviewBlockID = nil
        if !reviewQuotation.isEmpty, let page {
            var offset = 0
            for block in page.blocks {
                let end = offset + block.markdown.utf16.count
                if selection.location >= offset && selection.location < end { reviewBlockID = block.id; break }
                offset = end
            }
        }
        review = true
    }
    @discardableResult private func flush() -> Bool {
        guard dirty else { return true }
        guard let selected, let revision else { return false }
        do {
            self.revision = try session.edit(pageID: selected, revision: revision, markdown: draft)
            baseline = draft
            do { try session.clearDraft(draftID, matching: draft); error = nil }
            catch { self.error = "Gespeichert. Die zusätzliche Entwurfssicherung bleibt erhalten." }
            return true
        } catch {
            self.error = "Dein Entwurf konnte noch nicht gespeichert werden. Er bleibt geöffnet; du kannst ihn sichern und erneut versuchen."
            return false
        }
    }
}

private struct SharedPageReviewView: View {
    let session: ICloudSharedSession
    let pageID: UUID
    let quotation: String
    let blockID: UUID?
    let beforeMutation: () -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @State private var error: String?
    private var comments: [Comment] { session.context?.canonical.comments.filter { $0.pageID == pageID } ?? [] }
    private var canWrite: Bool { session.context?.permission == .readWrite }
    var body: some View {
        NavigationStack {
            List {
                ForEach(comments.filter { $0.parentCommentID == nil }) { comment in
                    CommentThreadRow(comment: comment, replies: comments.filter { $0.parentCommentID == comment.id }, reply: { body in
                        mutate { try session.reply(commentID: comment.id, body: body) }
                    }, resolve: {
                        _ = mutate { try session.resolve(commentID: comment.id, resolved: comment.resolvedAt == nil) }
                    }, canWrite: canWrite)
                }
                if canWrite {
                    if !quotation.isEmpty { Text("„\(quotation)“").font(.caption).foregroundStyle(.secondary).lineLimit(3) }
                    TextField(quotation.isEmpty ? "Kommentar zum Dokument" : "Kommentar zur Auswahl", text: $draft, axis: .vertical)
                    Button("Kommentar hinzufügen", systemImage: "plus.bubble") {
                        if mutate({ try session.addComment(pageID: pageID, blockID: blockID, quotation: quotation, body: draft) }) { draft = "" }
                    }.disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if let error { Text(error).foregroundStyle(.red) }
            }.scrollContentBackground(.hidden).background { PaperSurface() }
            .navigationTitle("Kommentare")
            .toolbar { Button("Schließen") { dismiss() } }
        }
    }
    private func mutate(_ operation: () throws -> Void) -> Bool {
        guard beforeMutation() else { return false }
        do { try operation(); error = nil; return true }
        catch { self.error = "Die Änderung konnte nicht gespeichert werden. Dein Text bleibt erhalten."; return false }
    }
}
