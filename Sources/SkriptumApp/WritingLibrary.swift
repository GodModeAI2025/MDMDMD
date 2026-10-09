import Foundation
import Observation
#if canImport(SkriptumCore)
import SkriptumCore
#endif

struct WritingPage: Identifiable, Codable, Equatable, Sendable {
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
    var assistantRules: String?
    var reusablePrompts: [ReusablePrompt]?
    var attachments: [MediaAttachment]?
    var purpose: PagePurpose?
    var effectivePurpose: PagePurpose { purpose ?? .writing }
    /// Present only in conflict recovery records that must preserve block identity.
    var blockDraft: [Block]?
    static func == (lhs: WritingPage, rhs: WritingPage) -> Bool {
        lhs.id == rhs.id && lhs.revision == rhs.revision && lhs.spaceID == rhs.spaceID && lhs.parentID == rhs.parentID &&
        lhs.title.utf8.elementsEqual(rhs.title.utf8) && lhs.markdown.utf8.elementsEqual(rhs.markdown.utf8) &&
        lhs.favorite == rhs.favorite && lhs.trashed == rhs.trashed && lhs.modified == rhs.modified && lhs.wordGoal == rhs.wordGoal &&
        lhs.tags.count == rhs.tags.count && zip(lhs.tags, rhs.tags).allSatisfy { $0.utf8.elementsEqual($1.utf8) } &&
        (lhs.assistantRules.map { Data($0.utf8) } == rhs.assistantRules.map { Data($0.utf8) }) &&
        lhs.reusablePrompts == rhs.reusablePrompts && lhs.attachments == rhs.attachments && lhs.purpose == rhs.purpose &&
        lhs.blockDraft?.count == rhs.blockDraft?.count && zip(lhs.blockDraft ?? [], rhs.blockDraft ?? []).allSatisfy { $0.id == $1.id && $0.markdown.utf8.elementsEqual($1.markdown.utf8) }
    }
}
struct WritingSpace: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var assistantRules: String = ""
    var reusablePrompts: [ReusablePrompt]?
}
@MainActor @Observable final class WritingLibrary {
    var spaces: [WritingSpace] = []
    var pages: [WritingPage] = []
    var saveError: String?
    var lastSaved: Date?
    var revisions: [Revision] = []
    var comments: [Comment] = []
    var recoveries: [RecoveredDraft] = []
    @ObservationIgnored private(set) var store: LibraryStore?
    let libraryIdentity = UUID()
    private var goals: [String: Int] = [:]
    private let documentRoot: URL
    private let supportRoot: URL
    let preferences: UserDefaults
    @ObservationIgnored var iCloudSession: ICloudLibrarySession?
    @ObservationIgnored var scheduleSession: LocalScheduleSession?
    func iCloudStorageDirectory() -> URL { supportRoot.appendingPathComponent("ICloudSync", isDirectory: true) }

    init() {
        documentRoot = WorkspaceSystemContainerRoots.documents; supportRoot = WorkspaceSystemContainerRoots.applicationSupport; preferences = .standard
        do {
            let selection = try Self.selectedDirectory(documentRoot: documentRoot)
            if selection.explicit, !FileManager.default.fileExists(atPath: selection.url.appendingPathComponent("library.json").path) {
                throw WritingLibraryOpenError.missingSelectedLibrary
            }
            store = try LibraryStore(directory: selection.url)
            loadLegacyGoals()
            if let store, !selection.explicit, store.snapshot.spaces.isEmpty {
                let space = try store.createSpace(title: "Mein Schreibraum")
                try store.createPage(spaceID: space.id, title: "Willkommen in Scriptum", markdown: "# Ein Raum für Ihre Gedanken\n\nHier beginnt Ihr nächster Text. Schreiben Sie in offenem Markdown — Ihre Bibliothek ist auch offline verfügbar.\n\n## Ihr erstes Projekt\n\nLegen Sie einen Space für Ihr Manuskript, Ihre Recherche oder Ihre Notizen an.\n\n## Konzentriert schreiben\n\nAktivieren Sie den Fokusmodus. Gliederung und Schreibstatistik finden Sie im Informationsbereich.\n")
            }
            reload()
            loadRecoveries()
            try rememberSelection()
        } catch { saveError = "Die Bibliothek konnte nicht geöffnet werden: \(error.localizedDescription). Die vorhandenen Daten werden nicht überschrieben." }
    }
    init(store: LibraryStore, documentRoot: URL = WorkspaceSystemContainerRoots.documents, supportRoot: URL = WorkspaceSystemContainerRoots.applicationSupport, preferences: UserDefaults = .standard) throws {
        self.documentRoot = documentRoot; self.supportRoot = supportRoot; self.preferences = preferences
        _ = try LibraryStoragePaths.recoveriesDirectory(libraryDirectory: store.directory, documentRoot: documentRoot)
        self.store = store
        loadLegacyGoals(); reload(); loadRecoveries()
    }
    func ownedWindowLocator() throws -> OwnedLibraryLocator {
        guard let store else { throw WritingLibraryOpenError.missingSelectedLibrary }
        return try LibraryStoragePaths.locator(libraryDirectory: store.directory, documentRoot: documentRoot)
    }
    /// Uses this facade's actual owned roots; metadata never selects credentials.
    func cloudBindingRepository() throws -> CloudLibraryBindingRepository {
        try CloudLibraryBindingRepository(locator: ownedWindowLocator(), documentRoot: documentRoot, supportRoot: supportRoot)
    }
    func assistantHistoryDirectory() throws -> URL {
        guard let store else { throw WritingLibraryOpenError.missingSelectedLibrary }
        return try LibraryStoragePaths.assistantHistoryDirectory(libraryDirectory: store.directory, documentRoot: documentRoot, applicationSupportRoot: supportRoot)
    }
    func rememberSelection() throws {
        guard let store else { throw WritingLibraryOpenError.missingSelectedLibrary }
        _ = try assistantHistoryDirectory()
        let relative = store.directory.pathComponents.dropFirst(documentRoot.pathComponents.count).joined(separator: "/")
        preferences.set(relative, forKey: "Scriptum.libraryRelativeDirectory")
    }
    private func loadLegacyGoals() {
        let primary = documentRoot.appendingPathComponent("Skriptum").standardizedFileURL
        goals = store?.directory.standardizedFileURL == primary ? (preferences.dictionary(forKey: "Skriptum.wordGoals") as? [String: Int] ?? [:]) : [:]
    }
    private static func selectedDirectory(documentRoot: URL) throws -> (url: URL, explicit: Bool) {
        let defaults = UserDefaults.standard
        let relative: String
        if let selected = defaults.string(forKey: "Scriptum.libraryRelativeDirectory") {
            relative = selected
        } else if let old = defaults.string(forKey: "Scriptum.libraryDirectory") {
            guard old.hasPrefix("/") else { throw LibraryStoragePathError.invalidURL }
            let parts = URL(fileURLWithPath: old).pathComponents
            guard !parts.contains("."), !parts.contains("..") else { throw LibraryStoragePathError.pathTraversal }
            if Array(parts.suffix(2)) == ["Documents", "Skriptum"] { relative = "Skriptum" }
            else if parts.count >= 3, parts[parts.count - 3] == "Documents", parts[parts.count - 2] == "ScriptumLibraries", let id = UUID(uuidString: parts.last ?? "") {
                relative = "ScriptumLibraries/" + id.uuidString
            } else { throw LibraryStoragePathError.invalidOwnedLibrary }
        } else { return (documentRoot.appendingPathComponent("Skriptum", isDirectory: true), false) }
        let parts = relative.components(separatedBy: "/")
        let canonical: String
        if parts == ["Skriptum"] { canonical = "Skriptum" }
        else if parts.count == 2, parts[0] == "ScriptumLibraries", let id = UUID(uuidString: parts[1]) { canonical = "ScriptumLibraries/" + id.uuidString }
        else { throw LibraryStoragePathError.invalidOwnedLibrary }
        let directory = documentRoot.appendingPathComponent(canonical, isDirectory: true)
        _ = try LibraryStoragePaths.recoveriesDirectory(libraryDirectory: directory, documentRoot: documentRoot)
        return (directory, true)
    }
    func reload() {
        guard let store else { return }
        revisions = store.snapshot.revisions
        comments = store.snapshot.comments
        spaces = store.snapshot.spaces.map { WritingSpace(id: $0.id, title: $0.title, assistantRules: $0.assistantRules, reusablePrompts: $0.reusablePrompts) }
        pages = store.snapshot.pages.map { page in
            WritingPage(id: page.id, revision: page.revision, spaceID: page.spaceID, parentID: page.parentID, title: page.title, markdown: page.markdown, favorite: page.isFavorite, trashed: page.trashedAt != nil, modified: page.modifiedAt, wordGoal: page.wordGoal ?? goals[page.id.uuidString] ?? 0, tags: page.tags, assistantRules: page.assistantRules, reusablePrompts: page.reusablePrompts, attachments: page.attachments, purpose: page.purpose)
        }
    }
    @discardableResult func update(_ page: WritingPage) -> UUID? {
        guard let store, let original = store.snapshot.pages.first(where: { $0.id == page.id }) else { return nil }
        guard original.revision == page.revision else {
            guard preserveConflictedDraft(page) else { return nil }
            saveError = "Diese Seite wurde in einem anderen Fenster geändert. Der Entwurf liegt unter Wiederherstellungen; die gespeicherte Fassung wurde nicht überschrieben."
            return nil
        }
        do {
            if !original.title.utf8.elementsEqual(page.title.utf8) { try store.renamePage(page.id, title: page.title) }
            if !original.markdown.utf8.elementsEqual(page.markdown.utf8) {
                guard let current = store.snapshot.pages.first(where: { $0.id == page.id }) else { return nil }
                try store.setMarkdown(page.id, markdown: page.markdown, baseRevision: current.revision)
            }
            if original.isFavorite != page.favorite { try store.setFavorite(page.id, value: page.favorite) }
            if original.tags.count != page.tags.count || !zip(original.tags, page.tags).allSatisfy({ $0.utf8.elementsEqual($1.utf8) }) { try store.setTags(page.id, tags: page.tags) }
            if (original.trashedAt != nil) != page.trashed {
                if page.trashed { try store.trashPage(page.id) } else { try store.restorePage(page.id) }
            }
            if original.wordGoal != page.wordGoal {
                guard let latest = store.snapshot.pages.first(where: { $0.id == page.id }) else { return nil }
                try store.setWordGoal(pageID: page.id, goal: max(0, page.wordGoal), baseRevision: latest.revision)
            }
            if original.effectivePurpose != page.effectivePurpose {
                guard let latest = store.snapshot.pages.first(where: { $0.id == page.id }) else { return nil }
                try store.setPurpose(pageID: page.id, purpose: page.effectivePurpose, baseRevision: latest.revision)
            }
            goals[page.id.uuidString] = max(0, page.wordGoal)
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
    func replyToComment(_ id: UUID, body: String) -> Bool {
        guard let store else { return false }
        do { try store.replyToComment(id, body: body, author: "Ich"); reload(); saveError = nil; return true }
        catch { saveError = "Die Antwort konnte nicht gespeichert werden."; return false }
    }
    func resolveComment(_ id: UUID, resolved: Bool) {
        guard let store else { return }
        do { try store.setCommentResolved(id, resolved: resolved); reload(); saveError = nil }
        catch { saveError = "Der Kommentarstatus konnte nicht gespeichert werden." }
    }
}

extension WritingLibrary {
    /// A nil journal token is not evidence that the view's draft was saved.
    func persistBeforeNavigation(_ draft: WritingPage, token: UUID?) -> Bool {
        guard finishTyping(token) else { return false }
        if draftMatchesStored(draft) { reload(); return true }
        var pending = draft
        if let blocks = draft.blockDraft {
            guard let result = updateBlocks(draft, blocks: blocks, token: nil), finishTyping(result.0) else { return false }
            pending.revision = result.1
        }
        guard update(pending) != nil, draftMatchesStored(pending) else { return false }
        reload(); return true
    }
    private func draftMatchesStored(_ draft: WritingPage) -> Bool {
        guard let current = store?.snapshot.pages.first(where: { $0.id == draft.id }) else { return false }
        let a = current.reusablePrompts ?? [], b = draft.reusablePrompts ?? []
        let promptsEqual = a.count == b.count && zip(a,b).allSatisfy { $0.id == $1.id && $0.title.utf8.elementsEqual($1.title.utf8) && $0.text.utf8.elementsEqual($1.text.utf8) }
        let blocksEqual = draft.blockDraft.map { blocks in
            blocks.count == current.blocks.count && zip(blocks,current.blocks).allSatisfy { $0.id == $1.id && $0.markdown.utf8.elementsEqual($1.markdown.utf8) }
        } ?? true
        return current.spaceID == draft.spaceID && current.parentID == draft.parentID &&
            current.title.utf8.elementsEqual(draft.title.utf8) && current.markdown.utf8.elementsEqual(draft.markdown.utf8) &&
            current.isFavorite == draft.favorite && (current.trashedAt != nil) == draft.trashed &&
            current.effectivePurpose == draft.effectivePurpose && (current.wordGoal ?? goals[draft.id.uuidString] ?? 0) == draft.wordGoal &&
            current.tags.count == draft.tags.count && zip(current.tags,draft.tags).allSatisfy({ $0.utf8.elementsEqual($1.utf8) }) &&
            (current.assistantRules ?? "").utf8.elementsEqual((draft.assistantRules ?? "").utf8) &&
            promptsEqual && (current.attachments ?? []) == (draft.attachments ?? []) && blocksEqual
    }
    func updateText(_ page: WritingPage, token: UUID?) -> (token: UUID, revision: UUID)? {
        guard let store, let current = store.snapshot.pages.first(where: { $0.id == page.id }) else { return nil }
        guard current.revision == page.revision else { guard preserveConflictedDraft(page) else { return nil }; saveError = "Die Seite wurde in einem anderen Fenster geändert. Der Entwurf liegt unter Wiederherstellungen."; return nil }
        // Already committed changes also reach the view's onChange handler.
        // Do not open a new typing journal for that notification: it would
        // block the next atomic correction/undo with editInProgress.
        guard !current.markdown.utf8.elementsEqual(page.markdown.utf8) else {
            return token.map { ($0, current.revision) }
        }
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

extension WritingLibrary {
    private func recoveryDirectory() throws -> URL {
        guard let store else { throw WritingLibraryOpenError.missingSelectedLibrary }
        return try LibraryStoragePaths.recoveriesDirectory(libraryDirectory: store.directory, documentRoot: documentRoot)
    }
    private func loadRecoveries() {
        do { recoveries = try RecoveryArchive<WritingPage>(directory: recoveryDirectory()).records() }
        catch { saveError = "Wiederherstellungen konnten nicht gelesen werden: \(error.localizedDescription)" }
    }
    @discardableResult func preserveConflictedDraft(_ page: WritingPage) -> Bool {
        guard let store else { saveError = "Konfliktentwurf konnte ohne Bibliothek nicht gesichert werden."; return false }
        if let current = store.snapshot.pages.first(where: { $0.id == page.id }), current.revision == page.revision, draftMatchesStored(page) { return true }
        do {
            try store.archiveAttachments(page.attachments ?? [], to: recoveryDirectory())
            try RecoveryArchive<WritingPage>(directory: recoveryDirectory()).preserve(page)
            loadRecoveries()
            return true
        } catch {
            saveError = "Konfliktentwurf konnte nicht gesichert werden: \(error.localizedDescription). Exportieren Sie den geöffneten Text vor dem Schließen."
            return false
        }
    }
    func recoverAsCopy(_ recovery: RecoveredDraft) -> UUID? {
        guard let store else { return nil }
        do {
            let available = store.snapshot.spaces.contains(where: { $0.id == recovery.page.spaceID }) ? recovery.page.spaceID : store.snapshot.spaces.first?.id
            guard let available else { return nil }
            var draft = Page(spaceID: available, title: recovery.page.title + " — Wiederherstellung", markdown: recovery.page.markdown)
            draft.tags = recovery.page.tags; draft.isFavorite = recovery.page.favorite
            draft.assistantRules = recovery.page.assistantRules; draft.reusablePrompts = recovery.page.reusablePrompts
            draft.wordGoal = recovery.page.wordGoal; draft.attachments = recovery.page.attachments; draft.purpose = recovery.page.purpose
            if let blocks = recovery.page.blockDraft {
                guard blocks.map(\.markdown).joined().utf8.elementsEqual(recovery.page.markdown.utf8) else { throw LibraryError.invalidLibrary }
                draft.blocks = blocks
            }
            let parent = recovery.page.parentID.flatMap { id in
                store.snapshot.pages.first(where: { $0.id == id && $0.spaceID == available && $0.trashedAt == nil })?.id
            }
            let restored = try store.createRecoveredPage(from: draft, spaceID: available, parentID: parent, mediaRoot: recoveryDirectory(), fallbackMediaRoot: store.directory)
            // Read durable metadata and every referenced blob before deleting the only draft record.
            let readback = try JSONDecoder().decode(LibrarySnapshot.self, from: Data(contentsOf: store.directory.appendingPathComponent("library.json")))
            guard let durable = readback.pages.first(where: { $0.id == restored.id }), durable == restored,
                  durable.markdown.utf8.elementsEqual(recovery.page.markdown.utf8) else { throw LibraryError.invalidLibrary }
            for attachment in durable.attachments ?? [] { _ = try store.attachmentData(attachment) }
            try RecoveryArchive<WritingPage>(directory: recoveryDirectory()).remove(recovery.id)
            reload(); loadRecoveries(); return restored.id
        } catch { saveError = "Wiederherstellung fehlgeschlagen: \(error.localizedDescription)"; return nil }
    }
}

private enum WritingLibraryOpenError: Error, LocalizedError {
    case missingSelectedLibrary
    var errorDescription: String? { "Die ausgewählte Bibliothek ist an ihrem Speicherort nicht mehr vorhanden. Importieren Sie eine vorhandene Bibliothek, um sie wieder zu öffnen." }
}
