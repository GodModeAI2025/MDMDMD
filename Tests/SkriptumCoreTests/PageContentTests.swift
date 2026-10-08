import XCTest
@testable import SkriptumCore

@MainActor final class PageContentTests: XCTestCase {
    func testLegacyMetadataAndPackageRoundTrip() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try LibraryStore(directory: root.appendingPathComponent("source"))
        let space = try store.createSpace(title: "Space")
        let page = try store.createPage(spaceID: space.id, title: "Page", markdown: "e\u{301}\r\n")
        try store.setRules(pageID: page.id, rules: "Rules", baseRevision: page.revision)
        let child = try store.createPage(spaceID: space.id, parentID: page.id, title: "Child", markdown: "text")
        try store.setPrompts(spaceID: space.id, prompts: [ReusablePrompt(title: "Review", text: "Read carefully")])
        try store.addComment(Comment(pageID: child.id, blockID: child.blocks.first?.id, body: "Comment", author: "Writer"))
        let current = try XCTUnwrap(store.snapshot.pages.first)
        try store.setWordGoal(pageID: page.id, goal: 100, baseRevision: current.revision)
        let package = root.appendingPathComponent("Archive.scriptum")
        try store.exportPackage(to: package)
        let imported = try LibraryStore.importPackage(from: package, to: root.appendingPathComponent("imported"))
        XCTAssertEqual(imported.snapshot, store.snapshot)
        XCTAssertEqual(Array(imported.snapshot.pages[0].markdown.utf8), Array(page.markdown.utf8))
        XCTAssertThrowsError(try LibraryStore.importPackage(from: package, to: store.directory))
    }
    func testInvalidAttachmentAndConflictAreAtomic() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try LibraryStore(directory: root)
        let space = try store.createSpace(title: "S")
        let page = try store.createPage(spaceID: space.id, title: "P")
        let before = store.snapshot
        XCTAssertThrowsError(try store.addAttachment(pageID: page.id, data: Data("bad".utf8), mediaType: "image/png", filename: "x.png", baseRevision: page.revision))
        XCTAssertEqual(before, store.snapshot)
        XCTAssertThrowsError(try store.setWordGoal(pageID: page.id, goal: -1, baseRevision: page.revision))
    }
    func testMediaSurvivesRemovalAndArchiveAndRejectsTampering() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try LibraryStore(directory: root.appendingPathComponent("source"))
        let space = try store.createSpace(title: "S")
        let page = try store.createPage(spaceID: space.id, title: "P")
        let png = try XCTUnwrap(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII="))
        let attachment = try store.addAttachment(pageID: page.id, data: png, mediaType: "image/png", filename: "pixel.png", baseRevision: page.revision)
        let current = try XCTUnwrap(store.snapshot.pages.first)
        try store.removeAttachment(pageID: page.id, attachmentID: attachment.id, baseRevision: current.revision)
        XCTAssertEqual(try store.attachmentData(attachment), png)
        let before = store.snapshot
        XCTAssertThrowsError(try store.addAttachment(pageID: page.id, data: png, mediaType: "image/png", filename: "conflict.png", baseRevision: page.revision))
        XCTAssertEqual(store.snapshot, before)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: store.directory.appendingPathComponent("media").path).count, 1)
        let package = root.appendingPathComponent("media.scriptum")
        try store.exportPackage(to: package)
        let imported = try LibraryStore.importPackage(from: package, to: root.appendingPathComponent("imported"))
        XCTAssertEqual(try imported.attachmentData(attachment), png)
        try Data("tampered".utf8).write(to: package.appendingPathComponent(attachment.relativePath))
        XCTAssertThrowsError(try LibraryStore.importPackage(from: package, to: root.appendingPathComponent("bad")))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("bad").path))
    }
    func testPackageRejectsSymlinkAndUnexpectedPaths() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try LibraryStore(directory: root.appendingPathComponent("source"))
        let package = root.appendingPathComponent("x.scriptum")
        try store.exportPackage(to: package)
        try FileManager.default.createSymbolicLink(at: package.appendingPathComponent("escape"), withDestinationURL: root)
        XCTAssertThrowsError(try LibraryStore.importPackage(from: package, to: root.appendingPathComponent("new")))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("new").path))
    }
    func testMissingOptionalFieldsDecode() throws {
        let page = Page(spaceID: UUID(), title: "Old")
        let decoded = try JSONDecoder().decode(Page.self, from: JSONEncoder().encode(page))
        XCTAssertNil(decoded.wordGoal)
        XCTAssertNil(decoded.attachments)
    }
}
