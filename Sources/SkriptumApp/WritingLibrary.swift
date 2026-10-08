import Foundation
import Observation

struct WritingPage: Identifiable, Codable, Equatable {
    var id = UUID()
    var revision: UUID
    var spaceID: UUID
    var parentID: UUID?
    var title: String
    var markdown: String
    var favorite = false
    var trashed = false
    var modified = Date()
    var wordGoal = 0
    var tags: [String] = []
}
struct WritingSpace: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
}
@MainActor @Observable final class WritingLibrary {
    var spaces: [WritingSpace] = []
    var pages: [WritingPage] = []
    var saveError: String?
    var lastSaved: Date?
    var revisions: [Revision] = []
    var comments: [Comment] = []
    private var store: LibraryStore?
    private var goals: [String: Int] = [:]

    init() {
        do {
            store = try LibraryStore(directory: URL.documentsDirectory.appending(path: "Skriptum", directoryHint: .isDirectory))
            goals = UserDefaults.standard.dictionary(forKey: "Skriptum.wordGoals") as? [String: Int] ?? [:]
            if let store, store.snapshot.spaces.isEmpty {
                let space = try store.createSpace(title: "Mein Schreibraum")
                try store.createPage(spaceID: space.id, title: "Willkommen in Skriptum", markdown: "# Ein Raum für Ihre Gedanken\n\nHier beginnt Ihr nächster Text. Schreiben Sie in offenem Markdown — Ihre Bibliothek ist auch offline verfügbar.\n\n## Ihr erstes Projekt\n\nLegen Sie einen Space für Ihr Manuskript, Ihre Recherche oder Ihre Notizen an.\n\n## Konzentriert schreiben\n\nAktivieren Sie den Fokusmodus. Gliederung und Schreibstatistik finden Sie im Informationsbereich.\n")
            }
            reload()
        } catch { saveError = "Die Bibliothek konnte nicht geöffnet werden: \(error.localizedDescription). Die vorhandenen Daten werden nicht überschrieben." }
    }
    private func reload() {
        guard let store else { return }
        revisions = store.snapshot.revisions
        comments = store.snapshot.comments
        spaces = store.snapshot.spaces.map { WritingSpace(id: $0.id, title: $0.title) }
        pages = store.snapshot.pages.map { page in
            WritingPage(id: page.id, revision: page.revision, spaceID: page.spaceID, parentID: page.parentID, title: page.title, markdown: page.markdown, favorite: page.isFavorite, trashed: page.trashedAt != nil, modified: page.modifiedAt, wordGoal: goals[page.id.uuidString] ?? 0, tags: page.tags)
        }
    }
    @discardableResult func update(_ page: WritingPage) -> UUID? {
        guard let store, let original = store.snapshot.pages.first(where: { $0.id == page.id }) else { return nil }
        guard original.revision == page.revision else {
            saveError = "Diese Seite wurde in einem anderen Fenster geändert. Ihr Entwurf bleibt geöffnet; die gespeicherte Fassung wurde nicht überschrieben."
            return nil
        }
        do {
            if original.title != page.title { try store.renamePage(page.id, title: page.title) }
            if original.markdown != page.markdown {
                guard let current = store.snapshot.pages.first(where: { $0.id == page.id }) else { return nil }
                try store.setMarkdown(page.id, markdown: page.markdown, baseRevision: current.revision)
            }
            if original.isFavorite != page.favorite { try store.setFavorite(page.id, value: page.favorite) }
            if original.tags != page.tags { try store.setTags(page.id, tags: page.tags) }
            if (original.trashedAt != nil) != page.trashed {
                if page.trashed { try store.trashPage(page.id) } else { try store.restorePage(page.id) }
            }
            goals[page.id.uuidString] = max(0, page.wordGoal)
            UserDefaults.standard.set(goals, forKey: "Skriptum.wordGoals")
            lastSaved = Date(); saveError = nil; reload()
            return store.snapshot.pages.first(where: { $0.id == page.id })?.revision
        } catch { saveError = "Speichern fehlgeschlagen: \(error.localizedDescription)"; return nil }
    }
    @discardableResult func createPage(spaceID: UUID?, parentID: UUID? = nil) -> UUID? {
        guard let store, let spaceID = spaceID ?? spaces.first?.id else { return nil }
        do { let page = try store.createPage(spaceID: spaceID, parentID: parentID, title: "Neue Seite"); reload(); return page.id }
        catch { saveError = error.localizedDescription; return nil }
    }
    func createSpace(title: String) -> UUID? {
        guard let store else { return nil }
        do { let space = try store.createSpace(title: title); reload(); return space.id }
        catch { saveError = error.localizedDescription; return nil }
    }
}

extension WritingLibrary {
    func importMarkdown(url: URL, spaceID: UUID?) -> UUID? {
        guard let store, let spaceID = spaceID ?? spaces.first?.id else { return nil }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            var readingError: NSError?
            var content: String?
            var decodingError: Error?
            NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &readingError) { coordinated in
                do {
                    let data = try Data(contentsOf: coordinated)
                    guard let decoded = String(data: data, encoding: .utf8) else { throw MarkdownDocumentError.invalidUTF8 }
                    content = decoded
                } catch { decodingError = error }
            }
            if let readingError { throw readingError }
            if let decodingError { throw decodingError }
            guard let content else { return nil }
            let page = try store.createPage(spaceID: spaceID, title: url.deletingPathExtension().lastPathComponent, markdown: content)
            reload(); return page.id
        } catch { saveError = "Import fehlgeschlagen: \(error.localizedDescription)"; return nil }
    }
    func exportMarkdown(_ page: WritingPage) -> SharedMarkdown? {
        do {
            let directory = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let name = page.title.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            let url = directory.appending(path: (name.isEmpty ? "Ohne Titel" : name) + ".md")
            try Data(page.markdown.utf8).write(to: url, options: .atomic)
            return SharedMarkdown(url: url)
        } catch { saveError = "Export fehlgeschlagen: \(error.localizedDescription)"; return nil }
    }
    func restore(_ revision: Revision, baseRevision: UUID) -> WritingPage? {
        guard let store else { return nil }
        do {
            try store.restoreRevision(pageID: revision.page.id, revisionID: revision.id, baseRevision: baseRevision)
            reload(); return pages.first(where: { $0.id == revision.page.id })
        } catch { saveError = "Wiederherstellung fehlgeschlagen: \(error.localizedDescription)"; return nil }
    }
    func addComment(page: WritingPage, selection: NSRange, body: String) {
        guard let store, let current = store.snapshot.pages.first(where: { $0.id == page.id }) else { return }
        guard current.revision == page.revision else { saveError = "Die Seite wurde geändert. Kommentar konnte nicht sicher verankert werden."; return }
        let text = page.markdown as NSString
        let validRange = NSIntersectionRange(selection, NSRange(location: 0, length: text.length))
        var offset = 0
        let block = current.blocks.first { block in
            defer { offset += (block.markdown as NSString).length }
            return validRange.location >= offset && validRange.location < offset + (block.markdown as NSString).length
        }
        do {
            try store.addComment(Comment(pageID: page.id, blockID: block?.id, quotedText: text.substring(with: validRange), body: body, author: "Ich"))
            reload()
        } catch { saveError = "Kommentar fehlgeschlagen: \(error.localizedDescription)" }
    }
}

extension WritingLibrary {
    func updateText(_ page: WritingPage, token: UUID?) -> (token: UUID, revision: UUID)? {
        guard let store, let current = store.snapshot.pages.first(where: { $0.id == page.id }) else { return nil }
        guard current.revision == page.revision else { saveError = "Die Seite wurde in einem anderen Fenster geändert. Ihr Entwurf bleibt erhalten."; return nil }
        do {
            let active = try token ?? store.beginEditing(pageID: page.id, baseRevision: page.revision)
            try store.updateEditing(active, markdown: page.markdown)
            reload(); lastSaved = Date(); saveError = nil
            guard let revision = store.snapshot.pages.first(where: { $0.id == page.id })?.revision else { return nil }
            return (active, revision)
        } catch { saveError = "Schreibsitzung konnte nicht gespeichert werden: \(error.localizedDescription)"; return nil }
    }
    func finishTyping(_ token: UUID?) -> Bool {
        guard let token, let store else { return true }
        do { try store.finishEditing(token); reload(); return true }
        catch { saveError = "Schreibsitzung konnte nicht abgeschlossen werden: \(error.localizedDescription)"; return false }
    }
}
