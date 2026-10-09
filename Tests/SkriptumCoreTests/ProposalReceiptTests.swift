import Foundation
import Testing
@testable import SkriptumCore

@Test @MainActor func proposalReceiptRestartRetryAndConflicts() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try LibraryStore(directory: root)
    let space = try store.createSpace(title: "Space")
    let page = try store.createPage(spaceID: space.id, title: "Page", markdown: "old")
    let id = UUID()
    var patch = PagePatch(pageID: page.id, baseRevision: page.revision, allowedBlockIDs: [page.blocks[0].id], operations: [.replace(blockID: page.blocks[0].id, markdown: "e\u{301}\r\n🦊")])
    let receipt = try store.applyProposal(id, patch: patch, author: "Agent")
    #expect(store.snapshot.revisions.count == 1)
    try store.renamePage(page.id, title: "Later")
    let reopened = try LibraryStore(directory: root)
    let before = reopened.snapshot
    let bytes = try Data(contentsOf: root.appendingPathComponent("library.json"))
    #expect(try reopened.applyProposal(id, patch: patch, author: "Agent") == receipt)
    #expect(reopened.snapshot == before)
    #expect(throws: LibraryError.proposalConflict) { try reopened.applyProposal(id, patch: patch, author: "Other") }
    patch.operations = [.replace(blockID: page.blocks[0].id, markdown: "é\r\n🦊")]
    #expect(throws: LibraryError.proposalConflict) { try reopened.applyProposal(id, patch: patch, author: "Agent") }
    #expect(try Data(contentsOf: root.appendingPathComponent("library.json")) == bytes)
}

@Test @MainActor func proposalNoopAndDeniedAndAtomicWriteFailure() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try LibraryStore(directory: root)
    let space = try store.createSpace(title: "Space")
    let page = try store.createPage(spaceID: space.id, title: "Page", markdown: "old")
    var patch = PagePatch(pageID: page.id, baseRevision: page.revision, allowedBlockIDs: [page.blocks[0].id], operations: [])
    let noop = try store.applyProposal(UUID(), patch: patch)
    #expect(noop.appliedRevision == page.revision)
    #expect(store.snapshot.revisions.isEmpty)
    let token = try store.beginEditing(pageID: page.id, baseRevision: page.revision)
    #expect(throws: LibraryError.editInProgress) { try store.applyProposal(UUID(), patch: patch) }
    try store.finishEditing(token)
    patch.baseRevision = UUID()
    #expect(throws: LibraryError.revisionConflict) { try store.applyProposal(UUID(), patch: patch) }
    patch.baseRevision = page.revision
    patch.allowedBlockIDs = [UUID()]
    #expect(throws: LibraryError.forbiddenBlock) { try store.applyProposal(UUID(), patch: patch) }
    patch.allowedBlockIDs = [page.blocks[0].id]
    patch.operations = [.replace(blockID: page.blocks[0].id, markdown: "new")]
    let before = store.snapshot
    let file = root.appendingPathComponent("library.json")
    let bytes = try Data(contentsOf: file)
    try FileManager.default.removeItem(at: file)
    try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
    #expect(throws: (any Error).self) { try store.applyProposal(UUID(), patch: patch) }
    #expect(store.snapshot == before)
    try FileManager.default.removeItem(at: file)
    try bytes.write(to: file)
    #expect(try LibraryStore(directory: root).snapshot == before)
}

@Test @MainActor func proposalReceiptScopePageAndOrderingAreExact() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try LibraryStore(directory: root)
    let space = try store.createSpace(title: "Space")
    let page = try store.createPage(spaceID: space.id, title: "Page", markdown: "a\n\nb")
    let ids = page.blocks.map(\.id)
    #expect(ids.count >= 2)
    let patch = PagePatch(pageID: page.id, baseRevision: page.revision, allowedBlockIDs: Set(ids), operations: [.replace(blockID: ids[0], markdown: "a\r\n\r\n"), .replace(blockID: ids[1], markdown: "b")])
    let id = UUID()
    let receipt = try store.applyProposal(id, patch: patch, author: "é")
    var reorderedSet = patch
    reorderedSet.allowedBlockIDs = Set(ids.reversed())
    #expect(try store.applyProposal(id, patch: reorderedSet, author: "é") == receipt)
    let before = try Data(contentsOf: root.appendingPathComponent("library.json"))
    var changed = patch
    changed.allowedBlockIDs = [ids[0]]
    #expect(throws: LibraryError.proposalConflict) { try store.applyProposal(id, patch: changed, author: "é") }
    changed = patch; changed.pageID = UUID()
    #expect(throws: LibraryError.proposalConflict) { try store.applyProposal(id, patch: changed, author: "é") }
    changed = patch; changed.operations.reverse()
    #expect(throws: LibraryError.proposalConflict) { try store.applyProposal(id, patch: changed, author: "é") }
    #expect(throws: LibraryError.proposalConflict) { try store.applyProposal(id, patch: patch, author: "e\u{301}") }
    #expect(try Data(contentsOf: root.appendingPathComponent("library.json")) == before)
    let current = try #require(store.snapshot.pages.first)
    try store.trashPage(current.id)
    var trashedPatch = patch
    trashedPatch.baseRevision = store.snapshot.pages[0].revision
    let count = store.snapshot.proposalReceipts?.count
    #expect(throws: LibraryError.trashedPage) { try store.applyProposal(UUID(), patch: trashedPatch) }
    #expect(store.snapshot.proposalReceipts?.count == count)
}

@Test @MainActor func proposalReceiptLegacyAndMalformedSnapshots() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let file = root.appendingPathComponent("library.json")
    let legacy = Data(#"{"schemaVersion":1,"spaces":[],"pages":[],"comments":[],"revisions":[]}"#.utf8)
    try legacy.write(to: file)
    #expect(try LibraryStore(directory: root).snapshot.proposalReceipts == nil)
    let store = try LibraryStore(directory: root)
    let space = try store.createSpace(title: "Space")
    let page = try store.createPage(spaceID: space.id, title: "Page", markdown: "old")
    let patch = PagePatch(pageID: page.id, baseRevision: page.revision, allowedBlockIDs: [], operations: [])
    let receipt = try store.applyProposal(UUID(), patch: patch)
    let bytes = try Data(contentsOf: file)
    var json = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
    let receipts = try #require(json["proposalReceipts"] as? [[String: Any]])
    for field in ["schemaVersion", "patchFingerprint", "author", "acceptedAt"] {
        var bad = receipts[0]
        switch field {
        case "schemaVersion": bad[field] = 2
        case "patchFingerprint": bad[field] = "not-a-hash"
        case "author": bad[field] = String(repeating: "a", count: 1025)
        default: bad[field] = "not-a-date"
        }
        json["proposalReceipts"] = [bad]
        let malformed = try JSONSerialization.data(withJSONObject: json)
        try malformed.write(to: file)
        #expect(throws: (any Error).self) { try LibraryStore(directory: root) }
        #expect(try Data(contentsOf: file) == malformed)
    }
    json["proposalReceipts"] = [receipts[0], receipts[0]]
    try JSONSerialization.data(withJSONObject: json).write(to: file)
    #expect(throws: LibraryError.invalidLibrary) { try LibraryStore(directory: root) }
    try bytes.write(to: file)
    #expect(try LibraryStore(directory: root).snapshot.proposalReceipts == [receipt])
}

@Test @MainActor func proposalReceiptBoundsAndUnrelatedJournalDurability() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try LibraryStore(directory: root)
    let space = try store.createSpace(title: "Space")
    let page = try store.createPage(spaceID: space.id, title: "Target", markdown: "é\r\n")
    let other = try store.createPage(spaceID: space.id, title: "Typing", markdown: "baseline")
    let token = try store.beginEditing(pageID: other.id, baseRevision: other.revision)
    try store.updateEditing(token, markdown: "active 🦊\r\n")
    let patch = PagePatch(pageID: page.id, baseRevision: page.revision, allowedBlockIDs: [page.blocks[0].id], operations: [.replace(blockID: page.blocks[0].id, markdown: "e\u{301}\r\n")])
    let before = try Data(contentsOf: root.appendingPathComponent("library.json"))
    #expect(throws: LibraryError.invalidProposalMetadata) { try store.applyProposal(UUID(), patch: patch, author: "") }
    #expect(try Data(contentsOf: root.appendingPathComponent("library.json")) == before)
    let id = UUID()
    let receipt = try store.applyProposal(id, patch: patch)
    let disk = try JSONDecoder().decode(LibrarySnapshot.self, from: Data(contentsOf: root.appendingPathComponent("library.json")))
    #expect(disk.pages.first(where: { $0.id == page.id })?.markdown.utf8.elementsEqual("e\u{301}\r\n".utf8) == true)
    #expect(disk.pages.first(where: { $0.id == other.id })?.markdown == "baseline")
    #expect(disk.proposalReceipts == [receipt])
    try store.finishEditing(token)
    let restarted = try LibraryStore(directory: root)
    #expect(restarted.snapshot.pages.first(where: { $0.id == other.id })?.markdown == "active 🦊\r\n")
    #expect(try restarted.applyProposal(id, patch: patch) == receipt)
    let file = root.appendingPathComponent("library.json")
    var json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
    let original = try #require((json["proposalReceipts"] as? [[String: Any]])?.first)
    json["proposalReceipts"] = (0..<ProposalReceipt.maximumCount).map { _ in
        var row = original; row["proposalID"] = UUID().uuidString; return row
    }
    try JSONSerialization.data(withJSONObject: json).write(to: file)
    let bounded = try LibraryStore(directory: root)
    let bytes = try Data(contentsOf: file)
    #expect(throws: LibraryError.receiptLimitExceeded) { try bounded.applyProposal(UUID(), patch: patch) }
    #expect(try Data(contentsOf: file) == bytes)
    var tooMany = try #require(json["proposalReceipts"] as? [[String: Any]])
    var extra = original; extra["proposalID"] = UUID().uuidString; tooMany.append(extra)
    json["proposalReceipts"] = tooMany
    try JSONSerialization.data(withJSONObject: json).write(to: file)
    #expect(throws: LibraryError.invalidLibrary) { try LibraryStore(directory: root) }
}
