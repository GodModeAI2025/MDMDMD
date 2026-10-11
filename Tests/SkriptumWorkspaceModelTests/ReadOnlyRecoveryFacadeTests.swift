import Foundation
import Testing
import SkriptumCore
@testable import SkriptumWorkspaceModel

@MainActor struct ReadOnlyRecoveryFacadeTests {
    @Test func foregroundRescueReadsDurablePagesExportsPendingSourceAndRejectsBackground() throws {
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString); defer { try? FileManager.default.removeItem(at: root) }
        let documents = root.appending(path: "Documents"), support = root.appending(path: "Support")
        let store = try LibraryStore(directory: documents.appending(path: "Skriptum"))
        let space = try store.createSpace(title: "Book")
        let page = try store.createPage(spaceID: space.id, title: "Chapter", markdown: "Durable e\u{301}\r\n")
        let token = try store.beginEditing(pageID: page.id, baseRevision: page.revision)
        let source = "Pending 🦊 名 e\u{301}\r\n\r\n"
        try store.updateEditing(token, markdown: source)
        let bad = store.directory.appending(path: "edits/" + UUID().uuidString + ".json")
        try Data("damaged".utf8).write(to: bad)
        let preferences = UserDefaults(suiteName: UUID().uuidString)!
        let registry = WorkspaceWindowRegistry(documentRoot: documents, supportRoot: support, preferences: preferences)
        let locator = try LibraryStoragePaths.locator(libraryDirectory: store.directory, documentRoot: documents)
        let request = WorkspaceWindowRequest(id: UUID(), libraryID: UUID(), pageID: page.id, locator: locator)
        let library = try #require(registry.resolve(request))
        #expect(library.isReadOnlyRecovery && library.saveError != nil)
        #expect(library.pages[0].markdown.utf8.elementsEqual(page.markdown.utf8))
        let draft = try #require(library.pendingJournalDrafts.first)
        let exported = try #require(library.exportPendingJournal(draft))
        defer { try? FileManager.default.removeItem(at: exported.url.deletingLastPathComponent()) }
        #expect(try Data(contentsOf: exported.url) == Data(source.utf8))
        #expect(library.persistBeforeNavigation(library.pages[0], token: nil))
        var edited = library.pages[0]; edited.markdown = "Cannot save"
        #expect(library.update(edited) == nil)
        #expect(library.pages[0].markdown.utf8.elementsEqual(page.markdown.utf8))
        #expect(throws: WorkspaceWindowError.unavailableLibrary) { try registry.backgroundLibrary(locator) }
        #expect(try Data(contentsOf: bad) == Data("damaged".utf8))
        #expect(FileManager.default.fileExists(atPath: store.directory.appending(path: "edits/" + token.uuidString + ".json").path))
    }
}

extension ReadOnlyRecoveryFacadeTests {
    @Test func originalZipExportWorksWithoutRepairingReadOnlyLibrary() async throws {
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString); defer { try? FileManager.default.removeItem(at: root) }
        let documents = root.appending(path: "Documents")
        let store = try LibraryStore(directory: documents.appending(path: "Skriptum"))
        let space = try store.createSpace(title: "Book")
        _ = try store.createPage(spaceID: space.id, title: "Chapter", markdown: "Durable 🦊\r\n")
        let edits = store.directory.appending(path: "edits"); try FileManager.default.createDirectory(at: edits, withIntermediateDirectories: true)
        let damaged = edits.appending(path: UUID().uuidString + ".json"), bytes = Data([0xff, 0, 0xaa])
        try bytes.write(to: damaged)
        let protected = try LibraryStore(directory: store.directory, recoveryPolicy: .readOnlyOnFailure)
        let library = try WritingLibrary(store: protected, documentRoot: documents, supportRoot: root.appending(path: "Support"), preferences: UserDefaults(suiteName: UUID().uuidString)!)
        let original = try Data(contentsOf: store.directory.appending(path: "library.json"))
        let export = try #require(await library.exportRecoveryOriginals())
        defer { try? FileManager.default.removeItem(at: export.url.deletingLastPathComponent()) }
        #expect(export.url.pathExtension == "zip" && library.isReadOnlyRecovery)
        #expect(try Data(contentsOf: damaged) == bytes)
        #expect(try Data(contentsOf: store.directory.appending(path: "library.json")) == original)
    }
}
