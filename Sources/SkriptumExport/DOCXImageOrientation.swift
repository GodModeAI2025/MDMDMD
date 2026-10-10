import Foundation
import ImageIO

/// Word receives upright pixels rather than relying on a reader's EXIF policy.
/// Only the export copy changes; already-upright images remain byte-identical.
enum DOCXImageOrientation {
    static func normalized(_ asset: ExportAsset, path: String) throws -> ExportAsset {
        try Task.checkCancellation()
        guard let source = CGImageSourceCreateWithData(asset.data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { throw ExportError.unsupportedAsset(path) }
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        guard (1...8).contains(orientation) else { throw ExportError.unsupportedAsset(path) }
        if orientation == 1 { return asset }
        guard let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
              width.intValue > 0, height.intValue > 0,
              width.doubleValue * height.doubleValue <= 50_000_000 else {
            throw ExportError.unsupportedAsset(path)
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(width.intValue, height.intValue),
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw ExportError.unsupportedAsset(path)
        }
        try Task.checkCancellation()
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else {
            throw ExportError.unsupportedAsset(path)
        }
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: 1] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ExportError.unsupportedAsset(path) }
        try Task.checkCancellation()
        return ExportAsset(data: data as Data, mediaType: "image/png")
    }
}
