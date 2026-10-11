import Foundation
import CoreGraphics

/// One logical paragraph can own marked line sequences across many pages.
/// ActualText is intentionally absent: Unicode comes from the shaped text runs.
@available(iOS 27.0, macOS 27.0, *)
final class PDFParagraphStructure {
    enum StructureError: Error { case attachmentFailed, sequenceUnavailable }
    private let element: CGPDFStructureElement
    init(context: CGContext) throws {
        element = CGPDFStructureElement(tagType: .paragraph)
        guard context.addStructureTreeRootChild(element) == 0 else { throw StructureError.attachmentFailed }
    }
    func draw(_ line: PDFTextTypesetter.Line, context: CGContext, baseline: CGPoint) throws {
        try Task.checkCancellation()
        guard let item = context.beginMarkedContentSequence(.paragraph) else { throw StructureError.sequenceUnavailable }
        defer { context.endMarkedContentSequence() }
        guard element.addMarkedContentItem(item) == 0 else { throw StructureError.attachmentFailed }
        try line.draw(in: context, baseline: baseline)
    }
}
