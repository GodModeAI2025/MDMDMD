import Foundation
import Testing
import SkriptumCore
@testable import SkriptumWorkspaceModel

@Test @MainActor func unprovisionedICloudSessionCannotActivateAfterStopOrCreateSyncFiles() async throws {
    let root = URL(fileURLWithPath: "/private/tmp/ICloudSession-" + UUID().uuidString)
    let suite = "test.icloudsession." + UUID().uuidString
    defer { try? FileManager.default.removeItem(at: root); UserDefaults.standard.removePersistentDomain(forName: suite) }
    let documents = root.appendingPathComponent("Documents"), support = root.appendingPathComponent("Support")
    let store = try LibraryStore(directory: documents.appendingPathComponent("Skriptum"))
    let space = try store.createSpace(title: "Local")
    _ = try store.createPage(spaceID: space.id, title: "Page", markdown: "e\u{301}\r\n🦊")
    let library = try WritingLibrary(store: store, documentRoot: documents, supportRoot: support,
        preferences: #require(UserDefaults(suiteName: suite)))
    let bytes = try Data(contentsOf: store.directory.appendingPathComponent("library.json"))
    let session = ICloudLibrarySession(library: library)
    #expect(session.status == .notConfigured)
    await session.activate(); await session.stop(); await session.activate()
    let activeScene = library.iCloudForegroundScenes.register()
    activeScene.update(active: true); session.setForegroundActive(library.iCloudForegroundScenes.isActive)
    await session.receiveCloudChangeHint()
    activeScene.close(); session.setForegroundActive(library.iCloudForegroundScenes.isActive)
    await session.synchronize()
    do { _ = try await session.createShare(scope: .space(space.id)); Issue.record("Unprovisioned share created") }
    catch { #expect(error is ICloudOwnerPresentationError) }
    let local = store.snapshot.pages[0]
    var remote = local; remote.revision = UUID(); remote.title = "Remote title"
    let conflict = try ICloudPageConflict(scope: ICloudSyncScope(accountID: "unused", libraryID: UUID()), local: local,
        change: ICloudSyncChange(recordID: .init(kind: .page, id: local.id), revisionID: remote.revision,
            operation: .upsert, payload: ICloudPagePayload(page: remote, baseRevision: nil).encoded()))
    #expect(try await session.pageConflicts().isEmpty)
    #expect(!session.canResolve(conflict))
    #expect(throws: (any Error).self) { try session.reviewStore(for: conflict) }
    do { try await session.resolve(conflict, choice: .remote); Issue.record("Unprovisioned conflict resolved") }
    catch { #expect(error is ICloudPageConflictError) }
    #expect(session.status == .notConfigured)
    #expect(session.pendingCount == 0)
    #expect(session.incomingCount == 0 && session.conflictCount == 0 && session.lastSynchronized == nil)
    #expect(!FileManager.default.fileExists(atPath: library.iCloudStorageDirectory().path))
    #expect(try Data(contentsOf: store.directory.appendingPathComponent("library.json")) == bytes)
}
