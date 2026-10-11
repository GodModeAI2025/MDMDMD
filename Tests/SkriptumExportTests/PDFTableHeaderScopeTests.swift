import Foundation
import CoreGraphics
import Testing
@testable import SkriptumExport

@Test(arguments: [false, true]) func semanticTableHeadersDeclareColumnScope(withLanguage: Bool) throws {
    let writer = try PDFDocumentWriter(theme: .standard, title: "Column headers", taggedStructure: true, language: withLanguage ? "de-DE" : nil)
    try writer.table(header: [NSAttributedString(string: "Name"), NSAttributedString(string: "Value")],
        rows: (0..<100).map { [NSAttributedString(string: "Row \($0)"), NSAttributedString(string: "🦊")] }, alignments: [])
    let data = try writer.finish()
    let provider = try #require(CGDataProvider(data: data as CFData)), pdf = try #require(CGPDFDocument(provider))
    var tree: CGPDFDictionaryRef?, document: CGPDFDictionaryRef?, table: CGPDFDictionaryRef?, rows: CGPDFArrayRef?
    #expect(CGPDFDictionaryGetDictionary(try #require(pdf.catalog), "StructTreeRoot", &tree))
    #expect(CGPDFDictionaryGetDictionary(try #require(tree), "K", &document))
    #expect(CGPDFDictionaryGetDictionary(try #require(document), "K", &table))
    #expect(CGPDFDictionaryGetArray(try #require(table), "K", &rows))
    var row: CGPDFDictionaryRef?, cells: CGPDFArrayRef?
    #expect(CGPDFArrayGetDictionary(try #require(rows), 0, &row))
    #expect(CGPDFDictionaryGetArray(try #require(row), "K", &cells))
    #expect(CGPDFArrayGetCount(try #require(rows)) == 101)
    #expect(pdf.numberOfPages > 1)
    for column in 0..<2 {
        var cell: CGPDFDictionaryRef?, attrs: CGPDFDictionaryRef?, owner: UnsafePointer<CChar>?, scope: UnsafePointer<CChar>?
        #expect(CGPDFArrayGetDictionary(try #require(cells), column, &cell))
        #expect(CGPDFDictionaryGetDictionary(try #require(cell), "A", &attrs))
        #expect(CGPDFDictionaryGetName(try #require(attrs), "O", &owner))
        #expect(CGPDFDictionaryGetName(try #require(attrs), "Scope", &scope))
        #expect(String(cString: try #require(owner)) == "Table")
        #expect(String(cString: try #require(scope)) == "Column")
    }
    for index in 1..<101 {
        var row: CGPDFDictionaryRef?, cells: CGPDFArrayRef?
        #expect(CGPDFArrayGetDictionary(try #require(rows), index, &row))
        #expect(CGPDFDictionaryGetArray(try #require(row), "K", &cells))
        for column in 0..<2 {
            var cell: CGPDFDictionaryRef?, attrs: CGPDFObjectRef?, role: UnsafePointer<CChar>?
            #expect(CGPDFArrayGetDictionary(try #require(cells), column, &cell))
            #expect(CGPDFDictionaryGetName(try #require(cell), "S", &role))
            #expect(String(cString: try #require(role)) == "TD")
            #expect(!CGPDFDictionaryGetObject(try #require(cell), "A", &attrs))
        }
    }
    if let path = ProcessInfo.processInfo.environment["SCRIPTUM_PDF_SCOPE_QA_OUTPUT"] {
        let name = withLanguage ? "table-de-DE" : "table-no-language"
        let firstEOF = try #require(data.range(of: Data("%%EOF\n".utf8)))
        try data.prefix(firstEOF.upperBound).write(to: URL(fileURLWithPath: path).appending(path: name + "-before.pdf"), options: .atomic)
        try data.write(to: URL(fileURLWithPath: path).appending(path: withLanguage ? "table-de-DE.pdf" : "table-no-language.pdf"), options: .atomic)
    }
}

@Test func tableRoleScannerIgnoresArrayNamesStringsCommentsNestedDictionariesAndStreams() throws {
    let source = "1 0 obj\n<< /K [/S /TH] /Title (/S /TH) % /S /TH\n/Nested << /S /TH >> /S /TD >>\nendobj\n"
    let bytes = Array(source.utf8)
    #expect(try PDFStructureAttributeNormalizer.topLevelNames(bytes, range: 0..<bytes.count).map(\.name) == ["K", "Title", "Nested", "S", "TD"])
    let stream = Array((source + "stream\n/S /TH\nendstream\n").utf8)
    #expect(try PDFStructureAttributeNormalizer.topLevelNames(stream, range: 0..<stream.count).isEmpty)
}
