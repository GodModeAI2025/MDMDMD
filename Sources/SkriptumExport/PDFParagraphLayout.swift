import Foundation
import CoreGraphics

/// Two-pass paragraph layout: retain metrics, not every shaped CoreText line.
/// Both passes use the same immutable text snapshot and geometry.
struct PDFParagraphLayout {
    private let text: NSAttributedString
    private let width: CGFloat
    private let lineHeight: CGFloat
    private let minimumFirstAscent: CGFloat
    private let minimumFirstDescent: CGFloat
    let lineHeights: [CGFloat]
    let lineAscents: [CGFloat]

    init(text: NSAttributedString, width: CGFloat, lineHeight: CGFloat, minimumFirstAscent: CGFloat = 0, minimumFirstDescent: CGFloat = 0) throws {
        guard minimumFirstAscent.isFinite, minimumFirstAscent >= 0, minimumFirstDescent.isFinite, minimumFirstDescent >= 0 else { throw PDFPageCursor.PageError.invalidGeometry }
        let snapshot = NSAttributedString(attributedString: text)
        var typesetter = try PDFTextTypesetter(text: snapshot, availableWidth: width,
                                              lineHeightMultiple: lineHeight)
        var heights: [CGFloat] = [], ascents: [CGFloat] = []
        while let line = try typesetter.nextLine() {
            guard !line.exceedsAvailableWidth else { throw PDFPageCursor.PageError.itemExceedsPage }
            heights.append(max(line.advance, max(line.ascent, heights.isEmpty ? minimumFirstAscent : 0) + max(line.descent, heights.isEmpty ? minimumFirstDescent : 0)))
            ascents.append(line.ascent)
        }
        self.text = snapshot; self.width = width; self.lineHeight = lineHeight
        self.minimumFirstAscent = minimumFirstAscent; self.minimumFirstDescent = minimumFirstDescent
        lineHeights = heights; lineAscents = ascents
    }

    func streamingTypesetter() throws -> PDFTextTypesetter {
        try PDFTextTypesetter(text: text, availableWidth: width, lineHeightMultiple: lineHeight)
    }

    func fragments(firstPageHeight: CGFloat, pageHeight: CGFloat,
                   maximumPages: Int = 3000, mustStartOnCurrentPage: Bool = false) throws -> [PDFParagraphBreakPlanner.Fragment] {
        try PDFParagraphBreakPlanner().fragments(lineHeights: lineHeights,
            firstPageHeight: firstPageHeight, pageHeight: pageHeight, maximumPages: maximumPages, mustStartOnCurrentPage: mustStartOnCurrentPage)
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
                      max(line.advance, max(line.ascent, index == 0 ? minimumFirstAscent : 0) + max(line.descent, index == 0 ? minimumFirstDescent : 0)) == lineHeights[index] else {
                    throw PDFTextTypesetter.LayoutError.invalidBreak
                }
                try body(fragment, index, line)
            }
        }
        guard try typesetter.nextLine() == nil else { throw PDFTextTypesetter.LayoutError.invalidBreak }
    }
}
