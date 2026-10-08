import Foundation
import Testing
@testable import SkriptumCore

@Test @MainActor func malformedHistoricalPackagesAreRejectedBeforeDestinationCreation() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try LibraryStore(directory: root.appendingPathComponent("source"))
    let space = try store.createSpace(title: "S")
    let page = try store.createPage(spaceID: space.id, title: "P", markdown: "Original")
    try store.renamePage(page.id, title: "New")
    let package = root.appendingPathComponent("test.scriptum")
    try store.exportPackage(to: package)
    var variants: [LibrarySnapshot] = []
    var duplicate = store.snapshot; duplicate.revisions.append(duplicate.revisions[0]); variants.append(duplicate)
    var blocks = store.snapshot; blocks.revisions[0].page.blocks.append(blocks.revisions[0].page.blocks[0]); variants.append(blocks)
    var goal = store.snapshot; goal.revisions[0].page.wordGoal = -1; variants.append(goal)
    var prompts = store.snapshot; let prompt = ReusablePrompt(title: "P", text: "T"); prompts.revisions[0].page.reusablePrompts = [prompt, prompt]; variants.append(prompts)
    var media = store.snapshot; media.revisions[0].page.attachments = [MediaAttachment(filename: "../escape", mediaType: "image/png", byteCount: -1, sha256: "bad")]; variants.append(media)
    for (index, state) in variants.enumerated() {
        try JSONEncoder().encode(ScriptumPackageManifest(library: state)).write(to: package.appendingPathComponent("manifest.json"))
        let destination = root.appendingPathComponent("reject-\(index)")
        #expect(throws: LibraryError.invalidLibrary) { try LibraryStore.importPackage(from: package, to: destination) }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
    }
}

@Test @MainActor func historicalSnapshotsMayReferenceDeletedAncestorsAndSpaces() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try LibraryStore(directory: root.appendingPathComponent("source"))
    let space = try store.createSpace(title: "S")
    _ = try store.createPage(spaceID: space.id, title: "Current")
    var state = store.snapshot
    var historical = Page(spaceID: UUID(), parentID: UUID(), title: "Deleted page", markdown: "Exact\r\n")
    historical.trashedAt = Date(); historical.assistantRules = "Rules"; historical.reusablePrompts = [ReusablePrompt(title: "P", text: "T")]
    state.revisions.append(Revision(page: historical, author: "U", capturedAt: Date()))
    let package = root.appendingPathComponent("history.scriptum")
    try store.exportPackage(to: package)
    try JSONEncoder().encode(ScriptumPackageManifest(library: state)).write(to: package.appendingPathComponent("manifest.json"))
    let imported = try LibraryStore.importPackage(from: package, to: root.appendingPathComponent("imported"))
    #expect(imported.snapshot.revisions == state.revisions)
}
