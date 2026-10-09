import Foundation
#if canImport(SkriptumCore)
import SkriptumCore
#endif

extension WritingLibrary {
    func replaceBlock(pageID: UUID, baseRevision: UUID, blockID: UUID, expectedSource: String, replacement: String) -> WritingPage? {
        guard let store, let current = store.snapshot.pages.first(where: { $0.id == pageID }),
              current.revision == baseRevision,
              let index = current.blocks.firstIndex(where: { $0.id == blockID }),
              current.blocks[index].markdown.utf8.elementsEqual(expectedSource.utf8) else {
            saveError = "Die Seite oder der Block wurde inzwischen geändert. Bitte erneut öffnen."
            return nil
        }
        var blocks = current.blocks
        blocks[index].markdown = replacement
        do {
            try store.setBlocks(pageID: pageID, blocks: blocks, baseRevision: baseRevision)
            reload(); saveError = nil; lastSaved = Date()
            return currentPage(pageID)
        } catch {
            saveError = "Die Blockänderung konnte nicht gespeichert werden: \(error.localizedDescription)"
            return nil
        }
    }
}
