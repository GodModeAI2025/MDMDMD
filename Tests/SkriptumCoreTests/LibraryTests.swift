import Foundation
import Testing
@testable import SkriptumCore

@Test @MainActor func persistenceAndHierarchy() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try LibraryStore(directory: directory)
    let space = try store.createSpace(title: "Roman")
    let parent = try store.createPage(spaceID: space.id, title: "Kapitel", markdown: "Grüße 👨‍👩‍👧‍👦")
    let child = try store.createPage(spaceID: space.id, parentID: parent.id, title: "Recherche")
    #expect(throws: LibraryError.hierarchyCycle) { try store.movePage(parent.id, parentID: child.id) }
    try store.trashPage(parent.id)
    #expect(store.snapshot.pages.allSatisfy { $0.trashedAt != nil })
    try store.restorePage(parent.id)
    let reopened = try LibraryStore(directory: directory)
    #expect(reopened.snapshot == store.snapshot)
    #expect(reopened.snapshot.pages.first?.markdown == "Grüße 👨‍👩‍👧‍👦")
}

@Test @MainActor func patchesAreAtomicAndScoped() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try LibraryStore(directory: directory)
    let space = try store.createSpace(title: "Space")
    let page = try store.createPage(spaceID: space.id, title: "Seite", markdown: "Alt 🦊")
    let block = page.blocks[0]
    let initial = store.snapshot
    let invalid = PagePatch(pageID: page.id, baseRevision: page.revision, allowedBlockIDs: [block.id], operations: [.replace(blockID: block.id, markdown: "Neu"), .replace(blockID: UUID(), markdown: "Unerlaubt")])
    #expect(throws: LibraryError.forbiddenBlock) { try store.apply(invalid) }
    #expect(store.snapshot == initial)
    try store.apply(PagePatch(pageID: page.id, baseRevision: page.revision, allowedBlockIDs: [block.id], operations: [.replace(blockID: block.id, markdown: "Neu 👨‍👩‍👧‍👦")]))
    #expect(store.snapshot.pages[0].markdown == "Neu 👨‍👩‍👧‍👦")
    #expect(throws: LibraryError.revisionConflict) { try store.apply(invalid) }
    #expect(store.snapshot.revisions.count == 1)
}

@Test @MainActor func rejectedOperationsDoNotPersist() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try LibraryStore(directory: directory)
    #expect(throws: LibraryError.missingSpace) { try store.createPage(spaceID: UUID(), title: "invalid") }
    #expect(store.snapshot.pages.isEmpty)
}

@Test @MainActor func diskFailureDoesNotPublishMutation() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = try LibraryStore(directory: directory)
    let space = try store.createSpace(title: "Original")
    let before = store.snapshot
    try FileManager.default.removeItem(at: directory)
    #expect(throws: (any Error).self) { try store.renameSpace(space.id, title: "Not saved") }
    #expect(store.snapshot == before)
}

@Test @MainActor func noOpAndTrashedParentValidation() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try LibraryStore(directory: directory)
    let space = try store.createSpace(title: "Project")
    let page = try store.createPage(spaceID: space.id, title: "Parent")
    try store.renamePage(page.id, title: page.title)
    #expect(store.snapshot.revisions.isEmpty)
    try store.trashPage(page.id)
    #expect(throws: LibraryError.trashedParent) { try store.createPage(spaceID: space.id, parentID: page.id, title: "Child") }
}

@Test @MainActor func revisionRestorationIsConflictChecked() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try LibraryStore(directory: directory)
    let space = try store.createSpace(title: "Project")
    let page = try store.createPage(spaceID: space.id, title: "Page", markdown: "Original")
    try store.setMarkdown(page.id, markdown: "Changed", baseRevision: page.revision)
    #expect(throws: LibraryError.revisionConflict) { try store.restoreRevision(pageID: page.id, revisionID: page.revision, baseRevision: page.revision) }
    try store.restoreRevision(pageID: page.id, revisionID: page.revision, baseRevision: store.snapshot.pages[0].revision)
    #expect(store.snapshot.pages[0].markdown == "Original")
}

@Test func losslessStableParagraphReconciliation() {
    let text = "# Überschrift\r\n\r\nGrüße 👨‍👩‍👧‍👦 e\u{301}\n\n```swift\n\nprint(1)\n```\n\nEnde\n"
    let before = MarkdownReconciler.reconcile(text, previous: [])
    #expect(before.map(\.markdown).joined() == text)
    let changed = text.replacingOccurrences(of: "Grüße", with: "Hallo")
    let after = MarkdownReconciler.reconcile(changed, previous: before)
    #expect(after.map(\.markdown).joined() == changed)
    #expect(after.map(\.id) == before.map(\.id))
    #expect(after.contains(where: { $0.markdown.contains("```swift\n\nprint(1)\n```") }))
}

@Test func identicalParagraphsKeepDistinctStableIDs() {
    let before = MarkdownReconciler.reconcile("gleich\n\ngleich\n\nEnde", previous: [])
    let after = MarkdownReconciler.reconcile("Neu\n\ngleich\n\ngleich\n\nEnde", previous: before)
    #expect(Set(after.map(\.id)).count == after.count)
    #expect(Array(after.dropFirst().map(\.id)) == before.map(\.id))
}

@Test @MainActor func coalescedTypingRecoversWithoutLibraryRewrite() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try LibraryStore(directory: directory)
    let space = try store.createSpace(title: "Space")
    let page = try store.createPage(spaceID: space.id, title: "Page", markdown: "Original\n\nUnchanged")
    let originalFile = try Data(contentsOf: directory.appendingPathComponent("library.json"))
    let token = try store.beginEditing(pageID: page.id, baseRevision: page.revision)
    try store.updateEditing(token, markdown: "One\n\nUnchanged")
    try store.updateEditing(token, markdown: "Two 🦊\n\nUnchanged")
    #expect(store.snapshot.revisions.isEmpty)
    #expect(try Data(contentsOf: directory.appendingPathComponent("library.json")) == originalFile)
    #expect(store.snapshot.pages[0].blocks[1].id == page.blocks[1].id)
    let recovered = try LibraryStore(directory: directory)
    #expect(recovered.snapshot.pages[0].markdown == "Two 🦊\n\nUnchanged")
    #expect(recovered.snapshot.revisions.count == 1)
    #expect(recovered.snapshot.revisions[0].page == page)
}

@Test @MainActor func selectionScopeSurvivesSourceEdit() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try LibraryStore(directory: directory)
    let space = try store.createSpace(title: "Space")
    let page = try store.createPage(spaceID: space.id, title: "Page", markdown: "First\n\nTarget\n\nLast")
    let targetID = page.blocks[1].id
    try store.addComment(Comment(pageID: page.id, blockID: targetID, body: "Keep", author: "User"))
    try store.setMarkdown(page.id, markdown: "Changed\n\nTarget\n\nLast", baseRevision: page.revision)
    let current = store.snapshot.pages[0]
    try store.apply(PagePatch(pageID: page.id, baseRevision: current.revision, allowedBlockIDs: [targetID], operations: [.replace(blockID: targetID, markdown: "Revised\n\n")]))
    #expect(store.snapshot.pages[0].markdown == "Changed\n\nRevised\n\nLast")
    #expect(store.snapshot.comments[0].blockID == targetID)
}

@Test @MainActor func typingSessionFinishesAsOneRevision() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try LibraryStore(directory: directory)
    let space = try store.createSpace(title: "Space")
    let page = try store.createPage(spaceID: space.id, title: "Page", markdown: "Before")
    let token = try store.beginEditing(pageID: page.id, baseRevision: page.revision)
    try store.updateEditing(token, markdown: "A")
    #expect(throws: LibraryError.editInProgress) { try store.renamePage(page.id, title: "Blocked") }
    try store.updateEditing(token, markdown: "After")
    try store.finishEditing(token)
    #expect(store.snapshot.revisions.count == 1)
    #expect(store.snapshot.revisions[0].page.markdown == "Before")
    let reopened = try LibraryStore(directory: directory)
    #expect(reopened.snapshot == store.snapshot)
}

@Test @MainActor func canonicalEquivalentUnicodeStillPreservesChangedBytes() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try LibraryStore(directory: directory)
    let space = try store.createSpace(title: "Unicode")
    let page = try store.createPage(spaceID: space.id, title: "Page", markdown: "é")
    let decomposed = "e\u{301}"
    try store.setMarkdown(page.id, markdown: decomposed, baseRevision: page.revision)
    #expect(Array(store.snapshot.pages[0].markdown.utf8) == Array(decomposed.utf8))
    #expect(store.snapshot.pages[0].revision != page.revision)
}

@Test @MainActor func unrelatedCommitsCannotBreakActiveJournalRecovery() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try LibraryStore(directory: directory)
    let space = try store.createSpace(title: "Space")
    let page = try store.createPage(spaceID: space.id, title: "Page", markdown: "A0")
    let token = try store.beginEditing(pageID: page.id, baseRevision: page.revision)
    try store.updateEditing(token, markdown: "A1")
    try store.createSpace(title: "Unrelated durable mutation")
    try store.addComment(Comment(pageID: page.id, blockID: page.blocks[0].id, body: "Comment", author: "User"))
    try store.updateEditing(token, markdown: "A2")
    let recovered = try LibraryStore(directory: directory)
    #expect(recovered.snapshot.pages[0].markdown == "A2")
    #expect(recovered.snapshot.spaces.count == 2)
    #expect(recovered.snapshot.comments.count == 1)
    #expect(recovered.snapshot.revisions.count == 1)
    #expect(recovered.snapshot.revisions[0].page.markdown == "A0")
}
