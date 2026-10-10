import Foundation
import CoreGraphics
import ImageIO

/// Upright, bounded raster for the semantic PDF writer. The original attachment
/// stays untouched; physical size uses original oriented dimensions at 96 dpi,
/// independently of the decoded raster's pixel bound.
struct PDFImageRaster {
    let image: CGImage
    let naturalSize: CGSize
    init(asset: ExportAsset, path: String, maximumRasterDimension: Int = 4096) throws {
        try Task.checkCancellation()
        guard (1...4096).contains(maximumRasterDimension), validImage(asset),
              let source = CGImageSourceCreateWithData(asset.data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber else { throw ExportError.unsupportedAsset(path) }
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        guard (1...8).contains(orientation) else { throw ExportError.unsupportedAsset(path) }
        let rotated = orientation >= 5
        naturalSize = CGSize(width: (rotated ? height.doubleValue : width.doubleValue) * 72 / 96,
                             height: (rotated ? width.doubleValue : height.doubleValue) * 72 / 96)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumRasterDimension,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              image.width > 0, image.height > 0,
              max(image.width, image.height) <= maximumRasterDimension else { throw ExportError.unsupportedAsset(path) }
        try Task.checkCancellation()
        self.image = image
    }

    func fittedSize(availableWidth: CGFloat, availableHeight: CGFloat) throws -> CGSize {
        try Task.checkCancellation()
        guard availableWidth.isFinite, availableHeight.isFinite, availableWidth > 0, availableHeight > 0 else {
            throw PDFPageCursor.PageError.invalidGeometry
        }
        let scale = min(1, availableWidth / naturalSize.width, availableHeight / naturalSize.height)
        return CGSize(width: naturalSize.width * scale, height: naturalSize.height * scale)
    }

    func draw(in context: CGContext, frame: CGRect) throws {
        try Task.checkCancellation()
        guard frame.origin.x.isFinite, frame.origin.y.isFinite,
              frame.width.isFinite, frame.height.isFinite, frame.width > 0, frame.height > 0,
              abs(frame.width / frame.height - naturalSize.width / naturalSize.height) <= 0.0001 else {
            throw PDFPageCursor.PageError.invalidGeometry
        }
        context.saveGState(); defer { context.restoreGState() }
        context.interpolationQuality = .high
        context.draw(image, in: frame)
    }
}
