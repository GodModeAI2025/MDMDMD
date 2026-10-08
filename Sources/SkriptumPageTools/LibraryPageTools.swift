import Foundation

extension WritingLibrary {
    func blocks(for pageID: UUID) -> [Block] { store?.snapshot.pages.first(where: { $0.id == pageID })?.blocks ?? [] }
    func currentPage(_ id: UUID) -> WritingPage? { pages.first { $0.id == id } }
    func updateBlocks(_ page: WritingPage, blocks: [Block], token: UUID?) -> (UUID, UUID)? {
        guard let store, let current = store.snapshot.pages.first(where: { $0.id == page.id }), current.revision == page.revision else {
            preserveConflictedDraft(page); saveError = "Die Seite wurde geändert. Der Blockentwurf wurde nicht überschrieben."; return nil
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
    func importLibraryPackage(_ source: URL) -> Bool {
        guard store?.hasActiveEdits != true else { saveError = "Bitte laufende Schreibsitzungen zuerst schließen."; return false }
        let access = source.startAccessingSecurityScopedResource(); defer { if access { source.stopAccessingSecurityScopedResource() } }
        let destination = URL.documentsDirectory.appending(path: "ScriptumLibraries/" + UUID().uuidString, directoryHint: .isDirectory)
        do {
            let imported = try LibraryStore.importPackage(from: source, to: destination)
            activateStore(imported)
            UserDefaults.standard.set(destination.path, forKey: "Scriptum.libraryDirectory")
            saveError = nil; return true
        } catch { saveError = "Paketimport fehlgeschlagen: \(error.localizedDescription)"; return false }
    }
}
