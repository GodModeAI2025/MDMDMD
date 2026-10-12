import Foundation
import Testing
import SkriptumCore
@testable import SkriptumWorkspaceModel

@MainActor struct MarkdownFileCreationTests {
    @Test func createsUniqueVisibleFileAndImportsPageIntoSpace() throws {
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString); defer { try? FileManager.default.removeItem(at: root) }
        let documents = root.appending(path: "Documents")
        let store = try LibraryStore(directory: documents.appending(path: "Skriptum"))
        _ = try store.createSpace(title: "Erster")
        let target = try store.createSpace(title: "Buch")
        let library = try WritingLibrary(store: store, documentRoot: documents, supportRoot: root.appending(path: "Support"), preferences: UserDefaults(suiteName: UUID().uuidString)!)
        let existing = documents.appending(path: "Unbenannt.md"), bytes = Data("Bleibt 🦊".utf8)
        try bytes.write(to: existing)
        let id = try #require(library.createMarkdownFile(spaceID: target.id))
        let file = documents.appending(path: "Unbenannt 2.md")
        #expect(try Data(contentsOf: file).isEmpty)
        #expect(try Data(contentsOf: existing) == bytes)
        let page = try #require(library.pages.first(where: { $0.id == id }))
        #expect(page.spaceID == target.id && page.title == "Unbenannt 2" && page.markdown.isEmpty)
        #expect(library.saveError == nil)
        let next = try #require(library.createMarkdownFile(spaceID: nil))
        #expect(FileManager.default.fileExists(atPath: documents.appending(path: "Unbenannt 3.md").path))
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
        #expect(library.createMarkdownFile(spaceID: space.id) == nil)
        #expect(library.saveError == library.recoveryNotice)
        #expect(library.pages.count == 1)
        let markdown = try FileManager.default.contentsOfDirectory(atPath: documents.path).filter { $0.hasSuffix(".md") }
        #expect(markdown.isEmpty)
    }
}
