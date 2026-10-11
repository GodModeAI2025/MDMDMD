import Foundation
import CoreGraphics

/// A cell streams text lines and indivisible upright images in source order.
struct PDFTableCellLayout {
    enum Fragment {
        case text(NSAttributedString)
        case image(PDFImageRaster, alternativeText: String, target: String?)
    }
    enum Element {
        case text(PDFTextTypesetter.Line)
        case image(PDFImageRaster, size: CGSize, ascent: CGFloat, alternativeText: String, target: String?)
        var width: CGFloat { switch self { case .text(let line): line.width; case .image(_, let size, _, _, _): size.width } }
        var ascent: CGFloat { switch self { case .text(let line): line.ascent; case .image(_, _, let ascent, _, _): ascent } }
        var height: CGFloat { switch self { case .text(let line): max(line.advance, line.ascent + line.descent); case .image(_, let size, _, _, _): size.height } }
        func imageFrame(baseline: CGPoint) -> CGRect? {
            guard case .image(_, let size, let ascent, _, _) = self else { return nil }
            return CGRect(x: baseline.x, y: baseline.y + ascent - size.height, width: size.width, height: size.height)
        }
        func draw(in context: CGContext, baseline: CGPoint) throws {
            switch self {
            case .text(let line): try line.draw(in: context, baseline: baseline)
            case .image(let raster, _, _, _, _):
                guard let frame = imageFrame(baseline: baseline) else { throw PDFTextTypesetter.LayoutError.invalidBreak }
                try raster.draw(in: context, frame: frame)
            }
        }
        func addLinkAnnotations(in context: CGContext, baseline: CGPoint) throws {
            switch self {
            case .text(let line): try line.addLinkAnnotations(in: context, baseline: baseline)
            case .image(_, _, _, let alt, let target):
                if let target, let frame = imageFrame(baseline: baseline) {
                    try PDFLineDecorations.annotate([PDFLinkRegion(target: target,
                        sourceRange: NSRange(location: 0, length: 0), bounds: frame, label: alt)], context: context)
                }
            }
        }
    }
    private enum Part { case text(PDFParagraphLayout), image(Element) }
    private let parts: [Part]
    let lineHeights: [CGFloat]
    let lineAscents: [CGFloat]

    init(fragments: [Fragment], width: CGFloat, maximumImageHeight: CGFloat,
         imageAscent: CGFloat, lineHeight: CGFloat) throws {
        guard width.isFinite, width > 0, maximumImageHeight.isFinite, maximumImageHeight > 0,
              imageAscent.isFinite, imageAscent >= 0 else { throw PDFPageCursor.PageError.invalidGeometry }
        var parts: [Part] = [], heights: [CGFloat] = [], ascents: [CGFloat] = []
        for fragment in fragments {
            try Task.checkCancellation()
            switch fragment {
            case .text(let text):
                let layout = try PDFParagraphLayout(text: text, width: width, lineHeight: lineHeight)
                parts.append(.text(layout)); heights.append(contentsOf: layout.lineHeights)
                ascents.append(contentsOf: layout.lineAscents)
            case .image(let raster, let alt, let target):
                if let target, !safeLink(target) { throw ExportError.unsafeURL(target) }
                let size = try raster.fittedSize(availableWidth: width, availableHeight: maximumImageHeight)
                let ascent = min(imageAscent, size.height)
                parts.append(.image(.image(raster, size: size, ascent: ascent, alternativeText: alt, target: target)))
                heights.append(size.height); ascents.append(ascent)
            }
        }
        self.parts = parts; lineHeights = heights; lineAscents = ascents
    }

    struct Stream {
        fileprivate let layout: PDFTableCellLayout
        private var partIndex = 0
        private var typesetter: PDFTextTypesetter?
        fileprivate init(layout: PDFTableCellLayout) { self.layout = layout }
        mutating func nextLine() throws -> Element? {
            while partIndex < layout.parts.count {
                try Task.checkCancellation()
                switch layout.parts[partIndex] {
                case .image(let image): partIndex += 1; return image
                case .text(let text):
                    if typesetter == nil { typesetter = try text.streamingTypesetter() }
                    if let line = try typesetter?.nextLine() { return .text(line) }
                    typesetter = nil; partIndex += 1
                }
            }
            return nil
        }
    }
    func streamingTypesetter() throws -> Stream { try Task.checkCancellation(); return Stream(layout: self) }
    func forEachLine(in fragments: [PDFParagraphBreakPlanner.Fragment],
                     body: (PDFParagraphBreakPlanner.Fragment, Int, Element) throws -> Void) throws {
        var stream = try streamingTypesetter(), expected = 0
        for fragment in fragments {
            guard fragment.lineRange.lowerBound == expected,
                  fragment.lineRange.upperBound <= lineHeights.count else { throw PDFTextTypesetter.LayoutError.invalidBreak }
            for index in fragment.lineRange {
                guard let element = try stream.nextLine(), element.height == lineHeights[index],
                      element.ascent == lineAscents[index] else { throw PDFTextTypesetter.LayoutError.invalidBreak }
                try body(fragment, index, element)
            }
            expected = fragment.lineRange.upperBound
        }
        guard expected == lineHeights.count, try stream.nextLine() == nil else { throw PDFTextTypesetter.LayoutError.invalidBreak }
    }
}
