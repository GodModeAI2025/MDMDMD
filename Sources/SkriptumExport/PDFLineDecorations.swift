import Foundation
import CoreText
import CoreGraphics

struct PDFLinkRegion {
    let target: String
    let sourceRange: NSRange
    let bounds: CGRect
}

enum PDFLineDecorations {
    private static func bounds(_ run: CTRun, baseline: CGPoint) throws -> CGRect? {
        let count = CTRunGetGlyphCount(run)
        guard count > 0 else { return nil }
        var positions = [CGPoint](repeating: .zero, count: count)
        var advances = [CGSize](repeating: .zero, count: count)
        CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)
        CTRunGetAdvances(run, CFRange(location: 0, length: 0), &advances)
        var ascent: CGFloat = 0, descent: CGFloat = 0
        _ = CTRunGetTypographicBounds(run, CFRange(location: 0, length: 0), &ascent, &descent, nil)
        var result = CGRect.null
        for index in 0..<count {
            if index & 1023 == 0 { try Task.checkCancellation() }
            let x = baseline.x + positions[index].x
            let y = baseline.y + positions[index].y
            let width = advances[index].width
            let rect = CGRect(x: x + min(0, width), y: y - descent,
                              width: abs(width), height: ascent + descent)
            result = result.union(rect)
        }
        return result.isNull || result.isEmpty ? nil : result
    }

    static func links(_ line: CTLine, baseline: CGPoint) throws -> [PDFLinkRegion] {
        var regions: [PDFLinkRegion] = []
        for run in CTLineGetGlyphRuns(line) as! [CTRun] {
            try Task.checkCancellation()
            let attributes = CTRunGetAttributes(run) as NSDictionary
            guard let target = attributes[PDFInlineAdapter.linkTarget.rawValue] as? String,
                  let bounds = try bounds(run, baseline: baseline) else { continue }
            let range = CTRunGetStringRange(run)
            regions.append(PDFLinkRegion(target: target, sourceRange: NSRange(location: range.location, length: range.length), bounds: bounds))
        }
        return regions
    }

    static func annotate(_ regions: [PDFLinkRegion], context: CGContext) throws {
        for region in regions {
            try Task.checkCancellation()
            guard safeLink(region.target) else { throw ExportError.unsafeURL(region.target) }
            if region.target.hasPrefix("#") {
                context.setDestination(String(region.target.dropFirst()) as CFString, for: region.bounds)
            } else {
                guard let url = URL(string: region.target) else { throw ExportError.unsafeURL(region.target) }
                context.setURL(url as CFURL, for: region.bounds)
            }
        }
    }

    static func drawStrikes(_ line: CTLine, context: CGContext, baseline: CGPoint) throws {
        context.saveGState(); defer { context.restoreGState() }
        for run in CTLineGetGlyphRuns(line) as! [CTRun] {
            try Task.checkCancellation()
            let attributes = CTRunGetAttributes(run) as NSDictionary
            guard attributes[PDFInlineAdapter.strike.rawValue] as? Bool == true,
                  let bounds = try bounds(run, baseline: baseline),
                  let value = attributes[kCTFontAttributeName as String],
                  CFGetTypeID(value as CFTypeRef) == CTFontGetTypeID() else { continue }
            let font = value as! CTFont
            let y = bounds.minY + CTFontGetDescent(font) + CTFontGetXHeight(font) / 2
            if let color = attributes[kCTForegroundColorAttributeName as String], CFGetTypeID(color as CFTypeRef) == CGColor.typeID {
                context.setStrokeColor(color as! CGColor)
            } else { context.setStrokeColor(CGColor(gray: 0.1, alpha: 1)) }
            context.setLineWidth(max(0.5, CTFontGetSize(font) / 16))
            context.move(to: CGPoint(x: bounds.minX, y: y))
            context.addLine(to: CGPoint(x: bounds.maxX, y: y))
            context.strokePath()
        }
    }
}
