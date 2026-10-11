import Foundation
import CoreGraphics
import PDFKit
import Testing
@testable import SkriptumExport

@Test func documentWriterOwnsPagesMetadataAndRejectsPartialResults() throws {
    let adapter = try PDFInlineAdapter(theme: .standard, footnoteIDs: [])
    let pieces = try adapter.fragments([.text((0..<200).map { "Autor \($0) 🦊\n" }.joined())])
    guard case .text(let text) = pieces.first else { Issue.record("Missing text"); return }
    let writer = try PDFDocumentWriter(theme: .standard, title: "Manuskript", author: "Autor")
    try writer.paragraph(text)
    let document = try #require(PDFDocument(data: writer.finish()))
    #expect(document.pageCount > 1)
    #expect(document.string?.filter { $0 == "🦊" }.count == 200)
    #expect(document.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String == "Manuskript")
    #expect(document.documentAttributes?[PDFDocumentAttribute.authorAttribute] as? String == "Autor")
    #expect(throws: PDFDocumentWriter.WriterError.closed) { try writer.finish() }
    let limited = try PDFDocumentWriter(theme: .standard, title: "Limited", maximumPages: 1)
    #expect(throws: PDFParagraphBreakPlanner.PlanningError.pageLimitExceeded) { try limited.paragraph(text) }
    #expect(throws: PDFDocumentWriter.WriterError.closed) { try limited.finish() }
    let empty = try PDFDocumentWriter(theme: .standard, title: "Empty")
    #expect(try PDFDocument(data: empty.finish())?.pageCount == 1)
}

@Test func documentWriterInterleavesImagesAndTextWithoutBlankTrailingPage() throws {
    let writer = try PDFDocumentWriter(theme: .standard, title: "Images")
    let raster = try PDFImageRaster(asset: orientedPhoto(6), path: "photo.jpg")
    for _ in 0..<20 { try writer.image(raster) }
    let adapter = try PDFInlineAdapter(theme: .standard, footnoteIDs: [])
    let fragments = try adapter.fragments([.text("Nach den Bildern 🦊")])
    guard case .text(let text) = fragments.first else { Issue.record("Missing text"); return }
    try writer.paragraph(text)
    let pdf = try #require(PDFDocument(data: writer.finish()))
    #expect(pdf.pageCount > 1)
    #expect(pdf.page(at: pdf.pageCount - 1)?.string?.contains("Nach den Bildern 🦊") == true)
}

@Test func documentWriterRuleDrawsVisibleVectorAcrossContentWidth() throws {
    let writer = try PDFDocumentWriter(theme: .standard, title: "Rule")
    try writer.rule()
    let pdf = try #require(PDFDocument(data: writer.finish()))
    let page = try #require(pdf.page(at: 0))
    let geometry = try PDFPageCursor(theme: .standard)
    let width = Int(ceil(geometry.paper.width)), height = Int(ceil(geometry.paper.height))
    let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
        bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    page.draw(with: .mediaBox, to: context)
    let pixels = try #require(context.data).assumingMemoryBound(to: UInt8.self)
    // CoreGraphics bitmap row order is inspected in both directions; the rule
    // must span the content width while margins stay clear.
    let rows = [Int(geometry.content.maxY - 12), height - 1 - Int(geometry.content.maxY - 12)]
    var dark = 0, marginDark = 0
    for row in rows {
        for y in max(0, row - 2)...min(height - 1, row + 2) {
            for x in 0..<width where pixels[y * width * 4 + x * 4] < 230 {
                if x >= Int(geometry.content.minX) && x <= Int(geometry.content.maxX) { dark += 1 }
                else if x < Int(geometry.content.minX) - 1 || x > Int(geometry.content.maxX) + 1 { marginDark += 1 }
            }
        }
    }
    #expect(dark > 300)
    #expect(marginDark == 0)
}
