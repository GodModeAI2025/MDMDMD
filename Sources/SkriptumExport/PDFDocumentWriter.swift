import Foundation
import CoreGraphics

/// Worker-local semantic PDF document lifecycle. Failed writes never return a
/// partially drawn document. This writer is not yet the app's export backend.
final class PDFDocumentWriter {
    enum WriterError: Error, Equatable { case closed, contextCreationFailed, invalidStructure }
    private let bytes = NSMutableData()
    private let context: CGContext
    private var cursor: PDFPageCursor
    private let theme: ExportTheme
    private let taggedStructure: Bool
    // SDK27 structure types are erased only at this older-macOS package boundary;
    // all construction and use are checked in their availability branches.
    private var structureParents: [AnyObject] = []
    private var pageOpen = false
    private var closed = false
    private var keepNextParagraph = false

    init(theme: ExportTheme, title: String, author: String = "", maximumPages: Int = 3000, taggedStructure: Bool = false, language: String? = nil) throws {
        cursor = try PDFPageCursor(theme: theme, maximumPages: maximumPages)
        self.theme = theme; self.taggedStructure = taggedStructure
        guard let consumer = CGDataConsumer(data: bytes) else { throw WriterError.contextCreationFailed }
        var paper = cursor.paper
        let metadata: [CFString: Any] = [kCGPDFContextTitle: title, kCGPDFContextAuthor: author,
                                        kCGPDFContextCreator: "Scriptum"]
        guard let context = CGContext(consumer: consumer, mediaBox: &paper, metadata as CFDictionary) else {
            throw WriterError.contextCreationFailed
        }
        self.context = context
        if taggedStructure {
            if #available(iOS 27.0, macOS 27.0, *) {
                let root = CGPDFStructureElement(tagType: .document, attributes: .init(
                    title: title, language: language.map { Locale.Language(identifier: $0) }))
                guard context.addStructureTreeRootChild(root) == 0 else {
                    throw PDFParagraphStructure.StructureError.attachmentFailed
                }
                structureParents = [PDFStructureDocumentRoot(root)]
            } else { throw PDFParagraphStructureUnavailable.unsupportedSystem }
        }
    }

    deinit { close() }

    func beginStructureGroup(_ role: CGPDFTagType, language: String? = nil) throws {
        try perform {
            guard taggedStructure else { return }
            if #available(iOS 27.0, macOS 27.0, *) {
                guard let parent = structureParents.last as? PDFStructureDocumentRoot else {
                    throw WriterError.invalidStructure
                }
                let child = CGPDFStructureElement(tagType: role, attributes: .init(
                    language: language.map { Locale.Language(identifier: $0) }))
                guard parent.element.addChild(child) == 0 else { throw WriterError.invalidStructure }
                structureParents.append(PDFStructureDocumentRoot(child))
            } else { throw PDFParagraphStructureUnavailable.unsupportedSystem }
        }
    }

    func endStructureGroup() throws {
        try perform {
            guard taggedStructure else { return }
            guard structureParents.count > 1 else { throw WriterError.invalidStructure }
            structureParents.removeLast()
        }
    }

    func paragraph(_ text: NSAttributedString, indent: CGFloat = 0, destination: String? = nil, keepWithFollowing: NSAttributedString? = nil, structureRole: CGPDFTagType = .paragraph, language: String? = nil) throws {
        try perform {
            guard text.length > 0 else { return }
            if let following = keepWithFollowing, following.length > 0 {
                let heading = try PDFParagraphLayout(text: text, width: cursor.content.width - indent,
                                                      lineHeight: CGFloat(theme.lineHeight))
                let next = try PDFParagraphLayout(text: following, width: cursor.content.width - indent,
                                                   lineHeight: CGFloat(theme.lineHeight))
                let required = heading.lineHeights.reduce(0, +) + CGFloat(theme.paragraphSpacingPoints)
                    + next.lineHeights.prefix(3).reduce(0, +)
                let previousPage = cursor.pageIndex
                try cursor.reserve(height: required)
                if pageOpen && previousPage != cursor.pageIndex {
                    context.endPDFPage(); context.beginPDFPage(nil)
                }
            }
            openPage()
            let context = self.context
            var lineRenderer: ((PDFTextTypesetter.Line, CGPoint) throws -> Void)?
            if taggedStructure {
                if #available(iOS 27.0, macOS 27.0, *) {
                    guard let holder = structureParents.last as? PDFStructureDocumentRoot else {
                        throw PDFParagraphStructure.StructureError.attachmentFailed
                    }
                    let structure = try PDFParagraphStructure(context: context, role: structureRole,
                        language: language, parent: holder.element)
                    lineRenderer = { line, baseline in try structure.draw(line, context: context, baseline: baseline) }
                } else { throw PDFParagraphStructureUnavailable.unsupportedSystem }
            }
            let mustStart = keepNextParagraph
            keepNextParagraph = keepWithFollowing != nil
            try PDFParagraphRenderer.draw(text: text, cursor: &cursor, context: context,
                lineHeight: CGFloat(theme.lineHeight), indent: indent,
                paragraphSpacing: CGFloat(theme.paragraphSpacingPoints), mustStartOnCurrentPage: mustStart, lineRenderer: lineRenderer, firstLine: { placement in
                    if let destination { context.addDestination(destination as CFString, at: placement.baseline) }
                }) { _ in
                    context.endPDFPage(); context.beginPDFPage(nil)
                }
        }
    }

    func image(_ raster: PDFImageRaster, indent: CGFloat = 0, linkTarget: String? = nil, alternativeText: String? = nil, language: String? = nil) throws {
        try perform {
            guard indent.isFinite, indent >= 0, indent < cursor.content.width else {
                throw PDFPageCursor.PageError.invalidGeometry
            }
            if let linkTarget, !safeLink(linkTarget) { throw ExportError.unsafeURL(linkTarget) }
            let size = try raster.fittedSize(availableWidth: cursor.content.width - indent,
                                             availableHeight: cursor.content.height)
            let previousPage = cursor.pageIndex
            let placement = try cursor.placeRectangle(size: size, indent: indent)
            openPage()
            if previousPage != placement.pageIndex {
                context.endPDFPage(); context.beginPDFPage(nil)
            }
            if taggedStructure {
                if #available(iOS 27.0, macOS 27.0, *) {
                    guard let holder = structureParents.last as? PDFStructureDocumentRoot else {
                        throw PDFParagraphStructure.StructureError.attachmentFailed
                    }
                    let structure = try PDFParagraphStructure(context: context, role: .figure,
                        alternativeText: alternativeText, language: language, parent: holder.element)
                    try structure.withMarkedContent(context: context) { try raster.draw(in: context, frame: placement.frame) }
                } else { throw PDFParagraphStructureUnavailable.unsupportedSystem }
            } else { try raster.draw(in: context, frame: placement.frame) }
            if let linkTarget {
                try PDFLineDecorations.annotate([PDFLinkRegion(target: linkTarget,
                    sourceRange: NSRange(location: 0, length: 0), bounds: placement.frame)], context: context)
            }
            try cursor.space(after: CGFloat(theme.paragraphSpacingPoints))
        }
    }

    func table(header: [NSAttributedString], rows: [[NSAttributedString]],
               alignments: [String?], indent: CGFloat = 0) throws {
        try perform {
            guard !header.isEmpty, indent.isFinite, indent >= 0, indent < cursor.content.width,
                  rows.allSatisfy({ $0.count == header.count }) else {
                throw PDFPageCursor.PageError.invalidGeometry
            }
            try beginStructureGroup(.table)
            let padding: CGFloat = 6
            let headerCount = header.count
            typealias CellRenderer = (PDFTextTypesetter.Line, CGPoint) throws -> Void
            func cellRenderers(header: Bool, repeated: Bool = false) throws -> [CellRenderer?] {
                guard taggedStructure && !repeated else { return Array(repeating: nil, count: headerCount) }
                try beginStructureGroup(.tableRow)
                var result: [CellRenderer?] = []
                if #available(iOS 27.0, macOS 27.0, *) {
                    guard let parent = structureParents.last as? PDFStructureDocumentRoot else {
                        throw WriterError.invalidStructure
                    }
                    for _ in 0..<headerCount {
                        let structure = try PDFParagraphStructure(context: context,
                            role: header ? .tableHeaderCell : .tableDataCell, parent: parent.element)
                        result.append { line, baseline in try structure.draw(line, context: self.context, baseline: baseline) }
                    }
                } else { throw PDFParagraphStructureUnavailable.unsupportedSystem }
                try endStructureGroup()
                return result
            }
            func border(_ frame: CGRect, alreadyArtifact: Bool = false) {
                if taggedStructure && !alreadyArtifact {
                    if #available(iOS 27.0, macOS 27.0, *) {
                        context.beginNonStructuralMarkedContentSequence(.artifact)
                        context.stroke(frame)
                        context.endMarkedContentSequence()
                        return
                    }
                }
                context.stroke(frame)
            }
            let width = (cursor.content.width - indent) / CGFloat(header.count)
            guard width > padding * 2 else { throw PDFPageCursor.PageError.itemExceedsPage }
            func measure(_ cells: [NSAttributedString]) throws -> ([PDFParagraphLayout], CGFloat, CGFloat) {
                let layouts = try cells.map { try PDFParagraphLayout(text: $0, width: width - padding * 2,
                    lineHeight: CGFloat(theme.lineHeight)) }
                let ascents = try cells.map { cell -> CGFloat in
                    var typesetter = try PDFTextTypesetter(text: cell, availableWidth: width - padding * 2,
                                                          lineHeightMultiple: CGFloat(theme.lineHeight))
                    return try typesetter.nextLine()?.ascent ?? 0
                }
                let firstAscent = ascents.max() ?? 0
                let heights = layouts.enumerated().map { index, layout in
                    layout.lineHeights.reduce(0, +) + (layout.lineHeights.isEmpty ? 0 : firstAscent - ascents[index])
                }
                let height = max(CGFloat(theme.bodySizePoints), heights.max() ?? 0) + padding * 2
                return (layouts, height, firstAscent)
            }
            func draw(_ measured: ([PDFParagraphLayout], CGFloat, CGFloat), header: Bool = false,
                      repeated: Bool = false) throws {
                let renderers = try cellRenderers(header: header, repeated: repeated)
                let oldPage = cursor.pageIndex
                let placement = try cursor.placeRectangle(size: CGSize(width: cursor.content.width - indent,
                    height: measured.1), indent: indent)
                openPage()
                if oldPage != placement.pageIndex { context.endPDFPage(); context.beginPDFPage(nil) }
                context.saveGState()
                var artifactOpen = false
                if taggedStructure && repeated {
                    if #available(iOS 27.0, macOS 27.0, *) {
                        context.beginNonStructuralMarkedContentSequence(.artifact); artifactOpen = true
                    }
                }
                defer {
                    if artifactOpen {
                        if #available(iOS 27.0, macOS 27.0, *) { context.endMarkedContentSequence() }
                    }
                    context.restoreGState()
                }
                context.setStrokeColor(CGColor(gray: 0.65, alpha: 1)); context.setLineWidth(0.5)
                for (column, layout) in measured.0.enumerated() {
                    try Task.checkCancellation()
                    let cell = CGRect(x: placement.frame.minX + CGFloat(column) * width,
                        y: placement.frame.minY, width: width, height: measured.1)
                    border(cell, alreadyArtifact: repeated)
                    var top = cell.maxY - padding
                    let fragments: [PDFParagraphBreakPlanner.Fragment] = layout.lineHeights.isEmpty ? [] : [
                        .init(pageOffset: 0, lineRange: layout.lineHeights.indices,
                              height: layout.lineHeights.reduce(0, +))]
                    try layout.forEachLine(in: fragments) { _, index, line in
                        let free = max(0, width - padding * 2 - line.width)
                        let alignment = column < alignments.count ? alignments[column] : nil
                        let offset: CGFloat = alignment == "right" ? free : alignment == "center" ? free / 2 : 0
                        if index == 0 { top -= measured.2 - line.ascent }
                        let baseline = CGPoint(x: cell.minX + padding + offset, y: top - line.ascent)
                        if let renderer = renderers[column] { try renderer(line, baseline) }
                        else { try line.draw(in: context, baseline: baseline) }
                        try line.addLinkAnnotations(in: context, baseline: baseline)
                        top -= layout.lineHeights[index]
                    }
                }
            }
            let head = try measure(header)
            guard head.1 <= cursor.content.height else { throw PDFPageCursor.PageError.itemExceedsPage }
            if let first = rows.first {
                let firstHeight = try measure(first).1
                let previous = cursor.pageIndex
                try cursor.reserve(height: head.1 + min(firstHeight, cursor.content.height - head.1))
                if pageOpen && previous != cursor.pageIndex { context.endPDFPage(); context.beginPDFPage(nil) }
            }
            try draw(head, header: true)
            for row in rows {
                try Task.checkCancellation()
                let measured = try measure(row)
                if head.1 + measured.1 > cursor.content.height {
                    let metrics = measured.0.map { layout in
                        layout.lineHeights.indices.map {
                            PDFTableRowPlanner.Line(height: layout.lineHeights[$0], ascent: layout.lineAscents[$0])
                        }
                    }
                    let capacity = cursor.content.height - head.1
                    let plan = try PDFTableRowPlanner().fragments(cells: metrics,
                        firstPageHeight: min(cursor.remainingHeight, capacity), pageHeight: capacity,
                        maximumPages: cursor.remainingPageCount)
                    let renderers = try cellRenderers(header: false)
                    var streams = try measured.0.map { try $0.streamingTypesetter() }
                    var offsets = measured.0.map { _ in 0 }
                    let startPage = cursor.pageIndex
                    for fragment in plan {
                        try Task.checkCancellation()
                        while cursor.pageIndex < startPage + fragment.pageOffset {
                            try cursor.advancePage(); context.endPDFPage(); context.beginPDFPage(nil)
                            try draw(head, header: true, repeated: true)
                        }
                        let placement = try cursor.placeRectangle(size: CGSize(width: cursor.content.width - indent,
                            height: fragment.height), indent: indent)
                        guard placement.pageIndex == startPage + fragment.pageOffset else {
                            throw PDFTextTypesetter.LayoutError.invalidBreak
                        }
                        context.saveGState()
                        context.setStrokeColor(CGColor(gray: 0.65, alpha: 1)); context.setLineWidth(0.5)
                        for column in streams.indices {
                            let cell = CGRect(x: placement.frame.minX + CGFloat(column) * width,
                                y: placement.frame.minY, width: width, height: fragment.height)
                            border(cell)
                            var top = cell.maxY - padding
                            let range = fragment.cellRanges[column]
                            guard offsets[column] == range.lowerBound else { throw PDFTextTypesetter.LayoutError.invalidBreak }
                            for index in range {
                                guard let line = try streams[column].nextLine() else { throw PDFTextTypesetter.LayoutError.invalidBreak }
                                if index == range.lowerBound { top -= fragment.firstAscent - line.ascent }
                                let free = max(0, width - padding * 2 - line.width)
                                let alignment = column < alignments.count ? alignments[column] : nil
                                let offset: CGFloat = alignment == "right" ? free : alignment == "center" ? free / 2 : 0
                                let baseline = CGPoint(x: cell.minX + padding + offset, y: top - line.ascent)
                                if let renderer = renderers[column] { try renderer(line, baseline) }
                                else { try line.draw(in: context, baseline: baseline) }
                                try line.addLinkAnnotations(in: context, baseline: baseline)
                                top -= measured.0[column].lineHeights[index]; offsets[column] += 1
                            }
                        }
                        context.restoreGState()
                    }
                    for column in streams.indices {
                        guard offsets[column] == measured.0[column].lineHeights.count,
                              try streams[column].nextLine() == nil else { throw PDFTextTypesetter.LayoutError.invalidBreak }
                    }
                    continue
                }
                if measured.1 > cursor.remainingHeight {
                    try cursor.advancePage()
                    context.endPDFPage(); context.beginPDFPage(nil)
                    try draw(head, header: true, repeated: true)
                }
                try draw(measured)
            }
            try endStructureGroup()
            keepNextParagraph = false
            try cursor.space(after: CGFloat(theme.paragraphSpacingPoints))
        }
    }

    func rule(indent: CGFloat = 0) throws {
        try perform {
            guard indent.isFinite, indent >= 0, indent < cursor.content.width else {
                throw PDFPageCursor.PageError.invalidGeometry
            }
            let previousPage = cursor.pageIndex
            let placement = try cursor.placeRectangle(size: CGSize(width: cursor.content.width - indent, height: 24), indent: indent)
            openPage()
            if previousPage != placement.pageIndex { context.endPDFPage(); context.beginPDFPage(nil) }
            context.saveGState()
            context.setStrokeColor(CGColor(gray: 0.5, alpha: 1))
            context.setLineWidth(0.75)
            context.move(to: CGPoint(x: placement.frame.minX, y: placement.frame.midY))
            context.addLine(to: CGPoint(x: placement.frame.maxX, y: placement.frame.midY))
            context.strokePath()
            context.restoreGState()
        }
    }

    func finish() throws -> Data {
        guard !closed else { throw WriterError.closed }
        do {
            try Task.checkCancellation()
            guard !taggedStructure || structureParents.count == 1 else { throw WriterError.invalidStructure }
            openPage() // A valid empty document has one page.
            close()
            return try PDFCrossReferenceFinalizer.finalize(bytes as Data)
        } catch { close(); throw error }
    }

    private func perform(_ operation: () throws -> Void) throws {
        guard !closed else { throw WriterError.closed }
        do { try Task.checkCancellation(); try operation() }
        catch { close(); throw error }
    }
    private func openPage() {
        if !pageOpen { context.beginPDFPage(nil); pageOpen = true }
    }
    private func close() {
        guard !closed else { return }
        if pageOpen { context.endPDFPage(); pageOpen = false }
        context.closePDF(); closed = true
    }
}

enum PDFParagraphStructureUnavailable: Error { case unsupportedSystem }
