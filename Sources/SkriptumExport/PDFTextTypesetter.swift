import Foundation
import CoreText
import CoreGraphics

/// Streaming paragraph layout for the semantic PDF backend. CoreText values stay
/// local to the rendering worker; they are never passed across actor boundaries.
/// This primitive does not select an export backend or claim PDF accessibility.
struct PDFTextTypesetter {
    enum LayoutError: Error, Equatable { case invalidGeometry, invalidBreak }
    struct Line {
        let sourceRange: NSRange
        let width: CGFloat
        let ascent: CGFloat
        let descent: CGFloat
        let leading: CGFloat
        let advance: CGFloat
        let exceedsAvailableWidth: Bool
        private let coreTextLine: CTLine

        fileprivate init(range: NSRange, coreTextLine: CTLine, availableWidth: CGFloat,
                         lineHeightMultiple: CGFloat, fallbackFont: CTFont) {
            var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
            let width = CGFloat(CTLineGetTypographicBounds(coreTextLine, &ascent, &descent, &leading))
            if ascent + descent <= 0 {
                ascent = CTFontGetAscent(fallbackFont)
                descent = CTFontGetDescent(fallbackFont)
                leading = CTFontGetLeading(fallbackFont)
            }
            self.sourceRange = range; self.coreTextLine = coreTextLine
            self.width = width; self.ascent = ascent; self.descent = descent; self.leading = leading
            advance = (ascent + descent + max(0, leading)) * lineHeightMultiple
            exceedsAvailableWidth = width > availableWidth + 0.01
        }

        /// Baseline uses the PDF's bottom-left coordinate system. Text state is
        /// isolated so a caller's image or page transforms cannot leak into it.
        func draw(in context: CGContext, baseline: CGPoint) throws {
            try Task.checkCancellation()
            let previousTextMatrix = context.textMatrix
            let previousTextPosition = context.textPosition
            context.saveGState()
            defer {
                context.restoreGState()
                context.textMatrix = previousTextMatrix
                context.textPosition = previousTextPosition
            }
            context.textMatrix = .identity
            context.textPosition = baseline
            CTLineDraw(coreTextLine, context)
        }
    }

    private let text: NSAttributedString
    private let source: NSString
    private let typesetter: CTTypesetter
    private let availableWidth: CGFloat
    private let lineHeightMultiple: CGFloat
    private var offset = 0

    init(text: NSAttributedString, availableWidth: CGFloat, lineHeightMultiple: CGFloat = 1) throws {
        try Task.checkCancellation()
        guard availableWidth.isFinite, availableWidth > 0,
              lineHeightMultiple.isFinite, lineHeightMultiple >= 1 else { throw LayoutError.invalidGeometry }
        // Freeze mutable attribute/string input before asynchronous callers can
        // resume editing. The renderer retains only its own immutable snapshot.
        self.text = NSAttributedString(attributedString: text)
        source = self.text.string as NSString
        typesetter = CTTypesetterCreateWithAttributedString(self.text)
        self.availableWidth = availableWidth; self.lineHeightMultiple = lineHeightMultiple
    }

    mutating func nextLine() throws -> Line? {
        try Task.checkCancellation()
        guard offset < source.length else { return nil }
        var count = CTTypesetterSuggestLineBreak(typesetter, offset, Double(availableWidth))
        guard count >= 0, count <= source.length - offset else { throw LayoutError.invalidBreak }
        if count == 0 {
            count = NSMaxRange(source.rangeOfComposedCharacterSequence(at: offset)) - offset
        } else {
            // CoreText's shaping cluster boundaries need not equal an extended
            // grapheme boundary (e.g. an emoji family). Never split source text
            // into partial surrogate/combining/ZWJ sequences to fit a narrow line.
            let lastCluster = source.rangeOfComposedCharacterSequence(at: offset + count - 1)
            if NSMaxRange(lastCluster) > offset + count {
                count = lastCluster.location > offset ? lastCluster.location - offset : NSMaxRange(lastCluster) - offset
            }
        }
        guard count > 0, count <= source.length - offset else { throw LayoutError.invalidBreak }
        let range = NSRange(location: offset, length: count)
        let line = CTTypesetterCreateLine(typesetter, CFRange(location: offset, length: count))
        let fallbackFont: CTFont
        if let attribute = text.attribute(NSAttributedString.Key(kCTFontAttributeName as String), at: offset, effectiveRange: nil),
           CFGetTypeID(attribute as CFTypeRef) == CTFontGetTypeID() {
            fallbackFont = attribute as! CTFont // Type ID verified before the CF cast.
        } else { fallbackFont = CTFontCreateWithName("Georgia" as CFString, 12, nil) }
        let result = Line(range: range, coreTextLine: line, availableWidth: availableWidth,
                          lineHeightMultiple: lineHeightMultiple, fallbackFont: fallbackFont)
        offset += count
        return result
    }
}
