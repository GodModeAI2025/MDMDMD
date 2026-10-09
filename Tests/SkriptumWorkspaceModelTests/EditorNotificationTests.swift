import Foundation
import Testing
import SkriptumCore
@testable import SkriptumWorkspaceModel
@MainActor struct EditorNotificationTests {
    private func fixture() throws -> (URL, LibraryStore, WritingLibrary, WritingPage) {
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
        let documents = root.appending(path:"Documents"), store = try LibraryStore(directory: documents.appending(path:"Skriptum"))
        let space = try store.createSpace(title:"S")
        _ = try store.createPage(spaceID:space.id,title:"Base",markdown:"baseline\r\n")
        let library = try WritingLibrary(store:store,documentRoot:documents,supportRoot:root.appending(path:"Support"),preferences:UserDefaults(suiteName:UUID().uuidString)!)
        return (root,store,library,library.pages[0])
    }
    @Test func queuedPartialWithLatestRevisionCannotOverwriteCurrentJournal() throws {
        let (root,store,library,base) = try fixture(); defer { try? FileManager.default.removeItem(at:root) }
        var full = base; full.markdown = "full 😀 e\u{301} latest\r\n"
        let result = try #require(library.processEditorNotification(previous:base,changed:full,currentDraft:full,token:nil))
        full.revision = try #require(result.revision)
        let before = store.snapshot, recoveryCount = library.recoveries.count
        var queued = full; queued.markdown = "full 😀"
        let rejected = library.processEditorNotification(previous:base,changed:queued,currentDraft:full,token:result.token)
        #expect(rejected == nil)
        #expect(store.snapshot == before)
        #expect(store.snapshot.pages[0].markdown.utf8.elementsEqual(full.markdown.utf8))
        #expect(library.recoveries.count == recoveryCount)
        #expect(library.finishTyping(result.token))
        let disk = try JSONDecoder().decode(LibrarySnapshot.self,from:Data(contentsOf:store.directory.appending(path:"library.json")))
        #expect(disk.pages[0].markdown.utf8.elementsEqual(full.markdown.utf8))
    }
    @Test func currentRestoreAndTitleAreAcceptedStaleTitleIgnored() throws {
        let (root,store,library,base) = try fixture(); defer { try? FileManager.default.removeItem(at:root) }
        var changed = base; changed.markdown = "AI/source accepted\r\n"
        let saved = try #require(library.processEditorNotification(previous:base,changed:changed,currentDraft:changed,token:nil))
        changed.revision = try #require(saved.revision)
        var restored = changed; restored.markdown = base.markdown
        let restore = try #require(library.processEditorNotification(previous:changed,changed:restored,currentDraft:restored,token:saved.token))
        #expect(store.snapshot.pages[0].markdown.utf8.elementsEqual(base.markdown.utf8))
        restored.revision = try #require(restore.revision)
        var renamed = restored; renamed.title = "Current title"
        let metadata = try #require(library.processEditorNotification(previous:restored,changed:renamed,currentDraft:renamed,token:restore.token))
        #expect(metadata.token == nil)
        renamed.revision = try #require(metadata.revision)
        #expect(store.snapshot.pages[0].title == "Current title")
        var stale = renamed; stale.title = "Queued title"
        let snapshot = store.snapshot
        #expect(library.processEditorNotification(previous:restored,changed:stale,currentDraft:renamed,token:nil) == nil)
        #expect(store.snapshot == snapshot)
    }
    @Test func finishedMetadataSessionClearsTokenEvenWhenWriteFails() throws {
        let (root,store,library,base) = try fixture(); defer { try? FileManager.default.removeItem(at:root) }
        var text = base; text.markdown = "pending text\r\n"
        let saved = try #require(library.processEditorNotification(previous:base,changed:text,currentDraft:text,token:nil))
        text.revision = try #require(saved.revision)
        var metadata = text; metadata.title = "Unsaved title"; metadata.revision = UUID()
        let result = try #require(library.processEditorNotification(previous:text,changed:metadata,currentDraft:metadata,token:saved.token))
        #expect(result.token == nil && result.revision == nil)
        #expect(store.snapshot.pages[0].title == base.title)
        let next = try store.beginEditing(pageID:base.id,baseRevision:store.snapshot.pages[0].revision)
        try store.finishEditing(next)
    }

}
