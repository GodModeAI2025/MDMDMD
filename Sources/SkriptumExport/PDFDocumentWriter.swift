import Foundation
import CoreGraphics

/// Worker-local semantic PDF document lifecycle. Failed writes never return a
/// partially drawn document. This writer is not yet the app's export backend.
final class PDFDocumentWriter {
    enum WriterError: Error, Equatable { case closed, contextCreationFailed }
    private let bytes = NSMutableData()
    private let context: CGContext
    private var cursor: PDFPageCursor
    private let theme: ExportTheme
    private var pageOpen = false
    private var closed = false
    private var keepNextParagraph = false

    init(theme: ExportTheme, title: String, author: String = "", maximumPages: Int = 3000) throws {
        cursor = try PDFPageCursor(theme: theme, maximumPages: maximumPages)
        self.theme = theme
        guard let consumer = CGDataConsumer(data: bytes) else { throw WriterError.contextCreationFailed }
        var paper = cursor.paper
        let metadata: [CFString: Any] = [kCGPDFContextTitle: title, kCGPDFContextAuthor: author,
                                        kCGPDFContextCreator: "Scriptum"]
        guard let context = CGContext(consumer: consumer, mediaBox: &paper, metadata as CFDictionary) else {
            throw WriterError.contextCreationFailed
        }
        self.context = context
    }

    deinit { close() }

    func paragraph(_ text: NSAttributedString, indent: CGFloat = 0, destination: String? = nil, keepWithFollowing: NSAttributedString? = nil) throws {
        try perform {
            guard text.length > 0 else { return }
            if let following = keepWithFollowing, following.length > 0 {
                let heading = try PDFParagraphLayout(text: text, width: cursor.content.width - indent,
                                                      lineHeight: CGFloat(theme.lineHeight))
                let next = try PDFParagraphLayout(text: following, width: cursor.content.width - indent,
                                                   lineHeight: CGFloat(theme.lineHeight))
                let required = heading.lineHeights.reduce(0, +) + CGFloat(theme.paragraphSpacingPoints)
                    + next.lineHeights.prefix(3).reduce(0, +)
                let previousPage = cursor.pageIndex
                try cursor.reserve(height: required)
                if pageOpen && previousPage != cursor.pageIndex {
                    context.endPDFPage(); context.beginPDFPage(nil)
                }
            }
            openPage()
            let context = self.context
            let mustStart = keepNextParagraph
            keepNextParagraph = keepWithFollowing != nil
            try PDFParagraphRenderer.draw(text: text, cursor: &cursor, context: context,
                lineHeight: CGFloat(theme.lineHeight), indent: indent,
                paragraphSpacing: CGFloat(theme.paragraphSpacingPoints), mustStartOnCurrentPage: mustStart, firstLine: { placement in
                    if let destination { context.addDestination(destination as CFString, at: placement.baseline) }
                }) { _ in
                    context.endPDFPage(); context.beginPDFPage(nil)
                }
        }
    }

    func image(_ raster: PDFImageRaster, indent: CGFloat = 0, linkTarget: String? = nil) throws {
        try perform {
            guard indent.isFinite, indent >= 0, indent < cursor.content.width else {
                throw PDFPageCursor.PageError.invalidGeometry
            }
            if let linkTarget, !safeLink(linkTarget) { throw ExportError.unsafeURL(linkTarget) }
            let size = try raster.fittedSize(availableWidth: cursor.content.width - indent,
                                             availableHeight: cursor.content.height)
            let previousPage = cursor.pageIndex
            let placement = try cursor.placeRectangle(size: size, indent: indent)
            openPage()
            if previousPage != placement.pageIndex {
                context.endPDFPage(); context.beginPDFPage(nil)
            }
            try raster.draw(in: context, frame: placement.frame)
            if let linkTarget {
                try PDFLineDecorations.annotate([PDFLinkRegion(target: linkTarget,
                    sourceRange: NSRange(location: 0, length: 0), bounds: placement.frame)], context: context)
            }
            try cursor.space(after: CGFloat(theme.paragraphSpacingPoints))
        }
    }

    func table(header: [NSAttributedString], rows: [[NSAttributedString]],
               alignments: [String?], indent: CGFloat = 0) throws {
        try perform {
            guard !header.isEmpty, indent.isFinite, indent >= 0, indent < cursor.content.width,
                  rows.allSatisfy({ $0.count == header.count }) else {
                throw PDFPageCursor.PageError.invalidGeometry
            }
            let padding: CGFloat = 6
            let width = (cursor.content.width - indent) / CGFloat(header.count)
            guard width > padding * 2 else { throw PDFPageCursor.PageError.itemExceedsPage }
            func measure(_ cells: [NSAttributedString]) throws -> ([PDFParagraphLayout], CGFloat) {
                let layouts = try cells.map { try PDFParagraphLayout(text: $0, width: width - padding * 2,
                    lineHeight: CGFloat(theme.lineHeight)) }
                let height = max(CGFloat(theme.bodySizePoints), layouts.map { $0.lineHeights.reduce(0, +) }.max() ?? 0) + padding * 2
                return (layouts, height)
            }
            func draw(_ measured: ([PDFParagraphLayout], CGFloat)) throws {
                let oldPage = cursor.pageIndex
                let placement = try cursor.placeRectangle(size: CGSize(width: cursor.content.width - indent,
                    height: measured.1), indent: indent)
                openPage()
                if oldPage != placement.pageIndex { context.endPDFPage(); context.beginPDFPage(nil) }
                context.saveGState()
                defer { context.restoreGState() }
                context.setStrokeColor(CGColor(gray: 0.65, alpha: 1)); context.setLineWidth(0.5)
                for (column, layout) in measured.0.enumerated() {
                    try Task.checkCancellation()
                    let cell = CGRect(x: placement.frame.minX + CGFloat(column) * width,
                        y: placement.frame.minY, width: width, height: measured.1)
                    context.stroke(cell)
                    var top = cell.maxY - padding
                    let fragments: [PDFParagraphBreakPlanner.Fragment] = layout.lineHeights.isEmpty ? [] : [
                        .init(pageOffset: 0, lineRange: layout.lineHeights.indices,
                              height: layout.lineHeights.reduce(0, +))]
                    try layout.forEachLine(in: fragments) { _, index, line in
                        let free = max(0, width - padding * 2 - line.width)
                        let alignment = column < alignments.count ? alignments[column] : nil
                        let offset: CGFloat = alignment == "right" ? free : alignment == "center" ? free / 2 : 0
                        let baseline = CGPoint(x: cell.minX + padding + offset, y: top - line.ascent)
                        try line.draw(in: context, baseline: baseline)
                        try line.addLinkAnnotations(in: context, baseline: baseline)
                        top -= layout.lineHeights[index]
                    }
                }
            }
            let head = try measure(header)
            guard head.1 <= cursor.content.height else { throw PDFPageCursor.PageError.itemExceedsPage }
            if let first = rows.first {
                let firstHeight = try measure(first).1
                let previous = cursor.pageIndex
                try cursor.reserve(height: head.1 + firstHeight)
                if pageOpen && previous != cursor.pageIndex { context.endPDFPage(); context.beginPDFPage(nil) }
            }
            try draw(head)
            for row in rows {
                try Task.checkCancellation()
                let measured = try measure(row)
                guard head.1 + measured.1 <= cursor.content.height else { throw PDFPageCursor.PageError.itemExceedsPage }
                if measured.1 > cursor.remainingHeight {
                    try cursor.advancePage()
                    context.endPDFPage(); context.beginPDFPage(nil)
                    try draw(head)
                }
                try draw(measured)
            }
            keepNextParagraph = false
            try cursor.space(after: CGFloat(theme.paragraphSpacingPoints))
        }
    }

    func rule(indent: CGFloat = 0) throws {
        try perform {
            guard indent.isFinite, indent >= 0, indent < cursor.content.width else {
                throw PDFPageCursor.PageError.invalidGeometry
            }
            let previousPage = cursor.pageIndex
            let placement = try cursor.placeRectangle(size: CGSize(width: cursor.content.width - indent, height: 24), indent: indent)
            openPage()
            if previousPage != placement.pageIndex { context.endPDFPage(); context.beginPDFPage(nil) }
            context.saveGState()
            context.setStrokeColor(CGColor(gray: 0.5, alpha: 1))
            context.setLineWidth(0.75)
            context.move(to: CGPoint(x: placement.frame.minX, y: placement.frame.midY))
            context.addLine(to: CGPoint(x: placement.frame.maxX, y: placement.frame.midY))
            context.strokePath()
            context.restoreGState()
        }
    }

    func finish() throws -> Data {
        guard !closed else { throw WriterError.closed }
        do {
            try Task.checkCancellation()
            openPage() // A valid empty document has one page.
            close()
            return bytes as Data
        } catch { close(); throw error }
    }

    private func perform(_ operation: () throws -> Void) throws {
        guard !closed else { throw WriterError.closed }
        do { try Task.checkCancellation(); try operation() }
        catch { close(); throw error }
    }
    private func openPage() {
        if !pageOpen { context.beginPDFPage(nil); pageOpen = true }
    }
    private func close() {
        guard !closed else { return }
        if pageOpen { context.endPDFPage(); pageOpen = false }
        context.closePDF(); closed = true
    }
}
