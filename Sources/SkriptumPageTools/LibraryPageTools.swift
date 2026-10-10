import SwiftUI
import Foundation
#if canImport(SkriptumCore)
import SkriptumCore
#endif
#if canImport(SkriptumExport)
import SkriptumExport
#endif

extension WritingLibrary {
    func exportPreferenceKey(spaceID: UUID) -> String? {
        guard let scope = try? assistantHistoryDirectory().lastPathComponent else { return nil }
        return "Scriptum.export." + scope + "." + spaceID.uuidString
    }
    @discardableResult func duplicatePage(_ page: WritingPage) -> UUID? {
        guard let store, var original = store.snapshot.pages.first(where: { $0.id == page.id }), original.revision == page.revision else {
            saveError = "Die Seite wurde geändert. Bitte die aktuelle Fassung vor dem Duplizieren öffnen."; return nil
        }
        do {
            original.title += " — Kopie"
            let copy = try store.createRecoveredPage(from: original, spaceID: original.spaceID, parentID: original.parentID, mediaRoot: store.directory)
            reload(); saveError = nil; return copy.id
        } catch { saveError = "Duplizieren fehlgeschlagen: \(error.localizedDescription)"; return nil }
    }
    func blocks(for pageID: UUID) -> [Block] { store?.snapshot.pages.first(where: { $0.id == pageID })?.blocks ?? [] }
    func currentPage(_ id: UUID) -> WritingPage? { pages.first { $0.id == id } }
    func updateBlocks(_ page: WritingPage, blocks: [Block], token: UUID?) -> (UUID, UUID)? {
        guard let store, let current = store.snapshot.pages.first(where: { $0.id == page.id }), current.revision == page.revision else {
            var draft = page; draft.markdown = blocks.map(\.markdown).joined(); draft.blockDraft = blocks
            if preserveConflictedDraft(draft) { saveError = "Die Seite wurde geändert. Der Blockentwurf liegt unter Wiederherstellungen." }
            return nil
        }
        do {
            let active = try token ?? store.beginEditing(pageID: page.id, baseRevision: page.revision)
            try store.updateEditing(active, blocks: blocks)
            reload(); lastSaved = Date()
            guard let next = currentPage(page.id) else { return nil }
            return (active, next.revision)
        } catch { saveError = error.localizedDescription; return nil }
    }
    func savePageTools(pageID: UUID, baseRevision: UUID, rules: String, prompts: [ReusablePrompt]) -> WritingPage? {
        guard let store else { return nil }
        do {
            try store.setRules(pageID: pageID, rules: rules, baseRevision: baseRevision)
            guard let latest = store.snapshot.pages.first(where: { $0.id == pageID }) else { return nil }
            try store.setPrompts(pageID: pageID, prompts: prompts, baseRevision: latest.revision)
            reload(); return currentPage(pageID)
        } catch { saveError = error.localizedDescription; return nil }
    }
    func saveSpaceTools(spaceID: UUID, rules: String, prompts: [ReusablePrompt]) {
        guard let store else { return }
        do { try store.setRules(spaceID: spaceID, rules: rules); try store.setPrompts(spaceID: spaceID, prompts: prompts); reload() }
        catch { saveError = error.localizedDescription }
    }
    func addImage(page: WritingPage, data: Data, mediaType: String, filename: String) -> (WritingPage, MediaAttachment)? {
        guard let store else { return nil }
        do {
            let attachment = try store.addAttachment(pageID: page.id, data: data, mediaType: mediaType, filename: filename, baseRevision: page.revision)
            reload(); guard let updated = currentPage(page.id) else { return nil }; return (updated, attachment)
        } catch { saveError = "Bild konnte nicht gespeichert werden: \(error.localizedDescription)"; return nil }
    }
    func exportAssets(for page: WritingPage) throws -> [String: ExportAsset] {
        guard let store else { return [:] }
        return try Dictionary(uniqueKeysWithValues: (page.attachments ?? []).map { ($0.relativePath, ExportAsset(data: try store.attachmentData($0), mediaType: $0.mediaType)) })
    }
    func exportLibraryPackage() -> URL? {
        guard let store else { return nil }
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
        let destination = root.appending(path: "Scriptum.scriptum", directoryHint: .isDirectory)
        do { try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true); try store.exportPackage(to: destination); return destination }
        catch { saveError = "Paketexport fehlgeschlagen: \(error.localizedDescription)"; return nil }
    }
    func importLibraryPackage(_ source: URL) -> WritingLibrary? {
        guard store?.hasActiveEdits != true else { saveError = "Bitte laufende Schreibsitzungen zuerst schließen."; return nil }
        let access = source.startAccessingSecurityScopedResource(); defer { if access { source.stopAccessingSecurityScopedResource() } }
        let destination = WorkspaceSystemContainerRoots.documents.appending(path: "ScriptumLibraries/" + UUID().uuidString, directoryHint: .isDirectory)
        do {
            let imported = try LibraryStore.importPackage(from: source, to: destination)
            let library = try WritingLibrary(store: imported)
            try library.rememberSelection()
            saveError = nil; return library
        } catch { saveError = "Paketimport fehlgeschlagen: \(error.localizedDescription)"; return nil }
    }
}

/// Per-window native transaction state survives callbacks captured by an older
/// SwiftUI render. No Codable/provider/source metadata can manufacture it.
@MainActor final class PageBlockWritingAdmission {
    private var acceptedPage: WritingPage?
    private var acceptedCore: Page?
    private var ownedToken: UUID?
    private weak var ownedStore: LibraryStore?
    var hasAcceptedWrite: Bool { acceptedPage != nil }
    func finish(library: WritingLibrary) -> Bool {
        guard let acceptedPage, let store = library.store, store === ownedStore else { return false }
        guard let ownedToken else { return true }
        guard store.ownsEditingToken(ownedToken, pageID: acceptedPage.id) else { self.ownedToken = nil; return true }
        guard library.finishTyping(ownedToken) else { return false }
        self.ownedToken = nil
        return true
    }
    func refreshOwnedText(library: WritingLibrary, page: Binding<WritingPage>) {
        guard let acceptedPage, let acceptedCore, let store = library.store, store === ownedStore,
              page.wrappedValue.id == acceptedPage.id,
              let actual = store.snapshot.pages.first(where: { $0.id == acceptedPage.id }), actual.storageEquals(acceptedCore) else { return }
        // Publish only fields owned by the native text transaction; preserve
        // unrelated UI property drafts. Foreign document changes cannot refresh.
        var updated = page.wrappedValue
        updated.revision = acceptedPage.revision; updated.markdown = acceptedPage.markdown
        page.wrappedValue = updated
    }
    func commit(library: WritingLibrary, page: Binding<WritingPage>, token: Binding<UUID?>, blocks: [Block]) -> Bool {
        var current = page.wrappedValue
        var active = token.wrappedValue
        if let acceptedPage, let acceptedCore {
            guard let store = library.store, store === ownedStore, current.id == acceptedPage.id else {
                library.saveError = "Der Dokumentzugang hat sich geändert. Bitte den Editor erneut öffnen."; return false
            }
            guard let actual = store.snapshot.pages.first(where: { $0.id == acceptedPage.id }), actual.storageEquals(acceptedCore) else {
                var draft = current; draft.markdown = blocks.map(\.markdown).joined(); draft.blockDraft = blocks
                if library.preserveConflictedDraft(draft) { library.saveError = "Die Seite wurde geändert. Der Blockentwurf liegt unter Wiederherstellungen." }
                return false
            }
            current = acceptedPage
            active = ownedToken.flatMap { store.ownsEditingToken($0, pageID: current.id) ? $0 : nil }
        }
        guard let (nextToken, revision) = library.updateBlocks(current, blocks: blocks, token: active),
              let store = library.store, let stored = store.snapshot.pages.first(where: { $0.id == current.id }),
              let next = library.currentPage(current.id) else { return false }
        acceptedPage = next; acceptedCore = stored; ownedToken = nextToken; ownedStore = store
        token.wrappedValue = nextToken
        var updated = page.wrappedValue; updated.revision = revision
        page.wrappedValue = updated
        return true
    }
}
