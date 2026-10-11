import Foundation
import CoreGraphics
import CoreText
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

@Test func documentWriterLinkedImagesUseExactFramesAfterPagePromotion() throws {
    let writer = try PDFDocumentWriter(theme: .standard, title: "Linked images")
    let raster = try PDFImageRaster(asset: orientedPhoto(6), path: "image.jpg")
    let geometry = try PDFPageCursor(theme: .standard)
    let size = try raster.fittedSize(availableWidth: geometry.content.width - 18,
                                     availableHeight: geometry.content.height)
    // Twenty portrait images exceed one page. Every annotation must follow its
    // image's placement rather than staying on the originally current page.
    for index in 0..<20 { try writer.image(raster, indent: 18, linkTarget: "https://example.com/image/\(index)") }
    let pdf = try #require(PDFDocument(data: writer.finish()))
    #expect(pdf.pageCount > 1)
    let links = (0..<pdf.pageCount).flatMap { pdf.page(at: $0)?.annotations ?? [] }
    #expect(links.count == 20)
    #expect(Set(links.compactMap { $0.url?.absoluteString }) == Set((0..<20).map { "https://example.com/image/\($0)" }))
    for link in links {
        #expect(abs(link.bounds.width - size.width) < 0.01)
        #expect(abs(link.bounds.height - size.height) < 0.01)
        #expect(abs(link.bounds.minX - geometry.content.minX - 18) < 0.01)
        #expect(geometry.content.insetBy(dx: -0.01, dy: -0.01).contains(link.bounds))
    }
    let rejected = try PDFDocumentWriter(theme: .standard, title: "Unsafe")
    #expect(throws: ExportError.unsafeURL("javascript:alert(1)")) {
        try rejected.image(raster, linkTarget: "javascript:alert(1)")
    }
    #expect(throws: PDFDocumentWriter.WriterError.closed) { try rejected.finish() }
}

@Test func headingKeepMovesWithFollowingParagraphStart() throws {
    let adapter = try PDFInlineAdapter(theme: .standard, footnoteIDs: [])
    func text(_ value: String) throws -> NSAttributedString {
        guard case .text(let result)? = try adapter.fragments([.text(value)]).first else { throw PDFTextTypesetter.LayoutError.invalidBreak }
        return result
    }
    let heading = try text("Heading kept with body")
    let body = try text(String(repeating: "Following body 🦊.\n", count: 10))
    let geometry = try PDFPageCursor(theme: .standard)
    let line = try PDFParagraphLayout(text: text("Filler\n"), width: geometry.content.width,
                                       lineHeight: CGFloat(ExportTheme.standard.lineHeight)).lineHeights[0]
    let fillerCount = Int((geometry.content.height - 65) / line)
    for keep in [false, true] {
        let writer = try PDFDocumentWriter(theme: .standard, title: "Keep")
        try writer.paragraph(text(String(repeating: "Filler\n", count: fillerCount)))
        try writer.paragraph(heading, destination: "heading", keepWithFollowing: keep ? body : nil)
        try writer.paragraph(body)
        let pdf = try #require(PDFDocument(data: writer.finish()))
        let headingPage = try #require((0..<pdf.pageCount).first { pdf.page(at: $0)?.string?.contains("Heading kept") == true })
        let bodyPage = try #require((0..<pdf.pageCount).first { pdf.page(at: $0)?.string?.contains("Following body") == true })
        if keep { #expect(headingPage == bodyPage); #expect(headingPage == 1) }
        else { #expect(headingPage == 0); #expect(bodyPage == 1) }
        #expect(pdf.string?.filter { $0 == "🦊" }.count == 10)
    }
}

@Test func tableWrapsCellsAndSplitsOversizedRows() throws {
    let adapter = try PDFInlineAdapter(theme: .standard, footnoteIDs: [])
    func text(_ value: String) throws -> NSAttributedString {
        guard case .text(let result)? = try adapter.fragments([.text(value)]).first else { throw PDFTextTypesetter.LayoutError.invalidBreak }
        return result
    }
    let writer = try PDFDocumentWriter(theme: .standard, title: "Wrapped")
    let long = String(repeating: "wrapped 🦊 ", count: 30)
    try writer.table(header: [text("First"), text("Second")], rows: [[text(long), text("Adjacent cell")]], alignments: [nil, "center"])
    let pdf = try #require(PDFDocument(data: writer.finish()))
    #expect(pdf.string?.filter { $0 == "🦊" }.count == 30)
    #expect(pdf.string?.contains("Adjacent cell") == true)
    let limited = try PDFDocumentWriter(theme: .standard, title: "Oversized")
    let longCell = NSMutableAttributedString(attributedString: try text((0..<100).map { "Tall \($0) 🦊\n" }.joined()))
    longCell.addAttribute(PDFInlineAdapter.linkTarget, value: "https://example.com/tall",
                          range: NSRange(location: 0, length: longCell.length))
    try limited.table(header: [text("First"), text("Second")],
        rows: [[longCell, text("Other")]], alignments: [])
    let tallData = try limited.finish()
    if let path = ProcessInfo.processInfo.environment["SCRIPTUM_PDF_TALL_ROW_QA_OUTPUT"] {
        try tallData.write(to: URL(fileURLWithPath: path), options: .atomic)
    }
    let tall = try #require(PDFDocument(data: tallData))
    #expect(tall.pageCount > 1)
    #expect(tall.string?.filter { $0 == "🦊" }.count == 100)
    for index in 0..<100 { #expect(tall.string?.contains("Tall \(index) 🦊") == true) }
    for index in 0..<tall.pageCount { #expect(tall.page(at: index)?.string?.contains("First") == true) }
    let geometry = try PDFPageCursor(theme: .standard)
    let links = (0..<tall.pageCount).flatMap { tall.page(at: $0)?.annotations ?? [] }
    #expect(links.count >= 100)
    #expect(links.allSatisfy { $0.url?.absoluteString == "https://example.com/tall" })
    #expect(links.allSatisfy { geometry.content.insetBy(dx: -0.01, dy: -0.01).contains($0.bounds) })
    let bounded = try PDFDocumentWriter(theme: .standard, title: "Budget", maximumPages: 1)
    #expect(throws: PDFTableRowPlanner.PlanningError.pageLimitExceeded) {
        try bounded.table(header: [text("First"), text("Second")], rows: [[longCell, text("Other")]], alignments: [])
    }
    #expect(throws: PDFDocumentWriter.WriterError.closed) { try bounded.finish() }


}

@Test func tableFirstBaselinesAlignAcrossDifferentFontMetrics() throws {
    let large = CTFontCreateWithName("Georgia" as CFString, 24, nil)
    let small = CTFontCreateWithName("Georgia" as CFString, 12, nil)
    func text(_ font: CTFont, target: String) -> NSAttributedString {
        NSAttributedString(string: "Linked", attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            PDFInlineAdapter.linkTarget: target])
    }
    let writer = try PDFDocumentWriter(theme: .standard, title: "Baselines")
    try writer.table(header: [NSAttributedString(string: ""), NSAttributedString(string: "")],
        rows: [[text(large, target: "https://example.com/large"), text(small, target: "https://example.com/small")]], alignments: [])
    let pdf = try #require(PDFDocument(data: writer.finish()))
    let annotations = try #require(pdf.page(at: 0)).annotations
    let a = try #require(annotations.first { $0.url?.absoluteString.hasSuffix("large") == true })
    let b = try #require(annotations.first { $0.url?.absoluteString.hasSuffix("small") == true })
    #expect(abs(a.bounds.minY + CTFontGetDescent(large) - b.bounds.minY - CTFontGetDescent(small)) < 0.01)
}

@Test func reservedImageMinimumHeightDoesNotStretchPixelsOrLinkFrame() throws {
    let raster = try PDFImageRaster(asset: orientedPhoto(6), path: "photo.jpg")
    let writer = try PDFDocumentWriter(theme: .standard, title: "Minimum image row")
    try writer.image(raster, linkTarget: "https://example.com/image", minimumHeight: 100)
    let pdf = try #require(PDFDocument(data: writer.finish()))
    let frame = try #require(pdf.page(at: 0)?.annotations.first?.bounds)
    #expect(abs(frame.width - raster.naturalSize.width) < 0.01)
    #expect(abs(frame.height - raster.naturalSize.height) < 0.01)
    #expect(frame.height < 100)
}
