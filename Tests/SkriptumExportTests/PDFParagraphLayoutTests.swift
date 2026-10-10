import Foundation
import CoreText
import Testing
@testable import SkriptumExport

struct PDFParagraphLayoutTests {
    @Test func immutableTwoPassUnicodeAndCompletePlan() throws {
        let source = NSMutableAttributedString(string: String(repeating: "Autor 🦊 العربية é schreibt. ", count: 100),
            attributes: [NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Georgia" as CFString, 12, nil)])
        let original = NSString(string: source.string)
        let layout = try PDFParagraphLayout(text: source, width: 140, lineHeight: 1.5)
        source.mutableString.setString("Changed")
        let plan = try layout.fragments(firstPageHeight: 70, pageHeight: 200)
        var recovered = "", indices: [Int] = []
        try layout.forEachLine(in: plan) { _, index, line in
            indices.append(index)
            recovered += original.substring(with: line.sourceRange)
        }
        #expect(recovered == original as String)
        #expect(indices == Array(layout.lineHeights.indices))
        #expect(plan.count > 1)
        #expect(throws: PDFTextTypesetter.LayoutError.invalidBreak) {
            try layout.forEachLine(in: Array(plan.dropLast())) { _, _, _ in }
        }
    }
}
