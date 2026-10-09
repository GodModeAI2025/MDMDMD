import Foundation
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
