import Foundation
import CoreGraphics
import PDFKit
import Testing
@testable import SkriptumExport

@Test func paragraphRendererPreservesLongUnicodeAndLinksAcrossPages() throws {
    let adapter = try PDFInlineAdapter(theme: .standard, footnoteIDs: [])
    let target = "https://example.com/author"
    let content = (0..<200).map { "Zeile \($0) 🦊 العربية é\n" }.joined()
    let fragments = try adapter.fragments([.link(target, [.text(content)])])
    guard case .text(let text) = fragments.first else { Issue.record("Missing text"); return }
    var cursor = try PDFPageCursor(theme: .standard)
    try cursor.space(after: cursor.content.height - 15)
    let data = NSMutableData()
    let consumer = try #require(CGDataConsumer(data: data))
    var paper = cursor.paper
    let context = try #require(CGContext(consumer: consumer, mediaBox: &paper, nil))
    context.beginPDFPage(nil)
    // Existing content makes the first page legitimate, even when this entire
    // paragraph starts on its successor to respect widow/orphan rules.
    context.fill(CGRect(x: 72, y: 750, width: 20, height: 20))
    var opened: [Int] = []
    try PDFParagraphRenderer.draw(text: text, cursor: &cursor, context: context,
        lineHeight: 1.65, indent: 18, paragraphSpacing: 8) { page in
            opened.append(page); context.endPDFPage(); context.beginPDFPage(nil)
        }
    context.endPDFPage(); context.closePDF()
    let pdf = try #require(PDFDocument(data: data as Data))
    #expect(pdf.pageCount > 2)
    #expect(opened == Array(1..<pdf.pageCount))
    let extracted = try #require(pdf.string)
    #expect(extracted.filter { $0 == "🦊" }.count == 200)
    for index in 0..<200 { #expect(extracted.contains("Zeile \(index) 🦊")) }
    for index in 1..<pdf.pageCount {
        let page = try #require(pdf.page(at: index))
        #expect(!page.annotations.isEmpty)
        #expect(page.annotations.allSatisfy { $0.url?.absoluteString == target })
        #expect(page.annotations.allSatisfy { cursor.content.insetBy(dx: -0.01, dy: -0.01).contains($0.bounds) })
    }
}
