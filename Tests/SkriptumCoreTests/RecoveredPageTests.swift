import Foundation
import Testing
@testable import SkriptumCore

@Test @MainActor func recoveredCopyKeepsMediaAndMetadataAfterLibrarySwitch() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let source = try LibraryStore(directory: root.appendingPathComponent("source"))
    let space = try source.createSpace(title: "S")
    let original = try source.createPage(spaceID: space.id, title: "Draft")
    let data = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=")!
    let attachment = try source.addAttachment(pageID: original.id, data: data, mediaType: "image/png", filename: "image.png", baseRevision: original.revision)
    var draft = source.snapshot.pages[0]
    draft.blocks = [Block(markdown: "e\u{301}\r\n![image](" + attachment.relativePath + ")")]
    draft.assistantRules = "Rules"; draft.reusablePrompts = [ReusablePrompt(title: "P", text: "Prompt")]; draft.wordGoal = 321; draft.tags = ["T"]; draft.isFavorite = true
    let archive = root.appendingPathComponent("recovery")
    try source.archiveAttachments(draft.attachments ?? [], to: archive)
    try FileManager.default.removeItem(at: source.directory)
    let target = try LibraryStore(directory: root.appendingPathComponent("target"))
    let targetSpace = try target.createSpace(title: "New")
    let restored = try target.createRecoveredPage(from: draft, spaceID: targetSpace.id, mediaRoot: archive)
    #expect(restored.id != draft.id)
    #expect(Array(restored.markdown.utf8) == Array(draft.markdown.utf8))
    #expect(restored.attachments == draft.attachments)
    #expect(restored.assistantRules == draft.assistantRules)
    #expect(restored.reusablePrompts == draft.reusablePrompts)
    #expect(restored.wordGoal == 321 && restored.isFavorite && restored.tags == ["T"])
    #expect(try target.attachmentData(attachment) == data)
    #expect(try LibraryStore(directory: target.directory).snapshot == target.snapshot)
}

@Test @MainActor func recoveredCopyNeverPublishesMissingMediaOrFailedMetadata() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let target = try LibraryStore(directory: root)
    let space = try target.createSpace(title: "S")
    var draft = Page(spaceID: space.id, title: "Draft", markdown: "![missing](media/x)")
    draft.attachments = [MediaAttachment(filename: "missing.png", mediaType: "image/png", byteCount: 1, sha256: "bad")]
    let before = target.snapshot
    #expect(throws: (any Error).self) { try target.createRecoveredPage(from: draft, spaceID: space.id, mediaRoot: root.appendingPathComponent("missing")) }
    #expect(target.snapshot == before)
    draft.attachments = nil
    try FileManager.default.removeItem(at: root.appendingPathComponent("library.json"))
    try FileManager.default.createDirectory(at: root.appendingPathComponent("library.json"), withIntermediateDirectories: false)
    #expect(throws: (any Error).self) { try target.createRecoveredPage(from: draft, spaceID: space.id, mediaRoot: root) }
    #expect(target.snapshot == before)
}

@Test @MainActor func recoveredCopyRollsBackNewMediaOnCommitFailureAndSupportsVerifiedLegacyFallback() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let source = try LibraryStore(directory: root.appendingPathComponent("source"))
    let space = try source.createSpace(title: "S")
    let page = try source.createPage(spaceID: space.id, title: "P")
    let data = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=")!
    let attachment = try source.addAttachment(pageID: page.id, data: data, mediaType: "image/png", filename: "image.png", baseRevision: page.revision)
    let draft = source.snapshot.pages[0]
    let target = try LibraryStore(directory: root.appendingPathComponent("target"))
    let destinationSpace = try target.createSpace(title: "D")
    let absentRecovery = root.appendingPathComponent("old-recovery")
    let restored = try target.createRecoveredPage(from: draft, spaceID: destinationSpace.id, mediaRoot: absentRecovery, fallbackMediaRoot: source.directory)
    #expect(restored.attachments == [attachment])
    #expect(try target.attachmentData(attachment) == data)
    let failing = try LibraryStore(directory: root.appendingPathComponent("failing"))
    let failingSpace = try failing.createSpace(title: "F")
    let before = failing.snapshot
    try FileManager.default.removeItem(at: failing.directory.appendingPathComponent("library.json"))
    try FileManager.default.createDirectory(at: failing.directory.appendingPathComponent("library.json"), withIntermediateDirectories: false)
    #expect(throws: (any Error).self) { try failing.createRecoveredPage(from: draft, spaceID: failingSpace.id, mediaRoot: source.directory) }
    #expect(failing.snapshot == before)
    #expect(!FileManager.default.fileExists(atPath: failing.directory.appendingPathComponent(attachment.relativePath).path))
    #expect(try source.attachmentData(attachment) == data)
}
