import CoreGraphics
import Foundation
import PDFKit
import Testing
import SkriptumExport

private struct HeadingStructureNode {
    let role: String
    let language: String?
    let alternative: String?
    let actualText: String?
    let children: [HeadingStructureNode]
    var descendants: [HeadingStructureNode] { children.flatMap { [$0] + $0.descendants } }
}

private func headingStructure(_ data: Data) throws -> HeadingStructureNode {
    let provider = try #require(CGDataProvider(data: data as CFData))
    let pdf = try #require(CGPDFDocument(provider))
    var root: CGPDFDictionaryRef?
    #expect(CGPDFDictionaryGetDictionary(try #require(pdf.catalog), "StructTreeRoot", &root))
    var document: CGPDFDictionaryRef?
    #expect(CGPDFDictionaryGetDictionary(try #require(root), "K", &document))
    func read(_ dictionary: CGPDFDictionaryRef) throws -> HeadingStructureNode? {
        var name: UnsafePointer<CChar>?
        guard CGPDFDictionaryGetName(dictionary, "S", &name), let name else { return nil }
        func string(_ key: String) -> String? {
            var value: CGPDFStringRef?
            guard CGPDFDictionaryGetString(dictionary, key, &value), let value else { return nil }
            return CGPDFStringCopyTextString(value) as String?
        }
        var children: [HeadingStructureNode] = []
        var array: CGPDFArrayRef?
        var child: CGPDFDictionaryRef?
        if CGPDFDictionaryGetArray(dictionary, "K", &array), let array {
            for index in 0..<CGPDFArrayGetCount(array) {
                if CGPDFArrayGetDictionary(array, index, &child), let child, let item = try read(child) {
                    children.append(item)
                }
            }
        } else if CGPDFDictionaryGetDictionary(dictionary, "K", &child), let child, let item = try read(child) {
            children.append(item)
        }
        return HeadingStructureNode(role: String(cString: name), language: string("Lang"),
            alternative: string("Alt"), actualText: string("ActualText"), children: children)
    }
    let documentDictionary = try #require(document)
    let result = try read(documentDictionary)
    return try #require(result)
}

@Test(arguments: 1...6)
func imageOnlyHeadingHasItsOwnHeadingRole(level: Int) async throws {
    var theme = ExportTheme.standard
    theme.includeTitle = false
    let source = String(repeating: "#", count: level)
        + " [![Bildbeschreibung 🦊](photo.jpg)](https://example.com/image)\n\nBodyOutsideHeading.\n"
    let input = ExportInput(title: "Image heading", markdown: source, language: "de-DE",
        assets: ["photo.jpg": try orientedPhoto(1)], theme: theme)
    let artifact = try await ExportEngine.renderSemanticPDF(input, taggedStructure: true)
    let tree = try headingStructure(artifact.data)
    #expect(tree.children.map(\.role) == ["H\(level)", "P"])
    let heading = try #require(tree.children.first)
    #expect(heading.language == "de-DE")
    #expect(heading.descendants.filter { $0.role == "Figure" }.map(\.alternative) == ["Bildbeschreibung 🦊"])
    #expect(heading.descendants.filter { $0.role == "Link" }.count == 1)
    #expect(!heading.descendants.compactMap(\.actualText).joined().contains("BodyOutsideHeading"))
    let pdf = try #require(PDFDocument(data: artifact.data))
    #expect(pdf.page(at: 0)?.annotations.filter { $0.url?.absoluteString == "https://example.com/image" }.count == 1)
    #expect(pdf.string?.contains("BodyOutsideHeading.") == true)
}

@Test(arguments: [
    "Prefix [![First](photo.jpg)](https://example.com/first) Suffix",
    "[![First](photo.jpg)](https://example.com/first) Suffix [![Second](photo.jpg)](https://example.com/second)",
    "Prefix [![First](photo.jpg)](https://example.com/first) Middle [![Second](photo.jpg)](https://example.com/second) Suffix"
])
func mixedHeadingKeepsAllFragmentsUnderOneSemanticHeading(content: String) async throws {
    var theme = ExportTheme.standard
    theme.includeTitle = false
    theme.includeTOC = true
    let source = "[Jump](#heading-1)\n\n### \(content)\n\nBodyOutsideHeading 🦊.\n"
    let input = ExportInput(title: "Mixed heading", markdown: source, language: "de-DE",
        assets: ["photo.jpg": try orientedPhoto(1)], theme: theme)
    let tagged = try await ExportEngine.renderSemanticPDF(input, taggedStructure: true)
    let plain = try await ExportEngine.renderSemanticPDF(input, taggedStructure: false)
    let tree = try headingStructure(tagged.data)
    let headings = tree.children.filter { $0.role == "H3" }
    #expect(headings.count == 1)
    #expect(tree.children.filter { $0.role == "Figure" }.isEmpty)
    let heading = try #require(headings.first)
    #expect(heading.children.allSatisfy { ["Span", "Figure"].contains($0.role) })
    #expect(!heading.descendants.contains { $0.role.hasPrefix("H") })
    let alternatives = heading.descendants.filter { $0.role == "Figure" }.compactMap(\.alternative)
    #expect(alternatives == (content.contains("Second") ? ["First", "Second"] : ["First"]))
    let actualText = heading.descendants.compactMap(\.actualText).joined()
    #expect(actualText.contains("Suffix"))
    #expect(!actualText.contains("BodyOutsideHeading"))
    let pdf = try #require(PDFDocument(data: tagged.data))
    let other = try #require(PDFDocument(data: plain.data))
    #expect(pdf.pageCount == other.pageCount)
    let taggedText = try #require(pdf.string)
    let plainText = try #require(other.string)
    // PDFKit exposes each inline Figure in a heading as one object-replacement
    // character. Account for exactly those objects; all prose tokens must stay.
    #expect(taggedText.filter { $0 == "\u{fffc}" }.count == alternatives.count)
    #expect(!plainText.contains("\u{fffc}"))
    #expect(taggedText.replacingOccurrences(of: "\u{fffc}", with: "").split(whereSeparator: \.isWhitespace)
        == plainText.split(whereSeparator: \.isWhitespace))
    let links = (0..<pdf.pageCount).flatMap { pdf.page(at: $0)?.annotations ?? [] }
    #expect(links.filter { $0.url == nil && $0.destination?.page != nil }.count == 2)
    #expect(links.compactMap(\.url).count == alternatives.count)
    if content.contains("Middle"), let path = ProcessInfo.processInfo.environment["SCRIPTUM_HEADING_STRUCTURE_QA_OUTPUT"] {
        try tagged.data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }
}

@Test func imageHeadingRetainsOneStructureAcrossPageBreaks() async throws {
    var theme = ExportTheme.standard
    theme.includeTitle = false
    let words = (0..<150).map { "HeadingWord\($0)" }.joined(separator: " ")
    let source = "## ![First](photo.jpg) \(words) ![Second](photo.jpg)\n\nBodyOutsideHeading.\n"
    let input = ExportInput(title: "Long image heading", markdown: source, language: "en-GB",
        assets: ["photo.jpg": try orientedPhoto(1)], theme: theme)
    let tagged = try await ExportEngine.renderSemanticPDF(input, taggedStructure: true)
    let tree = try headingStructure(tagged.data)
    #expect(tree.children.map(\.role) == ["H2", "P"])
    let heading = try #require(tree.children.first)
    #expect(heading.language == "en-GB")
    #expect(heading.descendants.filter { $0.role == "Figure" }.map(\.alternative) == ["First", "Second"])
    let text = heading.descendants.compactMap(\.actualText).joined()
    for index in 0..<150 { #expect(text.contains("HeadingWord\(index)")) }
    #expect(!text.contains("BodyOutsideHeading"))
    let pdf = try #require(PDFDocument(data: tagged.data))
    #expect(pdf.pageCount > 1)
    #expect(pdf.string?.contains("BodyOutsideHeading.") == true)
}
