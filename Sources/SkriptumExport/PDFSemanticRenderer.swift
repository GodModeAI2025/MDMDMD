import Foundation
import CoreGraphics

/// Semantic traversal for the new PDF backend. Unsupported block geometry is
/// rejected explicitly until its renderer exists; the active app route is unchanged.
struct PDFSemanticRenderer {
    static func render(_ document: SemanticDocument, theme: ExportTheme) throws -> Data {
        let writer = try PDFDocumentWriter(theme: theme, title: document.input.title, author: document.input.author)
        let adapter = try PDFInlineAdapter(theme: theme, footnoteIDs: document.footnotes.map { $0.0 })
        func inline(_ items: [Inline], indent: CGFloat, size: CGFloat? = nil,
                    bold: Bool = false, heading: Bool = false, destination: String? = nil,
                    following: NSAttributedString? = nil) throws {
            var destination = destination
            var following = following
            for fragment in try adapter.fragments(items, sizePoints: size, bold: bold, heading: heading) {
                try Task.checkCancellation()
                switch fragment {
                case .text(let text):
                    try writer.paragraph(text, indent: indent, destination: destination, keepWithFollowing: following)
                    following = nil
                    destination = nil
                case .image(let path, _, let target):
                    guard let asset = document.input.assets[path] else { throw ExportError.missingAsset(path) }
                    try writer.image(PDFImageRaster(asset: asset, path: path), indent: indent, linkTarget: target)
                }
            }
        }
        let headings = exportHeadings(document.blocks)
        func contents(indent: CGFloat) throws {
            for entry in headings {
                try Task.checkCancellation()
                try inline([.link("#" + entry.htmlID, [.text(entry.text)])],
                           indent: indent + CGFloat(entry.level - 1) * 12)
            }
        }
        var pending = document.blocks.reversed().map { ($0, CGFloat(0)) }
        var headingIndex = 0
        if theme.includeTitle {
            try inline([.text(document.input.title)], indent: 0,
                       size: CGFloat(theme.bodySizePoints * 2), bold: true, heading: true)
        }
        func drain() throws {
            while let (block, indent) = pending.popLast() {
                try Task.checkCancellation()
                switch block {
                case .paragraph(let items): try inline(items, indent: indent)
                case .heading(let level, let items):
                    headingIndex += 1
                    var following: NSAttributedString?
                    if case .paragraph(let nextItems)? = pending.last?.0,
                       let nextIndent = pending.last?.1, nextIndent == indent,
                       case .text(let nextText)? = try adapter.fragments(nextItems).first {
                        following = nextText
                    }
                    try inline(items, indent: indent,
                        size: CGFloat(theme.bodySizePoints) * max(1, 2 - CGFloat(level - 1) * 0.2),
                        bold: true, heading: true, destination: "heading-\(headingIndex)", following: following)
                case .code(let code, _): try inline([.code(code)], indent: indent)
                case .quote(let blocks):
                    pending.append(contentsOf: blocks.reversed().map { ($0, indent + 18) })
                case .list(let start, let items):
                    var flattened: [(SemanticBlock, CGFloat)] = []
                    for (index, blocks) in items.enumerated() {
                        try Task.checkCancellation()
                        let prefix = start.map { "\($0 + index). " } ?? "• "
                        var blocks = blocks
                        if case .paragraph(let text)? = blocks.first { blocks[0] = .paragraph([.text(prefix)] + text) }
                        else { blocks.insert(.paragraph([.text(prefix)]), at: 0) }
                        flattened.append(contentsOf: blocks.map { ($0, indent + 18) })
                    }
                    pending.append(contentsOf: flattened.reversed())
                case .table(let header, let rows, let alignments):
                    func cell(_ items: [Inline], bold: Bool) throws -> NSAttributedString {
                        let text = NSMutableAttributedString(string: "")
                        for fragment in try adapter.fragments(items, bold: bold) {
                            guard case .text(let part) = fragment else {
                                throw ExportError.unsupportedMarkdown("PDF image inside table")
                            }
                            text.append(part)
                        }
                        return NSAttributedString(attributedString: text)
                    }
                    try writer.table(header: header.map { try cell($0, bold: true) },
                        rows: rows.map { try $0.map { try cell($0, bold: false) } },
                        alignments: alignments, indent: indent)
                case .rule: try writer.rule(indent: indent)
                case .toc: try contents(indent: indent)
                }
            }
        }
        // Automatic contents and unsupported block types never disappear silently.
        if theme.includeTOC && !hasTOCMarker(document.blocks) { try contents(indent: 0) }
        try drain()
        for (index, note) in document.footnotes.enumerated() {
            try inline([.text("\(index + 1).")], indent: 0, destination: "note-\(index + 1)")
            pending = note.1.reversed().map { ($0, CGFloat(18)) }
            try drain()
        }
        return try writer.finish()
    }
}
