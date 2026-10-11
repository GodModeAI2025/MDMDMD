import Foundation
import CoreGraphics
import ImageIO
import PDFKit
import Testing
@testable import SkriptumExport

@Test(arguments: [false, true]) func headingsStayWithFollowingImageMixedParagraphAndTable(tagged: Bool) throws {
    let theme = ExportTheme.standard
    let geometry = try PDFPageCursor(theme: theme)
    let adapter = try PDFInlineAdapter(theme: theme, footnoteIDs: [])
    guard case .text(let one)? = try adapter.fragments([.text("Filler\n")]).first else { Issue.record("Missing text"); return }
    let height = try PDFParagraphLayout(text: one, width: geometry.content.width, lineHeight: CGFloat(theme.lineHeight)).lineHeights[0]
    let count = Int((geometry.content.height - 110) / height)
    let asset = try headingMediaAsset(pixelHeight: 600)
    for kind in ["image", "mixed", "table"] {
        let next: SemanticBlock = kind == "table" ? .table([[.text("Column")]], [[[.text(String(repeating: "Row 🦊\n", count: 10))]]], []) : .paragraph([.link("https://example.com/figure", [.image("figure.png", "Blue figure")])] + (kind == "mixed" ? [.text("AfterImage 🦊")] : []))
        let doc = SemanticDocument(input: ExportInput(title: "Media keep", markdown: "", assets: ["figure.png": asset]), blocks: [.paragraph([.text(String(repeating: "Filler\n", count: count))]), .heading(1, [.text("TogetherMedia")]), next], footnotes: [], warnings: [], imagePaths: kind == "table" ? [] : ["figure.png"])
        let data = try PDFSemanticRenderer.render(doc, theme: theme, taggedStructure: tagged)
        if let prefix = ProcessInfo.processInfo.environment["SCRIPTUM_HEADING_MEDIA_OUTPUT"] {
            try data.write(to: URL(fileURLWithPath: prefix + "-" + kind + (tagged ? "-tagged.pdf" : "-plain.pdf")), options: .atomic)
        }
        let pdf = try #require(PDFDocument(data: data))
        let headingPage = try #require((0..<pdf.pageCount).first { pdf.page(at: $0)?.string?.contains("TogetherMedia") == true })
        #expect(headingPage > 0)
        if kind == "table" {
            #expect(pdf.page(at: headingPage)?.string?.contains("Column") == true)
            #expect(pdf.page(at: headingPage)?.string?.contains("Row 🦊") == true)
            #expect(pdf.string?.filter { $0 == "🦊" }.count == 10)
        } else {
            let imagePage = try #require((0..<pdf.pageCount).first { pdf.page(at: $0)?.annotations.contains { $0.url?.absoluteString == "https://example.com/figure" } == true })
            #expect(headingPage == imagePage)
            if kind == "mixed" { #expect(pdf.string?.contains("AfterImage 🦊") == true) }
        }
    }
}

private func headingMediaAsset(pixelHeight: Int) throws -> ExportAsset {
    let bitmap = try #require(CGContext(data: nil, width: 400, height: pixelHeight, bitsPerComponent: 8, bytesPerRow: 1600, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    bitmap.setFillColor(CGColor(red: 0.1, green: 0.35, blue: 0.75, alpha: 1)); bitmap.fill(CGRect(x: 0, y: 0, width: 400, height: pixelHeight))
    let bytes = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(bytes, "public.png" as CFString, 1, nil))
    CGImageDestinationAddImage(destination, try #require(bitmap.makeImage()), nil)
    #expect(CGImageDestinationFinalize(destination))
    return ExportAsset(data: bytes as Data, mediaType: "image/png")
}

@Test(arguments: [false, true]) func longHeadingChainKeepsOversizedImageOrFirstTallTableFragment(table: Bool) throws {
    let asset = try headingMediaAsset(pixelHeight: 1600)
    let headers = (1...30).map { SemanticBlock.heading(2, [.text("MediaHeading-\($0)-End")]) }
    let body: SemanticBlock = table ? .table([[.text("TableHeader")]], [[[.text(String(repeating: "TallRow 🦊\n", count: 100))]]], []) : .paragraph([.link("https://example.com/large", [.image("large.png", "Large blue figure")])])
    let doc = SemanticDocument(input: ExportInput(title: "Long media chain", markdown: "", assets: ["large.png":asset]), blocks: headers + [body], footnotes: [], warnings: [], imagePaths: table ? [] : ["large.png"])
    let pdf = try #require(PDFDocument(data: PDFSemanticRenderer.render(doc, theme: .standard, taggedStructure: true)))
    let text = try #require(pdf.string)
    for index in 1...30 { #expect(text.components(separatedBy: "MediaHeading-\(index)-End").count == 2) }
    let last = try #require((0..<pdf.pageCount).first { pdf.page(at: $0)?.string?.contains("MediaHeading-30-End") == true })
    if table {
        #expect(pdf.page(at: last)?.string?.contains("TableHeader") == true)
        #expect(pdf.page(at: last)?.string?.contains("TallRow 🦊") == true)
        #expect(text.filter { $0 == "🦊" }.count == 100)
    } else {
        let annotation = try #require(pdf.page(at: last)?.annotations.first { $0.url?.absoluteString == "https://example.com/large" })
        #expect(abs(annotation.bounds.width / annotation.bounds.height - 0.25) < 0.0001)
        #expect(annotation.bounds.height < 700)
    }
}
