import Foundation
import CryptoKit
import ImageIO
import CoreGraphics
import Testing
@testable import SkriptumCore

private let cloudPNG = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=")!
private func cloudImageDescriptor(id: UUID = UUID(), bytes: Data = cloudPNG, filename: String = "e\u{301}.png", type: String = "image/png", digest: String? = nil) -> MediaAttachment {
    MediaAttachment(id: id, filename: filename, mediaType: type, byteCount: bytes.count, sha256: digest ?? MediaValidation.digest(bytes))
}

@Test func iCloudImageBinaryRoundTripPreservesDescriptorAndExactBytes() throws {
    let attachment = cloudImageDescriptor(), revision = UUID()
    let value = try ICloudImagePayload(attachment: attachment, revisionID: revision, data: cloudPNG)
    let restored = try ICloudImagePayload.decode(value.encoded(), expectedImageID: attachment.id, expectedRevision: revision)
    #expect(restored.data == cloudPNG)
    #expect(restored.attachment.id == attachment.id)
    #expect(restored.attachment.filename.utf8.elementsEqual(attachment.filename.utf8))
    #expect(restored.attachment.relativePath == attachment.relativePath)
    #expect(restored.revisionID == revision)
}

@Test func iCloudImageWrongDigestMimeIdentityAndUnsafeFilenameReject() throws {
    let attachment = cloudImageDescriptor(), revision = UUID()
    #expect(throws: (any Error).self) { try ICloudImagePayload(attachment: cloudImageDescriptor(digest: String(repeating: "0", count: 64)), revisionID: revision, data: cloudPNG) }
    #expect(throws: (any Error).self) { try ICloudImagePayload(attachment: cloudImageDescriptor(type: "image/jpeg"), revisionID: revision, data: cloudPNG) }
    #expect(throws: (any Error).self) { try ICloudImagePayload(attachment: cloudImageDescriptor(filename: "../wrong.png"), revisionID: revision, data: cloudPNG) }
    let bytes = try ICloudImagePayload(attachment: attachment, revisionID: revision, data: cloudPNG).encoded()
    #expect(throws: (any Error).self) { try ICloudImagePayload.decode(bytes, expectedImageID: UUID(), expectedRevision: revision) }
    #expect(throws: (any Error).self) { try ICloudImagePayload.decode(bytes, expectedImageID: attachment.id, expectedRevision: UUID()) }
    #expect(throws: (any Error).self) { try ICloudImagePayload.decode(bytes.dropLast(), expectedImageID: attachment.id, expectedRevision: revision) }
}

@Test @MainActor func remotePageWaitsForDurableImageBeforeCommit() throws {
    let root = URL(fileURLWithPath: "/private/tmp/ScriptumICloudImageDependency-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try LibraryStore(directory: root), attachment = cloudImageDescriptor()
    let space = try store.createSpace(title: "Writing")
    var page = Page(spaceID: space.id, title: "Remote illustrated page")
    page.attachments = [attachment]
    let before = try Data(contentsOf: root.appendingPathComponent("library.json"))
    #expect(throws: (any Error).self) { try store.mergeICloudPage(page, basedOn: nil) }
    #expect(try Data(contentsOf: root.appendingPathComponent("library.json")) == before)
    #expect(store.snapshot.pages.isEmpty)
    try store.importICloudImage(ICloudImagePayload(attachment: attachment, revisionID: UUID(), data: cloudPNG))
    #expect(try store.mergeICloudPage(page, basedOn: nil) == .inserted)
    let restarted = try LibraryStore(directory: root)
    #expect(restarted.snapshot.pages.first?.id == page.id)
    #expect(try restarted.attachmentData(attachment) == cloudPNG)
}

@Test @MainActor func iCloudImageImportIsIdempotentAndSurvivesRestartWithoutDocumentMutation() throws {
    let root = URL(fileURLWithPath: "/private/tmp/ScriptumICloudImage-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try LibraryStore(directory: root), attachment = cloudImageDescriptor()
    _ = try store.createSpace(title: "Preserved local space")
    let library = try Data(contentsOf: root.appendingPathComponent("library.json"))
    let payload = try ICloudImagePayload(attachment: attachment, revisionID: UUID(), data: cloudPNG)
    #expect(try store.importICloudImage(payload).id == attachment.id)
    #expect(try store.importICloudImage(payload).id == attachment.id)
    let restarted = try LibraryStore(directory: root)
    #expect(try restarted.attachmentData(attachment) == cloudPNG)
    #expect(try Data(contentsOf: root.appendingPathComponent("library.json")) == library)
}

@Test @MainActor func iCloudImageImportNeverOverwritesWrongBytesOrLinkedMedia() throws {
    let root = URL(fileURLWithPath: "/private/tmp/ScriptumICloudImage-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try LibraryStore(directory: root), attachment = cloudImageDescriptor()
    let payload = try ICloudImagePayload(attachment: attachment, revisionID: UUID(), data: cloudPNG)
    try store.importICloudImage(payload)
    let file = root.appendingPathComponent(attachment.relativePath), wrong = Data("existing wrong bytes".utf8)
    try wrong.write(to: file)
    #expect(throws: (any Error).self) { try store.importICloudImage(payload) }
    #expect(try Data(contentsOf: file) == wrong)
    try FileManager.default.removeItem(at: file)
    let outside = root.appendingPathComponent("outside"); try cloudPNG.write(to: outside)
    try FileManager.default.createSymbolicLink(at: file, withDestinationURL: outside)
    #expect(throws: (any Error).self) { try store.importICloudImage(payload) }
    #expect(try Data(contentsOf: outside) == cloudPNG)
}

@Test func iCloudImageLargeOrdinaryPNGUsesRawBinaryWithoutBase64Inflation() throws {
    let side = 1800
    var pixels = Data(count: side * side * 4), state: UInt32 = 0x12345678
    pixels.withUnsafeMutableBytes { raw in
        let bytes = raw.bindMemory(to: UInt8.self)
        for index in bytes.indices {
            state ^= state << 13; state ^= state >> 17; state ^= state << 5
            bytes[index] = UInt8(truncatingIfNeeded: state)
        }
    }
    let provider = try #require(CGDataProvider(data: pixels as CFData))
    let image = try #require(CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    let encoded = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(encoded, "public.png" as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    #expect(CGImageDestinationFinalize(destination))
    let imageBytes = encoded as Data
    #expect(imageBytes.count > 8 * 1024 * 1024)
    let attachment = cloudImageDescriptor(bytes: imageBytes), revision = UUID()
    let payload = try ICloudImagePayload(attachment: attachment, revisionID: revision, data: imageBytes)
    let frame = try payload.encoded()
    #expect(frame.count < imageBytes.count + 8192)
    #expect(try ICloudImagePayload.decode(frame, expectedImageID: attachment.id, expectedRevision: revision).data == imageBytes)
}
