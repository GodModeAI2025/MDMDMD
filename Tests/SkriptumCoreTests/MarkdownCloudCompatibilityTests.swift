import Foundation
import Testing
@testable import SkriptumCore

private enum LegacyCloudVersionError: Error { case unsupported }
/// Characterizes the outer `schemaVersion == 1` admission clause shipped in
/// 6d70cdf. This is a format gate fixture, not a claim to run an older app.
private func legacyCloudVersionGate(_ bytes: Data) throws {
    let object = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
    guard object["schemaVersion"] as? Int == 1 else { throw LegacyCloudVersionError.unsupported }
}
private func cloudVersion(_ bytes: Data) throws -> Int {
    let object = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
    return try #require(object["schemaVersion"] as? Int)
}
private func downgradedCloudHeader(_ bytes: Data) throws -> Data {
    var object = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
    object["schemaVersion"] = 1
    return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .fragmentsAllowed])
}
private func compatibilityImage(alias: Bool) -> (Data, MediaAttachment) {
    let bytes = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=")!
    return (bytes, MediaAttachment(filename: "image.png", mediaType: "image/png", byteCount: bytes.count,
        sha256: MediaValidation.digest(bytes), sourcePath: alias ? "images/Cafe%CC%81.png" : nil))
}

@Test(arguments: [false, true]) func markdownCloudVersionsProtectAliasPagesImagesAndHistory(alias: Bool) throws {
    let (image, attachment) = compatibilityImage(alias: alias)
    var page = Page(spaceID: UUID(), title: "Imported", markdown: "![e\u{301}](images/Cafe%CC%81.png)\r\n")
    page.attachments = [attachment]
    let expected = alias ? 2 : 1
    let pageBytes = try ICloudPagePayload(page: page, baseRevision: nil).encoded()
    #expect(try cloudVersion(pageBytes) == expected)
    let read = try ICloudPagePayload.decode(pageBytes, expectedPageID: page.id, expectedRevision: page.revision)
    #expect(read.page.storageEquals(page))
    let history = Revision(page: page, author: "Writer", capturedAt: Date(timeIntervalSince1970: 100))
    let historyBytes = try ICloudMetadataPayload(value: history, baseDigest: nil).encoded()
    #expect(try cloudVersion(historyBytes) == expected)
    #expect(try ICloudMetadataPayload<Revision>.decode(historyBytes).value.page.storageEquals(page))
    let revision = UUID()
    let frame = try ICloudImagePayload(attachment: attachment, revisionID: revision, data: image).encoded()
    let length = frame.prefix(4).reduce(0) { ($0 << 8) | Int($1) }
    let header = frame.subdata(in: 4..<(4 + length))
    #expect(try cloudVersion(header) == expected)
    let restored = try ICloudImagePayload.decode(frame, expectedImageID: attachment.id, expectedRevision: revision)
    #expect(restored.attachment.storageEquals(attachment) && restored.data == image)
    for bytes in [pageBytes, historyBytes, header] {
        if alias { #expect(throws: LegacyCloudVersionError.self) { try legacyCloudVersionGate(bytes) } }
        else { try legacyCloudVersionGate(bytes) }
    }
    if alias {
        #expect(throws: LibraryError.invalidLibrary) {
            try ICloudPagePayload.decode(downgradedCloudHeader(pageBytes), expectedPageID: page.id, expectedRevision: page.revision)
        }
        #expect(throws: ICloudMetadataMergeError.invalidPayload) { try ICloudMetadataPayload<Revision>.decode(downgradedCloudHeader(historyBytes)) }
        let downgraded = try downgradedCloudHeader(header), size = UInt32(downgraded.count)
        var invalid = Data([UInt8((size >> 24) & 255), UInt8((size >> 16) & 255), UInt8((size >> 8) & 255), UInt8(size & 255)])
        invalid.append(downgraded); invalid.append(image)
        #expect(throws: ICloudImagePayloadError.invalidPayload) {
            try ICloudImagePayload.decode(invalid, expectedImageID: attachment.id, expectedRevision: revision)
        }
    }
}

@Test @MainActor func markdownCloudSharedCheckpointAndPendingEditsRetainAliasesAcrossRestart() throws {
    let directory = URL(fileURLWithPath: "/private/tmp/SharedAliasVersion-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let (_, image) = compatibilityImage(alias: true)
    var page = Page(spaceID: UUID(), title: "Imported", markdown: "![e\u{301}](images/Cafe%CC%81.png)\r\n")
    page.attachments = [image]
    var canonical = LibrarySnapshot(); canonical.pages = [page]
    let identity = try ICloudSharedStoreIdentity(accountID: "participant", ownerID: "owner", zoneName: "zone",
        shareName: "share", root: .init(kind: .page, id: page.id))
    let store = try ICloudSharedDocumentStore(directory: directory, identity: identity)
    _ = try store.replace(canonical, expectedRevision: nil)
    let checkpoint = try Data(contentsOf: store.fileURL)
    #expect(try cloudVersion(checkpoint) == 2)
    #expect(throws: LegacyCloudVersionError.self) { try legacyCloudVersionGate(checkpoint) }
    let text = page.markdown + "Edited 🦊\r\n"
    _ = try store.editMarkdown(pageID: page.id, expectedPageRevision: page.revision, markdown: text, permission: .readWrite)
    let reopened = try ICloudSharedDocumentStore(directory: directory, identity: identity)
    let context = try #require(try reopened.context(permission: .readWrite))
    let saved = try #require(context.page(page.id))
    #expect(Data(saved.markdown.utf8) == Data(text.utf8))
    #expect(saved.attachments?.first?.storageEquals(image) == true)
    let pending = try reopened.pendingChanges()
    #expect(Set(pending.map(\.recordID.kind)) == [.page, .revision])
    for change in pending { #expect(try cloudVersion(change.payload) == 2) }
}

@Test @MainActor func markdownCloudOwnerBaselineHasItsOwnLegacyVersionGate() throws {
    let directory = URL(fileURLWithPath: "/private/tmp/OwnerAliasVersion-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let (_, image) = compatibilityImage(alias: true), space = Space(title: "Space")
    var page = Page(spaceID: space.id, title: "Imported", markdown: "![e\u{301}](images/Cafe%CC%81.png)\r\n")
    page.attachments = [image]
    var canonical = LibrarySnapshot(); canonical.spaces = [space]; canonical.pages = [page]
    let scope = try ICloudSyncScope(accountID: "owner", libraryID: UUID())
    let journal = try ICloudSyncJournal(directory: directory, scope: scope)
    let bridge = try ICloudLibraryJournalBridge(journal: journal)
    _ = try bridge.bootstrap(canonical)
    let checkpoint = try Data(contentsOf: bridge.checkpointURL)
    #expect(try cloudVersion(checkpoint) == 2)
    #expect(throws: LegacyCloudVersionError.self) { try legacyCloudVersionGate(checkpoint) }
    let reopened = try ICloudLibraryJournalBridge(journal: journal)
    #expect(try reopened.lastProjectedSnapshot()?.pages.first?.storageEquals(page) == true)
    #expect(try reopened.bootstrap(canonical) == 0)
}
