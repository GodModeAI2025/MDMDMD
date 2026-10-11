import Foundation
import CoreGraphics

/// One logical paragraph can own marked line sequences across many pages.
/// ActualText is intentionally absent: Unicode comes from the shaped text runs.
@available(iOS 27.0, macOS 27.0, *)
final class PDFParagraphStructure {
    enum StructureError: Error { case attachmentFailed, sequenceUnavailable }
    private let element: CGPDFStructureElement
    private let role: CGPDFTagType
    init(context: CGContext, role: CGPDFTagType = .paragraph, alternativeText: String? = nil,
         language: String? = nil, parent: CGPDFStructureElement? = nil) throws {
        self.role = role
        element = CGPDFStructureElement(tagType: role, attributes: .init(
            language: language.map { Locale.Language(identifier: $0) }, alternativeText: alternativeText))
        let status = parent.map { $0.addChild(element) } ?? context.addStructureTreeRootChild(element)
        guard status == 0 else { throw StructureError.attachmentFailed }
    }
    func draw(_ line: PDFTextTypesetter.Line, context: CGContext, baseline: CGPoint) throws {
        try withMarkedContent(context: context) { try line.draw(in: context, baseline: baseline) }
    }
    func annotate(_ regions: [PDFLinkRegion], context: CGContext) throws {
        for region in regions {
            try Task.checkCancellation()
            guard safeLink(region.target) else { throw ExportError.unsafeURL(region.target) }
            let link = CGPDFStructureElement(tagType: .link, attributes: .init(title: region.target))
            guard element.addChild(link) == 0 else { throw StructureError.attachmentFailed }
            guard let reference = context.beginObjectReference() else { throw StructureError.sequenceUnavailable }
            defer { context.endObjectReference() }
            guard link.addMarkedContentItem(reference) == 0 else { throw StructureError.attachmentFailed }
            try PDFLineDecorations.annotate([region], context: context)
        }
    }
    func withMarkedContent(context: CGContext, body: () throws -> Void) throws {
        try Task.checkCancellation()
        guard let item = context.beginMarkedContentSequence(role) else { throw StructureError.sequenceUnavailable }
        defer { context.endMarkedContentSequence() }
        guard element.addMarkedContentItem(item) == 0 else { throw StructureError.attachmentFailed }
        try body()
    }
}

/// Availability-safe owner used through AnyObject by the macOS13 package.
@available(iOS 27.0, macOS 27.0, *)
final class PDFStructureDocumentRoot {
    let element: CGPDFStructureElement
    init(_ element: CGPDFStructureElement) { self.element = element }
}
