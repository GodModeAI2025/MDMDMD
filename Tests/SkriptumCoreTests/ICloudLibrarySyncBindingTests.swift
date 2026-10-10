import Foundation
import Testing
@testable import SkriptumCore

@Test @MainActor func incomingPageDoesNotEchoAndNextLocalEditUsesItsRevision() throws {
    let root = URL(fileURLWithPath: "/private/tmp/ICloudBinding-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try LibraryStore(directory: root.appendingPathComponent("Documents"))
    let space = try store.createSpace(title: "Writing")
    let page = try store.createPage(spaceID: space.id, title: "Page", markdown: "Initial")
    let journal = try ICloudSyncJournal(directory: root.appendingPathComponent("Sync"), scope: ICloudSyncScope(accountID: "A", libraryID: UUID()))
    let binding = try ICloudLibrarySyncBinding(store: store, journal: journal)
    for change in try journal.pendingBatch() { try journal.acknowledge(recordID: change.recordID, revisionID: change.revisionID) }
    var remote = page; remote.revision = UUID(); remote.blocks = [Block(markdown: "Remote")]
    _ = try binding.performIncomingMutation { try store.mergeICloudPage(remote, basedOn: page.revision) }
    #expect(try journal.pendingBatch().isEmpty)
    let token = try store.beginEditing(pageID: page.id, baseRevision: remote.revision)
    try store.updateEditing(token, markdown: "Local next"); try store.finishEditing(token)
    let value = try #require(try journal.pendingChange(recordID: .init(kind: .page, id: page.id)))
    let payload = try ICloudPagePayload.decode(value.payload, expectedPageID: page.id, expectedRevision: value.revisionID)
    #expect(payload.baseRevision == remote.revision)
}

@Test @MainActor func iCloudReplacedAccountBindingCannotRetryOrRemoveNewObserver() throws {
    let root = URL(fileURLWithPath: "/private/tmp/ICloudBinding-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try LibraryStore(directory: root.appendingPathComponent("Documents"))
    let space = try store.createSpace(title: "Writing"), libraryID = UUID()
    let a = try ICloudSyncJournal(directory: root.appendingPathComponent("Sync"), scope: ICloudSyncScope(accountID: "account-a", libraryID: libraryID))
    let b = try ICloudSyncJournal(directory: root.appendingPathComponent("Sync"), scope: ICloudSyncScope(accountID: "account-b", libraryID: libraryID))
    let old = try ICloudLibrarySyncBinding(store: store, journal: a)
    let current = try ICloudLibrarySyncBinding(store: store, journal: b)
    for journal in [a, b] {
        for change in try journal.pendingBatch() { try journal.acknowledge(recordID: change.recordID, revisionID: change.revisionID) }
    }
    #expect(throws: ICloudLibrarySyncBindingError.inactive) { try old.retry() }
    old.invalidate()
    let page = try store.createPage(spaceID: space.id, title: "New", markdown: "Account B")
    #expect(try a.pendingBatch().isEmpty)
    #expect(try b.pendingChange(recordID: .init(kind: .page, id: page.id)) != nil)
    current.invalidate()
    #expect(throws: ICloudLibrarySyncBindingError.inactive) { try current.retry() }
}

@Test @MainActor func iCloudBindingQueuesSavedChangesAndExcludesActiveDraftOnRetry() throws {
    let root = URL(fileURLWithPath: "/private/tmp/ICloudBinding-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try LibraryStore(directory: root.appendingPathComponent("Documents"))
    let space = try store.createSpace(title: "Writing")
    let page = try store.createPage(spaceID: space.id, title: "Page", markdown: "Saved")
    let journal = try ICloudSyncJournal(directory: root.appendingPathComponent("Sync"),
        scope: ICloudSyncScope(accountID: "owned-account", libraryID: UUID()))
    let binding = try ICloudLibrarySyncBinding(store: store, journal: journal)
    for change in try journal.pendingBatch() { try journal.acknowledge(recordID: change.recordID, revisionID: change.revisionID) }
    let token = try store.beginEditing(pageID: page.id, baseRevision: page.revision)
    try store.updateEditing(token, markdown: "Unfinished")
    try binding.retry()
    #expect(try journal.pendingBatch().isEmpty)
    #expect(store.snapshot.pages.first?.markdown == "Unfinished")
    try store.finishEditing(token)
    let change = try #require(try journal.pendingChange(recordID: .init(kind: .page, id: page.id)))
    let payload = try ICloudPagePayload.decode(change.payload, expectedPageID: page.id, expectedRevision: change.revisionID)
    #expect(payload.page.markdown == "Unfinished")
    #expect(payload.baseRevision == page.revision)
    #expect(binding.needsRetry == false)
}

@Test @MainActor func newDurableChangeSignalExcludesNoopRetryAndUnfinishedDraft() throws {
    let root = URL(fileURLWithPath: "/private/tmp/ICloudWakeBinding-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try LibraryStore(directory: root.appendingPathComponent("Documents"))
    let space = try store.createSpace(title: "Writing")
    let page = try store.createPage(spaceID: space.id, title: "Page", markdown: "Saved")
    let journal = try ICloudSyncJournal(directory: root.appendingPathComponent("Sync"),
        scope: ICloudSyncScope(accountID: "owned-account", libraryID: UUID()))
    let binding = try ICloudLibrarySyncBinding(store: store, journal: journal)
    for change in try journal.pendingBatch() { try journal.acknowledge(recordID: change.recordID, revisionID: change.revisionID) }
    var wakeups = 0, checks = 0
    binding.newChangesQueued = { wakeups += 1 }
    binding.changesQueued = { checks += 1 }
    for _ in 0..<20 { try binding.retry() }
    #expect(wakeups == 0 && checks == 20)
    let token = try store.beginEditing(pageID: page.id, baseRevision: page.revision)
    let draft = "Locally saved e\u{301}\r\n🦊"
    try store.updateEditing(token, markdown: draft)
    try binding.retry()
    let uncommittedBatch = try journal.pendingBatch()
    #expect(wakeups == 0 && uncommittedBatch.isEmpty)
    try store.finishEditing(token)
    #expect(wakeups == 1)
    let change = try #require(try journal.pendingChange(recordID: .init(kind: .page, id: page.id)))
    let payload = try ICloudPagePayload.decode(change.payload, expectedPageID: page.id, expectedRevision: change.revisionID)
    #expect(payload.page.markdown.utf8.elementsEqual(draft.utf8))
    #expect(payload.baseRevision == page.revision)
    for _ in 0..<20 { try binding.retry() }
    #expect(wakeups == 1)
    binding.invalidate()
    _ = try store.createPage(spaceID: space.id, title: "Detached", markdown: "Only local")
    #expect(wakeups == 1)
}
