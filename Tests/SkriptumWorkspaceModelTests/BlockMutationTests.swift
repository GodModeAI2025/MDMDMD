import Foundation
import Testing
import SkriptumCore
@testable import SkriptumWorkspaceModel

@MainActor struct BlockMutationTests {
    private func fixture() throws -> (URL, LibraryStore, WritingLibrary, UUID, [Block]) {
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
        let store = try LibraryStore(directory: root.appending(path: "Documents/Skriptum"))
        let space = try store.createSpace(title: "Book")
        let page = try store.createPage(spaceID: space.id, title: "Tables")
        let blocks = [Block(markdown: "# 😀 e\u{301}\r\n\r\n"), Block(markdown: "| 名 | Wert |\r\n| --- | ---: |\r\n| a\\|b | 7 |\r\n\r\n"), Block(markdown: "untouched\r\n")]
        try store.setBlocks(pageID: page.id, blocks: blocks, baseRevision: page.revision)
        let library = try WritingLibrary(store: store, documentRoot: root.appending(path: "Documents"), supportRoot: root.appending(path: "Support"), preferences: UserDefaults(suiteName: UUID().uuidString)!)
        return (root, store, library, page.id, blocks)
    }
    @Test func tableCommitAndUndoPreserveIDsAndAdjacentBytesOnDisk() throws {
        let (root, store, library, id, blocks) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let old = try #require(library.currentPage(id))
        let replacement = blocks[1].markdown.replacingOccurrences(of: "7", with: "八😀")
        let next = try #require(library.replaceBlock(pageID: id, baseRevision: old.revision, blockID: blocks[1].id, expectedSource: blocks[1].markdown, replacement: replacement))
        let disk = try JSONDecoder().decode(LibrarySnapshot.self, from: Data(contentsOf: store.directory.appending(path: "library.json")))
        #expect(disk.pages[0].blocks.map(\.id) == blocks.map(\.id))
        #expect(disk.pages[0].blocks[0] == blocks[0] && disk.pages[0].blocks[2] == blocks[2])
        #expect(disk.pages[0].blocks[1].markdown.utf8.elementsEqual(replacement.utf8))
        let undone = try #require(library.replaceBlock(pageID: id, baseRevision: next.revision, blockID: blocks[1].id, expectedSource: replacement, replacement: blocks[1].markdown))
        #expect(undone.markdown.utf8.elementsEqual(blocks.map(\.markdown).joined().utf8))
        #expect(store.snapshot.pages[0].blocks == blocks)
    }
    @Test func staleRevisionWrongBlockBytesAndActiveTypingCannotOverwrite() throws {
        let (root, store, library, id, blocks) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let old = try #require(library.currentPage(id))
        #expect(library.replaceBlock(pageID: id, baseRevision: old.revision, blockID: blocks[1].id, expectedSource: "different", replacement: "bad") == nil)
        let token = try store.beginEditing(pageID: id, baseRevision: old.revision)
        #expect(library.replaceBlock(pageID: id, baseRevision: old.revision, blockID: blocks[1].id, expectedSource: blocks[1].markdown, replacement: "bad") == nil)
        try store.finishEditing(token)
        try store.renamePage(id, title: "Other window")
        #expect(library.replaceBlock(pageID: id, baseRevision: old.revision, blockID: blocks[1].id, expectedSource: blocks[1].markdown, replacement: "bad") == nil)
        #expect(store.snapshot.pages[0].blocks == blocks)
        #expect(library.saveError != nil)
    }
    @Test func failedAtomicWriteKeepsCurrentTableAndNoopKeepsRevision() throws {
        let (root, store, library, id, blocks) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let old = try #require(library.currentPage(id))
        let noop = try #require(library.replaceBlock(pageID: id, baseRevision: old.revision, blockID: blocks[1].id, expectedSource: blocks[1].markdown, replacement: blocks[1].markdown))
        #expect(noop.revision == old.revision)
        let json = store.directory.appending(path: "library.json")
        try FileManager.default.removeItem(at: json)
        try FileManager.default.createDirectory(at: json, withIntermediateDirectories: true)
        #expect(library.replaceBlock(pageID: id, baseRevision: old.revision, blockID: blocks[1].id, expectedSource: blocks[1].markdown, replacement: "changed") == nil)
        #expect(store.snapshot.pages[0].blocks == blocks)
        #expect(store.snapshot.pages[0].revision == old.revision)
        #expect(library.saveError != nil)
    }
}
