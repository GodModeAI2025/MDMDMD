import Foundation
import CloudKit
import Testing
import SkriptumCore
@testable import SkriptumWorkspaceModel

@Test @MainActor func unprovisionedSharedSessionCannotRestoreWriteOrCreateCloudState() async throws {
    let directory = URL(fileURLWithPath: "/private/tmp/ScriptumUnprovisionedShared-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let session = ICloudSharedSession(directory: directory)
    #expect(session.status == .notConfigured)
    let id = UUID()
    let identity = try ICloudSharedStoreIdentity(accountID: "participant", ownerID: "owner", zoneName: "zone", shareName: "share", root: .init(kind: .page, id: id))
    await session.restore(identity)
    await session.receiveCloudChangeHint()
    await session.synchronize()
    #expect(session.status == .notConfigured)
    #expect(session.context == nil)
    #expect(session.pendingCount == 0)
    #expect(throws: ICloudSharedSessionError.unavailable) { try session.edit(pageID: id, revision: UUID(), markdown: "Must not save") }
    #expect(throws: ICloudSharedSessionError.unavailable) { try session.reply(commentID: UUID(), body: "Must not save") }
    session.stop()
    await session.restore(identity)
    #expect(!FileManager.default.fileExists(atPath: directory.path))
    #expect(session.identity == nil)
}

@Test @MainActor func accountNotificationFencesSuspendedRestoreAndPreservesPrivateDrafts() async throws {
    let directory = URL(fileURLWithPath: "/private/tmp/ScriptumSharedAccountFence-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let identity = try ICloudSharedStoreIdentity(accountID: "old-participant", ownerID: "owner", zoneName: "zone", shareName: "share", root: .init(kind: .page, id: UUID()))
    let drafts = try ICloudSharedDraftStore(directory: directory.appendingPathComponent("Drafts"), identity: identity)
    let draft = ICloudSharedDraft(id: UUID(), pageID: identity.root.id, baseRevision: UUID(), text: "Privater Entwurf 🦊 e\u{301}\r\n")
    try drafts.save(draft)
    let center = NotificationCenter(), lookup = SuspendedSharedAccountLookup()
    let session = ICloudSharedSession(directory: directory, provisioned: true, notificationCenter: center,
        accountLookup: { try await lookup.read() })
    let restore = Task { await session.restore(identity) }
    for _ in 0..<1000 where lookup.continuation == nil { await Task.yield() }
    let continuation = try #require(lookup.continuation)
    #expect(session.status == .accepting)
    // Notification and old completion race: the synchronous fence must reject
    // the old account even before the presentation cleanup task gets to run.
    center.post(name: .CKAccountChanged, object: nil)
    continuation.resume(returning: "old-participant"); lookup.continuation = nil
    await restore.value
    for _ in 0..<1000 where session.status != .accountChanged { await Task.yield() }
    #expect(session.status == .accountChanged)
    #expect(session.context == nil)
    #expect(session.identity == nil)
    #expect(session.pendingCount == 0)
    #expect(session.recoveredDrafts.isEmpty)
    #expect(try drafts.draft(draft.id)?.text.utf8.elementsEqual(draft.text.utf8) == true)
    #expect(throws: ICloudSharedSessionError.unavailable) {
        try session.edit(pageID: identity.root.id, revision: draft.baseRevision, markdown: "Must not write")
    }
    await session.synchronize()
    #expect(session.status == .accountChanged)
    // Fresh re-opening asks for the current account instead of using the old one.
    let retry = Task { await session.restore(identity) }
    for _ in 0..<1000 where lookup.continuation == nil { await Task.yield() }
    let second = try #require(lookup.continuation)
    second.resume(returning: "different-participant"); lookup.continuation = nil
    await retry.value
    #expect(session.status == .failed)
    #expect(session.context == nil)
    #expect(try drafts.draft(draft.id)?.text.utf8.elementsEqual(draft.text.utf8) == true)
}

@Test @MainActor func sharedAccountObserverDoesNotRetainClosedSession() async {
    let center = NotificationCenter()
    var session: ICloudSharedSession? = ICloudSharedSession(directory: URL(fileURLWithPath: "/private/tmp/unused-shared-observer"),
        provisioned: true, notificationCenter: center, accountLookup: { "unused" })
    weak var released = session
    session = nil
    #expect(released == nil)
    center.post(name: .CKAccountChanged, object: nil)
    await Task.yield()
    #expect(released == nil)
}

@MainActor private final class SuspendedSharedAccountLookup {
    var continuation: CheckedContinuation<String, any Error>?
    func read() async throws -> String {
        try await withCheckedThrowingContinuation { continuation = $0 }
    }
}
