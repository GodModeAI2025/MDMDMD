import Foundation
import CoreGraphics
import ImageIO
import Testing
import SkriptumCore
@testable import SkriptumBlocks

struct ImageThumbnailTests {
    private func png(width: Int, height: Int, orientation: Int = 1, color: CGFloat = 0.8) throws -> Data {
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: color, green: 0.2, blue: 0.1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let output = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(output, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: orientation] as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        return output as Data
    }
    @Test func largePreviewIsBoundedCachedAndOrientationCorrectWithoutChangingOriginal() async throws {
        let data = try png(width: 3200, height: 1800)
        let original = data
        let loader = WritingImageThumbnail()
        let image = try #require(await loader.image(data: data))
        #expect(image.width == 2048 && image.height == 1152)
        let again = try #require(await loader.image(data: data))
        #expect(again === image)
        let rotated = try #require(await loader.image(data: png(width: 120, height: 80, orientation: 6)))
        #expect(rotated.width == 80 && rotated.height == 120)
        #expect(data == original)
        let footprint = await loader.cacheFootprint()
        #expect(footprint.bytes <= 32 * 1024 * 1024 && footprint.count == 2)
        #expect(await loader.image(data: Data("not an image".utf8)) == nil)
    }
    @Test @MainActor func previewRequestsStayScopedAndMissingArrivalCanRefreshWithoutMutatingPage() async throws {
        let root = URL(fileURLWithPath: "/private/tmp/ImagePreview-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try LibraryStore(directory: root)
        let space = try store.createSpace(title: "Images")
        let page = try store.createPage(spaceID: space.id, title: "Page", markdown: "![Preview]")
        let data = try png(width: 80, height: 60)
        let attachment = try store.addAttachment(pageID: page.id, data: data, mediaType: "image/png", filename: "Original.png", baseRevision: page.revision)
        let original = try Data(contentsOf: root.appendingPathComponent("library.json"))
        let catalog = MediaPreviewSource(root: root, attachments: [attachment])
        #expect(catalog.request(for: "https://example.com/image.png") == nil)
        #expect(catalog.request(for: "media/../outside") == nil)
        let request = try #require(catalog.request(for: attachment.relativePath))
        #expect(try await request.data() == data)
        let refreshed = try #require(MediaPreviewSource(root: root, attachments: [attachment], refresh: UUID()).request(for: attachment.relativePath))
        #expect(request != refreshed)
        let file = root.appendingPathComponent(attachment.relativePath)
        try FileManager.default.removeItem(at: file)
        do { _ = try await request.data(); Issue.record("Missing attachment unexpectedly loaded") } catch { }
        try data.write(to: file)
        #expect(try await refreshed.data() == data)
        try Data("corrupt".utf8).write(to: file)
        do { _ = try await refreshed.data(); Issue.record("Corrupted attachment unexpectedly loaded") } catch { }
        #expect(try Data(contentsOf: root.appendingPathComponent("library.json")) == original)
    }
    @Test func cacheEvictsRatherThanRetainingEveryLargeOriginal() async throws {
        let loader = WritingImageThumbnail()
        for color in [CGFloat(0.2), 0.4, 0.6] {
            let data = try png(width: 2048, height: 2048, color: color)
            #expect(await loader.image(data: data) != nil)
        }
        let footprint = await loader.cacheFootprint()
        #expect(footprint.bytes <= 32 * 1024 * 1024 && footprint.count < 3)
    }

}
