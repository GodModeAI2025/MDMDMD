import Foundation
import CoreGraphics

/// Semantic traversal for the new PDF backend. Unsupported block geometry is
/// rejected explicitly until its renderer exists; the active app route is unchanged.
struct PDFSemanticRenderer {
    private enum Work {
        case block(SemanticBlock, CGFloat)
        case item(String, [SemanticBlock], CGFloat)
        case begin(CGPDFTagType)
        case end
    }
    static func render(_ document: SemanticDocument, theme: ExportTheme, taggedStructure: Bool = false) throws -> Data {
        let writer = try PDFDocumentWriter(theme: theme, title: document.input.title, author: document.input.author, taggedStructure: taggedStructure, language: document.input.language)
        let adapter = try PDFInlineAdapter(theme: theme, footnoteIDs: document.footnotes.map { $0.0 })
        func inline(_ items: [Inline], indent: CGFloat, size: CGFloat? = nil,
                    bold: Bool = false, heading: Bool = false, destination: String? = nil,
                    following: NSAttributedString? = nil, followingIndent: CGFloat? = nil, role: CGPDFTagType = .paragraph) throws {
            var destination = destination
            var following = following
            for fragment in try adapter.fragments(items, sizePoints: size, bold: bold, heading: heading) {
                try Task.checkCancellation()
                switch fragment {
                case .text(let text):
                    try writer.paragraph(text, indent: indent, destination: destination, keepWithFollowing: following, followingIndent: followingIndent, structureRole: role, language: document.input.language)
                    following = nil
                    destination = nil
                case .image(let path, let alt, let target):
                    guard let asset = document.input.assets[path] else { throw ExportError.missingAsset(path) }
                    try writer.image(PDFImageRaster(asset: asset, path: path), indent: indent, linkTarget: target, alternativeText: alt, language: document.input.language)
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
        var pending = document.blocks.reversed().map { Work.block($0, 0) }
        var headingIndex = 0
        if theme.includeTitle {
            try inline([.text(document.input.title)], indent: 0,
                       size: CGFloat(theme.bodySizePoints * 2), bold: true, heading: true)
        }
        func drain() throws {
            while let work = pending.popLast() {
                try Task.checkCancellation()
                switch work {
                case .begin(let role): try writer.beginStructureGroup(role, language: document.input.language); continue
                case .end: try writer.endStructureGroup(); continue
                case .item(let prefix, let blocks, let indent):
                    guard case .text(let label)? = try adapter.fragments([.text(prefix)]).first else {
                        throw ExportError.invalidMetadata("PDF list label")
                    }
                    var tail = blocks, fragments: [PDFInlineFragment] = []
                    var bodyRole: CGPDFTagType = .paragraph
                    if case .paragraph(let items)? = tail.first {
                        fragments = try adapter.fragments(items); tail.removeFirst()
                    } else if case .code(let code, _)? = tail.first {
                        fragments = try adapter.fragments([.code(code)]); tail.removeFirst()
                        bodyRole = .code
                    }
                    var bodyIndent = indent + 24
                    if case .text(let body)? = fragments.first {
                        bodyIndent = try writer.listParagraph(label: label, body: body, indent: indent,
                            language: document.input.language, keepBodyGroupOpen: true, bodyRole: bodyRole)
                        fragments.removeFirst()
                    } else if case .image(let path, let alt, let target)? = fragments.first {
                        guard let asset = document.input.assets[path] else { throw ExportError.missingAsset(path) }
                        bodyIndent = try writer.listImage(label: label, raster: PDFImageRaster(asset: asset, path: path),
                            indent: indent, linkTarget: target, alternativeText: alt, language: document.input.language,
                            keepBodyGroupOpen: true)
                        fragments.removeFirst()
                    } else {
                        try writer.paragraph(label, indent: indent, structureRole: .label, language: document.input.language)
                        try writer.beginStructureGroup(.listBody, language: document.input.language)
                    }
                    for fragment in fragments {
                        switch fragment {
                        case .text(let text): try writer.paragraph(text, indent: bodyIndent, language: document.input.language)
                        case .image(let path, let alt, let target):
                            guard let asset = document.input.assets[path] else { throw ExportError.missingAsset(path) }
                            try writer.image(PDFImageRaster(asset: asset, path: path), indent: bodyIndent,
                                linkTarget: target, alternativeText: alt, language: document.input.language)
                        }
                    }
                    pending.append(.end)
                    pending.append(contentsOf: tail.reversed().map { .block($0, bodyIndent) })
                    continue
                case .block: break
                }
                guard case .block(let block, let indent) = work else { continue }
                switch block {
                case .paragraph(let items): try inline(items, indent: indent)
                case .heading(let level, let items):
                    headingIndex += 1
                    var following: NSAttributedString?
                    if case .block(.paragraph(let nextItems), let nextIndent)? = pending.last, nextIndent == indent,
                       case .text(let nextText)? = try adapter.fragments(nextItems).first {
                        following = nextText
                    }
                    try inline(items, indent: indent,
                        size: CGFloat(theme.bodySizePoints) * max(1, 2 - CGFloat(level - 1) * 0.2),
                        bold: true, heading: true, destination: "heading-\(headingIndex)", following: following,
                        role: [.header1, .header2, .header3, .header4, .header5, .header6][min(5, max(0, level - 1))])
                case .code(let code, _): try inline([.code(code)], indent: indent, role: .code)
                case .quote(let blocks):
                    try writer.beginStructureGroup(.blockQuote, language: document.input.language)
                    pending.append(.end)
                    pending.append(contentsOf: blocks.reversed().map { .block($0, indent + 18) })
                case .list(let start, let items):
                    try writer.beginStructureGroup(.list, language: document.input.language)
                    var flattened: [Work] = []
                    for (index, blocks) in items.enumerated() {
                        try Task.checkCancellation()
                        let prefix = start.map { "\($0 + index)." } ?? "•"
                        flattened.append(.begin(.listItem))
                        flattened.append(.item(prefix, blocks, indent + 18))
                        flattened.append(.end)
                    }
                    pending.append(.end)
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
            try writer.beginStructureGroup(.note, language: document.input.language)
            var following: NSAttributedString?
            if case .paragraph(let items)? = note.1.first,
               case .text(let text)? = try adapter.fragments(items).first { following = text }
            try inline([.text("\(index + 1).")], indent: 0, destination: "note-\(index + 1)", following: following, followingIndent: 18)
            pending = note.1.reversed().map { Work.block($0, 18) }
            try drain()
            try writer.endStructureGroup()
        }
        return try writer.finish()
    }
}
