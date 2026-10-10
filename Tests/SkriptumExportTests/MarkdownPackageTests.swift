#if os(macOS)
import Foundation
import Testing
@testable import SkriptumExport

struct MarkdownPackageTests {
    private var image: Data { Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")! }
    private func contents(_ artifact: ExportArtifact) throws -> [String: Data] {
        let root = URL(fileURLWithPath: "/private/tmp/MarkdownZIP-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let archive = root.appendingPathComponent("source.zip")
        try artifact.data.write(to: archive)
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-qq", archive.path, "-d", root.appendingPathComponent("extracted").path]
        try process.run(); process.waitUntilExit(); #expect(process.terminationStatus == 0)
        let output = root.appendingPathComponent("extracted")
        let enumerator = try #require(FileManager.default.enumerator(at: output, includingPropertiesForKeys: [.isRegularFileKey]))
        var values: [String: Data] = [:]
        for case let url as URL in enumerator where try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
            values[String(url.path.dropFirst(output.path.count + 1))] = try Data(contentsOf: url)
        }
        return values
    }
    @Test func markdownAndReferencedImageAreExactAndCodeOrUnusedAssetsDoNotLeak() throws {
        let source = "# Grüße e\u{301}\r\n\r\n![Bild](media/image.png)\r\n\r\n![Noch einmal][same]\r\n\r\n[same]: media/image.png\r\n\r\n```md\r\n![Code](media/unused.png)\r\n```\r\n"
        let input = ExportInput(title: "Source", markdown: source, author: "Autor", language: "de", assets: ["media/image.png": .init(data: image, mediaType: "image/png"), "media/unused.png": .init(data: image, mediaType: "image/png")])
        let artifact = try ExportEngine.markdownPackage(input)
        let files = try contents(artifact)
        #expect(files["document.md"] == Data(source.utf8))
        #expect(files["media/image.png"] == image)
        #expect(files["media/unused.png"] == nil)
        #expect(files.count == 4 && artifact.fileExtension == "zip")
        let manifestData = try #require(files["manifest.json"])
        let manifest = try #require(try JSONSerialization.jsonObject(with: manifestData) as? [String: Any])
        #expect(manifest["schemaVersion"] as? Int == 1)
        #expect(manifest["author"] as? String == "Autor")
        #expect(manifest["language"] as? String == "de")
    }
    @Test func chapterNamespacesPreserveOriginalUnclosedFenceAndRepeatedMediaPaths() throws {
        let first = "# Erstes\r\n\r\n![Bild](media/picture.png)\r\n\r\n```swift\r\nunfinished"
        let second = "# Zweites\n\n![Bild](media/picture.png)\n"
        let sources = [first, second].map { ExportInput(title: "Kapitel", markdown: $0, assets: ["media/picture.png": .init(data: image, mediaType: "image/png")]) }
        let files = try contents(ExportEngine.markdownManuscriptPackage(title: "Manuskript", chapters: sources))
        #expect(files["chapters/001/document.md"] == Data(first.utf8))
        #expect(files["chapters/002/document.md"] == Data(second.utf8))
        #expect(files["chapters/001/media/picture.png"] == image && files["chapters/002/media/picture.png"] == image)
        #expect(files.count == 6)
    }
    @Test func missingUnsafeReservedCaseCollisionAndCorruptImagesAreRejected() throws {
        #expect(throws: ExportError.missingAsset("media/missing.png")) { try ExportEngine.markdownPackage(.init(title: "Missing", markdown: "![x](media/missing.png)")) }
        for path in ["../outside.png", "media/%2e%2e/outside.png", "https://example.com/pic.png", "Document.md", "media/file:stream.png"] {
            #expect(throws: ExportError.self) { try ExportEngine.markdownPackage(.init(title: "Unsafe", markdown: "![x](\(path))", assets: [path: .init(data: image, mediaType: "image/png")])) }
        }
        let input = ExportInput(title: "Case", markdown: "![one](media/Pic.png)\n![two](media/pic.png)", assets: ["media/Pic.png": .init(data: image, mediaType: "image/png"), "media/pic.png": .init(data: image, mediaType: "image/png")])
        #expect(throws: ExportError.self) { try ExportEngine.markdownPackage(input) }
        #expect(throws: ExportError.unsupportedAsset("media/bad.png")) { try ExportEngine.markdownPackage(.init(title: "Bad", markdown: "![x](media/bad.png)", assets: ["media/bad.png": .init(data: Data("bad".utf8), mediaType: "image/png")])) }
    }
    @Test func rawHTMLAndLinksRemainSourceWithExplicitCollectionWarnings() throws {
        let source = "<img src=\"media/only-html.png\">\r\n\r\n[Other](other.md)\r\n"
        let artifact = try ExportEngine.markdownPackage(.init(title: "Raw", markdown: source, assets: ["media/only-html.png": .init(data: image, mediaType: "image/png")]))
        let files = try contents(artifact)
        #expect(files["document.md"] == Data(source.utf8))
        #expect(files["media/only-html.png"] == nil)
        #expect(artifact.warnings.count == 2)
    }
}
#endif
