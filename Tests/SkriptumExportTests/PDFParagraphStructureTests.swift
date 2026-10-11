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
    let writer = try PDFDocumentWriter(theme: .standard, title: "Tagged", taggedStructure: true)
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
    var document: CGPDFDictionaryRef?
    #expect(CGPDFDictionaryGetDictionary(root, "K", &document))
    var paragraph: CGPDFDictionaryRef?
    #expect(CGPDFDictionaryGetDictionary(try #require(document), "K", &paragraph))
    let element = try #require(paragraph)
    var role: UnsafePointer<CChar>?
    #expect(CGPDFDictionaryGetName(element, "S", &role))
    #expect(String(cString: try #require(role)) == "P")
    var content: CGPDFArrayRef?
    #expect(CGPDFDictionaryGetArray(element, "K", &content))
    #expect(CGPDFArrayGetCount(try #require(content)) == 200)
}

@Test func taggedSemanticHeadingsRetainRolesLanguageAndOrder() throws {
    guard #available(macOS 27.0, *) else { return }
    var parser = SemanticParser(input: ExportInput(title: "Structure", markdown:
        "# Heading\n\nBody 🦊.\n\n## Subheading\n\n```swift\nlet value = 1\n```\n", language: "de"))
    let document = try parser.parse()
    let data = try PDFSemanticRenderer.render(document, theme: .standard, taggedStructure: true)
    let pdf = try #require(PDFDocument(data: data))
    let untagged = try #require(PDFDocument(data: PDFSemanticRenderer.render(document, theme: .standard)))
    #expect(pdf.string == untagged.string)
    #expect(pdf.string?.filter { $0 == "🦊" }.count == 1)
    let provider = try #require(CGDataProvider(data: data as CFData))
    let core = try #require(CGPDFDocument(provider))
    var structure: CGPDFDictionaryRef?
    #expect(CGPDFDictionaryGetDictionary(try #require(core.catalog), "StructTreeRoot", &structure))
    var documentRoot: CGPDFDictionaryRef?
    #expect(CGPDFDictionaryGetDictionary(try #require(structure), "K", &documentRoot))
    let logicalDocument = try #require(documentRoot)
    var documentRole: UnsafePointer<CChar>?
    #expect(CGPDFDictionaryGetName(logicalDocument, "S", &documentRole))
    #expect(String(cString: try #require(documentRole)) == "Document")
    var documentLanguage: CGPDFStringRef?
    #expect(CGPDFDictionaryGetString(logicalDocument, "Lang", &documentLanguage))
    #expect(CGPDFStringCopyTextString(try #require(documentLanguage)) as String? == "de")
    var children: CGPDFArrayRef?
    #expect(CGPDFDictionaryGetArray(logicalDocument, "K", &children))
    let array = try #require(children)
    #expect(CGPDFArrayGetCount(array) == 4)
    var roles: [String] = []
    for index in 0..<4 {
        var child: CGPDFDictionaryRef?
        #expect(CGPDFArrayGetDictionary(array, index, &child))
        let item = try #require(child)
        var name: UnsafePointer<CChar>?
        #expect(CGPDFDictionaryGetName(item, "S", &name))
        roles.append(String(cString: try #require(name)))
        var lang: CGPDFStringRef?
        #expect(CGPDFDictionaryGetString(item, "Lang", &lang))
        #expect(CGPDFStringCopyTextString(try #require(lang)) as String? == "de")
    }
    #expect(roles == ["H1", "P", "H2", "Code"])
}

@Test func taggedFigureExportsStandardAlternativeText() throws {
    guard #available(macOS 27.0, *) else { return }
    var parser = SemanticParser(input: ExportInput(title: "Image", markdown: "![Description /AltText 🦊](photo.jpg)",
        assets: ["photo.jpg": try orientedPhoto(6)]))
    let document = try parser.parse()
    let data = try PDFSemanticRenderer.render(document, theme: .standard, taggedStructure: true)
    if let path = ProcessInfo.processInfo.environment["SCRIPTUM_PDF_FIGURE_QA_OUTPUT"] {
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }
    let provider = try #require(CGDataProvider(data: data as CFData))
    let core = try #require(CGPDFDocument(provider))
    var root: CGPDFDictionaryRef?
    #expect(CGPDFDictionaryGetDictionary(try #require(core.catalog), "StructTreeRoot", &root))
    var documentRoot: CGPDFDictionaryRef?
    #expect(CGPDFDictionaryGetDictionary(try #require(root), "K", &documentRoot))
    var figure: CGPDFDictionaryRef?
    #expect(CGPDFDictionaryGetDictionary(try #require(documentRoot), "K", &figure))
    var alt: CGPDFStringRef?
    #expect(CGPDFDictionaryGetString(try #require(figure), "Alt", &alt))
    #expect(CGPDFStringCopyTextString(try #require(alt)) as String? == "Description /AltText 🦊")
    var wrong: CGPDFObjectRef?
    #expect(!CGPDFDictionaryGetObject(try #require(figure), "AltText", &wrong))
}
