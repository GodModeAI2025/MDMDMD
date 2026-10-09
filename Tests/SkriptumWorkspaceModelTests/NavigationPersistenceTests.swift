import Foundation
import Testing
import SkriptumCore
@testable import SkriptumWorkspaceModel

@MainActor struct NavigationPersistenceTests {
    private func fixture() throws -> (URL, LibraryStore, WritingLibrary, WritingPage) {
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
        let store = try LibraryStore(directory: root.appending(path: "Documents/Skriptum"))
        let space = try store.createSpace(title: "Test")
        _ = try store.createPage(spaceID: space.id, title: "Draft", markdown: "baseline\r\n")
        let library = try WritingLibrary(store: store, documentRoot: root.appending(path: "Documents"), supportRoot: root.appending(path: "Support"), preferences: UserDefaults(suiteName: UUID().uuidString)!)
        return (root, store, library, library.pages[0])
    }
    @Test func missingJournalTokenStillPersistsDraftBeforeNavigation() throws {
        let (root, store, library, baseline) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        try Data("blocked".utf8).write(to: store.directory.appending(path: "edits"))
        var draft = baseline; draft.markdown = "edited 😀 e\u{301}\r\n"
        #expect(library.updateText(draft, token: nil) == nil)
        #expect(store.snapshot.pages[0].revision == baseline.revision)
        #expect(library.persistBeforeNavigation(draft, token: nil))
        let disk = try JSONDecoder().decode(LibrarySnapshot.self, from: Data(contentsOf: store.directory.appending(path: "library.json")))
        #expect(disk.pages[0].markdown.utf8.elementsEqual(draft.markdown.utf8))
    }
    @Test func trashTargetRequiresExplicitAccessAndRemainsDurablyTrashed() throws {
        let (root, store, library, baseline) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        try store.trashPage(baseline.id)
        library.reload()
        let target = PageLinkTarget(pageID: baseline.id)
        #expect(library.resolvePageTarget(target) == nil)
        let resolved = try #require(library.resolvePageTarget(target, allowTrashed: true))
        #expect(resolved.page.trashed)
        #expect(resolved.page.markdown.utf8.elementsEqual(baseline.markdown.utf8))
        #expect(library.persistBeforeNavigation(resolved.page, token: nil))
        let disk = try JSONDecoder().decode(LibrarySnapshot.self, from: Data(contentsOf: store.directory.appending(path: "library.json")))
        #expect(disk.pages[0].trashedAt != nil)
        #expect(disk.pages[0].revision == resolved.page.revision)
    }
    @Test func failedDurableCommitBlocksNavigationAndSameRevisionDraftIsRecovered() throws {
        let (root, store, library, baseline) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        try Data("blocked".utf8).write(to: store.directory.appending(path: "edits"))
        var draft = baseline; draft.markdown = "must survive\r\n"
        #expect(library.updateText(draft, token: nil) == nil)
        let json = store.directory.appending(path: "library.json")
        try FileManager.default.removeItem(at: json); try FileManager.default.createDirectory(at: json, withIntermediateDirectories: true)
        #expect(!library.persistBeforeNavigation(draft, token: nil))
        #expect(library.preserveConflictedDraft(draft))
        #expect(library.recoveries.count == 1)
        #expect(library.recoveries[0].page.markdown.utf8.elementsEqual(draft.markdown.utf8))
        #expect(store.snapshot.pages[0].markdown.utf8.elementsEqual(baseline.markdown.utf8))
    }
}
