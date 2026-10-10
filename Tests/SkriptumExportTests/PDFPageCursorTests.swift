import Foundation
import CoreGraphics
import CoreText
import PDFKit
import Testing
@testable import SkriptumExport

@Test func semanticPDFPageGeometryUsesThemePaperAndMargins() throws {
    for size in ExportPaperSize.allCases {
        let theme = try ExportTheme(marginsMM: 25.4, paperSize: size)
        let cursor = try PDFPageCursor(theme: theme)
        #expect(abs(cursor.paper.width - CGFloat(size.widthMM * 72 / 25.4)) < 0.001)
        #expect(abs(cursor.paper.height - CGFloat(size.heightMM * 72 / 25.4)) < 0.001)
        #expect(abs(cursor.content.minX - 72) < 0.001)
        #expect(abs(cursor.content.minY - 72) < 0.001)
        #expect(cursor.isAtPageStart)
    }
}

@Test func semanticPDFCursorDrawsEveryUnicodeLineAcrossRealPages() throws {
    let adapter = try PDFInlineAdapter(theme: .standard, footnoteIDs: [])
    let items = (0..<180).map { Inline.text("Absatz \($0) 🦊\n") }
    let fragments = try adapter.fragments(items)
    guard case .text(let text) = fragments.first else { Issue.record("Missing text"); return }
    var cursor = try PDFPageCursor(theme: .standard)
    var layout = try PDFTextTypesetter(text: text, availableWidth: cursor.content.width, lineHeightMultiple: 1.65)
    let bytes = NSMutableData()
    let consumer = try #require(CGDataConsumer(data: bytes))
    var paper = cursor.paper
    let context = try #require(CGContext(consumer: consumer, mediaBox: &paper, nil))
    var drawnPage = 0
    context.beginPDFPage(nil)
    while let line = try layout.nextLine() {
        let placement = try cursor.place(line)
        if placement.pageIndex != drawnPage {
            #expect(placement.pageIndex == drawnPage + 1)
            context.endPDFPage(); context.beginPDFPage(nil); drawnPage = placement.pageIndex
        }
        #expect(placement.baseline.y + line.ascent <= cursor.content.maxY + 0.001)
        #expect(placement.baseline.y - line.descent >= cursor.content.minY - 0.001)
        try line.draw(in: context, baseline: placement.baseline)
    }
    context.endPDFPage(); context.closePDF()
    let pdf = try #require(PDFDocument(data: bytes as Data))
    #expect(pdf.pageCount == cursor.pageIndex + 1)
    #expect(pdf.pageCount > 1)
    let extracted = try #require(pdf.string)
    #expect(extracted.filter { $0 == "🦊" }.count == 180)
    for index in 0..<180 { #expect(extracted.contains("Absatz \(index) 🦊")) }
}

@Test func semanticPDFReservationRejectsOverflowWithoutSkippingPages() throws {
    var cursor = try PDFPageCursor(theme: .standard, maximumPages: 2)
    let originalTop = cursor.top
    do { try cursor.reserve(height: cursor.content.height + 1); Issue.record("Oversized item accepted") }
    catch PDFPageCursor.PageError.itemExceedsPage {} catch { Issue.record("Unexpected error: \(error)") }
    #expect(cursor.top == originalTop && cursor.pageIndex == 0)
    try cursor.space(after: cursor.content.height)
    try cursor.reserve(height: 20)
    #expect(cursor.pageIndex == 1 && cursor.isAtPageStart)
    try cursor.space(after: cursor.content.height)
    let exhaustedTop = cursor.top
    do { try cursor.reserve(height: 20); Issue.record("Page budget exceeded") }
    catch PDFPageCursor.PageError.pageLimitExceeded {} catch { Issue.record("Unexpected error: \(error)") }
    #expect(cursor.top == exhaustedTop && cursor.pageIndex == 1)
}
