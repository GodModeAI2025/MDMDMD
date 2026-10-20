import Foundation
import Testing
import SkriptumCore
@testable import SkriptumWorkspaceModel

@MainActor struct ExternalMarkdownImportTests {
    @Test func openingFirstMarkdownInEmptyLibraryCreatesDestinationAndPreservesOriginal() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let documents = root.appendingPathComponent("Documents")
        let store = try LibraryStore(directory: documents.appendingPathComponent("Skriptum"))
        let library = try WritingLibrary(store: store, documentRoot: documents, supportRoot: root.appendingPathComponent("Support"), preferences: UserDefaults(suiteName: UUID().uuidString)!)
        let file = root.appendingPathComponent("External.md")
        let bytes = Data("# External\r\n\r\ncafe\u{301} 🦊\r\n".utf8)
        try bytes.write(to: file)

        let id = try #require(library.importMarkdown(url: file, spaceID: nil))

        #expect(library.spaces.count == 1)
        let page = try #require(library.currentPage(id))
        #expect(page.spaceID == library.spaces.first?.id)
        #expect(Data(page.markdown.utf8) == bytes)
        #expect(try Data(contentsOf: file) == bytes)
        #expect(library.saveError == nil)
    }

    @Test func unreadableExternalDocumentDoesNotCreateSpaceOrPage() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let documents = root.appendingPathComponent("Documents")
        let store = try LibraryStore(directory: documents.appendingPathComponent("Skriptum"))
        let library = try WritingLibrary(store: store, documentRoot: documents, supportRoot: root.appendingPathComponent("Support"), preferences: UserDefaults(suiteName: UUID().uuidString)!)
        let file = root.appendingPathComponent("Invalid.md")
        try Data([0xff, 0xfe, 0x00]).write(to: file)

        #expect(library.importMarkdown(url: file, spaceID: nil) == nil)
        #expect(library.pages.isEmpty && library.spaces.isEmpty)
        #expect(library.saveError != nil)
    }
}
