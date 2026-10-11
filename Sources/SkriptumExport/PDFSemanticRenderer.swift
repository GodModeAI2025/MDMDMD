import Foundation
import CoreGraphics

/// Semantic traversal for the new PDF backend. Unsupported block geometry is
/// rejected explicitly until its renderer exists; the active app route is unchanged.
struct PDFSemanticRenderer {
    static func render(_ document: SemanticDocument, theme: ExportTheme) throws -> Data {
        let writer = try PDFDocumentWriter(theme: theme, title: document.input.title, author: document.input.author)
        let adapter = try PDFInlineAdapter(theme: theme, footnoteIDs: document.footnotes.map { $0.0 })
        func inline(_ items: [Inline], indent: CGFloat, size: CGFloat? = nil,
                    bold: Bool = false, heading: Bool = false, destination: String? = nil) throws {
            var destination = destination
            for fragment in try adapter.fragments(items, sizePoints: size, bold: bold, heading: heading) {
                try Task.checkCancellation()
                switch fragment {
                case .text(let text):
                    try writer.paragraph(text, indent: indent, destination: destination)
                    destination = nil
                case .image(let path, _, let target):
                    guard target == nil else { throw ExportError.unsupportedMarkdown("PDF linked image") }
                    guard let asset = document.input.assets[path] else { throw ExportError.missingAsset(path) }
                    try writer.image(PDFImageRaster(asset: asset, path: path), indent: indent)
                }
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
                    try inline(items, indent: indent,
                        size: CGFloat(theme.bodySizePoints) * max(1, 2 - CGFloat(level - 1) * 0.2),
                        bold: true, heading: true, destination: "heading-\(headingIndex)")
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
                case .table: throw ExportError.unsupportedMarkdown("PDF table layout")
                case .rule: throw ExportError.unsupportedMarkdown("PDF thematic rule layout")
                case .toc: throw ExportError.unsupportedMarkdown("PDF contents layout")
                }
            }
        }
        // Automatic contents and unsupported block types never disappear silently.
        guard !theme.includeTOC else { throw ExportError.unsupportedMarkdown("PDF contents layout") }
        try drain()
        for (index, note) in document.footnotes.enumerated() {
            try inline([.text("\(index + 1).")], indent: 0, destination: "note-\(index + 1)")
            pending = note.1.reversed().map { ($0, CGFloat(18)) }
            try drain()
        }
        return try writer.finish()
    }
}
