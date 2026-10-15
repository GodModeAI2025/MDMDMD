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
        var deferredHeadings: [PDFDocumentWriter.Heading]?
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
                    let raster = try PDFImageRaster(asset: asset, path: path)
                    if let chain = deferredHeadings {
                        deferredHeadings = nil
                        try writer.headingImage(chain, raster: raster, indent: indent, linkTarget: target,
                            alternativeText: alt, language: document.input.language)
                    } else {
                        try writer.image(raster, indent: indent, destination: destination, linkTarget: target,
                            alternativeText: alt, language: document.input.language)
                    }
                    // A heading starts at its first visible fragment, even
                    // when that fragment is an image rather than text.
                    destination = nil
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
                    func headingText(_ level: Int, _ items: [Inline]) throws -> NSAttributedString? {
                        let fragments = try adapter.fragments(items,
                            sizePoints: CGFloat(theme.bodySizePoints) * max(1, 2 - CGFloat(level - 1) * 0.2),
                            bold: true, heading: true)
                        guard fragments.count == 1, case .text(let text)? = fragments.first else { return nil }
                        return text
                    }
                    let roles: [CGPDFTagType] = [.header1, .header2, .header3, .header4, .header5, .header6]
                    headingIndex += 1
                    guard let first = try headingText(level, items) else {
                        try inline(items, indent: indent,
                            size: CGFloat(theme.bodySizePoints) * max(1, 2 - CGFloat(level - 1) * 0.2),
                            bold: true, heading: true, destination: "heading-\(headingIndex)",
                            role: roles[min(5, max(0, level - 1))])
                        continue
                    }
                    var chain = [PDFDocumentWriter.Heading(text: first, destination: "heading-\(headingIndex)",
                        role: roles[min(5, max(0, level - 1))])]
                    while case .block(.heading(let nextLevel, let nextItems), let nextIndent)? = pending.last,
                          nextIndent == indent, let text = try headingText(nextLevel, nextItems) {
                        try Task.checkCancellation()
                        pending.removeLast(); headingIndex += 1
                        chain.append(.init(text: text, destination: "heading-\(headingIndex)",
                            role: roles[min(5, max(0, nextLevel - 1))]))
                    }
                    var following: NSAttributedString?
                    if case .block(let nextBlock, let nextIndent)? = pending.last, nextIndent == indent {
                        let fragments: [PDFInlineFragment]
                        switch nextBlock {
                        case .paragraph(let items): fragments = try adapter.fragments(items)
                        case .code(let code, _): fragments = try adapter.fragments([.code(code)])
                        case .table: deferredHeadings = chain; fragments = []
                        default: fragments = []
                        }
                        if case .text(let text)? = fragments.first { following = text }
                        else if case .image? = fragments.first { deferredHeadings = chain }
                    }
                    if deferredHeadings == nil { try writer.headingChain(chain, following: following, indent: indent, language: document.input.language) }
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
                    var rasters: [String: PDFImageRaster] = [:]
                    func cell(_ items: [Inline], bold: Bool) throws -> [PDFTableCellLayout.Fragment] {
                        try adapter.fragments(items, bold: bold).map { fragment in
                            switch fragment {
                            case .text(let text): return .text(text)
                            case .image(let path, let alt, let target):
                                if rasters[path] == nil {
                                    guard let asset = document.input.assets[path] else { throw ExportError.missingAsset(path) }
                                    rasters[path] = try PDFImageRaster(asset: asset, path: path)
                                }
                                guard let raster = rasters[path] else { throw ExportError.missingAsset(path) }
                                return .image(raster, alternativeText: alt, target: target)
                            }
                        }
                    }
                    try writer.richTable(header: header.map { try cell($0, bold: true) },
                        rows: rows.map { try $0.map { try cell($0, bold: false) } },
                        alignments: alignments, indent: indent, language: document.input.language, precedingHeadings: deferredHeadings ?? [])
                    deferredHeadings = nil
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
            var tail = note.1
            let firstItems: [Inline]?
            var bodyRole: CGPDFTagType = .paragraph
            switch note.1.first {
            case .paragraph(let items): firstItems = items
            case .code(let code, _): firstItems = [.code(code)]; bodyRole = .code
            default: firstItems = nil
            }
            var fragments = try firstItems.map { try adapter.fragments($0) } ?? []
            var bodyIndent: CGFloat = 18
            if case .text(let body)? = fragments.first,
               case .text(let label)? = try adapter.fragments([.text("\(index + 1).")]).first {
                tail.removeFirst()
                fragments.removeFirst()
                bodyIndent = try writer.noteParagraph(label: label, body: body, destination: "note-\(index + 1)",
                    language: document.input.language, bodyRole: bodyRole)
                for fragment in fragments {
                    switch fragment {
                    case .text(let text):
                        try writer.paragraph(text, indent: bodyIndent, structureRole: bodyRole, language: document.input.language)
                    case .image(let path, let alt, let target):
                        guard let asset = document.input.assets[path] else { throw ExportError.missingAsset(path) }
                        try writer.image(PDFImageRaster(asset: asset, path: path), indent: bodyIndent,
                            linkTarget: target, alternativeText: alt, language: document.input.language)
                    }
                }
            } else {
                // Image/container-first notes retain their complete block traversal.
                try inline([.text("\(index + 1).")], indent: 0, destination: "note-\(index + 1)")
            }
            pending = tail.reversed().map { Work.block($0, bodyIndent) }
            try drain()
            try writer.endStructureGroup()
        }
        return try writer.finish()
    }
}
