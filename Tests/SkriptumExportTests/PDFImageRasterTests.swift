import Foundation
import CoreGraphics
import ImageIO
import CoreText
import PDFKit
import Testing
@testable import SkriptumExport

private func pdfImageCorners(_ image: CGImage) throws -> [Int] {
    let width = image.width, height = image.height
    let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
        bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    let buffer = try #require(context.data).assumingMemoryBound(to: UInt8.self)
    let palette = [[240,20,20], [20,220,20], [20,20,240], [240,220,20]]
    return [(width/4,height/4),(3*width/4,height/4),(width/4,3*height/4),(3*width/4,3*height/4)].map { x,y in
        let i = (y * width + x) * 4
        return palette.indices.min { a,b in
            (0..<3).reduce(0) { $0 + abs(Int(buffer[i+$1])-palette[a][$1]) }
            < (0..<3).reduce(0) { $0 + abs(Int(buffer[i+$1])-palette[b][$1]) }
        }!
    }
}

@Test func semanticPDFRasterCorrectsAllEXIFOrientationsWithoutChangingOriginalBytes() throws {
    let expected = [[0,1,2,3],[1,0,3,2],[3,2,1,0],[2,3,0,1],[0,2,1,3],[2,0,3,1],[3,1,2,0],[1,3,0,2]]
    for orientation in 1...8 {
        let asset = try orientedPhoto(orientation), before = asset.data
        let raster = try PDFImageRaster(asset: asset, path: "photo.jpg")
        #expect(raster.image.width == (orientation >= 5 ? 40 : 80))
        #expect(raster.image.height == (orientation >= 5 ? 80 : 40))
        #expect(try pdfImageCorners(raster.image) == expected[orientation-1])
        #expect(raster.naturalSize == (orientation >= 5 ? CGSize(width: 30,height: 60) : CGSize(width: 60,height: 30)))
        #expect(asset.data == before)
    }
}

@Test func semanticPDFDownsamplingKeepsNaturalPhysicalSizeAndAspect() throws {
    let asset = try orientedPhoto(1)
    let raster = try PDFImageRaster(asset: asset, path: "photo.jpg", maximumRasterDimension: 8)
    #expect(raster.image.width == 8 && raster.image.height == 4)
    #expect(raster.naturalSize == CGSize(width: 60, height: 30))
    #expect(try raster.fittedSize(availableWidth: 500, availableHeight: 500) == CGSize(width: 60,height: 30))
    #expect(try raster.fittedSize(availableWidth: 20, availableHeight: 500) == CGSize(width: 20,height: 10))
    #expect(throws: PDFPageCursor.PageError.invalidGeometry) { try raster.fittedSize(availableWidth: .infinity, availableHeight: 100) }
}

@Test func semanticPDFImageMovesToNextPageAndFollowingTextSurvives() throws {
    let raster = try PDFImageRaster(asset: orientedPhoto(6), path: "photo.jpg")
    var cursor = try PDFPageCursor(theme: .standard)
    let data = NSMutableData(); let consumer = try #require(CGDataConsumer(data: data))
    var box = cursor.paper
    let context = try #require(CGContext(consumer: consumer, mediaBox: &box, nil))
    context.beginPDFPage(nil)
    context.fill(CGRect(x: cursor.content.minX, y: cursor.content.maxY - 10, width: 10, height: 10))
    try cursor.space(after: cursor.content.height - 1)
    let size = try raster.fittedSize(availableWidth: cursor.content.width, availableHeight: cursor.content.height)
    let placement = try cursor.placeRectangle(size: size)
    #expect(placement.pageIndex == 1)
    #expect(cursor.content.contains(placement.frame))
    context.endPDFPage(); context.beginPDFPage(nil)
    try raster.draw(in: context, frame: placement.frame)
    let adapter = try PDFInlineAdapter(theme: .standard, footnoteIDs: [])
    let fragments = try adapter.fragments([.text("Text nach dem Bild 🦊")])
    guard case .text(let text) = fragments.first else { Issue.record("No text"); return }
    var layout = try PDFTextTypesetter(text: text, availableWidth: cursor.content.width)
    while let line = try layout.nextLine() {
        let position = try cursor.place(line)
        #expect(position.pageIndex == 1)
        try line.draw(in: context, baseline: position.baseline)
    }
    context.endPDFPage(); context.closePDF()
    let pdf = try #require(PDFDocument(data: data as Data)); let extracted = try #require(pdf.string)
    #expect(pdf.pageCount == 2)
    #expect(extracted.contains("Text nach dem Bild 🦊"))
}
