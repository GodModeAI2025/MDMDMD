import Foundation
#if canImport(SkriptumCore)
import SkriptumCore
#endif
#if canImport(SkriptumExport)
import SkriptumExport
#endif

@MainActor final class EditorNavigationGuard {
    private var key: String?
    private var action: (() -> Bool)?
    func register(key: String, action: @escaping () -> Bool) { self.key = key; self.action = action }
    func unregister(key: String) { if self.key == key { self.key = nil; action = nil } }
    func prepare() -> Bool { action?() ?? true }
}

struct WritingHeadingJump: Identifiable {
    let id = UUID()
    let pageID: UUID
    let revision: UUID
    let offset: Int
}

extension WritingLibrary {
    /// Current private libraries are owned in full. Shared-library callers must
    /// supply a permission-filtered snapshot before this UI exposes those pages.
    func resolvePageTarget(_ target: PageLinkTarget, allowTrashed: Bool = false) -> (page: WritingPage, offset: Int?)? {
        guard let store, let raw = store.snapshot.pages.first(where: { $0.id == target.pageID }),
              (raw.trashedAt == nil || allowTrashed), store.snapshot.spaces.contains(where: { $0.id == raw.spaceID }) else {
            saveError = "Die Zielseite ist nicht verfügbar."; return nil
        }
        var offset: Int?
        if target.heading != nil {
            let index = PageLinkIndex(libraryID: libraryIdentity, spaceID: raw.spaceID, pages: [raw])
            guard case .resolved(_, let heading?) = index.resolve(target),
                  let range = heading.span?.utf16Range(in: raw.markdown) else {
                saveError = "Die verlinkte Überschrift ist nicht mehr verfügbar."; return nil
            }
            offset = range.location
        }
        reload()
        guard let page = currentPage(raw.id), page.revision == raw.revision else {
            saveError = "Das Ziel wurde inzwischen geändert. Bitte den Verweis erneut öffnen."; return nil
        }
        saveError = nil; return (page, offset)
    }
}
