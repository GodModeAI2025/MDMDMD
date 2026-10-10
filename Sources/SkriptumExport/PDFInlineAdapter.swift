import Foundation
import CoreText
import CoreGraphics

/// Images remain explicit layout items; alt text is metadata, not a replacement
/// for the asset. Text attributes retain destinations for later PDF annotations.
enum PDFInlineFragment {
    case text(NSAttributedString)
    case image(path: String, alternativeText: String, linkTarget: String?)
}

struct PDFInlineAdapter {
    enum AdapterError: Error { case fontVariantUnavailable }
    static let linkTarget = NSAttributedString.Key("Scriptum.PDF.LinkTarget")
    static let noteID = NSAttributedString.Key("Scriptum.PDF.NoteID")
    static let strike = NSAttributedString.Key("Scriptum.PDF.Strike")
    private let theme: ExportTheme
    private let noteNumbers: [String: Int]
    private struct Style {
        var bold = false
        var italic = false
        var monospaced = false
        var strike = false
        var link: String?
    }

    init(theme: ExportTheme, footnoteIDs: [String]) throws {
        try theme.validate()
        var numbers: [String: Int] = [:]
        for (index, id) in footnoteIDs.enumerated() {
            try Task.checkCancellation()
            guard numbers[id] == nil else { throw ExportError.duplicateFootnote(id) }
            numbers[id] = index + 1
        }
        self.theme = theme; noteNumbers = numbers
    }

    func fragments(_ items: [Inline], sizePoints: CGFloat? = nil, bold: Bool = false,
                   heading: Bool = false) throws -> [PDFInlineFragment] {
        try Task.checkCancellation()
        let size = sizePoints ?? CGFloat(theme.bodySizePoints)
        guard size.isFinite, size > 0 else { throw ExportError.invalidMetadata("PDF font size") }
        var initial = Style(); initial.bold = bold
        var pending = items.reversed().map { ($0, initial) }
        var result: [PDFInlineFragment] = []
        var buffer = NSMutableAttributedString(string: "")
        func flush() {
            if buffer.length > 0 {
                result.append(.text(NSAttributedString(attributedString: buffer)))
                buffer = NSMutableAttributedString(string: "")
            }
        }
        while let (item, style) = pending.popLast() {
            try Task.checkCancellation()
            switch item {
            case .emphasis(let children), .strong(let children), .strike(let children), .link(_, let children):
                var next = style
                switch item {
                case .emphasis: next.italic = true
                case .strong: next.bold = true
                case .strike: next.strike = true
                case .link(let target, _): next.link = target
                default: break
                }
                pending.append(contentsOf: children.reversed().map { ($0, next) })
            case .image(let path, let alt):
                flush()
                result.append(.image(path: path, alternativeText: alt, linkTarget: style.link))
            case .footnote(let id):
                guard let number = noteNumbers[id] else { throw ExportError.missingFootnote(id) }
                var noteStyle = style; noteStyle.link = "#note-\(number)"
                var attributes = try attributes(for: noteStyle, size: size * 0.75, heading: heading)
                attributes[Self.noteID] = id
                attributes[NSAttributedString.Key(kCTBaselineOffsetAttributeName as String)] = size * 0.35
                buffer.append(NSAttributedString(string: String(number), attributes: attributes))
            case .text(let value), .code(let value):
                var next = style
                if case .code = item { next.monospaced = true }
                buffer.append(NSAttributedString(string: value, attributes: try attributes(for: next, size: size, heading: heading)))
            case .lineBreak, .softBreak:
                let value = if case .lineBreak = item { "\n" } else { " " }
                buffer.append(NSAttributedString(string: value, attributes: try attributes(for: style, size: size, heading: heading)))
            }
        }
        flush()
        return result
    }

    private func attributes(for style: Style, size: CGFloat, heading: Bool) throws -> [NSAttributedString.Key: Any] {
        let name = style.monospaced ? ExportFont.courierNew.displayName : theme.bodyFont.displayName
        var font = CTFontCreateWithName(name as CFString, size, nil)
        var traits: CTFontSymbolicTraits = []
        if style.bold { traits.insert(.traitBold) }
        if style.italic { traits.insert(.traitItalic) }
        if !traits.isEmpty {
            guard let variant = CTFontCreateCopyWithSymbolicTraits(font, size, nil, traits, traits) else {
                throw AdapterError.fontVariantUnavailable
            }
            font = variant
        }
        let hex = style.link != nil ? "164D88" : heading ? theme.headingColorHex : "17202A"
        guard let rgb = UInt32(hex, radix: 16) else { throw ExportError.invalidMetadata("PDF color") }
        let color = CGColor(red: CGFloat((rgb >> 16) & 255) / 255,
                            green: CGFloat((rgb >> 8) & 255) / 255, blue: CGFloat(rgb & 255) / 255, alpha: 1)
        var values: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color
        ]
        if let link = style.link { values[Self.linkTarget] = link }
        if style.strike { values[Self.strike] = true }
        return values
    }
}
