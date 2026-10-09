import Foundation
#if canImport(SkriptumCore)
import SkriptumCore
#endif
#if canImport(SkriptumExport)
import SkriptumExport
#endif

extension WritingLibrary {
    func changePurpose(_ page: WritingPage, purpose: PagePurpose) -> WritingPage? {
        guard let store else { return nil }
        do {
            try store.setPurpose(pageID: page.id, purpose: purpose, baseRevision: page.revision)
            reload(); saveError = nil; lastSaved = Date(); return currentPage(page.id)
        } catch { saveError = "Die Seitenart konnte nicht gespeichert werden: \(error.localizedDescription)"; return nil }
    }
    func instantiateTemplate(_ page: WritingPage, spaceID: UUID?) -> UUID? {
        guard let store else { return nil }
        do {
            let copy = try store.instantiateTemplate(pageID: page.id, baseRevision: page.revision, spaceID: spaceID ?? page.spaceID)
            reload(); saveError = nil; lastSaved = Date(); return copy.id
        } catch { saveError = "Die Vorlage konnte nicht verwendet werden: \(error.localizedDescription)"; return nil }
    }
}
