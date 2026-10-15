import Foundation
import Testing
@testable import SkriptumCore

@MainActor struct MarkdownImportTests {
    private let image = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")!
    private func fixture(_ markdown: String) throws -> (URL, URL, LibraryStore, UUID) {
        let root = URL(fileURLWithPath: "/private/tmp/MarkdownImport-" + UUID().uuidString)
        let source = root.appendingPathComponent("source")
        try FileManager.default.createDirectory(at: source.appendingPathComponent("images"), withIntermediateDirectories: true)
        try Data(markdown.utf8).write(to: source.appendingPathComponent("document.md"))
        try image.write(to: source.appendingPathComponent("images/Photo one.png"))
        let store = try LibraryStore(directory: root.appendingPathComponent("library"))
        return (root, source, store, try store.createSpace(title: "Imported").id)
    }
    @Test func preservesOriginalBytesReferenceImagesAndPersistentPreviewAfterSourceRemoval() async throws {
        let markdown = "\u{feff}# Cafe\u{301} 🦊\r\n\r\n![First][picture]\r\n\r\n[picture]: ./images/Photo%20one.png\r\n\r\n`![code](missing.png)`\r\n\r\n```md\r\n![code](also-missing.png)\r\n```\r\n"
        let (root, source, store, space) = try fixture(markdown)
        defer { try? FileManager.default.removeItem(at: root) }
        let imported = try MarkdownImport.read(file: source.appendingPathComponent("document.md"), sourceDirectory: source)
        #expect(Data(imported.markdown.utf8) == Data(markdown.utf8))
        #expect(imported.attachments.count == 1)
        var events = 0
        store.onDurableChange = { _ in events += 1 }
        let page = try #require(try store.importMarkdown([imported], spaceID: space).first)
        #expect(events == 1 && store.snapshot.revisions.isEmpty)
        try FileManager.default.removeItem(at: source)
        let reopened = try LibraryStore(directory: store.directory)
        let saved = try #require(reopened.snapshot.pages.first)
        #expect(saved.id == page.id && Data(saved.markdown.utf8) == Data(markdown.utf8))
        let attachment = try #require(saved.attachments?.first)
        #expect(try reopened.attachmentData(attachment) == image)
        let preview = MediaPreviewSource(root: reopened.directory, attachments: saved.attachments ?? [])
        let request = try #require(preview.request(for: "./images/Photo%20one.png"))
        #expect(try await request.data() == image)
        #expect(preview.request(for: "../source/images/Photo one.png") == nil)
        let inventory = AttachmentInventory(libraryID: UUID(), snapshot: reopened.snapshot)
        #expect(inventory.entries.first?.activeReferenceCount == 1)
        let package = root.appendingPathComponent("Copy.scriptum")
        try reopened.exportPackage(to: package)
        let copy = try LibraryStore.importPackage(from: package, to: root.appendingPathComponent("copy"))
        #expect(copy.snapshot.pages.first?.attachments?.first?.storageEquals(attachment) == true)
    }
    @Test func bareFileNeverImportsNeighbouringImageAndPlainTextStillWorks() throws {
        let (root, source, store, space) = try fixture("![image](images/Photo%20one.png)")
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(throws: MarkdownImportError.folderRequired) { try MarkdownImport.read(file: source.appendingPathComponent("document.md")) }
        #expect(store.snapshot.pages.isEmpty)
        let plain = source.appendingPathComponent("plain.md")
        let bytes = Data("plain e\u{301}\r\n".utf8); try bytes.write(to: plain)
        let page = try #require(try store.importMarkdown([MarkdownImport.read(file: plain)], spaceID: space).first)
        #expect(Data(page.markdown.utf8) == bytes && page.attachments == nil)
    }
    @Test(arguments: ["../outside.png", "/private/tmp/image.png", "https://example.com/image.png", "file:///tmp/image.png", "images/%2e%2e/outside.png", "images/%252e%252e/outside.png", "images/Photo%20one.png?size=1", "images/Photo%20one.png#fragment", "images/%00.png", "images/%5csecret.png"])
    func rejectsUnsafeOrRemoteDestinationsWithoutPublishing(_ path: String) throws {
        let (root, source, store, _) = try fixture("![image](\(path))")
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(throws: MarkdownImportError.self) { try MarkdownImport.read(file: source.appendingPathComponent("document.md"), sourceDirectory: source) }
        #expect(store.snapshot.pages.isEmpty)
    }
    @Test func rejectsSourceOutsideGrantSymlinkFileAndIntermediateDirectory() throws {
        let (root, source, store, _) = try fixture("![image](images/link.png)")
        defer { try? FileManager.default.removeItem(at: root) }
        let outside = root.appendingPathComponent("outside.png"); try image.write(to: outside)
        try FileManager.default.createSymbolicLink(at: source.appendingPathComponent("images/link.png"), withDestinationURL: outside)
        #expect(throws: MarkdownImportError.unsafeSource) { try MarkdownImport.read(file: source.appendingPathComponent("document.md"), sourceDirectory: source) }
        try FileManager.default.createSymbolicLink(at: source.appendingPathComponent("linked"), withDestinationURL: root)
        try Data("![x](linked/outside.png)".utf8).write(to: source.appendingPathComponent("document.md"))
        #expect(throws: MarkdownImportError.unsafeSource) { try MarkdownImport.read(file: source.appendingPathComponent("document.md"), sourceDirectory: source) }
        let external = root.appendingPathComponent("external.md"); try Data("Outside".utf8).write(to: external)
        #expect(throws: MarkdownImportError.unsafeSource) { try MarkdownImport.read(file: external, sourceDirectory: source) }
        #expect(store.snapshot.pages.isEmpty)
        #expect(try MarkdownImport.catalog(in: source) == ["document.md"])
    }
    @Test func invalidUTF8MissingImageCorruptImageAndCaseCollisionAreActionableFailures() throws {
        let (root, source, _, _) = try fixture("![x](images/missing.png)")
        defer { try? FileManager.default.removeItem(at: root) }
        let file = source.appendingPathComponent("document.md")
        #expect(throws: MarkdownImportError.missingImage("images/missing.png")) { try MarkdownImport.read(file: file, sourceDirectory: source) }
        try Data([0xFF, 0xFE]).write(to: file)
        #expect(throws: MarkdownImportError.invalidUTF8) { try MarkdownImport.read(file: file, sourceDirectory: source) }
        try Data("![x](bad.png)".utf8).write(to: file); try Data("bad".utf8).write(to: source.appendingPathComponent("bad.png"))
        #expect(throws: MarkdownImportError.unsupportedImage("bad.png")) { try MarkdownImport.read(file: file, sourceDirectory: source) }
        try Data("![a](images/Photo%20one.png)\n![b](images/photo%20one.png)".utf8).write(to: file)
        #expect(throws: MarkdownImportError.self) { try MarkdownImport.read(file: file, sourceDirectory: source) }
    }
    @Test func failedDiskCommitRollsBackOnlyNewBlobsAndDoesNotNotify() throws {
        let (root, source, store, space) = try fixture("![x](images/Photo%20one.png)")
        defer { try? FileManager.default.removeItem(at: root) }
        let prepared = try MarkdownImport.read(file: source.appendingPathComponent("document.md"), sourceDirectory: source)
        let other = try LibraryStore(directory: store.directory)
        _ = try other.createPage(spaceID: space, title: "Foreign", markdown: "Keep")
        let persisted = try Data(contentsOf: store.directory.appendingPathComponent("library.json"))
        var events = 0; store.onDurableChange = { _ in events += 1 }
        #expect(throws: LibraryError.revisionConflict) { try store.importMarkdown([prepared], spaceID: space) }
        #expect(events == 0 && store.snapshot.pages.isEmpty)
        #expect(try Data(contentsOf: store.directory.appendingPathComponent("library.json")) == persisted)
        #expect(try FileManager.default.contentsOfDirectory(atPath: store.directory.appendingPathComponent("media").path).isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: store.directory.path).allSatisfy { !$0.hasPrefix(".markdown-import-") })
    }
    @Test func fileMutationAfterPreparationCannotChangeImportedBytes() throws {
        let (root, source, store, space) = try fixture("![x](images/Photo%20one.png)")
        defer { try? FileManager.default.removeItem(at: root) }
        let prepared = try MarkdownImport.read(file: source.appendingPathComponent("document.md"), sourceDirectory: source)
        try Data("changed".utf8).write(to: source.appendingPathComponent("images/Photo one.png"))
        let saved = try #require(try store.importMarkdown([prepared], spaceID: space).first)
        #expect(try store.attachmentData(#require(saved.attachments?.first)) == image)
    }
    @Test func pathDecoderSeparatesLookupKeysFromFileNames() {
        #expect(MarkdownAssetPath.filePath(for: "./images/Photo%20one.png") == "images/Photo one.png")
        #expect(MarkdownAssetPath.filePath(for: "images/100%25.png") == "images/100%.png")
        #expect(MarkdownAssetPath.filePath(for: "images/a%2Fb.png") == "images/a/b.png")
        #expect(MarkdownAssetPath.filePath(for: "./") == nil)
        #expect(MarkdownAssetPath.filePath(for: "images/a.png/.") == nil)
        #expect(MarkdownAssetPath.filePath(for: "images/a.png/%2e") == nil)
        #expect(MarkdownAssetPath.filePath(for: "images/./a.png") == "images/a.png")
        #expect(MarkdownAssetPath.filePath(for: "a/%252e%252e/b.png") == nil)
    }
    @Test func publishedOrHistoricalImagesNeverQualifyForFailedCommitRollback() throws {
        let (root, source, store, space) = try fixture("![x](images/Photo%20one.png)")
        defer { try? FileManager.default.removeItem(at: root) }
        let document = try MarkdownImport.read(file: source.appendingPathComponent("document.md"), sourceDirectory: source)
        let ids = Set(document.attachments.map(\.id))
        #expect(LibraryStore.markdownImportIsUnreferenced(ids, in: store.snapshot))
        let page = try #require(try store.importMarkdown([document], spaceID: space).first)
        #expect(!LibraryStore.markdownImportIsUnreferenced(ids, in: store.snapshot))
        var historyOnly = store.snapshot
        historyOnly.pages = []
        historyOnly.revisions = [Revision(page: page, author: "Writer", capturedAt: Date())]
        #expect(!LibraryStore.markdownImportIsUnreferenced(ids, in: historyOnly))
    }
    @Test func importRejectsReservedExportFileDirectoryPrefixesBeforeReadingImages() throws {
        let (root, source, _, _) = try fixture("![x](manifest.json/image.png)")
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(throws: MarkdownImportError.conflictingImagePath("manifest.json/image.png")) {
            try MarkdownImport.read(file: source.appendingPathComponent("document.md"), sourceDirectory: source)
        }
    }
    @Test func storageRejectsReplacedMediaDirectoryAndRollbackNeverTouchesOutsideFiles() throws {
        let (root, source, store, _) = try fixture("![x](images/Photo%20one.png)")
        defer { try? FileManager.default.removeItem(at: root) }
        let prepared = try MarkdownImport.read(file: source.appendingPathComponent("document.md"), sourceDirectory: source)
        let attachment = try #require(prepared.attachments.first)
        let storage = try MarkdownImportStorage(directory: store.directory)
        try storage.write(image, attachment: attachment)
        let media = store.directory.appendingPathComponent("media"), old = store.directory.appendingPathComponent("old-media")
        let outside = root.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let sentinel = outside.appendingPathComponent(attachment.id.uuidString)
        let keep = Data("Keep outside file".utf8); try keep.write(to: sentinel)
        try FileManager.default.moveItem(at: media, to: old)
        try FileManager.default.createSymbolicLink(at: media, withDestinationURL: outside)
        #expect(throws: LibraryError.invalidAttachment) { try storage.finishWrites() }
        #expect(throws: LibraryError.invalidAttachment) { try storage.write(image, attachment: attachment) }
        storage.rollback()
        #expect(try Data(contentsOf: sentinel) == keep)
        #expect(!FileManager.default.fileExists(atPath: old.appendingPathComponent(attachment.id.uuidString).path))
        #expect(throws: LibraryError.invalidAttachment) { try MarkdownImportStorage(directory: store.directory) }
    }
    @Test func rollbackDoesNotDeleteReplacementFileAndSystemDirectoryAliasesWork() throws {
        let (root, source, store, _) = try fixture("![x](images/Photo%20one.png)")
        defer { try? FileManager.default.removeItem(at: root) }
        let prepared = try MarkdownImport.read(file: source.appendingPathComponent("document.md"), sourceDirectory: source)
        let attachment = try #require(prepared.attachments.first)
        let alias = URL(fileURLWithPath: store.directory.path.replacingOccurrences(of: "/private/tmp/", with: "/tmp/"))
        let storage = try MarkdownImportStorage(directory: alias)
        try storage.write(image, attachment: attachment)
        try storage.finishWrites()
        let replacement = Data("A different file owns this path now".utf8)
        let target = store.directory.appendingPathComponent(attachment.relativePath)
        try replacement.write(to: target, options: .atomic)
        storage.rollback()
        #expect(try Data(contentsOf: target) == replacement)
    }
    @Test func aliasLibrariesAndPackagesAdvertiseAReaderVersionLegacyClientsReject() throws {
        // The released reader's exact admission rule was schemaVersion == 1.
        // Codable itself ignores unknown sourcePath fields, so the outer gate
        // must reject before an older client can re-encode this metadata.
        struct LegacyHeader: Decodable { let schemaVersion: Int }
        struct PackageHeader: Decodable { let formatVersion: Int }
        func legacyRead(_ bytes: Data) throws {
            guard try JSONDecoder().decode(LegacyHeader.self, from: bytes).schemaVersion == 1 else { throw LibraryError.unsupportedSchema }
        }
        let (root, source, store, space) = try fixture("![x](images/Photo%20one.png)")
        defer { try? FileManager.default.removeItem(at: root) }
        let original = try Data(contentsOf: store.directory.appendingPathComponent("library.json"))
        try legacyRead(original)
        let imported = try MarkdownImport.read(file: source.appendingPathComponent("document.md"), sourceDirectory: source)
        _ = try store.importMarkdown([imported], spaceID: space)
        #expect(store.snapshot.schemaVersion == 2)
        let current = try Data(contentsOf: store.directory.appendingPathComponent("library.json"))
        #expect(throws: LibraryError.unsupportedSchema) { try legacyRead(current) }
        #expect(try LibraryStore(directory: store.directory).snapshot.schemaVersion == 2)
        let package = root.appendingPathComponent("Source.scriptum")
        try store.exportPackage(to: package)
        let manifest = try Data(contentsOf: package.appendingPathComponent("manifest.json"))
        #expect(try JSONDecoder().decode(PackageHeader.self, from: manifest).formatVersion == 2)
        let roundtrip = try LibraryStore.importPackage(from: package, to: root.appendingPathComponent("again"))
        #expect(roundtrip.snapshot == store.snapshot)
        var staged = store.snapshot; staged.schemaVersion = 1
        #expect(try JSONDecoder().decode(LegacyHeader.self, from: JSONEncoder().encode(staged)).schemaVersion == 2)
    }
}
