import Foundation
import Testing
import SkriptumCore
@testable import SkriptumWorkspaceModel

@MainActor struct WritingPreferencesStorageTests {
    @Test func actualLibraryNamespaceSeparatesSameSpaceIdentityAndReloads() throws {
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
        let documents = root.appending(path: "Documents"), support = root.appending(path: "Support")
        let suite = UUID().uuidString, defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let firstStore = try LibraryStore(directory: documents.appending(path: "Skriptum"))
        let space = try firstStore.createSpace(title: "Same identity")
        let first = try WritingLibrary(store: firstStore, documentRoot: documents, supportRoot: support, preferences: defaults)
        let package = root.appending(path: "copy.scriptum")
        try firstStore.exportPackage(to: package)
        let secondStore = try LibraryStore.importPackage(from: package, to: documents.appending(path: "ScriptumLibraries/" + UUID().uuidString))
        let second = try WritingLibrary(store: secondStore, documentRoot: documents, supportRoot: support, preferences: defaults)
        #expect(firstStore.snapshot.spaces[0].id == secondStore.snapshot.spaces[0].id)
        #expect(try first.writingPreferenceKey(spaceID: space.id) != second.writingPreferenceKey(spaceID: space.id))
        let changed = try WritingPreferences(fontDesign: .serif, fontScale: 1.4, lineSpacing: 9, contentWidth: 680)
        try first.saveWritingPreferences(changed, spaceID: space.id)
        #expect(try second.loadWritingPreferences(spaceID: space.id) == .standard)
        let reloaded = try WritingLibrary(store: firstStore, documentRoot: documents, supportRoot: support, preferences: defaults)
        #expect(try reloaded.loadWritingPreferences(spaceID: space.id) == changed)
    }
    @Test func invalidScopeAndPersistedSettingsNeverFallback() throws {
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString), suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let documents = root.appending(path: "Documents"), store = try LibraryStore(directory: documents.appending(path: "Skriptum"))
        let space = try store.createSpace(title: "S")
        let library = try WritingLibrary(store: store, documentRoot: documents, supportRoot: root.appending(path: "Support"), preferences: defaults)
        #expect(throws: WritingPreferencesStorageError.invalidScope) { try library.loadWritingPreferences(spaceID: UUID()) }
        let key = try library.writingPreferenceKey(spaceID: space.id)
        defaults.set("wrong type", forKey: key)
        #expect(throws: WritingPreferencesStorageError.invalidStoredData) { try library.loadWritingPreferences(spaceID: space.id) }
        defaults.set(Data("{}".utf8), forKey: key)
        #expect(throws: (any Error).self) { try library.loadWritingPreferences(spaceID: space.id) }
        #expect(defaults.data(forKey: key) == Data("{}".utf8))
    }
}
