import Foundation
import CoreGraphics

/// Two-pass paragraph layout: retain metrics, not every shaped CoreText line.
/// Both passes use the same immutable text snapshot and geometry.
struct PDFParagraphLayout {
    private let text: NSAttributedString
    private let width: CGFloat
    private let lineHeight: CGFloat
    let lineHeights: [CGFloat]

    init(text: NSAttributedString, width: CGFloat, lineHeight: CGFloat) throws {
        let snapshot = NSAttributedString(attributedString: text)
        var typesetter = try PDFTextTypesetter(text: snapshot, availableWidth: width,
                                              lineHeightMultiple: lineHeight)
        var heights: [CGFloat] = []
        while let line = try typesetter.nextLine() {
            guard !line.exceedsAvailableWidth else { throw PDFPageCursor.PageError.itemExceedsPage }
            heights.append(max(line.advance, line.ascent + line.descent))
        }
        self.text = snapshot; self.width = width; self.lineHeight = lineHeight
        lineHeights = heights
    }

    func fragments(firstPageHeight: CGFloat, pageHeight: CGFloat,
                   maximumPages: Int = 3000) throws -> [PDFParagraphBreakPlanner.Fragment] {
        try PDFParagraphBreakPlanner().fragments(lineHeights: lineHeights,
            firstPageHeight: firstPageHeight, pageHeight: pageHeight, maximumPages: maximumPages)
    }

    /// Streams the second pass to the page writer. The callback receives the
    /// planned fragment and one line at a time, including its global line index.
    func forEachLine(in fragments: [PDFParagraphBreakPlanner.Fragment],
                     body: (PDFParagraphBreakPlanner.Fragment, Int, PDFTextTypesetter.Line) throws -> Void) throws {
        var expected = 0
        for fragment in fragments {
            guard fragment.lineRange.lowerBound == expected,
                  fragment.lineRange.upperBound <= lineHeights.count,
                  !fragment.lineRange.isEmpty else { throw PDFTextTypesetter.LayoutError.invalidBreak }
            expected = fragment.lineRange.upperBound
        }
        guard expected == lineHeights.count else { throw PDFTextTypesetter.LayoutError.invalidBreak }
        var typesetter = try PDFTextTypesetter(text: text, availableWidth: width,
                                              lineHeightMultiple: lineHeight)
        for fragment in fragments {
            for index in fragment.lineRange {
                try Task.checkCancellation()
                guard let line = try typesetter.nextLine(),
                      max(line.advance, line.ascent + line.descent) == lineHeights[index] else {
                    throw PDFTextTypesetter.LayoutError.invalidBreak
                }
                try body(fragment, index, line)
            }
        }
        guard try typesetter.nextLine() == nil else { throw PDFTextTypesetter.LayoutError.invalidBreak }
    }
}
