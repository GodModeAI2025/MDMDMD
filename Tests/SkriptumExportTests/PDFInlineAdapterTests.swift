import Foundation
import CoreText
import Testing
@testable import SkriptumExport

private func adapterText(_ fragments: [PDFInlineFragment]) throws -> NSAttributedString {
    let value = NSMutableAttributedString(string: "")
    for fragment in fragments {
        guard case .text(let text) = fragment else { throw ExportError.unsupportedMarkdown("unexpected image") }
        value.append(text)
    }
    return value
}
private func adapterFont(_ text: NSAttributedString, at index: Int) throws -> CTFont {
    let value = try #require(text.attribute(NSAttributedString.Key(kCTFontAttributeName as String), at: index, effectiveRange: nil))
    #expect(CFGetTypeID(value as CFTypeRef) == CTFontGetTypeID())
    return value as! CTFont
}

@Test func pdfInlineAdapterPreservesNestedTypographyAndDestinations() throws {
    let adapter = try PDFInlineAdapter(theme: .standard, footnoteIDs: ["n"])
    let text = try adapterText(adapter.fragments([
        .text("A"), .strong([.emphasis([.text("🦊")])]),
        .link("https://example.com/path", [.code("x")]), .strike([.text("s")]),
        .softBreak, .text("e\u{301}"), .lineBreak, .footnote("n")
    ]))
    #expect(Array(text.string.utf8) == Array("A🦊xs e\u{301}\n1".utf8))
    let font = try adapterFont(text, at: 1)
    #expect(CTFontGetSymbolicTraits(font).contains([.traitBold, .traitItalic]))
    let codeFont = try adapterFont(text, at: 3)
    #expect(CTFontGetSymbolicTraits(codeFont).contains(.traitMonoSpace))
    #expect(text.attribute(PDFInlineAdapter.linkTarget, at: 3, effectiveRange: nil) as? String == "https://example.com/path")
    #expect(text.attribute(PDFInlineAdapter.strike, at: 4, effectiveRange: nil) as? Bool == true)
    #expect(text.attribute(PDFInlineAdapter.linkTarget, at: text.length - 1, effectiveRange: nil) as? String == "#note-1")
    #expect(text.attribute(PDFInlineAdapter.noteID, at: text.length - 1, effectiveRange: nil) as? String == "n")
    #expect(CTFontGetSize(try adapterFont(text, at: text.length - 1)) == 9)
}

@Test func pdfInlineAdapterKeepsLinkedImagesSeparateAndInOrder() throws {
    let adapter = try PDFInlineAdapter(theme: .standard, footnoteIDs: [])
    let fragments = try adapter.fragments([.text("Before"), .link("#heading-1", [.image("images/original.png", "Bild 🦊")]), .text("After")])
    #expect(fragments.count == 3)
    guard case .text(let before) = fragments[0], case .image(let path, let alt, let target) = fragments[1], case .text(let after) = fragments[2] else {
        Issue.record("Image was flattened or order changed"); return
    }
    #expect(before.string == "Before" && after.string == "After")
    #expect(path == "images/original.png" && alt == "Bild 🦊" && target == "#heading-1")
}

@Test func pdfInlineAdapterRejectsMissingNotesAndRetainsDeepInlineContent() throws {
    let adapter = try PDFInlineAdapter(theme: .standard, footnoteIDs: [])
    #expect(throws: ExportError.missingFootnote("missing")) { try adapter.fragments([.footnote("missing")]) }
    var item = Inline.text("Deep 🦊")
    for _ in 0..<2048 { item = .emphasis([item]) }
    // The indirect semantic enum has recursive ARC teardown. Release this
    // artificial deep fixture iteratively, independently of adapter traversal.
    defer { while case .emphasis(let children) = item { item = children[0] } }
    let text = try adapterText(adapter.fragments([item]))
    #expect(text.string == "Deep 🦊")
    #expect(CTFontGetSymbolicTraits(try adapterFont(text, at: 0)).contains(.traitItalic))
}
