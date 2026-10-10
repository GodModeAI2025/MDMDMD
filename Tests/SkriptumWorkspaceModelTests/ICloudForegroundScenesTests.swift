import Foundation
import Testing
import SkriptumCore
@testable import SkriptumWorkspaceModel

@MainActor struct ICloudForegroundScenesTests {
    @Test func inactiveOrClosedWindowCannotPauseAnotherActiveWindow() {
        let scenes = ICloudForegroundScenes()
        let first = scenes.register(), second = scenes.register()
        #expect(!scenes.isActive)
        first.update(active: true); second.update(active: true)
        first.update(active: false)
        #expect(scenes.isActive)
        first.close()
        #expect(scenes.isActive)
        second.update(active: false)
        #expect(!scenes.isActive)
        second.update(active: true)
        #expect(scenes.isActive)
        second.close(); second.update(active: true)
        #expect(!scenes.isActive)
    }
    @Test func sceneRegistrationsAreWeakAndLibrariesStayIndependent() {
        let owned = ICloudForegroundScenes(), other = ICloudForegroundScenes()
        weak var observation: ICloudForegroundScenes.Lease?
        do {
            let window = owned.register(); observation = window
            window.update(active: true)
            #expect(owned.isActive && !other.isActive)
        }
        #expect(observation == nil && !owned.isActive)
        let second = other.register(); second.update(active: true)
        #expect(!owned.isActive && other.isActive)
        let replacement = owned.register(); replacement.update(active: true)
        second.close()
        #expect(owned.isActive && !other.isActive)
        replacement.close()
    }
    @Test func retiredViewDetachCannotRevokeReplacementLibraryRegistration() throws {
        let root = URL(fileURLWithPath: "/private/tmp/OwnerForegroundLease-" + UUID().uuidString)
        let suite = "test.ownerforeground." + UUID().uuidString
        defer { try? FileManager.default.removeItem(at: root); UserDefaults.standard.removePersistentDomain(forName: suite) }
        let preferences = try #require(UserDefaults(suiteName: suite))
        func library(_ name: String) throws -> WritingLibrary {
            let documents = root.appendingPathComponent(name).appendingPathComponent("Documents")
            let store = try LibraryStore(directory: documents.appendingPathComponent("Skriptum"))
            let space = try store.createSpace(title: name)
            _ = try store.createPage(spaceID: space.id, title: "Local", markdown: "e\u{301}\r\n🦊")
            return try WritingLibrary(store: store, documentRoot: documents,
                supportRoot: root.appendingPathComponent(name).appendingPathComponent("Support"), preferences: preferences)
        }
        let first = try library("First"), second = try library("Second")
        let registration = ICloudOwnerForegroundRegistration()
        registration.update(library: first, active: true)
        #expect(first.iCloudForegroundScenes.isActive && !second.iCloudForegroundScenes.isActive)
        registration.update(library: second, active: true)
        #expect(!first.iCloudForegroundScenes.isActive && second.iCloudForegroundScenes.isActive)
        registration.close(ifBoundTo: first)
        #expect(second.iCloudForegroundScenes.isActive)
        registration.update(library: second, active: false)
        #expect(!second.iCloudForegroundScenes.isActive)
        registration.update(library: second, active: true)
        registration.close(ifBoundTo: second)
        #expect(!second.iCloudForegroundScenes.isActive)
        #expect(!FileManager.default.fileExists(atPath: first.iCloudStorageDirectory().path))
        #expect(!FileManager.default.fileExists(atPath: second.iCloudStorageDirectory().path))
    }

}
