import Foundation
import Testing
@testable import SkriptumCore

@Test @MainActor func trashedTargetPatchRejectsWithoutDiskOrHistoryMutationAndRestoredTargetAccepts() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try LibraryStore(directory: directory)
    let space = try store.createSpace(title: "Space")
    let page = try store.createPage(spaceID: space.id, title: "Page", markdown: "Original 🦊")
    let blockID = page.blocks[0].id
    func patch(_ page: Page, text: String) -> PagePatch {
        PagePatch(pageID: page.id, baseRevision: page.revision, allowedBlockIDs: [blockID], operations: [.replace(blockID: blockID, markdown: text)])
    }
    try store.apply(patch(page, text: "Before trash"))
    #expect(store.snapshot.pages[0].markdown == "Before trash")
    try store.trashPage(page.id)
    let trashed = try #require(store.snapshot.pages.first)
    let before = store.snapshot
    let file = directory.appendingPathComponent("library.json")
    let beforeBytes = try Data(contentsOf: file)
    #expect(throws: LibraryError.trashedPage) { try store.apply(patch(trashed, text: "Forbidden change")) }
    #expect(store.snapshot == before)
    #expect(store.snapshot.revisions == before.revisions)
    #expect(try Data(contentsOf: file) == beforeBytes)
    #expect(try LibraryStore(directory: directory).snapshot == before)
    try store.restorePage(page.id)
    let restored = try #require(store.snapshot.pages.first)
    try store.apply(patch(restored, text: "After restore"))
    #expect(store.snapshot.pages[0].markdown == "After restore")
    #expect(store.snapshot.revisions.count == before.revisions.count + 2)
    #expect(try LibraryStore(directory: directory).snapshot == store.snapshot)
}
