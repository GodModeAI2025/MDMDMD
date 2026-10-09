import Foundation
import Testing
import SkriptumCore
@testable import SkriptumWorkspaceModel

@MainActor struct CloudBindingFacadeTests {
    @Test func ownedFacadeKeepsBindingOutsideDocumentsAndPreservesSiblingContent() throws {
        let root = URL(fileURLWithPath: "/private/tmp/CloudFacade-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let documents = root.appending(path: "Documents"), support = root.appending(path: "Support")
        let defaults = try #require(UserDefaults(suiteName: "CloudFacade-" + UUID().uuidString))
        var libraries: [WritingLibrary] = []
        for _ in 0..<2 {
            let directory = try LibraryStoragePaths.libraryDirectory(locator: .imported(UUID()), documentRoot: documents)
            let store = try LibraryStore(directory: directory)
            let space = try store.createSpace(title: "Recherche")
            try store.createPage(spaceID: space.id, title: "Original", markdown: "Unverändert: e\u{301} 🖋️")
            libraries.append(try WritingLibrary(store: store, documentRoot: documents, supportRoot: support, preferences: defaults))
        }
        let snapshots = try libraries.map { try Data(contentsOf: #require($0.store).directory.appending(path: "library.json")) }
        let first = try libraries[0].cloudBindingRepository()
        let second = try libraries[1].cloudBindingRepository()
        #expect(try first.locator == libraries[0].ownedWindowLocator())
        #expect(first.fileURL != second.fileURL)
        #expect(first.fileURL.path.hasPrefix(support.path + "/"))
        let binding = try CloudLibraryBinding(locator: first.locator, origin: "https://workspace.example", profileID: "apple", accountID: UUID(), remoteLibraryID: UUID())
        try first.save(binding, replacing: nil)
        #expect(try first.load() == binding)
        #expect(try second.load() == nil)
        try first.remove(expected: binding)
        for (index, library) in libraries.enumerated() {
            #expect(try Data(contentsOf: #require(library.store).directory.appending(path: "library.json")) == snapshots[index])
        }
    }
}
