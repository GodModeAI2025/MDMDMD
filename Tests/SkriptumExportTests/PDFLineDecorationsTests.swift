import Foundation
import CoreGraphics
import CoreText
import PDFKit
import Testing
@testable import SkriptumExport

@Test func wrappedUnicodePDFLinksProduceBoundedRealAnnotations() throws {
    let target = "https://example.com/proof"
    let adapter = try PDFInlineAdapter(theme: .standard, footnoteIDs: [])
    let fragments = try adapter.fragments([.text("Before "), .link(target, [.text(String(repeating: "link 🦊 مرحبا ", count: 10))]), .text("After")])
    guard case .text(let text) = fragments.first else { Issue.record("Missing text"); return }
    var layout = try PDFTextTypesetter(text: text, availableWidth: 140)
    let data = NSMutableData(); let consumer = try #require(CGDataConsumer(data: data))
    var box = CGRect(x: 0,y: 0,width: 180,height: 600)
    let context = try #require(CGContext(consumer: consumer,mediaBox: &box,nil))
    context.beginPDFPage(nil); var top: CGFloat = 580, regionCount = 0, lineCount = 0
    while let line = try layout.nextLine() {
        let baseline = CGPoint(x: 20,y: top - line.ascent)
        let regions = try line.linkRegions(baseline: baseline)
        for region in regions {
            #expect(region.target == target)
            #expect(region.bounds.minX >= 20 - 0.01 && region.bounds.maxX <= 160 + 0.01)
            #expect(NSIntersectionRange(region.sourceRange,line.sourceRange) == region.sourceRange)
            #expect(region.bounds.height > 0 && region.bounds.width > 0)
        }
        regionCount += regions.count; lineCount += 1
        try line.draw(in: context,baseline: baseline)
        try line.addLinkAnnotations(in: context,baseline: baseline)
        top -= line.advance
    }
    context.endPDFPage(); context.closePDF()
    let pdf = try #require(PDFDocument(data: data as Data)); let page = try #require(pdf.page(at: 0))
    #expect(lineCount > 1 && regionCount > 1)
    #expect(page.annotations.count == regionCount)
    for annotation in page.annotations { #expect(annotation.url?.absoluteString == target) }
    #expect(pdf.string?.filter { $0 == "🦊" }.count == 10)
}

@Test func semanticPDFStrikethroughDrawsAcrossWhitespace() throws {
    func bitmap(strike: Bool) throws -> [UInt8] {
        let adapter = try PDFInlineAdapter(theme: .standard,footnoteIDs: [])
        let items: [Inline] = strike ? [.strike([.text("ab    cd")])] : [.text("ab    cd")]
        let fragments = try adapter.fragments(items)
        guard case .text(let text) = fragments.first else { throw ExportError.unsupportedMarkdown("no text") }
        var layout = try PDFTextTypesetter(text: text,availableWidth: 100)
        let candidate = try layout.nextLine(); let line = try #require(candidate)
        let context = try #require(CGContext(data: nil,width: 120,height: 80,bitsPerComponent: 8,bytesPerRow: 480,
            space: CGColorSpaceCreateDeviceRGB(),bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 1,alpha: 1)); context.fill(CGRect(x: 0,y: 0,width: 120,height: 80))
        try line.draw(in: context,baseline: CGPoint(x: 10,y: 30))
        return Array(UnsafeBufferPointer(start: try #require(context.data).assumingMemoryBound(to: UInt8.self),count: 480*80))
    }
    let plain = try bitmap(strike: false), struck = try bitmap(strike: true)
    // A central space column has no glyph ink; a continuous strike adds ink.
    let column = 30
    let plainInk = (0..<80).reduce(0) { $0 + 255 - Int(plain[$1*480+column*4]) }
    let struckInk = (0..<80).reduce(0) { $0 + 255 - Int(struck[$1*480+column*4]) }
    #expect(struckInk > plainInk + 20)
}

@Test func superscriptPDFNoteLinksResolveToNamedDestinationOnAnotherPage() throws {
    let adapter = try PDFInlineAdapter(theme: .standard,footnoteIDs: ["n"])
    let fragments = try adapter.fragments([.text("Text"), .footnote("n")])
    guard case .text(let text) = fragments.first else { Issue.record("No text"); return }
    var layout = try PDFTextTypesetter(text: text,availableWidth: 200)
    let candidate = try layout.nextLine(); let line = try #require(candidate)
    let baseline = CGPoint(x: 20,y: 100)
    let regions = try line.linkRegions(baseline: baseline)
    #expect(regions.count == 1)
    #expect(regions.first?.target == "#note-1")
    #expect(regions.first?.sourceRange == NSRange(location: 4,length: 1))
    #expect((regions.first?.bounds.minY ?? 0) > baseline.y)
    let data = NSMutableData(); let consumer = try #require(CGDataConsumer(data: data))
    var box = CGRect(x: 0,y: 0,width: 260,height: 180)
    let context = try #require(CGContext(consumer: consumer,mediaBox: &box,nil))
    context.beginPDFPage(nil)
    try line.draw(in: context,baseline: baseline)
    try line.addLinkAnnotations(in: context,baseline: baseline)
    context.endPDFPage(); context.beginPDFPage(nil)
    context.addDestination("note-1" as CFString,at: CGPoint(x: 20,y: 100))
    context.endPDFPage(); context.closePDF()
    let pdf = try #require(PDFDocument(data: data as Data))
    let annotation = try #require(pdf.page(at: 0)?.annotations.first)
    let destination = try #require(annotation.destination)
    #expect(destination.page === pdf.page(at: 1))
}
