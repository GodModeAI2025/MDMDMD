import Foundation
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
