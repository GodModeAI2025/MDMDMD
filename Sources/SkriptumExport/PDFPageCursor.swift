import Foundation
import CoreGraphics

/// Geometry/admission for the semantic PDF backend. Paragraph keep/widow rules
/// reserve groups before placing lines; this cursor does not replace those rules.
struct PDFPageCursor {
    enum PageError: Error, Equatable {
        case invalidGeometry, itemExceedsPage, pageLimitExceeded
    }
    struct Placement {
        let pageIndex: Int
        let baseline: CGPoint
    }
    let paper: CGRect
    let content: CGRect
    private let maximumPages: Int
    private(set) var pageIndex = 0
    private(set) var top: CGFloat

    init(theme: ExportTheme, maximumPages: Int = 3000) throws {
        try Task.checkCancellation()
        try theme.validate()
        guard maximumPages > 0 else { throw PageError.invalidGeometry }
        let factor: CGFloat = 72 / 25.4
        paper = CGRect(x: 0, y: 0, width: CGFloat(theme.paperSize.widthMM) * factor,
                       height: CGFloat(theme.paperSize.heightMM) * factor)
        content = paper.insetBy(dx: CGFloat(theme.marginsMM) * factor,
                               dy: CGFloat(theme.marginsMM) * factor)
        guard content.width > 0, content.height > 0 else { throw PageError.invalidGeometry }
        self.maximumPages = maximumPages; top = content.maxY
    }

    var remainingHeight: CGFloat { max(0, top - content.minY) }
    var isAtPageStart: Bool { top == content.maxY }

    /// Moves to a new page only when needed. An impossible reservation or page
    /// budget failure leaves the cursor unchanged, so retry cannot skip pages.
    mutating func reserve(height: CGFloat) throws {
        try Task.checkCancellation()
        guard height.isFinite, height >= 0 else { throw PageError.invalidGeometry }
        guard height <= content.height else { throw PageError.itemExceedsPage }
        if height > remainingHeight { try nextPage() }
    }

    mutating func place(_ line: PDFTextTypesetter.Line, indent: CGFloat = 0) throws -> Placement {
        try Task.checkCancellation()
        guard indent.isFinite, indent >= 0, indent < content.width,
              line.ascent.isFinite, line.descent.isFinite, line.advance.isFinite,
              line.ascent >= 0, line.descent >= 0, line.advance > 0 else { throw PageError.invalidGeometry }
        // Over-wide composed clusters must be handled by the block layout before
        // drawing; shrinking or clipping text silently would violate fidelity.
        guard line.width <= content.width - indent + 0.01 else { throw PageError.itemExceedsPage }
        let required = max(line.advance, line.ascent + line.descent)
        try reserve(height: required)
        let placement = Placement(pageIndex: pageIndex,
                                  baseline: CGPoint(x: content.minX + indent, y: top - line.ascent))
        top -= required
        return placement
    }

    /// Paragraph spacing is consumed only on the current page and never creates
    /// a blank trailing page. The next actual element decides whether to advance.
    mutating func space(after height: CGFloat) throws {
        try Task.checkCancellation()
        guard height.isFinite, height >= 0 else { throw PageError.invalidGeometry }
        top = max(content.minY, top - height)
    }

    private mutating func nextPage() throws {
        guard pageIndex + 1 < maximumPages else { throw PageError.pageLimitExceeded }
        pageIndex += 1; top = content.maxY
    }
}
