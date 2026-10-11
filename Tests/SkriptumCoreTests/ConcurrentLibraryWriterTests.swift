import Foundation
import Testing
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
@testable import SkriptumCore

@Test @MainActor func libraryMetadataChangeDoesNotPreventAnUnchangedOwnerFromWriting() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try LibraryStore(directory: directory)
    _ = try store.createSpace(title: "Original")
    let file = directory.appendingPathComponent("library.json")
    let bytes = try Data(contentsOf: file)
    let before = try #require(try LibraryDiskAccess.version(of: file))
    let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
    let permissions = try #require(attributes[.posixPermissions] as? NSNumber)
    try FileManager.default.setAttributes([.posixPermissions: permissions.intValue ^ 0o040], ofItemAtPath: file.path)
    let after = try #require(try LibraryDiskAccess.version(of: file))
    #expect(before.device == after.device && before.inode == after.inode && before.size == after.size)
    #expect(before.modifiedSeconds == after.modifiedSeconds && before.modifiedNanoseconds == after.modifiedNanoseconds)
    #expect(before != after)
    #expect(try Data(contentsOf: file) == bytes)
    let new = try store.createSpace(title: "After metadata update")
    #expect(try LibraryStore(directory: directory).snapshot.spaces.last?.id == new.id)
}

@Test @MainActor func sameSizeExternalContentWithRestoredModificationTimeRemainsAConflict() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try LibraryStore(directory: directory)
    _ = try store.createSpace(title: "Original")
    let baseline = store.snapshot, file = directory.appendingPathComponent("library.json")
    let before = try #require(try LibraryDiskAccess.version(of: file))
    let source = try String(contentsOf: file, encoding: .utf8)
    let changed = Data(source.replacingOccurrences(of: "Original", with: "Tampered").utf8)
    #expect(changed.count == before.size)
    try changed.write(to: file)
    let times = [timespec(tv_sec: Int(before.modifiedSeconds), tv_nsec: Int(before.modifiedNanoseconds)),
                 timespec(tv_sec: Int(before.modifiedSeconds), tv_nsec: Int(before.modifiedNanoseconds))]
    #expect(times.withUnsafeBufferPointer { utimensat(AT_FDCWD, file.path, $0.baseAddress, 0) } == 0)
    let current = try #require(try LibraryDiskAccess.version(of: file))
    #expect(current.hasSamePayloadCoordinates(as: before))
    #expect(current != before)
    var notifications = 0
    store.onDurableChange = { _ in notifications += 1 }
    #expect(throws: LibraryError.revisionConflict) { try store.createSpace(title: "Must not overwrite") }
    #expect(store.snapshot == baseline && notifications == 0)
    #expect(try Data(contentsOf: file) == changed)
}

@Test @MainActor func atomicReplacementWithIdenticalBytesRemainsAConflict() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try LibraryStore(directory: directory)
    _ = try store.createSpace(title: "Original")
    let file = directory.appendingPathComponent("library.json"), baseline = store.snapshot
    let bytes = try Data(contentsOf: file)
    try bytes.write(to: file, options: .atomic)
    #expect(throws: LibraryError.revisionConflict) { try store.createSpace(title: "Must not overwrite") }
    #expect(store.snapshot == baseline)
    #expect(try Data(contentsOf: file) == bytes)
}

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

@Test @MainActor func alreadyLoadedWriterCannotOverwriteAnotherStoresActiveJournal() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let owner = try LibraryStore(directory: directory)
    let space = try owner.createSpace(title: "Book")
    let page = try owner.createPage(spaceID: space.id, title: "Page", markdown: "Baseline")
    let other = try LibraryStore(directory: directory)
    let token = try owner.beginEditing(pageID: page.id, baseRevision: page.revision)
    try owner.updateEditing(token, markdown: "Journal draft 🦊")
    #expect(throws: LibraryError.editInProgress) { try other.beginEditing(pageID: page.id, baseRevision: page.revision) }
    #expect(throws: LibraryError.editInProgress) { try other.setMarkdown(page.id, markdown: "Would clobber journal", baseRevision: page.revision) }
    try owner.finishEditing(token)
    #expect(try LibraryStore(directory: directory).snapshot.pages.first?.markdown == "Journal draft 🦊")
}

@Test @MainActor func staleUnchangedJournalDoesNotBlockAValidExternalRevision() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let owner = try LibraryStore(directory: directory)
    let space = try owner.createSpace(title: "Book")
    let page = try owner.createPage(spaceID: space.id, title: "Page", markdown: "Baseline")
    _ = try owner.beginEditing(pageID: page.id, baseRevision: page.revision)
    var external = owner.snapshot
    external.revisions.append(Revision(page: page, author: "External", capturedAt: Date()))
    external.pages[0].blocks = [Block(markdown: "Valid external revision")]
    external.pages[0].revision = UUID()
    try JSONEncoder().encode(external).write(to: directory.appendingPathComponent("library.json"), options: .atomic)
    let reopened = try LibraryStore(directory: directory)
    #expect(reopened.snapshot == external)
    #expect(try FileManager.default.contentsOfDirectory(atPath: directory.appendingPathComponent("edits").path).isEmpty)
}
