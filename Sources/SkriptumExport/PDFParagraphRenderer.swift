import Foundation
import CoreGraphics

/// Draws a complete measured paragraph into the caller-owned PDF context.
/// Page lifecycle remains with the document writer, so other block types share
/// the same cursor and page headers, destinations and metadata.
struct PDFParagraphRenderer {
    static func draw(text: NSAttributedString, cursor: inout PDFPageCursor,
                     context: CGContext, lineHeight: CGFloat, indent: CGFloat = 0,
                     paragraphSpacing: CGFloat = 0,
                     beginPage: (Int) throws -> Void) throws {
        try Task.checkCancellation()
        guard indent.isFinite, indent >= 0, indent < cursor.content.width,
              paragraphSpacing.isFinite, paragraphSpacing >= 0 else {
            throw PDFPageCursor.PageError.invalidGeometry
        }
        let layout = try PDFParagraphLayout(text: text, width: cursor.content.width - indent,
                                            lineHeight: lineHeight)
        let fragments = try layout.fragments(firstPageHeight: cursor.remainingHeight,
            pageHeight: cursor.content.height, maximumPages: cursor.remainingPageCount)
        let startPage = cursor.pageIndex
        try layout.forEachLine(in: fragments) { fragment, index, line in
            let targetPage = startPage + fragment.pageOffset
            if index == fragment.lineRange.lowerBound {
                while cursor.pageIndex < targetPage {
                    try cursor.advancePage()
                    try beginPage(cursor.pageIndex)
                }
                guard cursor.pageIndex == targetPage else { throw PDFTextTypesetter.LayoutError.invalidBreak }
                try cursor.reserve(height: fragment.height)
            }
            let placement = try cursor.place(line, indent: indent)
            guard placement.pageIndex == targetPage else { throw PDFTextTypesetter.LayoutError.invalidBreak }
            try line.draw(in: context, baseline: placement.baseline)
            try line.addLinkAnnotations(in: context, baseline: placement.baseline)
        }
        if !layout.lineHeights.isEmpty { try cursor.space(after: paragraphSpacing) }
    }
}
