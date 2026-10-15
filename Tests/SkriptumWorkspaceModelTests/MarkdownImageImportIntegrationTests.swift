import Foundation
import Testing
import SkriptumCore
import SkriptumExport
@testable import SkriptumWorkspaceModel

@MainActor struct MarkdownImageImportIntegrationTests {
    private let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")!
    private func fixture() throws -> (URL, LibraryStore, WritingLibrary, UUID) {
        let root = URL(fileURLWithPath: "/private/tmp/MarkdownImportIntegration-" + UUID().uuidString)
        let store = try LibraryStore(directory: root.appendingPathComponent("Documents/Skriptum"))
        let space = try store.createSpace(title: "Book")
        let library = try WritingLibrary(store: store, documentRoot: root.appendingPathComponent("Documents"), supportRoot: root.appendingPathComponent("Support"), preferences: UserDefaults(suiteName: UUID().uuidString)!)
        return (root, store, library, space.id)
    }
    private func writeSource(root: URL, markdown: String) throws -> URL {
        try FileManager.default.createDirectory(at: root.appendingPathComponent("images"), withIntermediateDirectories: true)
        try png.write(to: root.appendingPathComponent("images/Cafe\u{301} one.png"))
        let file = root.appendingPathComponent("document.md")
        try Data(markdown.utf8).write(to: file)
        return file
    }
    private func extract(_ archive: Data, at root: URL) throws -> URL {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("source.zip"), output = root.appendingPathComponent("unpacked")
        try archive.write(to: file)
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-qq", file.path, "-d", output.path]
        // Use an installed macOS UTF-8 locale for the external archive reader.
        process.environment = ProcessInfo.processInfo.environment.merging(["LANG": "en_US.UTF-8", "LC_ALL": "en_US.UTF-8"]) { _, value in value }
        let diagnostics = Pipe(); process.standardError = diagnostics; process.standardOutput = diagnostics
        try process.run(); process.waitUntilExit()
        let message = String(decoding: diagnostics.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        #expect(process.terminationStatus == 0, "\(message)")
        return output
    }
    @Test func folderImportPreviewAllExportsAndUnpackedZIPReimportUseSameImages() async throws {
        let (root, store, library, space) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("chosen")
        let source = "# Café 🦊\r\n\r\n![One](./images/Cafe%CC%81%20one.png)\r\n\r\n![Two](images/Cafe%CC%81%20one.png)\r\n"
        let file = try writeSource(root: folder, markdown: source)
        let imported = await library.importMarkdown(files: [file], sourceDirectory: folder, spaceID: space)
        let id = try #require(imported?.first), page = try #require(library.currentPage(id))
        #expect(Data(page.markdown.utf8) == Data(source.utf8))
        try FileManager.default.removeItem(at: folder)
        let assets = try library.exportAssets(for: page)
        #expect(assets["./images/Cafe%CC%81%20one.png"]?.data == png)
        #expect(assets["images/Cafe%CC%81%20one.png"]?.data == png)
        let preview = MediaPreviewSource(root: store.directory, attachments: page.attachments ?? [])
        let request = try #require(preview.request(for: "./images/Cafe%CC%81%20one.png"))
        #expect(try await request.data() == assets["./images/Cafe%CC%81%20one.png"]?.data)
        let input = ExportInput(title: page.title, markdown: page.markdown, assets: assets)
        for format in ExportFormat.allCases { #expect(!(try ExportEngine.export(input, format: format)).data.isEmpty) }
        let pdf = try await ExportEngine.renderSemanticPDF(input)
        #expect(!pdf.data.isEmpty)
        let unpacked = try extract(ExportEngine.markdownPackage(input).data, at: root.appendingPathComponent("export"))
        #expect(try Data(contentsOf: unpacked.appendingPathComponent("document.md")) == Data(source.utf8))
        #expect(try Data(contentsOf: unpacked.appendingPathComponent("images/Cafe\u{301} one.png")) == png)
        #expect(try FileManager.default.contentsOfDirectory(atPath: unpacked.appendingPathComponent("images").path).count == 1)
        let again = await library.importMarkdown(files: [unpacked.appendingPathComponent("document.md")], sourceDirectory: unpacked, spaceID: space)
        let restoredID = try #require(again?.first)
        let restored = try #require(library.currentPage(restoredID))
        #expect(restored.id != page.id && Data(restored.markdown.utf8) == Data(page.markdown.utf8))
        #expect(try library.exportAssets(for: restored)["./images/Cafe%CC%81%20one.png"]?.data == png)
    }
    @Test func exportedCanonicalImageAndManuscriptChapterNamespacesReimportWithoutRewriting() async throws {
        let (root, store, library, space) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = try store.createPage(spaceID: space, title: "Original", markdown: "")
        let saved = try store.addImageBlock(pageID: original.id, data: png, mediaType: "image/png", filename: "one.png", altText: "Image", afterBlockID: nil, baseRevision: original.revision).page
        library.reload()
        let page = try #require(library.currentPage(saved.id))
        let input = ExportInput(title: "Chapter", markdown: page.markdown, assets: try library.exportAssets(for: page))
        let unpacked = try extract(ExportEngine.markdownManuscriptPackage(title: "Book", chapters: [input, input]).data, at: root.appendingPathComponent("export"))
        let chapters = ["chapters/001/document.md", "chapters/002/document.md"]
        #expect(try MarkdownImport.catalog(in: unpacked).filter { $0.hasPrefix("chapters/") } == chapters)
        let imported = await library.importMarkdown(files: chapters.map { unpacked.appendingPathComponent($0) }, sourceDirectory: unpacked, spaceID: space)
        #expect(imported?.count == 2)
        for id in imported ?? [] {
            let chapter = try #require(library.currentPage(id))
            #expect(Data(chapter.markdown.utf8) == Data(page.markdown.utf8))
            let destination = try #require(page.attachments?.first?.relativePath)
            #expect(try library.exportAssets(for: chapter)[destination]?.data == png)
        }
    }
    @Test func invalidSecondDocumentRollsBackTheEntireSelectionAndBareImportExplainsFolder() async throws {
        let (root, store, library, space) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("chosen")
        let file = try writeSource(root: folder, markdown: "![One](images/Cafe%CC%81%20one.png)")
        #expect(library.importMarkdown(url: file, spaceID: space) == nil)
        #expect(library.saveError?.contains("Markdown mit Bildern importieren") == true)
        let invalid = folder.appendingPathComponent("second.md")
        try Data("![missing](absent.png)".utf8).write(to: invalid)
        let before = try Data(contentsOf: store.directory.appendingPathComponent("library.json"))
        var events = 0; store.onDurableChange = { _ in events += 1 }
        #expect(await library.importMarkdown(files: [file, invalid], sourceDirectory: folder, spaceID: space) == nil)
        #expect(events == 0 && store.snapshot.pages.isEmpty)
        #expect(try Data(contentsOf: store.directory.appendingPathComponent("library.json")) == before)
        #expect(library.saveError?.contains("absent.png") == true)
    }
}
