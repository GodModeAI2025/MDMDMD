import Foundation
import Testing
import SkriptumCore
@testable import SkriptumWorkspaceModel

@MainActor struct MarkdownFileCreationTests {
    @Test func libraryPageExportsActualEditedTextWithoutPhantomFile() throws {
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString); defer { try? FileManager.default.removeItem(at: root) }
        let documents = root.appending(path: "Documents")
        let store = try LibraryStore(directory: documents.appending(path: "Skriptum"))
        _ = try store.createSpace(title: "Erster")
        let target = try store.createSpace(title: "Buch")
        let library = try WritingLibrary(store: store, documentRoot: documents, supportRoot: root.appending(path: "Support"), preferences: UserDefaults(suiteName: UUID().uuidString)!)
        let existing = documents.appending(path: "Unbenannt.md"), bytes = Data("Bleibt 🦊".utf8)
        try bytes.write(to: existing)
        let id = try #require(library.createPage(spaceID: target.id))
        let file = documents.appending(path: "Unbenannt 2.md")
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(try Data(contentsOf: existing) == bytes)
        let page = try #require(library.pages.first(where: { $0.id == id }))
        #expect(page.spaceID == target.id && page.title == "Neue Seite" && page.markdown.isEmpty)
        #expect(library.saveError == nil)
        let next = try #require(library.createPage(spaceID: nil))
        #expect(!FileManager.default.fileExists(atPath: documents.appending(path: "Unbenannt 3.md").path))
        var edited = page; edited.markdown = "Geschrieben: Café é 🦊\r\n\n**Text**\r\n"
        _ = try #require(library.update(edited))
        let saved = try #require(library.currentPage(id))
        let exported = try #require(library.exportMarkdown(saved))
        defer { try? FileManager.default.removeItem(at: exported.url.deletingLastPathComponent()) }
        #expect(try Data(contentsOf: exported.url) == Data(edited.markdown.utf8))
        #expect(try Data(contentsOf: existing) == bytes)
        #expect(library.pages.first(where: { $0.id == next })?.spaceID == library.spaces.first?.id)
        #expect(try LibraryStore(directory: store.directory).snapshot.pages.contains(where: { $0.id == id && $0.spaceID == target.id }))
    }

    @Test func readOnlyRecoveryRefusesWithoutWritingFile() throws {
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString); defer { try? FileManager.default.removeItem(at: root) }
        let documents = root.appending(path: "Documents")
        let store = try LibraryStore(directory: documents.appending(path: "Skriptum"))
        let space = try store.createSpace(title: "Buch")
        _ = try store.createPage(spaceID: space.id, title: "Kapitel", markdown: "Text\n")
        let edits = store.directory.appending(path: "edits"); try FileManager.default.createDirectory(at: edits, withIntermediateDirectories: true)
        try Data([0xff, 0, 0xaa]).write(to: edits.appending(path: UUID().uuidString + ".json"))
        let protected = try LibraryStore(directory: store.directory, recoveryPolicy: .readOnlyOnFailure)
        let library = try WritingLibrary(store: protected, documentRoot: documents, supportRoot: root.appending(path: "Support"), preferences: UserDefaults(suiteName: UUID().uuidString)!)
        #expect(library.isReadOnlyRecovery)
        library.saveError = nil
        #expect(library.createPage(spaceID: space.id) == nil)
        #expect(library.saveError != nil)
        #expect(library.pages.count == 1)
        let markdown = try FileManager.default.contentsOfDirectory(atPath: documents.path).filter { $0.hasSuffix(".md") }
        #expect(markdown.isEmpty)
    }
}
