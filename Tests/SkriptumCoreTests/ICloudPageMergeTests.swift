import Foundation
import Testing
@testable import SkriptumCore

@Test @MainActor func iCloudDivergentEditsPreserveBothVersionsAcrossRestart() throws {
    let root = URL(fileURLWithPath: "/private/tmp/ICloudMerge-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try LibraryStore(directory: root)
    let space = try store.createSpace(title: "Writing")
    let original = try store.createPage(spaceID: space.id, title: "Page", markdown: "Local e\u{301}\r\n🦊")
    var remote = original; remote.revision = UUID(); remote.blocks = [Block(markdown: "Remote text")]
    #expect(try store.mergeICloudPage(remote, basedOn: UUID()) == .conflictPreserved)
    let reopened = try LibraryStore(directory: root)
    #expect(reopened.snapshot.pages == [original])
    #expect(reopened.snapshot.revisions.map(\.page) == [remote])
    #expect(try reopened.mergeICloudPage(remote, basedOn: UUID()) == .unchanged)
    #expect(reopened.snapshot.revisions.count == 1)
}

@Test @MainActor func iCloudFastForwardRetainsLocalHistoryAndRejectsRevisionReuse() throws {
    let root = URL(fileURLWithPath: "/private/tmp/ICloudMerge-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try LibraryStore(directory: root)
    let space = try store.createSpace(title: "Writing")
    let original = try store.createPage(spaceID: space.id, title: "Page", markdown: "Baseline")
    var remote = original; remote.revision = UUID(); remote.blocks = [Block(markdown: "Next")]
    #expect(try store.mergeICloudPage(remote, basedOn: original.revision) == .advanced)
    #expect(store.snapshot.pages == [remote])
    #expect(store.snapshot.revisions.map(\.page) == [original])
    let bytes = try Data(contentsOf: root.appendingPathComponent("library.json"))
    var rewritten = remote; rewritten.title = "Changed under same revision"
    #expect(throws: LibraryError.invalidLibrary) { try store.mergeICloudPage(rewritten, basedOn: original.revision) }
    #expect(try Data(contentsOf: root.appendingPathComponent("library.json")) == bytes)
}

@Test @MainActor func iCloudIncomingChangeCannotOverwriteOpenJournal() throws {
    let root = URL(fileURLWithPath: "/private/tmp/ICloudMerge-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try LibraryStore(directory: root)
    let space = try store.createSpace(title: "Writing")
    let original = try store.createPage(spaceID: space.id, title: "Page", markdown: "Baseline")
    let token = try store.beginEditing(pageID: original.id, baseRevision: original.revision)
    try store.updateEditing(token, markdown: "Unsaved local draft")
    var remote = original; remote.revision = UUID()
    #expect(throws: LibraryError.editInProgress) { try store.mergeICloudPage(remote, basedOn: original.revision) }
    #expect(store.snapshot.pages.first?.markdown == "Unsaved local draft")
    try store.finishEditing(token)
}
