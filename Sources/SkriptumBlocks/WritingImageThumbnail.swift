import Foundation
import CoreGraphics
import ImageIO
import CryptoKit
#if canImport(SkriptumCore)
import SkriptumCore
#endif

/// Serial background thumbnail work, bounded retained cache. CGImage is
/// immutable and Sendable in the installed SDK; no UIKit object crosses actors.
actor WritingImageThumbnail {
    static let shared = WritingImageThumbnail()
    static let maximumDimension = 2048
    private let maximumCacheBytes = 32 * 1024 * 1024
    private struct Entry { let image: CGImage; let bytes: Int; var use: UInt64 }
    private var cache: [String: Entry] = [:]
    private var bytes = 0
    private var sequence: UInt64 = 0
    func image(data: Data) -> CGImage? {
        guard !Task.isCancelled, !data.isEmpty, data.count <= MediaValidation.maximumBytes else { return nil }
        let key = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        sequence &+= 1
        if var item = cache[key] { item.use = sequence; cache[key] = item; return item.image }
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let type = CGImageSourceGetType(source) as String?, ["public.jpeg", "public.png"].contains(type),
              CGImageSourceGetCount(source) == 1,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let width = properties[kCGImagePropertyPixelWidth as String] as? Int,
              let height = properties[kCGImagePropertyPixelHeight as String] as? Int,
              width > 0, height > 0, width <= 16384, height <= 16384, width * height <= 40_000_000,
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: Self.maximumDimension
              ] as CFDictionary), !Task.isCancelled,
              image.width <= Self.maximumDimension, image.height <= Self.maximumDimension else { return nil }
        let cost = image.bytesPerRow * image.height
        while bytes + cost > maximumCacheBytes, let oldest = cache.min(by: { $0.value.use < $1.value.use }) {
            bytes -= oldest.value.bytes; cache.removeValue(forKey: oldest.key)
        }
        if cost <= maximumCacheBytes { cache[key] = Entry(image: image, bytes: cost, use: sequence); bytes += cost }
        return image
    }
    func cacheFootprint() -> (bytes: Int, count: Int) { (bytes, cache.count) }
}
