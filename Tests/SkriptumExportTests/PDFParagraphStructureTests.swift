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

@Test func taggedContainersPreserveNestingAndRejectUnbalancedGroups() throws {
    guard #available(macOS 27.0, *) else { return }
    var parser = SemanticParser(input: ExportInput(title: "Containers", markdown:
        "> Quoted 🦊.\n\n1. First[^n]\n2. Second\n\n[^n]: Note body.\n"))
    let document = try parser.parse()
    let data = try PDFSemanticRenderer.render(document, theme: .standard, taggedStructure: true)
    if let path = ProcessInfo.processInfo.environment["SCRIPTUM_PDF_CONTAINER_QA_OUTPUT"] {
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }
    let tagged = try #require(PDFDocument(data: data))
    let plain = try #require(PDFDocument(data: PDFSemanticRenderer.render(document, theme: .standard)))
    #expect(tagged.string == plain.string)
    let provider = try #require(CGDataProvider(data: data as CFData))
    let core = try #require(CGPDFDocument(provider))
    var root: CGPDFDictionaryRef?
    #expect(CGPDFDictionaryGetDictionary(try #require(core.catalog), "StructTreeRoot", &root))
    var doc: CGPDFDictionaryRef?
    #expect(CGPDFDictionaryGetDictionary(try #require(root), "K", &doc))
    var children: CGPDFArrayRef?
    #expect(CGPDFDictionaryGetArray(try #require(doc), "K", &children))
    let array = try #require(children)
    #expect(CGPDFArrayGetCount(array) == 3)
    var roles: [String] = []
    for index in 0..<3 {
        var child: CGPDFDictionaryRef?, name: UnsafePointer<CChar>?
        #expect(CGPDFArrayGetDictionary(array, index, &child))
        #expect(CGPDFDictionaryGetName(try #require(child), "S", &name))
        roles.append(String(cString: try #require(name)))
    }
    #expect(roles == ["BlockQuote", "L", "Note"])
    let open = try PDFDocumentWriter(theme: .standard, title: "Unbalanced", taggedStructure: true)
    try open.beginStructureGroup(.list)
    #expect(throws: PDFDocumentWriter.WriterError.invalidStructure) { try open.finish() }
    #expect(throws: PDFDocumentWriter.WriterError.closed) { try open.finish() }
}

@Test func nestedQuoteGroupsSpanPagesWithoutFragmentingLogicalParagraph() throws {
    guard #available(macOS 27.0, *) else { return }
    let document = SemanticDocument(input: ExportInput(title: "Nested", markdown: ""), blocks: [
        .quote([.quote([.paragraph([.text((0..<200).map { "Nested \($0) 🦊\n" }.joined())])])])
    ], footnotes: [], warnings: [], imagePaths: [])
    let data = try PDFSemanticRenderer.render(document, theme: .standard, taggedStructure: true)
    let pdf = try #require(PDFDocument(data: data))
    #expect(pdf.pageCount > 1)
    #expect(pdf.string?.filter { $0 == "🦊" }.count == 200)
    let provider = try #require(CGDataProvider(data: data as CFData))
    let core = try #require(CGPDFDocument(provider))
    var root: CGPDFDictionaryRef?
    #expect(CGPDFDictionaryGetDictionary(try #require(core.catalog), "StructTreeRoot", &root))
    var current = try #require(root)
    for expected in ["Document", "BlockQuote", "BlockQuote", "P"] {
        var child: CGPDFDictionaryRef?, name: UnsafePointer<CChar>?
        #expect(CGPDFDictionaryGetDictionary(current, "K", &child))
        current = try #require(child)
        #expect(CGPDFDictionaryGetName(current, "S", &name))
        #expect(String(cString: try #require(name)) == expected)
    }
    var items: CGPDFArrayRef?
    #expect(CGPDFDictionaryGetArray(current, "K", &items))
    #expect(CGPDFArrayGetCount(try #require(items)) == 200)
}

@Test func taggedTallTableKeepsOneLogicalRowAndCellAcrossPages() throws {
    guard #available(macOS 27.0, *) else { return }
    let adapter = try PDFInlineAdapter(theme: .standard, footnoteIDs: [])
    func text(_ source: String) throws -> NSAttributedString {
        guard case .text(let result)? = try adapter.fragments([.text(source)]).first else { throw PDFTextTypesetter.LayoutError.invalidBreak }
        return result
    }
    let writer = try PDFDocumentWriter(theme: .standard, title: "Table structure", taggedStructure: true, language: "de")
    try writer.table(header: [text("First"), text("Second")],
        rows: [[text((0..<100).map { "Cell \($0) 🦊\n" }.joined()), text("Other")]], alignments: [])
    let data = try writer.finish()
    if let path = ProcessInfo.processInfo.environment["SCRIPTUM_PDF_TABLE_TAG_QA_OUTPUT"] {
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }
    let pdf = try #require(PDFDocument(data: data))
    #expect(pdf.pageCount > 1)
    #expect(pdf.string?.filter { $0 == "🦊" }.count == 100)
    let provider = try #require(CGDataProvider(data: data as CFData))
    let core = try #require(CGPDFDocument(provider))
    var root: CGPDFDictionaryRef?
    #expect(CGPDFDictionaryGetDictionary(try #require(core.catalog), "StructTreeRoot", &root))
    var document: CGPDFDictionaryRef?, table: CGPDFDictionaryRef?
    #expect(CGPDFDictionaryGetDictionary(try #require(root), "K", &document))
    #expect(CGPDFDictionaryGetDictionary(try #require(document), "K", &table))
    var rows: CGPDFArrayRef?
    #expect(CGPDFDictionaryGetArray(try #require(table), "K", &rows))
    let rowArray = try #require(rows)
    #expect(CGPDFArrayGetCount(rowArray) == 2) // one header and one split data row
    for row in 0..<2 {
        var item: CGPDFDictionaryRef?, cells: CGPDFArrayRef?
        #expect(CGPDFArrayGetDictionary(rowArray, row, &item))
        #expect(CGPDFDictionaryGetArray(try #require(item), "K", &cells))
        let cellArray = try #require(cells)
        #expect(CGPDFArrayGetCount(cellArray) == 2)
        for column in 0..<2 {
            var cell: CGPDFDictionaryRef?, name: UnsafePointer<CChar>?
            #expect(CGPDFArrayGetDictionary(cellArray, column, &cell))
            #expect(CGPDFDictionaryGetName(try #require(cell), "S", &name))
            #expect(String(cString: try #require(name)) == (row == 0 ? "TH" : "TD"))
        }
    }
}

@Test func taggedTextLinkReferencesActualAnnotationObject() throws {
    guard #available(macOS 27.0, *) else { return }
    let adapter = try PDFInlineAdapter(theme: .standard, footnoteIDs: [])
    guard case .text(let text)? = try adapter.fragments([.text("Before "),
        .link("https://example.com", [.text("Read source")]), .text(" after.")]).first else {
        Issue.record("Missing text"); return
    }
    let writer = try PDFDocumentWriter(theme: .standard, title: "Link", taggedStructure: true)
    try writer.paragraph(text)
    let data = try writer.finish()
    if let path = ProcessInfo.processInfo.environment["SCRIPTUM_PDF_LINK_TAG_QA_OUTPUT"] {
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }
    let pdf = try #require(PDFDocument(data: data))
    #expect(pdf.page(at: 0)?.annotations.count == 1)
    #expect(pdf.page(at: 0)?.annotations.first?.url?.absoluteString == "https://example.com")
    #expect(pdf.string?.contains("Read source") == true)
    let provider = try #require(CGDataProvider(data: data as CFData))
    let core = try #require(CGPDFDocument(provider))
    var root: CGPDFDictionaryRef?
    #expect(CGPDFDictionaryGetDictionary(try #require(core.catalog), "StructTreeRoot", &root))
    var document: CGPDFDictionaryRef?, paragraph: CGPDFDictionaryRef?
    #expect(CGPDFDictionaryGetDictionary(try #require(root), "K", &document))
    #expect(CGPDFDictionaryGetDictionary(try #require(document), "K", &paragraph))
    var items: CGPDFArrayRef?
    #expect(CGPDFDictionaryGetArray(try #require(paragraph), "K", &items))
    let array = try #require(items)
    var link: CGPDFDictionaryRef?
    #expect(CGPDFArrayGetDictionary(array, CGPDFArrayGetCount(array) - 1, &link))
    var reference: CGPDFDictionaryRef?
    #expect(CGPDFDictionaryGetDictionary(try #require(link), "K", &reference))
    var type: UnsafePointer<CChar>?
    #expect(CGPDFDictionaryGetName(try #require(reference), "Type", &type))
    #expect(String(cString: try #require(type)) == "OBJR")
    var annotation: CGPDFDictionaryRef?
    #expect(CGPDFDictionaryGetDictionary(try #require(reference), "Obj", &annotation))
}

@Test func taggedFigureAndTableCellLinksRetainExactlyOneAnnotationEach() throws {
    guard #available(macOS 27.0, *) else { return }
    let adapter = try PDFInlineAdapter(theme: .standard, footnoteIDs: [])
    guard case .text(let linked)? = try adapter.fragments([.link("https://example.com/cell", [.text("Cell source")])]).first else {
        Issue.record("Missing text"); return
    }
    let writer = try PDFDocumentWriter(theme: .standard, title: "Mixed links", taggedStructure: true)
    try writer.image(PDFImageRaster(asset: orientedPhoto(6), path: "photo.jpg"),
                     linkTarget: "https://example.com/image", alternativeText: "Linked photograph")
    try writer.table(header: [NSAttributedString(string: "Header")], rows: [[linked]], alignments: [])
    let data = try writer.finish()
    if let path = ProcessInfo.processInfo.environment["SCRIPTUM_PDF_MIXED_LINK_QA_OUTPUT"] {
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }
    let pdf = try #require(PDFDocument(data: data))
    let annotations = (0..<pdf.pageCount).flatMap { pdf.page(at: $0)?.annotations ?? [] }
    #expect(annotations.count == 2)
    #expect(Set(annotations.compactMap { $0.url?.absoluteString }) == ["https://example.com/image", "https://example.com/cell"])
    #expect(pdf.string?.contains("Cell source") == true)
}

@Test func wrappedLinkKeepsOneLogicalIdentityAndHumanReadableLabel() throws {
    guard #available(macOS 27.0, *) else { return }
    let label = (0..<100).map { "Source \($0) 🦊\n" }.joined()
    let adapter = try PDFInlineAdapter(theme: .standard, footnoteIDs: [])
    guard case .text(let text)? = try adapter.fragments([
        .link("https://example.com", [.strong([.text(label)])]),
        .text("Separator\n"), .link("https://example.com", [.text("Another source")])
    ]).first else { Issue.record("Missing text"); return }
    let writer = try PDFDocumentWriter(theme: .standard, title: "Wrapped link", taggedStructure: true)
    try writer.paragraph(text)
    let data = try writer.finish()
    if let path = ProcessInfo.processInfo.environment["SCRIPTUM_PDF_WRAPPED_LINK_QA_OUTPUT"] {
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }
    let pdf = try #require(PDFDocument(data: data))
    #expect(pdf.pageCount > 1)
    #expect(pdf.string?.filter { $0 == "🦊" }.count == 100)
    let provider = try #require(CGDataProvider(data: data as CFData))
    let core = try #require(CGPDFDocument(provider))
    var root: CGPDFDictionaryRef?, doc: CGPDFDictionaryRef?, paragraph: CGPDFDictionaryRef?
    #expect(CGPDFDictionaryGetDictionary(try #require(core.catalog), "StructTreeRoot", &root))
    #expect(CGPDFDictionaryGetDictionary(try #require(root), "K", &doc))
    #expect(CGPDFDictionaryGetDictionary(try #require(doc), "K", &paragraph))
    var children: CGPDFArrayRef?
    #expect(CGPDFDictionaryGetArray(try #require(paragraph), "K", &children))
    let array = try #require(children)
    var labels: [String] = []
    for index in 0..<CGPDFArrayGetCount(array) {
        var item: CGPDFDictionaryRef?
        guard CGPDFArrayGetDictionary(array, index, &item), let item else { continue }
        var role: UnsafePointer<CChar>?
        guard CGPDFDictionaryGetName(item, "S", &role), let role, String(cString: role) == "Link" else { continue }
        var alt: CGPDFStringRef?
        #expect(CGPDFDictionaryGetString(item, "Alt", &alt))
        let alternative = try #require(alt)
        labels.append(try #require(CGPDFStringCopyTextString(alternative) as String?))
    }
    #expect(labels == [label, "Another source"])
}

@Test func semanticListLabelsRemainSeparateFromHangingBodyAcrossPages() throws {
    guard #available(macOS 27.0, *) else { return }
    var parser = SemanticParser(input: ExportInput(title: "Lists", markdown:
        "3. " + String(repeating: "Wrapped 🦊 body text. ", count: 200) + "\n4. Second item.\n"))
    let document = try parser.parse()
    let data = try PDFSemanticRenderer.render(document, theme: .standard, taggedStructure: true)
    if let path = ProcessInfo.processInfo.environment["SCRIPTUM_PDF_LIST_QA_OUTPUT"] {
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }
    let pdf = try #require(PDFDocument(data: data))
    #expect(pdf.pageCount > 1)
    #expect(pdf.string?.filter { $0 == "🦊" }.count == 200)
    let provider = try #require(CGDataProvider(data: data as CFData))
    let core = try #require(CGPDFDocument(provider))
    var root: CGPDFDictionaryRef?, doc: CGPDFDictionaryRef?, list: CGPDFDictionaryRef?
    #expect(CGPDFDictionaryGetDictionary(try #require(core.catalog), "StructTreeRoot", &root))
    #expect(CGPDFDictionaryGetDictionary(try #require(root), "K", &doc))
    #expect(CGPDFDictionaryGetDictionary(try #require(doc), "K", &list))
    var items: CGPDFArrayRef?
    #expect(CGPDFDictionaryGetArray(try #require(list), "K", &items))
    let array = try #require(items)
    #expect(CGPDFArrayGetCount(array) == 2)
    for index in 0..<2 {
        var item: CGPDFDictionaryRef?, children: CGPDFArrayRef?
        #expect(CGPDFArrayGetDictionary(array, index, &item))
        #expect(CGPDFDictionaryGetArray(try #require(item), "K", &children))
        let pair = try #require(children)
        #expect(CGPDFArrayGetCount(pair) == 2)
        for (childIndex, expected) in ["Lbl", "LBody"].enumerated() {
            var child: CGPDFDictionaryRef?, role: UnsafePointer<CChar>?
            #expect(CGPDFArrayGetDictionary(pair, childIndex, &child))
            #expect(CGPDFDictionaryGetName(try #require(child), "S", &role))
            #expect(String(cString: try #require(role)) == expected)
        }
    }
}

@Test func imageListMarkerPromotesTogetherWithLinkedImage() throws {
    guard #available(macOS 27.0, *) else { return }
    let adapter = try PDFInlineAdapter(theme: .standard, footnoteIDs: [])
    func text(_ value: String) throws -> NSAttributedString {
        guard case .text(let result)? = try adapter.fragments([.text(value)]).first else { throw PDFTextTypesetter.LayoutError.invalidBreak }
        return result
    }
    let geometry = try PDFPageCursor(theme: .standard)
    let fillerLine = try PDFParagraphLayout(text: text("Filler\n"), width: geometry.content.width, lineHeight: 1.65).lineHeights[0]
    let count = Int((geometry.content.height - 20) / fillerLine)
    let writer = try PDFDocumentWriter(theme: .standard, title: "Image list", taggedStructure: true)
    try writer.paragraph(text(String(repeating: "Filler\n", count: count)))
    try writer.beginStructureGroup(.list); try writer.beginStructureGroup(.listItem)
    let original = try orientedPhoto(6)
    _ = try writer.listImage(label: text("9."), raster: PDFImageRaster(asset: original, path: "photo.jpg"),
        indent: 18, linkTarget: "https://example.com/image", alternativeText: "Portrait")
    try writer.endStructureGroup(); try writer.endStructureGroup()
    let data = try writer.finish()
    if let path = ProcessInfo.processInfo.environment["SCRIPTUM_PDF_IMAGE_LIST_QA_OUTPUT"] {
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }
    let pdf = try #require(PDFDocument(data: data))
    #expect(pdf.pageCount == 2)
    #expect(pdf.page(at: 0)?.string?.contains("9.") == false)
    #expect(pdf.page(at: 1)?.string?.contains("9.") == true)
    #expect(pdf.page(at: 0)?.annotations.isEmpty == true)
    let link = try #require(pdf.page(at: 1)?.annotations.first)
    #expect(link.url?.absoluteString == "https://example.com/image")
    #expect(abs(link.bounds.minX - geometry.content.minX - 42) < 0.01)
}

@Test func parsedImageFirstListKeepsCaptionInSameLogicalBody() throws {
    guard #available(macOS 27.0, *) else { return }
    var parser = SemanticParser(input: ExportInput(title: "Parsed image list", markdown:
        "9. [![Portrait](photo.jpg)](https://example.com/image)\n\n    Caption 🦊\n",
        assets: ["photo.jpg": try orientedPhoto(6)]))
    let document = try parser.parse()
    let data = try PDFSemanticRenderer.render(document, theme: .standard, taggedStructure: true)
    let pdf = try #require(PDFDocument(data: data))
    #expect(pdf.string?.contains("Caption 🦊") == true)
    #expect(pdf.page(at: 0)?.annotations.first?.url?.absoluteString == "https://example.com/image")
    let provider = try #require(CGDataProvider(data: data as CFData))
    let core = try #require(CGPDFDocument(provider))
    var root: CGPDFDictionaryRef?, doc: CGPDFDictionaryRef?, list: CGPDFDictionaryRef?, item: CGPDFDictionaryRef?
    #expect(CGPDFDictionaryGetDictionary(try #require(core.catalog), "StructTreeRoot", &root))
    #expect(CGPDFDictionaryGetDictionary(try #require(root), "K", &doc))
    #expect(CGPDFDictionaryGetDictionary(try #require(doc), "K", &list))
    #expect(CGPDFDictionaryGetDictionary(try #require(list), "K", &item))
    var children: CGPDFArrayRef?
    #expect(CGPDFDictionaryGetArray(try #require(item), "K", &children))
    let pair = try #require(children)
    #expect(CGPDFArrayGetCount(pair) == 2)
    var body: CGPDFDictionaryRef?, content: CGPDFArrayRef?
    #expect(CGPDFArrayGetDictionary(pair, 1, &body))
    #expect(CGPDFDictionaryGetArray(try #require(body), "K", &content))
    #expect(CGPDFArrayGetCount(try #require(content)) == 2) // Figure and caption paragraph
}
