import Foundation
import CoreGraphics

/// One logical paragraph can own marked line sequences across many pages.
/// ActualText is intentionally absent: Unicode comes from the shaped text runs.
@available(iOS 27.0, macOS 27.0, *)
final class PDFParagraphStructure {
    enum StructureError: Error { case attachmentFailed, sequenceUnavailable }
    private let element: CGPDFStructureElement
    private let role: CGPDFTagType
    private var linksByIdentity: [Int: (String, CGPDFStructureElement)] = [:]
    init(context: CGContext, role: CGPDFTagType = .paragraph, alternativeText: String? = nil,
         language: String? = nil, parent: CGPDFStructureElement? = nil) throws {
        self.role = role
        element = CGPDFStructureElement(tagType: role, attributes: .init(
            language: language.map { Locale.Language(identifier: $0) }, alternativeText: alternativeText))
        try PDFStructureLanguage.apply(language, to: element)
        let status = parent.map { $0.addChild(element) } ?? context.addStructureTreeRootChild(element)
        guard status == 0 else { throw StructureError.attachmentFailed }
    }
    func draw(_ line: PDFTextTypesetter.Line, context: CGContext, baseline: CGPoint) throws {
        try withMarkedContent(context: context) { try line.draw(in: context, baseline: baseline) }
    }
    func drawImage(_ raster: PDFImageRaster, frame: CGRect, alternativeText: String,
                   target: String?, language: String?, context: CGContext) throws {
        let figure = try PDFParagraphStructure(context: context, role: .figure,
            alternativeText: alternativeText, language: language, parent: element)
        try figure.withMarkedContent(context: context) { try raster.draw(in: context, frame: frame) }
        if let target {
            try figure.annotate([PDFLinkRegion(target: target, sourceRange: NSRange(location: 0, length: 0),
                bounds: frame, label: alternativeText)], context: context)
        }
    }
    func annotate(_ regions: [PDFLinkRegion], context: CGContext) throws {
        for region in regions {
            try Task.checkCancellation()
            guard safeLink(region.target) else { throw ExportError.unsafeURL(region.target) }
            let link: CGPDFStructureElement
            if let identity = region.identity, let existing = linksByIdentity[identity] {
                guard existing.0 == region.target else { throw StructureError.attachmentFailed }
                link = existing.1
            } else {
                link = CGPDFStructureElement(tagType: .link, attributes: .init(
                    title: region.target, alternativeText: region.label ?? region.target))
                guard element.addChild(link) == 0 else { throw StructureError.attachmentFailed }
                if let identity = region.identity { linksByIdentity[identity] = (region.target, link) }
            }
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
    let role: CGPDFTagType
    init(_ element: CGPDFStructureElement, role: CGPDFTagType = .document) { self.element = element; self.role = role }
}

/// The public C setter accepts a complete BCP47 identifier. SDK27's Swift
/// Attributes.language overlay serializes only languageCode, losing region/script.
@available(iOS 27.0, macOS 27.0, *)
enum PDFStructureLanguage {
    static func apply(_ language: String?, to element: CGPDFStructureElement) throws {
        if let tag = try PDFCatalogLanguageFinalizer.languageTag(language) {
            __CGPDFStructureElementSetLanguageIdentifier(element, tag as CFString)
        }
    }
}
