import Foundation
import Testing
import SkriptumCore
@testable import SkriptumWorkspaceModel

private func conflictFixture() throws -> ICloudPageConflict {
    let scope = try ICloudSyncScope(accountID: "participant-e\u{301}", libraryID: UUID())
    let local = Page(spaceID: UUID(), title: "Local", markdown: "Local e\u{301}\r\n🦊")
    var remote = local; remote.revision = UUID(); remote.blocks = [Block(markdown: "Remote e\u{301}\r\n🦊")]
    let change = ICloudSyncChange(recordID: .init(kind: .page, id: local.id), revisionID: remote.revision,
        operation: .upsert, payload: try ICloudPagePayload(page: remote, baseRevision: UUID()).encoded())
    return try ICloudPageConflict(scope: scope, local: local, change: change)
}
@Test func pageConflictCompletionRequiresExactScopeLatestInputQueuedRevisionAndRemoteBase() throws {
    let conflict = try conflictFixture()
    var resolved = conflict.local; resolved.revision = UUID()
    let queued = ICloudSyncChange(recordID: conflict.change.recordID, revisionID: resolved.revision,
        operation: .upsert, payload: try ICloudPagePayload(page: resolved, baseRevision: conflict.remote.revision).encoded())
    try ICloudPageConflict.admitCompletion(scope: conflict.scope, expectedScope: conflict.scope, expected: conflict.change,
        latest: conflict.change, queued: queued, resolvedRevision: resolved.revision)
    let other = try ICloudSyncScope(accountID: conflict.scope.accountID, libraryID: UUID())
    #expect(throws: (any Error).self) { try ICloudPageConflict.admitCompletion(scope: other, expectedScope: conflict.scope, expected: conflict.change,
        latest: conflict.change, queued: queued, resolvedRevision: resolved.revision) }
    var changed = conflict.remote; changed.blocks[0].markdown = "Remote é\r\n🦊"
    let latest = ICloudSyncChange(recordID: conflict.change.recordID, revisionID: changed.revision,
        operation: .upsert, payload: try ICloudPagePayload(page: changed, baseRevision: UUID()).encoded())
    #expect(throws: (any Error).self) { try ICloudPageConflict.admitCompletion(scope: conflict.scope, expectedScope: conflict.scope, expected: conflict.change,
        latest: latest, queued: queued, resolvedRevision: resolved.revision) }
    #expect(throws: (any Error).self) { try ICloudPageConflict.admitCompletion(scope: conflict.scope, expectedScope: conflict.scope, expected: conflict.change,
        latest: nil, queued: queued, resolvedRevision: resolved.revision) }
    #expect(throws: (any Error).self) { try ICloudPageConflict.admitCompletion(scope: conflict.scope, expectedScope: conflict.scope, expected: conflict.change,
        latest: conflict.change, queued: queued, resolvedRevision: UUID()) }
    let wrongBase = ICloudSyncChange(recordID: queued.recordID, revisionID: queued.revisionID, operation: .upsert,
        payload: try ICloudPagePayload(page: resolved, baseRevision: conflict.local.revision).encoded())
    #expect(throws: (any Error).self) { try ICloudPageConflict.admitCompletion(scope: conflict.scope, expectedScope: conflict.scope, expected: conflict.change,
        latest: conflict.change, queued: wrongBase, resolvedRevision: resolved.revision) }
}
@Test @MainActor func pageConflictReviewDraftRestoresExactLatestBytesAndDoesNotCrossComparisonOrAccount() throws {
    let root = URL(fileURLWithPath: "/private/tmp/ScriptumConflictReview-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let conflict = try conflictFixture()
    let store = try ICloudConflictReviewStore(directory: root, identity: conflict.reviewIdentity)
    let text = "Merged e\u{301}\r\n🦊"
    try store.save(text)
    let reopened = try ICloudConflictReviewStore(directory: root, identity: conflict.reviewIdentity, draftID: store.draftID)
    #expect(try reopened.load()?.utf8.elementsEqual(text.utf8) == true)
    try reopened.save(conflict.local.markdown)
    #expect(try store.load()?.utf8.elementsEqual(conflict.local.markdown.utf8) == true)
    let identity = conflict.reviewIdentity
    let other = ICloudConflictReviewIdentity(scope: try ICloudSyncScope(accountID: "participant-é", libraryID: conflict.scope.libraryID),
        pageID: identity.pageID, localRevision: identity.localRevision, remoteRevision: identity.remoteRevision, localDigest: identity.localDigest, remoteDigest: identity.remoteDigest)
    #expect(try ICloudConflictReviewStore(directory: root, identity: other).load() == nil)
    var alteredLocal = conflict.local; alteredLocal.blocks[0].markdown = "Altered under same local ID"
    let altered = try ICloudPageConflict(scope: conflict.scope, local: alteredLocal, change: conflict.change)
    #expect(try ICloudConflictReviewStore(directory: root, identity: altered.reviewIdentity).load() == nil)
    let changed = ICloudConflictReviewIdentity(scope: identity.scope, pageID: identity.pageID,
        localRevision: UUID(), remoteRevision: identity.remoteRevision, localDigest: identity.localDigest, remoteDigest: identity.remoteDigest)
    #expect(try ICloudConflictReviewStore(directory: root, identity: changed).load() == nil)
}
@Test @MainActor func pageConflictReviewCorruptionAndLinksRemainUnchangedOnSaveFailure() throws {
    let root = URL(fileURLWithPath: "/private/tmp/ScriptumConflictReviewUnsafe-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try ICloudConflictReviewStore(directory: root, identity: conflictFixture().reviewIdentity)
    try store.save("Private draft")
    let file = try #require(try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).first)
    let corrupted = Data("not-json".utf8); try corrupted.write(to: file)
    #expect(throws: (any Error).self) { try store.save("Must not replace") }
    #expect(try Data(contentsOf: file) == corrupted)
    let foreign = root.appendingPathComponent("unrelated.txt"), bytes = Data("Unrelated bytes".utf8)
    try bytes.write(to: foreign); try FileManager.default.removeItem(at: file)
    try FileManager.default.createSymbolicLink(at: file, withDestinationURL: foreign)
    #expect(throws: (any Error).self) { try store.save("Must not follow") }
    #expect(try Data(contentsOf: foreign) == bytes)
}

@Test @MainActor func pageConflictReviewWindowsAndOlderComparisonsRetainIndependentRecoverableBuffers() throws {
    let root = URL(fileURLWithPath: "/private/tmp/ScriptumConflictReviewWindows-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let conflict = try conflictFixture()
    let first = try ICloudConflictReviewStore(directory: root, identity: conflict.reviewIdentity)
    let second = try ICloudConflictReviewStore(directory: root, identity: conflict.reviewIdentity)
    try first.save("First window e\u{301}\r\n🦊"); try second.save("Second window")
    try first.save("First latest")
    #expect(try second.load() == "Second window")
    let reopened = try ICloudConflictReviewStore(directory: root, identity: conflict.reviewIdentity)
    let listing = try reopened.listing()
    #expect(listing.drafts.count == 2 && listing.unreadableCount == 0)
    let firstSaved = try #require(listing.drafts.first { $0.draftID == first.draftID })
    #expect(try reopened.load(firstSaved) == "First latest")
    var differentLocal = conflict.local; differentLocal.revision = UUID()
    let later = try ICloudPageConflict(scope: conflict.scope, local: differentLocal, change: conflict.change)
    let differentComparison = try ICloudConflictReviewStore(directory: root, identity: later.reviewIdentity)
    let older = try differentComparison.listing()
    #expect(older.drafts.count == 2 && older.drafts.allSatisfy { !$0.matchesCurrentComparison })
    #expect(try differentComparison.load(firstSaved) == "First latest")
    try differentComparison.save("Forked later comparison")
    #expect(try first.load() == "First latest")
    #expect(try second.load() == "Second window")
    let anotherScope = try ICloudSyncScope(accountID: conflict.scope.accountID, libraryID: UUID())
    var remote = conflict.remote
    let otherLocal = Page(spaceID: UUID(), title: "Other library")
    remote.id = otherLocal.id
    let foreignConflict = try ICloudPageConflict(scope: anotherScope, local: otherLocal,
        change: ICloudSyncChange(recordID: .init(kind: .page, id: otherLocal.id), revisionID: remote.revision,
            operation: .upsert, payload: ICloudPagePayload(page: remote, baseRevision: nil).encoded()))
    let foreignStore = try ICloudConflictReviewStore(directory: root, identity: foreignConflict.reviewIdentity)
    #expect(try foreignStore.listing().drafts.isEmpty)
    #expect(throws: (any Error).self) { try foreignStore.load(firstSaved) }
}
@Test @MainActor func pageConflictReviewCatalogRetainsCorruptionWhileLoadingOtherWindow() throws {
    let root = URL(fileURLWithPath: "/private/tmp/ScriptumConflictReviewMixed-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let conflict = try conflictFixture()
    let first = try ICloudConflictReviewStore(directory: root, identity: conflict.reviewIdentity)
    let second = try ICloudConflictReviewStore(directory: root, identity: conflict.reviewIdentity)
    try first.save("Keep good window"); try second.save("Other window")
    let file = try #require(try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        .first { $0.lastPathComponent.contains(second.draftID.uuidString.lowercased()) })
    let bytes = Data("Corrupt retained frame".utf8); try bytes.write(to: file)
    let listing = try first.listing()
    #expect(listing.drafts.count == 1 && listing.unreadableCount == 1)
    #expect(try first.load(listing.drafts[0]) == "Keep good window")
    #expect(try Data(contentsOf: file) == bytes)
}
