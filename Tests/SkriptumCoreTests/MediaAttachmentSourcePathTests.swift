import Foundation
import Testing
@testable import SkriptumCore

private let sourcePathPNG = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=")!

private func sourcePathImage(id: UUID = UUID(), path: String? = "./images/Foo%20Bar.png", filename: String = "Foo Bar.png") -> MediaAttachment {
    MediaAttachment(id: id, filename: filename, mediaType: "image/png", byteCount: sourcePathPNG.count,
        sha256: MediaValidation.digest(sourcePathPNG), sourcePath: path)
}

struct MediaAttachmentSourcePathTests {
    @Test func legacyMetadataStillDecodesAndEncodesWithoutAnAliasField() throws {
        struct Legacy: Codable {
            let id: UUID, filename: String, mediaType: String, byteCount: Int, sha256: String
        }
        let image = sourcePathImage(path: nil)
        let legacy = Legacy(id: image.id, filename: image.filename, mediaType: image.mediaType,
            byteCount: image.byteCount, sha256: image.sha256)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let oldBytes = try encoder.encode(legacy)
        let restored = try JSONDecoder().decode(MediaAttachment.self, from: oldBytes)
        #expect(restored.sourcePath == nil)
        #expect(restored.storageEquals(image))
        #expect(try encoder.encode(restored) == oldBytes)
        #expect(restored.referencePaths == [image.relativePath])
    }

    @Test func aliasIsAnExactLookupKeyAndNeverChangesCanonicalStorage() throws {
        let image = sourcePathImage(path: "./images/Foo%20Bar.png")
        #expect(image.relativePath == "media/" + image.id.uuidString)
        #expect(image.referencePaths == [image.relativePath, "./images/Foo%20Bar.png"])
        #expect(image.matches(reference: image.relativePath))
        #expect(image.matches(reference: "./images/Foo%20Bar.png"))
        #expect(!image.matches(reference: "images/Foo Bar.png"))
        #expect(!image.matches(reference: "./images/Foo%20Bar.png?download=1"))
        #expect(!image.matches(reference: "https://example.test/" + image.relativePath))
        let canonicalAlias = sourcePathImage(id: image.id, path: image.relativePath)
        #expect(canonicalAlias.referencePaths == [image.relativePath])
    }

    @Test func descriptorAndPageStorageComparisonKeepUnicodeAliasBytesDistinct() {
        let first = sourcePathImage(path: "images/é.png")
        let second = sourcePathImage(id: first.id, path: "images/e\u{301}.png")
        #expect(first == second) // Swift canonical-equivalence comparison.
        #expect(!first.storageEquals(second))
        #expect(!ICloudImagePayload.descriptorsMatch(first, second))
        #expect(!first.matches(reference: "images/e\u{301}.png"))
        #expect(!first.storageEquals(sourcePathImage(id: first.id, path: nil)))
        var page = Page(spaceID: UUID(), title: "Image"); page.attachments = [first]
        var different = page; different.attachments = [second]
        #expect(!page.storageEquals(different))
    }

    @Test func snapshotAndRevisionRoundTripsRetainAliasAndOriginalMarkdownBytes() throws {
        let image = sourcePathImage(path: "./images/e%CC%81.png")
        let markdown = "Illustration e\u{301}\r\n![Exact](./images/e%CC%81.png)\r\n"
        var page = Page(spaceID: UUID(), title: "Original", markdown: markdown); page.attachments = [image]
        var snapshot = LibrarySnapshot(); snapshot.pages = [page]
        snapshot.revisions = [Revision(page: page, author: "Writer", capturedAt: Date())]
        let bytes = try JSONEncoder().encode(snapshot)
        let restored = try JSONDecoder().decode(LibrarySnapshot.self, from: bytes)
        #expect(restored.pages[0].markdown.utf8.elementsEqual(markdown.utf8))
        #expect(restored.pages[0].attachments?[0].storageEquals(image) == true)
        #expect(restored.revisions[0].page.attachments?[0].storageEquals(image) == true)
    }

    @Test func previewRequiresExactlyOnePageLocalDescriptor() {
        let first = sourcePathImage(), second = sourcePathImage()
        let root = URL(fileURLWithPath: "/private/tmp/unused-preview-root")
        let ordinary = MediaPreviewSource(root: root, attachments: [first])
        #expect(ordinary.request(for: first.sourcePath!)?.attachment.storageEquals(first) == true)
        #expect(ordinary.request(for: first.relativePath)?.attachment.storageEquals(first) == true)
        #expect(ordinary.request(for: "images/Foo Bar.png") == nil)
        #expect(MediaPreviewSource(root: root, attachments: []).request(for: first.sourcePath!) == nil)
        #expect(MediaPreviewSource(root: root, attachments: [first, second]).request(for: first.sourcePath!) == nil)
    }

    @Test @MainActor func aliasPreviewLoadsCanonicalBytesEvenWhenOriginalPathHasDifferentBytes() async throws {
        let root = URL(fileURLWithPath: "/private/tmp/ScriptumAliasPreview-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try LibraryStore(directory: root), image = sourcePathImage(path: "images/Original.png")
        try store.importICloudImage(ICloudImagePayload(attachment: image, revisionID: UUID(), data: sourcePathPNG))
        let unrelated = root.appendingPathComponent("images/Original.png")
        try FileManager.default.createDirectory(at: unrelated.deletingLastPathComponent(), withIntermediateDirectories: true)
        let witness = Data("Do not read or replace this unrelated file.".utf8)
        try witness.write(to: unrelated)
        let request = try #require(MediaPreviewSource(root: root, attachments: [image]).request(for: image.sourcePath!))
        #expect(try await request.data() == MediaValidation.readEncodedPreview(image, root: root))
        #expect(try Data(contentsOf: root.appendingPathComponent(image.relativePath)) == sourcePathPNG)
        #expect(try Data(contentsOf: unrelated) == witness)
    }

    @Test func inventoryResolvesAliasesOnlyWithinEachPageAndIgnoresCode() {
        let image = sourcePathImage(path: "images/local.png"), space = UUID()
        var first = Page(spaceID: space, title: "Owner", markdown: "![Image](images/local.png)\n\n[Open](images/local.png)\n\n`![Code](images/local.png)`\n\n```md\n![Code](images/local.png)\n```\n")
        first.attachments = [image]
        let other = Page(spaceID: space, title: "Other", markdown: "![Not mine](images/local.png)")
        var snapshot = LibrarySnapshot(); snapshot.pages = [first, other]
        snapshot.revisions = [Revision(page: first, author: "Writer", capturedAt: Date())]
        let inventory = AttachmentInventory(libraryID: UUID(), snapshot: snapshot)
        #expect(inventory.entries.count == 1)
        #expect(inventory.entries[0].activeReferenceCount == 2)
        #expect(inventory.entries[0].historicalReferenceCount == 2)
        #expect(!inventory.entries[0].isUnusedInCurrentPages)
        #expect(inventory.references(on: other.id).isEmpty)
    }

    @Test func ambiguousAliasesRemainConflictsAndAreNeverProbed() {
        let first = sourcePathImage(), second = sourcePathImage()
        var page = Page(spaceID: UUID(), title: "Ambiguous", markdown: "![Image](./images/Foo%20Bar.png)")
        page.attachments = [first, second]
        var snapshot = LibrarySnapshot(); snapshot.pages = [page]
        var reads = 0
        let inventory = AttachmentInventory(libraryID: UUID(), snapshot: snapshot, probe: { _ in reads += 1; return .verified })
        #expect(inventory.entries.count == 2)
        #expect(inventory.entries.allSatisfy { $0.storageStatus == .conflictingMetadata && $0.activeReferenceCount == 1 })
        #expect(reads == 0)
    }

    @Test func imagePayloadRoundTripBindsAliasWithoutChangingImageBytes() throws {
        let image = sourcePathImage(), revision = UUID()
        let payload = try ICloudImagePayload(attachment: image, revisionID: revision, data: sourcePathPNG)
        let restored = try ICloudImagePayload.decode(payload.encoded(), expectedImageID: image.id, expectedRevision: revision)
        #expect(restored.attachment.storageEquals(image))
        #expect(restored.data == sourcePathPNG)
        #expect(restored.attachment.relativePath == image.relativePath)
    }

    @Test(arguments: ["", "../image.png", "/image.png", "https://example.test/image.png", "file:///image.png",
        "images\\image.png", "%2e%2e/image.png", "%252e%252e/image.png", "image.png?x=1", "image.png#fragment", "image%00.png",
        String(repeating: "a", count: 4097) + ".png"])
    func imagePayloadRejectsUnsafeOrUnboundedAliases(_ path: String) {
        #expect(throws: ICloudImagePayloadError.invalidPayload) {
            try ICloudImagePayload(attachment: sourcePathImage(path: path), revisionID: UUID(), data: sourcePathPNG)
        }
    }

    @Test func escapedHeaderSizeIsCheckedBeforeImagePayloadCanBeUsed() throws {
        let path = String(repeating: "\"", count: 4092) + ".png"
        #expect(path.utf8.count == 4096)
        #expect(MarkdownAssetPath.filePath(for: path) != nil)
        #expect(throws: ICloudImagePayloadError.invalidPayload) {
            try ICloudImagePayload.validateDescriptor(sourcePathImage(path: path))
        }
    }

    @Test @MainActor func existingImageIdentityCannotAcquireADifferentAlias() throws {
        let root = URL(fileURLWithPath: "/private/tmp/ScriptumAliasIdentity-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try LibraryStore(directory: root), image = sourcePathImage()
        let space = try store.createSpace(title: "Writing")
        try store.importICloudImage(ICloudImagePayload(attachment: image, revisionID: UUID(), data: sourcePathPNG))
        var page = Page(spaceID: space.id, title: "Existing", markdown: "![Image](./images/Foo%20Bar.png)"); page.attachments = [image]
        try store.mergeICloudPage(page, basedOn: nil)
        let before = try Data(contentsOf: root.appendingPathComponent("library.json"))
        let changed = sourcePathImage(id: image.id, path: "images/different.png")
        #expect(throws: ICloudImagePayloadError.existingMismatch) {
            try store.importICloudImage(ICloudImagePayload(attachment: changed, revisionID: UUID(), data: sourcePathPNG))
        }
        #expect(try Data(contentsOf: root.appendingPathComponent("library.json")) == before)
        #expect(try store.attachmentData(image) == sourcePathPNG)
    }

    @Test @MainActor func mergedAliasReferencesUseRemoteAndOnlyReferencedSamePageHistory() throws {
        let root = URL(fileURLWithPath: "/private/tmp/ScriptumAliasMerge-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try LibraryStore(directory: root), used = sourcePathImage(path: "images/history.png"), unused = sourcePathImage(path: "images/unused.png")
        let space = try store.createSpace(title: "Writing")
        var original = Page(spaceID: space.id, title: "Original"); original.attachments = [used, unused]
        for image in [used, unused] { try store.importICloudImage(ICloudImagePayload(attachment: image, revisionID: UUID(), data: sourcePathPNG)) }
        try store.mergeICloudPage(original, basedOn: nil)
        try store.edit(original.id) { $0.attachments = [] }
        let local = try #require(store.snapshot.pages.first { $0.id == original.id })
        // Unreferenced history remains recoverable metadata; a merge must not
        // require or restore its file as a side effect of looking up aliases.
        try FileManager.default.removeItem(at: root.appendingPathComponent(unused.relativePath))
        let remoteImage = sourcePathImage(path: "images/remote.png")
        try store.importICloudImage(ICloudImagePayload(attachment: remoteImage, revisionID: UUID(), data: sourcePathPNG))
        var remote = local; remote.revision = UUID(); remote.attachments = [remoteImage]
        let body = "Older e\u{301}\r\n![Historical](images/history.png)\r\n![Remote](images/remote.png)\r\n`![Example](images/unused.png)`\r\n"
        let resolution = try store.prepareICloudPageResolution(remote: remote, expectedLocalRevision: local.revision, choice: .mergedMarkdown(body))
        #expect(Set((resolution.resolved.attachments ?? []).map(\.id)) == [used.id, remoteImage.id])
        #expect(resolution.resolved.markdown.utf8.elementsEqual(body.utf8))
        try store.applyICloudPageResolution(resolution)
        let reopened = try LibraryStore(directory: root)
        #expect(reopened.snapshot.pages[0].attachments?.contains { $0.storageEquals(used) } == true)
        #expect(reopened.snapshot.pages[0].attachments?.contains { $0.id == unused.id } == false)
        #expect(try reopened.attachmentData(used) == sourcePathPNG)
    }

    @Test @MainActor func mergedAliasesNeverBorrowAnotherPagesImage() throws {
        let root = URL(fileURLWithPath: "/private/tmp/ScriptumPrivateAlias-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try LibraryStore(directory: root), image = sourcePathImage(path: "private/secret.png")
        let space = try store.createSpace(title: "Writing")
        let local = try store.createPage(spaceID: space.id, title: "Local")
        var other = Page(spaceID: space.id, title: "Private other page"); other.attachments = [image]
        try store.importICloudImage(ICloudImagePayload(attachment: image, revisionID: UUID(), data: sourcePathPNG))
        try store.mergeICloudPage(other, basedOn: nil)
        var remote = local; remote.revision = UUID()
        let resolution = try store.prepareICloudPageResolution(remote: remote, expectedLocalRevision: local.revision,
            choice: .mergedMarkdown("![Unbound](private/secret.png)"))
        #expect(resolution.resolved.attachments?.isEmpty ?? true)
        #expect(store.snapshot.pages.first { $0.id == other.id }?.attachments == [image])
    }

    @Test @MainActor func mergedAmbiguousHistoricalAliasFailsWithoutChangingEitherVersion() throws {
        let root = URL(fileURLWithPath: "/private/tmp/ScriptumAmbiguousAlias-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try LibraryStore(directory: root), first = sourcePathImage(), second = sourcePathImage()
        let space = try store.createSpace(title: "Writing")
        var original = Page(spaceID: space.id, title: "Original"); original.attachments = [first]
        for image in [first, second] { try store.importICloudImage(ICloudImagePayload(attachment: image, revisionID: UUID(), data: sourcePathPNG)) }
        try store.mergeICloudPage(original, basedOn: nil)
        try store.edit(original.id) { $0.attachments = [second] }
        let local = try #require(store.snapshot.pages.first { $0.id == original.id })
        var remote = local; remote.revision = UUID()
        let before = try Data(contentsOf: root.appendingPathComponent("library.json"))
        #expect(throws: LibraryError.invalidAttachment) {
            try store.prepareICloudPageResolution(remote: remote, expectedLocalRevision: local.revision,
                choice: .mergedMarkdown("![Ambiguous](./images/Foo%20Bar.png)"))
        }
        #expect(try Data(contentsOf: root.appendingPathComponent("library.json")) == before)
    }
}
