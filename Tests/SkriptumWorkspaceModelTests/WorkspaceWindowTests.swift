import Foundation
import Testing
import SkriptumCore
@testable import SkriptumWorkspaceModel

@MainActor struct WorkspaceWindowTests {
    private func library(_ root: URL, _ name: String) throws -> WritingLibrary {
        let documents = root.appending(path: "Documents")
        let store = try LibraryStore(directory: documents.appending(path: "ScriptumLibraries/" + name))
        let space = try store.createSpace(title: name)
        _ = try store.createPage(spaceID: space.id, title: name, markdown: "Initial 🦊\r\n\r\n")
        return try WritingLibrary(store: store, documentRoot: documents,
            supportRoot: root.appending(path: "Support"), preferences: UserDefaults(suiteName: UUID().uuidString)!)
    }
    @Test func handoffRetainsExactFacadeAndStoreWithoutDefaultLibraryFallback() throws {
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let a = try library(root, UUID().uuidString), b = try library(root, UUID().uuidString)
        let registry = registry(root), now = Date()
        let request = try registry.request(library: a, pageID: a.pages[0].id, now: now)
        #expect(request.libraryID == a.libraryIdentity)
        #expect(registry.resolve(request, now: now) === a)
        #expect(registry.resolve(request, now: now)?.store === a.store)
        #expect(registry.resolve(request, now: now) !== b)
        // SwiftUI may construct a host more than once before it appears.
        #expect(registry.resolve(request, now: now) === a)
        let claimed = try #require(registry.claim(request, now: now))
        #expect(claimed === a && claimed.store === a.store)
        #expect(registry.resolve(request, now: now) === a)
        #expect(claimed.pages[0].id == request.pageID)
        #expect(registry.resolve(WorkspaceWindowRequest(id: UUID(), libraryID: b.libraryIdentity, pageID: nil, locator: .imported(UUID())), now: now) == nil)
    }
    @Test func requestsAreUniqueBoundedExpireAndRejectForgedIdentity() throws {
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let a = try library(root, UUID().uuidString), now = Date()
        let registry = WorkspaceWindowRegistry(lifetime: 2, capacity: 2, documentRoot: root.appending(path: "Documents"), supportRoot: root.appending(path: "Support"), preferences: UserDefaults(suiteName: UUID().uuidString)!)
        let one = try registry.request(library: a, pageID: UUID(), now: now)
        let two = try registry.request(library: a, pageID: nil, now: now)
        #expect(one.id != two.id && one.pageID == nil)
        #expect(throws: WorkspaceWindowError.tooManyPendingWindows) { try registry.request(library: a, pageID: nil, now: now) }
        #expect(registry.resolve(WorkspaceWindowRequest(id: one.id, libraryID: UUID(), pageID: one.pageID, locator: one.locator), now: now) == nil)
        #expect(registry.resolve(WorkspaceWindowRequest(id: one.id, libraryID: one.libraryID, pageID: UUID(), locator: one.locator), now: now) == nil)
        #expect(registry.resolve(one, now: now.addingTimeInterval(3)) == nil)
        #expect(try registry.request(library: a, pageID: nil, now: now.addingTimeInterval(3)).id != one.id)
        #expect(try JSONDecoder().decode(WorkspaceWindowRequest.self, from: JSONEncoder().encode(two)) == two)
    }
    private func registry(_ root: URL) -> WorkspaceWindowRegistry {
        WorkspaceWindowRegistry(documentRoot: root.appending(path: "Documents"), supportRoot: root.appending(path: "Support"), preferences: UserDefaults(suiteName: UUID().uuidString)!)
    }
    @Test func coldRegistryRestoresRequestedLibraryRatherThanDifferentDefault() throws {
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let a = try library(root, UUID().uuidString)
        let request = try registry(root).request(library: a, pageID: a.pages[0].id)
        let bDirectory = root.appending(path: "Documents/ScriptumLibraries/" + UUID().uuidString)
        try FileManager.default.copyItem(at: a.store!.directory, to: bDirectory)
        let b = try WritingLibrary(store: LibraryStore(directory: bDirectory), documentRoot: root.appending(path: "Documents"), supportRoot: root.appending(path: "Support"), preferences: UserDefaults(suiteName: UUID().uuidString)!)
        let cold = registry(root)
        try cold.register(b)
        let restored = try #require(cold.resolve(try JSONDecoder().decode(WorkspaceWindowRequest.self, from: JSONEncoder().encode(request))))
        #expect(restored !== b && restored.store !== b.store)
        #expect(restored.pages[0].id == b.pages[0].id)
        #expect(try restored.ownedWindowLocator() == request.locator)
        #expect(cold.resolve(request) === restored)
        #expect(try cold.register(restored) === restored)
    }

    @Test func missingCorruptAndSymlinkRestorationNeverCreatesOrOverwrites() throws {
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let a = try library(root, UUID().uuidString), source = a.store!.directory
        let request = try registry(root).request(library: a, pageID: a.pages[0].id)
        let missing = WorkspaceWindowRequest(id: UUID(), libraryID: UUID(), pageID: request.pageID, locator: .imported(UUID()))
        let missingURL = try LibraryStoragePaths.libraryDirectory(locator: missing.locator, documentRoot: root.appending(path: "Documents"))
        #expect(registry(root).resolve(missing) == nil)
        #expect(!FileManager.default.fileExists(atPath: missingURL.path))
        let file = source.appending(path: "library.json"), bad = Data("invalid UTF8 JSON 🦊".utf8)
        try bad.write(to: file)
        #expect(registry(root).resolve(request) == nil)
        #expect(try Data(contentsOf: file) == bad)
        let outside = root.appending(path: "outside.json")
        try bad.write(to: outside); try FileManager.default.removeItem(at: file)
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: outside)
        #expect(registry(root).resolve(request) == nil)
        #expect(try Data(contentsOf: outside) == bad)
        for json in [#"{"schemaVersion":1,"kind":"../../outside"}"#, #"{"schemaVersion":1,"kind":"imported","id":"../../outside"}"#, #"{"schemaVersion":1,"kind":"primary","id":"../../outside"}"#] {
            #expect(throws: (any Error).self) { try JSONDecoder().decode(OwnedLibraryLocator.self, from: Data(json.utf8)) }
        }
    }
    @Test func coldRestorationRecoversNormalJournalExactlyOnceAndReusesLiveStore() throws {
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let a = try library(root, UUID().uuidString), store = try #require(a.store)
        let page = store.snapshot.pages[0]
        let request = try registry(root).request(library: a, pageID: page.id)
        let token = try store.beginEditing(pageID: page.id, baseRevision: page.revision)
        let draft = "Cold 🦊 e\u{301}\r\n\r\n"
        try store.updateEditing(token, markdown: draft)
        let acceptedIDs = store.snapshot.pages[0].blocks.map(\.id)
        // A fresh session registry simulates process-local caches disappearing.
        let cold = registry(root), restored = try #require(cold.resolve(request))
        #expect(restored.pages[0].markdown.utf8.elementsEqual(draft.utf8))
        #expect(restored.store!.snapshot.revisions.contains { $0.page.revision == page.revision })
        #expect(cold.resolve(request)?.store === restored.store)
        #expect(!restored.store!.hasActiveEdits)
        #expect(!FileManager.default.fileExists(atPath: store.directory.appending(path: "edits/" + token.uuidString + ".json").path))
        #expect(restored.store!.snapshot.pages[0].blocks.map(\.id) == acceptedIDs)
        let next = try restored.store!.beginEditing(pageID: page.id, baseRevision: restored.pages[0].revision)
        let live = registry(root); try live.register(restored)
        #expect(live.resolve(request) === restored && restored.store!.hasActiveEdits)
        try restored.store!.finishEditing(next)
    }

    @Test func primaryRestoresFromExistingStorageAndMissingPrimaryNeverCreates() throws {
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let documents = root.appending(path: "Documents"), directory = documents.appending(path: "Skriptum")
        let store = try LibraryStore(directory: directory)
        let space = try store.createSpace(title: "Primary")
        let page = try store.createPage(spaceID: space.id, title: "Primary", markdown: "Primary e\u{301}\r\n")
        let facade = try WritingLibrary(store: store, documentRoot: documents, supportRoot: root.appending(path: "Support"), preferences: UserDefaults(suiteName: UUID().uuidString)!)
        let request = try registry(root).request(library: facade, pageID: page.id)
        #expect(request.locator == .primary)
        let restored = try #require(registry(root).resolve(request))
        #expect(restored.pages[0].markdown.utf8.elementsEqual(page.markdown.utf8))
        let before = try Data(contentsOf: directory.appending(path: "library.json"))
        #expect(try Data(contentsOf: directory.appending(path: "library.json")) == before)
        try FileManager.default.removeItem(at: directory)
        #expect(registry(root).resolve(request) == nil)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

}
