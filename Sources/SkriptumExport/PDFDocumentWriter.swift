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

    func paragraph(_ text: NSAttributedString, indent: CGFloat = 0) throws {
        try perform {
            guard text.length > 0 else { return }
            openPage()
            let context = self.context
            try PDFParagraphRenderer.draw(text: text, cursor: &cursor, context: context,
                lineHeight: CGFloat(theme.lineHeight), indent: indent,
                paragraphSpacing: CGFloat(theme.paragraphSpacingPoints)) { _ in
                    context.endPDFPage(); context.beginPDFPage(nil)
                }
        }
    }

    func image(_ raster: PDFImageRaster, indent: CGFloat = 0) throws {
        try perform {
            guard indent.isFinite, indent >= 0, indent < cursor.content.width else {
                throw PDFPageCursor.PageError.invalidGeometry
            }
            let size = try raster.fittedSize(availableWidth: cursor.content.width - indent,
                                             availableHeight: cursor.content.height)
            let previousPage = cursor.pageIndex
            let placement = try cursor.placeRectangle(size: size, indent: indent)
            openPage()
            if previousPage != placement.pageIndex {
                context.endPDFPage(); context.beginPDFPage(nil)
            }
            try raster.draw(in: context, frame: placement.frame)
            try cursor.space(after: CGFloat(theme.paragraphSpacingPoints))
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
