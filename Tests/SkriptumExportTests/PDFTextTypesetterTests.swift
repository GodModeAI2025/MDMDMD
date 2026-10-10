import Foundation
import CoreText
import CoreGraphics
import PDFKit
import Testing
@testable import SkriptumExport

private func pdfText(_ text: String) -> NSAttributedString {
    NSAttributedString(string: text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Georgia" as CFString, 12, nil)])
}

@Test func pdfTextLayoutKeepsExactUnicodeRangesAtNarrowWidths() throws {
    let value = "e\u{301} 👩🏽‍💻 🦊 👨‍👩‍👧‍👦 🇩🇪\r\nمرحبا بالعالم\n最後の段落"
    let source = value as NSString
    for width: CGFloat in [1, 18, 55, 200] {
        var layout = try PDFTextTypesetter(text: pdfText(value), availableWidth: width)
        var consumed = 0, slices = ""
        while let line = try layout.nextLine() {
            #expect(line.sourceRange.location == consumed)
            #expect(line.sourceRange.length > 0)
            #expect(source.rangeOfComposedCharacterSequences(for: line.sourceRange) == line.sourceRange)
            #expect(line.advance.isFinite && line.advance > 0)
            slices += source.substring(with: line.sourceRange)
            consumed = NSMaxRange(line.sourceRange)
        }
        #expect(consumed == source.length)
        #expect(Array(slices.utf8) == Array(value.utf8))
    }
}

@Test func pdfTextLayoutFreezesMutableSourceAndRejectsInvalidGeometry() throws {
    let mutable = NSMutableAttributedString(attributedString: pdfText("Original 🦊"))
    var layout = try PDFTextTypesetter(text: mutable, availableWidth: 200)
    mutable.mutableString.setString("Changed")
    let candidate = try layout.nextLine()
    let line = try #require(candidate)
    #expect(line.sourceRange.length == ("Original 🦊" as NSString).length)
    let finalLine = try layout.nextLine()
    #expect(finalLine == nil)
    for width: CGFloat in [0, -1, .infinity, .nan] {
        #expect(throws: PDFTextTypesetter.LayoutError.invalidGeometry) {
            try PDFTextTypesetter(text: pdfText("A"), availableWidth: width)
        }
    }
}

@Test func coreTextPDFParagraphsRetainEmojiAcrossWrappedPages() throws {
    let source = (0..<64).map { "Absatz \($0) 🦊" }.joined(separator: "\n")
    var layout = try PDFTextTypesetter(text: pdfText(source), availableWidth: 180, lineHeightMultiple: 1.5)
    let bytes = NSMutableData()
    let consumer = try #require(CGDataConsumer(data: bytes))
    var box = CGRect(x: 0, y: 0, width: 220, height: 180)
    let context = try #require(CGContext(consumer: consumer, mediaBox: &box, nil))
    context.beginPDFPage(nil)
    var y: CGFloat = 160
    while let line = try layout.nextLine() {
        if y - line.ascent - line.descent < 20 {
            context.endPDFPage(); context.beginPDFPage(nil); y = 160
        }
        context.textMatrix = CGAffineTransform(scaleX: 2, y: 2)
        context.textPosition = CGPoint(x: 3, y: 4)
        let matrixBeforeDrawing = context.textMatrix
        let positionBeforeDrawing = context.textPosition
        try line.draw(in: context, baseline: CGPoint(x: 20, y: y - line.ascent))
        #expect(context.textMatrix == matrixBeforeDrawing)
        #expect(context.textPosition == positionBeforeDrawing)
        y -= line.advance
    }
    context.endPDFPage(); context.closePDF()
    let document = try #require(PDFDocument(data: bytes as Data))
    #expect(document.pageCount > 1)
    let extracted = try #require(document.string)
    #expect(extracted.filter { $0 == "🦊" }.count == 64)
    for index in 0..<64 { #expect(extracted.contains("Absatz \(index) 🦊")) }
}
