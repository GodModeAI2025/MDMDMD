import Foundation
import Testing
@testable import SkriptumCore

private let imagePixel = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=")!

@Test @MainActor func imageBlockMiddleInsertionPreservesCRLFAndStableIDs() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try LibraryStore(directory: root)
    let space = try store.createSpace(title: "S")
    let page = try store.createPage(spaceID: space.id, title: "P", markdown: "A\r\n\r\nB\r\n\r\nC")
    let result = try store.addImageBlock(pageID: page.id, data: imagePixel, mediaType: "image/png", filename: "pixel.png", altText: "a[b]\\c\r\nd", afterBlockID: page.blocks[0].id, baseRevision: page.revision)
    #expect(result.page.blocks.count == 4)
    #expect(result.page.blocks[0] == page.blocks[0])
    #expect(result.page.blocks[2] == page.blocks[1])
    #expect(result.page.blocks[3] == page.blocks[2])
    #expect(result.page.blocks[1].markdown == "![a\\[b\\]\\\\c d](" + result.attachment.relativePath + ")\r\n\r\n")
    #expect(result.page.attachments == [result.attachment])
    #expect(store.snapshot.revisions.count == 1)
    #expect(try store.attachmentData(result.attachment) == imagePixel)
    #expect(try LibraryStore(directory: root).snapshot == store.snapshot)
}

@Test @MainActor func imageBlockFailuresDoNotPublishOrLeaveMedia() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try LibraryStore(directory: root)
    let space = try store.createSpace(title: "S")
    let page = try store.createPage(spaceID: space.id, title: "P", markdown: "End")
    let before = store.snapshot
    #expect(throws: LibraryError.missingBlock) { try store.addImageBlock(pageID: page.id, data: imagePixel, mediaType: "image/png", filename: "p.png", altText: "", afterBlockID: UUID(), baseRevision: page.revision) }
    for data in [Data("bad".utf8), Data(count: MediaValidation.maximumBytes + 1)] {
        #expect(throws: LibraryError.invalidAttachment) { try store.addImageBlock(pageID: page.id, data: data, mediaType: "image/png", filename: "p.png", altText: "", afterBlockID: nil, baseRevision: page.revision) }
    }
    #expect(store.snapshot == before)
    #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("media").path))
    try FileManager.default.removeItem(at: root.appendingPathComponent("library.json"))
    try FileManager.default.createDirectory(at: root.appendingPathComponent("library.json"), withIntermediateDirectories: false)
    #expect(throws: (any Error).self) { try store.addImageBlock(pageID: page.id, data: imagePixel, mediaType: "image/png", filename: "p.png", altText: "", afterBlockID: nil, baseRevision: page.revision) }
    #expect(store.snapshot == before)
    #expect(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("media").path).isEmpty)
}

@Test @MainActor func imageBlockAppendAddsSeparatorInsideNewBlockOnly() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try LibraryStore(directory: root)
    let space = try store.createSpace(title: "S")
    let page = try store.createPage(spaceID: space.id, title: "P", markdown: "End\r\n")
    let result = try store.addImageBlock(pageID: page.id, data: imagePixel, mediaType: "image/png", filename: "p.png", altText: "", afterBlockID: nil, baseRevision: page.revision)
    #expect(result.page.blocks[0] == page.blocks[0])
    #expect(result.page.blocks[1].markdown.hasPrefix("\r\n![]("))
    #expect(result.page.markdown.hasPrefix("End\r\n\r\n![]("))
}
