import Foundation
import CoreGraphics
import PDFKit
import Testing
@testable import SkriptumExport

@Test func taggedParagraphOwnsAllPagesWithoutReplacingUnicodeText() throws {
    guard #available(macOS 27.0, *) else { return }
    let adapter = try PDFInlineAdapter(theme: .standard, footnoteIDs: [])
    guard case .text(let text)? = try adapter.fragments([.text((0..<200).map { "Paragraph \($0) 🦊\n" }.joined())]).first else {
        Issue.record("Missing text"); return
    }
    let writer = try PDFDocumentWriter(theme: .standard, title: "Tagged", taggedParagraphs: true)
    try writer.paragraph(text)
    let data = try writer.finish()
    if let path = ProcessInfo.processInfo.environment["SCRIPTUM_PDF_PARAGRAPH_TAG_QA_OUTPUT"] {
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }
    let pdf = try #require(PDFDocument(data: data))
    #expect(pdf.pageCount > 1)
    let extracted = try #require(pdf.string)
    #expect(extracted.filter { $0 == "🦊" }.count == 200)
    #expect(!extracted.contains("\u{fffc}"))
    for index in 0..<200 { #expect(extracted.contains("Paragraph \(index) 🦊")) }
    let provider = try #require(CGDataProvider(data: data as CFData))
    let corePDF = try #require(CGPDFDocument(provider))
    let catalog = try #require(corePDF.catalog)
    var structure: CGPDFDictionaryRef?
    #expect(CGPDFDictionaryGetDictionary(catalog, "StructTreeRoot", &structure))
    let root = try #require(structure)
    var paragraph: CGPDFDictionaryRef?
    #expect(CGPDFDictionaryGetDictionary(root, "K", &paragraph))
    let element = try #require(paragraph)
    var role: UnsafePointer<CChar>?
    #expect(CGPDFDictionaryGetName(element, "S", &role))
    #expect(String(cString: try #require(role)) == "P")
    var content: CGPDFArrayRef?
    #expect(CGPDFDictionaryGetArray(element, "K", &content))
    #expect(CGPDFArrayGetCount(try #require(content)) == 200)
}
