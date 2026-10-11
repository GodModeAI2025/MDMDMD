import Foundation
import Testing
import SkriptumCore
@testable import SkriptumWorkspaceModel

@MainActor struct AtomicWritingPageTests {
    private func fixture() throws -> (URL, LibraryStore, WritingLibrary, WritingPage) {
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
        let store = try LibraryStore(directory: root.appending(path: "Documents/Skriptum"))
        let space = try store.createSpace(title: "Book")
        _ = try store.createPage(spaceID: space.id, title: "Original", markdown: "Baseline\r\n")
        let library = try WritingLibrary(store: store, documentRoot: root.appending(path: "Documents"), supportRoot: root.appending(path: "Support"), preferences: UserDefaults(suiteName: UUID().uuidString)!)
        return (root, store, library, library.pages[0])
    }
    @Test func invalidCombinedChangeDoesNotPartiallyRenameOrTrash() throws {
        let (root, store, library, baseline) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let before = store.snapshot, bytes = try Data(contentsOf: store.directory.appending(path: "library.json"))
        var draft = baseline; draft.title = "Must roll back"; draft.trashed = true; draft.purpose = .material
        #expect(library.update(draft) == nil)
        #expect(store.snapshot == before)
        #expect(try Data(contentsOf: store.directory.appending(path: "library.json")) == bytes)
    }
    @Test func combinedSavePublishesOnceAndRetainsOneHistoricalBaseline() throws {
        let (root, store, library, baseline) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        var notifications = 0
        store.onDurableChange = { _ in notifications += 1 }
        var draft = baseline; draft.title = "New"; draft.markdown = "e\u{301} 🦊\r\n"; draft.favorite = true
        draft.tags = ["b", "a", "a"]; draft.wordGoal = 42; draft.purpose = .material
        #expect(library.update(draft) != nil)
        #expect(notifications == 1)
        #expect(store.snapshot.revisions.count == 1)
        let page = try #require(store.snapshot.pages.first)
        #expect(page.title == "New" && page.isFavorite && page.wordGoal == 42 && page.purpose == .material)
        #expect(page.markdown.utf8.elementsEqual(draft.markdown.utf8))
        #expect(page.tags == ["a", "b"])
        #expect(store.snapshot.revisions.first?.page.title == "Original")
    }
    @Test func invalidPromptListDoesNotPersistPageOrSpaceRules() throws {
        let (root, store, library, baseline) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let before = store.snapshot
        let prompt = ReusablePrompt(title: "One", text: "Text")
        #expect(library.savePageTools(pageID: baseline.id, baseRevision: baseline.revision, rules: "Must not persist", prompts: [prompt, prompt]) == nil)
        #expect(store.snapshot == before)
        library.saveSpaceTools(spaceID: baseline.spaceID, rules: "Must not persist", prompts: [prompt, prompt])
        #expect(store.snapshot == before)
    }
}

extension AtomicWritingPageTests {
    @Test func rejectedNativeBlocksAreDurableRecoveryWithoutPublishingOverCurrentPage() throws {
        let (root, store, library, baseline) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        var newer = baseline; newer.markdown = "Committed foreign 🦊\r\n"; newer.title = "Current title"
        #expect(library.update(newer) != nil)
        let before = store.snapshot, file = store.directory.appendingPathComponent("library.json")
        let bytes = try Data(contentsOf: file)
        var notifications = 0
        store.onDurableChange = { _ in notifications += 1 }
        let rejected = [Block(markdown: "# Native e\u{301} 🦊\r\n\r\nDraft\r\n")]
        #expect(library.preserveRejectedBlocks(rejected, page: baseline))
        #expect(store.snapshot == before && notifications == 0)
        #expect(try Data(contentsOf: file) == bytes)
        let copied = try #require(library.recoveries.last)
        #expect(copied.value.title == "Current title")
        #expect(copied.value.markdown.utf8.elementsEqual(rejected[0].markdown.utf8))
        #expect(copied.value.blockDraft?.map(\.id) == rejected.map(\.id))
        let reopened = try WritingLibrary(store: LibraryStore(directory: store.directory), documentRoot: root.appending(path: "Documents"), supportRoot: root.appending(path: "Support"), preferences: UserDefaults(suiteName: UUID().uuidString)!)
        #expect(reopened.recoveries.contains { $0.id == copied.id && $0.value == copied.value })
    }
    @Test(arguments: [true, false])
    func successfulCreationClearsPriorFailureAndPublishesSaveTime(createSpace: Bool) throws {
        let (root, store, library, baseline) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(library.createPage(spaceID: UUID()) == nil)
        #expect(library.saveError != nil && library.lastSaved == nil)
        let started = Date()
        let id = try #require(createSpace ? library.createSpace(title: "New project") : library.createPage(spaceID: baseline.spaceID))
        #expect(library.saveError == nil)
        let saved = try #require(library.lastSaved)
        #expect(saved >= started)
        let reopened = try LibraryStore(directory: store.directory)
        if createSpace {
            #expect(library.spaces.contains { $0.id == id })
            #expect(reopened.snapshot.spaces.contains { $0.id == id })
        } else {
            #expect(library.pages.contains { $0.id == id })
            #expect(reopened.snapshot.pages.contains { $0.id == id })
        }
    }

    @Test func combinedTrashChangesDescendantsInTheSameCommit() throws {
        let (root, store, library, baseline) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let child = try store.createPage(spaceID: baseline.spaceID, parentID: baseline.id, title: "Child", markdown: "Child 🦊")
        var notifications = 0
        store.onDurableChange = { _ in notifications += 1 }
        var draft = baseline; draft.title = "Trashed title"; draft.trashed = true
        #expect(library.update(draft) != nil)
        #expect(notifications == 1)
        #expect(store.snapshot.pages.allSatisfy { $0.trashedAt != nil })
        #expect(store.snapshot.pages.first(where: { $0.id == child.id })?.markdown == "Child 🦊")
        #expect(store.snapshot.revisions.count == 2)
        #expect(store.snapshot.revisions.first(where: { $0.page.id == baseline.id })?.page.title == "Original")
    }
    @Test func validAssistantConfigurationIsOneRevisionAndNoOpOnRetry() throws {
        let (root, store, library, baseline) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        var notifications = 0
        store.onDurableChange = { _ in notifications += 1 }
        let prompt = ReusablePrompt(title: "Prompt e\u{301}", text: "Keep 🦊\r\n")
        let saved = try #require(library.savePageTools(pageID: baseline.id, baseRevision: baseline.revision, rules: "Rules 🦊", prompts: [prompt]))
        #expect(notifications == 1 && store.snapshot.revisions.count == 1)
        #expect(library.savePageTools(pageID: baseline.id, baseRevision: saved.revision, rules: "Rules 🦊", prompts: [prompt]) != nil)
        #expect(notifications == 1 && store.snapshot.revisions.count == 1)
    }
}
