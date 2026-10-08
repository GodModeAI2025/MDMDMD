import Foundation
import Testing
@testable import SkriptumCore

@Test @MainActor func movedSourceBlockRetainsCommentAnchorAfterReopen() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try LibraryStore(directory: root)
    let space = try store.createSpace(title: "S")
    let page = try store.createPage(spaceID: space.id, title: "P", markdown: "A\n\nB\n\nC\n\n")
    let moved = page.blocks[2]
    try store.addComment(Comment(pageID: page.id, blockID: moved.id, body: "C comment", author: "U"))
    try store.setMarkdown(page.id, markdown: "C\n\nA\n\nB\n\n", baseRevision: page.revision)
    let reopened = try LibraryStore(directory: root)
    #expect(reopened.snapshot.pages[0].blocks.map(\.id) == [moved.id, page.blocks[0].id, page.blocks[1].id])
    #expect(reopened.snapshot.comments[0].blockID == moved.id)
}

@Test @MainActor func suppliedBlockOrderSurvivesJournalRecoveryAndRejectsDuplicateIDs() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try LibraryStore(directory: root)
    let space = try store.createSpace(title: "S")
    let page = try store.createPage(spaceID: space.id, title: "P", markdown: "same\n\nsame\n\n")
    let token = try store.beginEditing(pageID: page.id, baseRevision: page.revision)
    let reordered = Array(page.blocks.reversed())
    try store.updateEditing(token, blocks: reordered)
    #expect(throws: LibraryError.duplicateBlock) { try store.updateEditing(token, blocks: [page.blocks[0], page.blocks[0]]) }
    #expect(store.snapshot.pages[0].blocks == reordered)
    let reopened = try LibraryStore(directory: root)
    #expect(reopened.snapshot.pages[0].blocks == reordered)
    #expect(reopened.snapshot.revisions.count == 1)
    #expect(Set(reopened.snapshot.pages[0].blocks.map(\.id)).count == 2)
}

@Test @MainActor func setBlocksChecksConflictAndExactSource() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try LibraryStore(directory: root)
    let space = try store.createSpace(title: "S")
    let page = try store.createPage(spaceID: space.id, title: "P", markdown: "é")
    let block = Block(id: page.blocks[0].id, markdown: "e\u{301}\r\n")
    try store.setBlocks(pageID: page.id, blocks: [block], baseRevision: page.revision)
    #expect(Array(store.snapshot.pages[0].markdown.utf8) == Array(block.markdown.utf8))
    #expect(throws: LibraryError.revisionConflict) { try store.setBlocks(pageID: page.id, blocks: [], baseRevision: page.revision) }
}
