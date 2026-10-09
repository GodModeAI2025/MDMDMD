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
    await session.synchronize()
    #expect(session.status == .notConfigured)
    #expect(session.pendingCount == 0)
    #expect(session.incomingCount == 0 && session.conflictCount == 0 && session.lastSynchronized == nil)
    #expect(!FileManager.default.fileExists(atPath: library.iCloudStorageDirectory().path))
    #expect(try Data(contentsOf: store.directory.appendingPathComponent("library.json")) == bytes)
}
