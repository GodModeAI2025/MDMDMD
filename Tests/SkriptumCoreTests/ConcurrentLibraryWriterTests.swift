import Foundation
import Testing
@testable import SkriptumCore

@Test @MainActor func staleLibraryWriterCannotOverwriteACommittedLibrary() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let first = try LibraryStore(directory: directory), stale = try LibraryStore(directory: directory)
    let before = stale.snapshot
    let space = try first.createSpace(title: "Durable first writer")
    #expect(throws: LibraryError.revisionConflict) { try stale.createSpace(title: "Stale second writer") }
    #expect(stale.snapshot == before)
    let reopened = try LibraryStore(directory: directory)
    #expect(reopened.snapshot.spaces.map(\.id) == [space.id])
}

@Test @MainActor func recoveredJournalRejectsFurtherWritesFromItsOlderOwner() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let original = try LibraryStore(directory: directory)
    let space = try original.createSpace(title: "Book")
    let page = try original.createPage(spaceID: space.id, title: "Page", markdown: "Baseline\r\n")
    let token = try original.beginEditing(pageID: page.id, baseRevision: page.revision)
    try original.updateEditing(token, markdown: "Recovered 🦊 e\u{301}\r\n")
    let before = original.snapshot
    let recovered = try LibraryStore(directory: directory)
    let bytes = try Data(contentsOf: directory.appendingPathComponent("library.json"))
    #expect(throws: LibraryError.revisionConflict) { try original.updateEditing(token, markdown: "Late obsolete writer") }
    #expect(throws: LibraryError.revisionConflict) { try original.finishEditing(token) }
    #expect(original.snapshot == before)
    #expect(try Data(contentsOf: directory.appendingPathComponent("library.json")) == bytes)
    #expect(recovered.snapshot.pages.first?.markdown.utf8.elementsEqual("Recovered 🦊 e\u{301}\r\n".utf8) == true)
}

@Test @MainActor func staleWriterLeavesCommittedPageAndObserverUntouched() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let first = try LibraryStore(directory: directory)
    let space = try first.createSpace(title: "Book")
    let page = try first.createPage(spaceID: space.id, title: "Page", markdown: "Baseline")
    let stale = try LibraryStore(directory: directory), before = stale.snapshot
    var notifications = 0
    stale.onDurableChange = { _ in notifications += 1 }
    try first.setMarkdown(page.id, markdown: "Committed 🦊\r\n", baseRevision: page.revision)
    #expect(throws: LibraryError.revisionConflict) { try stale.renamePage(page.id, title: "Obsolete rename") }
    #expect(throws: LibraryError.revisionConflict) { try stale.beginEditing(pageID: page.id, baseRevision: page.revision) }
    #expect(stale.snapshot == before)
    #expect(notifications == 0)
    #expect(try LibraryStore(directory: directory).snapshot.pages.first?.markdown == "Committed 🦊\r\n")
}

@Test @MainActor func libraryLockSymlinkNeverWritesItsTarget() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let directory = root.appendingPathComponent("Library")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let target = root.appendingPathComponent("Unrelated")
    let bytes = Data("Keep this file unchanged".utf8)
    try bytes.write(to: target)
    try FileManager.default.createSymbolicLink(at: directory.appendingPathComponent(".library.lock"), withDestinationURL: target)
    #expect(throws: (any Error).self) { try LibraryStore(directory: directory) }
    #expect(try Data(contentsOf: target) == bytes)
    #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("library.json").path))
}
