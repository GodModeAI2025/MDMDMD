import Foundation
import CoreGraphics

/// One logical paragraph can own marked line sequences across many pages.
/// ActualText is intentionally absent: Unicode comes from the shaped text runs.
@available(iOS 27.0, macOS 27.0, *)
final class PDFParagraphStructure {
    enum StructureError: Error { case attachmentFailed, sequenceUnavailable }
    private let element: CGPDFStructureElement
    private let role: CGPDFTagType
    init(context: CGContext, role: CGPDFTagType = .paragraph,
         language: String? = nil) throws {
        self.role = role
        element = CGPDFStructureElement(tagType: role, attributes: .init(
            language: language.map { Locale.Language(identifier: $0) }))
        guard context.addStructureTreeRootChild(element) == 0 else { throw StructureError.attachmentFailed }
    }
    func draw(_ line: PDFTextTypesetter.Line, context: CGContext, baseline: CGPoint) throws {
        try withMarkedContent(context: context) { try line.draw(in: context, baseline: baseline) }
    }
    func withMarkedContent(context: CGContext, body: () throws -> Void) throws {
        try Task.checkCancellation()
        guard let item = context.beginMarkedContentSequence(role) else { throw StructureError.sequenceUnavailable }
        defer { context.endMarkedContentSequence() }
        guard element.addMarkedContentItem(item) == 0 else { throw StructureError.attachmentFailed }
        try body()
    }
}
