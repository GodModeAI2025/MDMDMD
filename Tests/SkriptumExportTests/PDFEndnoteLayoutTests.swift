import Foundation
import PDFKit
import Testing
@testable import SkriptumExport

@Test(arguments: [false, true])
func endnoteNumberSharesFirstBodyBaselineAndDestination(tagged: Bool) throws {
    if tagged {
        guard #available(macOS 27.0, iOS 27.0, *) else { return }
    }
    var theme = ExportTheme.standard
    theme.includeTitle = false
    let longBody = "NoteStart 🦊 " + String(repeating: "Mehrsprachiger Notentext français ελληνικά. ", count: 240)
    let source = "Text[^n].\n\n[^n]: " + longBody + " [NoteLink](https://example.com/note)\n\n    NoteTail.\n"
    var parser = SemanticParser(input: ExportInput(title: "Endnotes", markdown: source, language: "de-DE"))
    let document = try parser.parse()
    let data = try PDFSemanticRenderer.render(document, theme: theme, taggedStructure: tagged)
    if let folder = ProcessInfo.processInfo.environment["SCRIPTUM_ENDNOTE_QA_OUTPUT"] {
        try data.write(to: URL(fileURLWithPath: folder).appendingPathComponent(tagged ? "tagged.pdf" : "plain.pdf"), options: .atomic)
    }
    let pdf = try #require(PDFDocument(data: data))
    let page = try #require((0..<pdf.pageCount).compactMap { pdf.page(at: $0) }.first { $0.string?.contains("NoteStart") == true })
    let body = try #require(page.string)
    let startRange = (body as NSString).range(of: "NoteStart")
    let labelRange = (body as NSString).range(of: "1.")
    #expect(startRange.location != NSNotFound && labelRange.location != NSNotFound)
    let start = try #require(page.selection(for: startRange)).bounds(for: page)
    let label = try #require(page.selection(for: labelRange)).bounds(for: page)
    #expect(abs(start.minY - label.minY) < 0.5)
    #expect(label.maxX < start.minX)
    #expect(pdf.pageCount > 1)
    #expect(pdf.string?.contains("NoteTail.") == true)
    let annotations = (0..<pdf.pageCount).flatMap { pdf.page(at: $0)?.annotations ?? [] }
    let reference = try #require(annotations.first { $0.destination != nil })
    #expect(reference.destination?.page === page)
    #expect(abs((reference.destination?.point.y ?? 0) - start.minY) < 20)
    #expect(annotations.filter { $0.url?.absoluteString == "https://example.com/note" }.count == 1)
}

@Test(arguments: [0, 1, 2])
func endnoteLayoutRetainsCodeImagesAndNestedTail(kind: Int) throws {
    guard #available(macOS 27.0, iOS 27.0, *) else { return }
    let asset = try orientedPhoto(6)
    let first: SemanticBlock
    switch kind {
    case 0: first = .code("CodeWitness 🦊", "swift")
    case 1: first = .paragraph([.text("BeforeImageWitness "), .image("photo.jpg", "Note photograph"), .text(" AfterImageWitness")])
    default: first = .paragraph([.image("photo.jpg", "Image-first note"), .text("ImageFirstWitness")])
    }
    let input = ExportInput(title: "Rich notes", markdown: "", assets: ["photo.jpg": asset])
    let document = SemanticDocument(input: input, blocks: [.paragraph([.text("BodyWitness")])],
        footnotes: [("n", [first, .quote([.paragraph([.text("QuoteWitness")])]),
            .table([[.text("HeaderWitness")]], [[[.text("CellWitness")]]], ["left"])])],
        warnings: [], imagePaths: kind == 0 ? [] : ["photo.jpg"])
    let data = try PDFSemanticRenderer.render(document, theme: .standard, taggedStructure: true)
    let pdf = try #require(PDFDocument(data: data))
    let text = try #require(pdf.string)
    let witnesses = ["BodyWitness", "QuoteWitness", "HeaderWitness", "CellWitness"]
        + (kind == 0 ? ["CodeWitness"] : kind == 1 ? ["BeforeImageWitness", "AfterImageWitness"] : ["ImageFirstWitness"])
    for witness in witnesses { #expect(text.components(separatedBy: witness).count - 1 == 1) }
    if let folder = ProcessInfo.processInfo.environment["SCRIPTUM_ENDNOTE_QA_OUTPUT"] {
        try data.write(to: URL(fileURLWithPath: folder).appendingPathComponent("rich-\(kind).pdf"), options: .atomic)
    }
}
