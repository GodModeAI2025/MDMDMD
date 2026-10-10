import Foundation
import ImageIO

struct DOCXRenderer {
    var document: SemanticDocument
    let profile: ExportProfile
    var links: [String] = []
    var lists: [(Int, Int?, Int)] = []
    var drawingID = 0
    var headingIndex = 0
    var theme: ExportTheme { document.input.theme ?? .preset(for: profile) }
    func twips(_ mm: Double) -> Int { Int((mm / 25.4 * 1440).rounded()) }
    func toc() -> String {
        "<w:p><w:r><w:t>Contents</w:t></w:r></w:p>" + exportHeadings(document.blocks).map { heading in
            "<w:p><w:pPr><w:ind w:left=\"\((heading.level - 1) * 240)\" /></w:pPr><w:hyperlink w:anchor=\"\(heading.wordID)\"><w:r><w:rPr><w:rStyle w:val=\"Hyperlink\" /></w:rPr><w:t>\(escape(heading.text))</w:t></w:r></w:hyperlink></w:p>"
        }.joined()
    }
    let w = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
    func archive() throws -> Data { var writer = self; return try writer.build() }
    mutating func build() throws -> Data {
        for path in document.imagePaths {
            try Task.checkCancellation()
            guard let asset = document.input.assets[path] else { throw ExportError.missingAsset(path) }
            document.input.assets[path] = try DOCXImageOrientation.normalized(asset, path: path)
        }
        var body = theme.includeTitle ? try paragraph([.text(document.input.title)], style: "Title") : ""
        if theme.includeTOC && !hasTOCMarker(document.blocks) { body += toc() }
        body += try blocks(document.blocks)
        var notes = "<w:footnote w:type=\"separator\" w:id=\"-1\"><w:p><w:r><w:separator /></w:r></w:p></w:footnote><w:footnote w:type=\"continuationSeparator\" w:id=\"0\"><w:p><w:r><w:continuationSeparator /></w:r></w:p></w:footnote>"
        for (index, note) in document.footnotes.enumerated() { notes += "<w:footnote w:id=\"\(index + 1)\"><w:p><w:r><w:rPr><w:rStyle w:val=\"FootnoteReference\" /></w:rPr><w:footnoteRef /></w:r></w:p>\(try blocks(note.1))</w:footnote>" }
        let namespaces = "xmlns:w=\"\(w)\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\" xmlns:wp=\"http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing\" xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" xmlns:pic=\"http://schemas.openxmlformats.org/drawingml/2006/picture\""
        let xml = declaration + "<w:document \(namespaces)><w:body>\(body)<w:sectPr><w:pgSz w:w=\"\(twips(theme.paperSize.widthMM))\" w:h=\"\(twips(theme.paperSize.heightMM))\" /><w:pgMar w:top=\"\(twips(theme.marginsMM))\" w:right=\"\(twips(theme.marginsMM))\" w:bottom=\"\(twips(theme.marginsMM))\" w:left=\"\(twips(theme.marginsMM))\" /></w:sectPr></w:body></w:document>"
        let footnotes = declaration + "<w:footnotes \(namespaces)>\(notes)</w:footnotes>"
        let images = document.imagePaths.enumerated().map { index, path in "<Relationship Id=\"image\(index + 1)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/image\" Target=\"media/\(imageName(path))\" />" }.joined()
        let hyperlinks = links.enumerated().map { index, link in "<Relationship Id=\"link\(index + 1)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink\" Target=\"\(escape(link))\" TargetMode=\"External\" />" }.joined()
        let relations = declaration + "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"styles\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\" /><Relationship Id=\"numbering\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/numbering\" Target=\"numbering.xml\" /><Relationship Id=\"footnotes\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/footnotes\" Target=\"footnotes.xml\" />\(images)\(hyperlinks)</Relationships>"
        let types = declaration + "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\" /><Default Extension=\"xml\" ContentType=\"application/xml\" /><Default Extension=\"png\" ContentType=\"image/png\" /><Default Extension=\"jpg\" ContentType=\"image/jpeg\" /><Override PartName=\"/word/document.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml\" /><Override PartName=\"/word/styles.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml\" /><Override PartName=\"/word/numbering.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml\" /><Override PartName=\"/word/footnotes.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.footnotes+xml\" /><Override PartName=\"/docProps/core.xml\" ContentType=\"application/vnd.openxmlformats-package.core-properties+xml\" /></Types>"
        let rootRels = declaration + "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"document\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"word/document.xml\" /><Relationship Id=\"core\" Type=\"http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties\" Target=\"docProps/core.xml\" /></Relationships>"
        let core = declaration + "<cp:coreProperties xmlns:cp=\"http://schemas.openxmlformats.org/package/2006/metadata/core-properties\" xmlns:dc=\"http://purl.org/dc/elements/1.1/\"><dc:title>\(escape(document.input.title))</dc:title><dc:creator>\(escape(document.input.author))</dc:creator><dc:language>\(escape(document.input.language))</dc:language></cp:coreProperties>"
        var entries: [StoredZIP.Entry] = [("[Content_Types].xml", types), ("_rels/.rels", rootRels), ("docProps/core.xml", core), ("word/document.xml", xml), ("word/styles.xml", styles()), ("word/numbering.xml", numbering()), ("word/footnotes.xml", footnotes), ("word/_rels/document.xml.rels", relations), ("word/_rels/footnotes.xml.rels", relations)].map { .init(name: $0.0, data: Data($0.1.utf8)) }
        for path in document.imagePaths { entries.append(.init(name: "word/media/" + imageName(path), data: document.input.assets[path]!.data)) }
        return try StoredZIP.archive(entries)
    }
    var declaration: String { "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>" }
    func imageName(_ path: String) -> String { "image\((document.imagePaths.firstIndex(of: path) ?? 0) + 1).\(document.input.assets[path]?.mediaType == "image/png" ? "png" : "jpg")" }
    func run(_ text: String, properties: String = "") -> String { "<w:r>\(properties.isEmpty ? "" : "<w:rPr>" + properties + "</w:rPr>")<w:t xml:space=\"preserve\">\(escape(text))</w:t></w:r>" }
    mutating func inline(_ items: [Inline], properties: String = "") throws -> String {
        try items.map { item in
            switch item {
            case .text(let text): return run(text, properties: properties)
            case .code(let text): return run(text, properties: properties + "<w:rFonts w:ascii=\"Courier New\" w:hAnsi=\"Courier New\" />")
            case .emphasis(let a): return try inline(a, properties: properties + "<w:i />")
            case .strong(let a): return try inline(a, properties: properties + "<w:b />")
            case .strike(let a): return try inline(a, properties: properties + "<w:strike />")
            case .softBreak: return run(" ", properties: properties)
            case .lineBreak: return "<w:r><w:br /></w:r>"
            case .footnote(let id): let number = (document.footnotes.firstIndex(where: { $0.0 == id }) ?? 0) + 1; return "<w:r><w:rPr><w:rStyle w:val=\"FootnoteReference\" /></w:rPr><w:footnoteReference w:id=\"\(number)\" /></w:r>"
            case .link(let url, let content):
                if url.hasPrefix("#") { return "<w:hyperlink w:anchor=\"\(escape(String(url.dropFirst()).replacingOccurrences(of: "heading-", with: "heading_")))\">\(try inline(content, properties: properties + "<w:rStyle w:val=\"Hyperlink\" />"))</w:hyperlink>" }
                if !links.contains(url) { links.append(url) }; let index = links.firstIndex(of: url)! + 1
                return "<w:hyperlink r:id=\"link\(index)\">\(try inline(content, properties: properties + "<w:rStyle w:val=\"Hyperlink\" />"))</w:hyperlink>"
            case .image(let path, let alt): return try image(path, alt: alt)
            }
        }.joined()
    }
    mutating func image(_ path: String, alt: String) throws -> String {
        guard let asset = document.input.assets[path], let source = CGImageSourceCreateWithData(asset.data as CFData, nil), let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any], let width = properties[kCGImagePropertyPixelWidth] as? NSNumber, let height = properties[kCGImagePropertyPixelHeight] as? NSNumber, width.doubleValue > 0, height.doubleValue > 0 else { throw ExportError.unsupportedAsset(path) }
        let availableWidth = (theme.paperSize.widthMM - 2 * theme.marginsMM) / 25.4 * 914400
        let availableHeight = (theme.paperSize.heightMM - 2 * theme.marginsMM) / 25.4 * 914400
        // Match CSS natural image sizing at 96 pixels per inch; never upscale.
        let scale = min(9525, availableWidth / width.doubleValue, availableHeight / height.doubleValue)
        let cx = max(1, Int(width.doubleValue * scale)), cy = max(1, Int(height.doubleValue * scale)); drawingID += 1
        let imageID = (document.imagePaths.firstIndex(of: path) ?? 0) + 1
        return "<w:r><w:drawing><wp:inline><wp:extent cx=\"\(cx)\" cy=\"\(cy)\" /><wp:docPr id=\"\(drawingID)\" name=\"Image \(drawingID)\" descr=\"\(escape(alt))\" /><a:graphic><a:graphicData uri=\"http://schemas.openxmlformats.org/drawingml/2006/picture\"><pic:pic><pic:nvPicPr><pic:cNvPr id=\"\(drawingID)\" name=\"\(escape(alt))\" /><pic:cNvPicPr /></pic:nvPicPr><pic:blipFill><a:blip r:embed=\"image\(imageID)\" /><a:stretch><a:fillRect /></a:stretch></pic:blipFill><pic:spPr><a:xfrm><a:off x=\"0\" y=\"0\" /><a:ext cx=\"\(cx)\" cy=\"\(cy)\" /></a:xfrm><a:prstGeom prst=\"rect\"><a:avLst /></a:prstGeom></pic:spPr></pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing></w:r>"
    }
    mutating func paragraph(_ content: [Inline], style: String = "Normal", numbering: (Int, Int)? = nil, quote: Bool = false, alignment: String? = nil) throws -> String {
        let num = numbering.map { "<w:numPr><w:ilvl w:val=\"\($0.1)\" /><w:numId w:val=\"\($0.0)\" /></w:numPr>" } ?? ""
        return "<w:p><w:pPr><w:pStyle w:val=\"\(style)\" />\(alignment.map { "<w:jc w:val=\"\($0)\" />" } ?? "")\(num)\(quote ? "<w:ind w:left=\"720\" />" : "")</w:pPr>\(try inline(content))</w:p>"
    }
    mutating func blocks(_ blocks: [SemanticBlock], depth: Int = 0, quote: Bool = false) throws -> String {
        var output = ""
        for block in blocks {
            try Task.checkCancellation()
            switch block {
            case .paragraph(let a): output += try paragraph(a, quote: quote)
            case .heading(let level, let a):
                headingIndex += 1
                let p = try paragraph(a, style: "Heading\(level)", quote: quote)
                let bookmark = "<w:bookmarkStart w:id=\"\(headingIndex)\" w:name=\"heading_\(headingIndex)\" /><w:bookmarkEnd w:id=\"\(headingIndex)\" />"
                output += p.replacingOccurrences(of: "</w:pPr>", with: "</w:pPr>" + bookmark)
            case .toc: output += toc()
            case .code(let text, _): for line in text.components(separatedBy: "\n") { output += try paragraph([.text(line)], style: "Code") }
            case .quote(let children): output += try self.blocks(children, depth: depth, quote: true)
            case .rule: output += "<w:p><w:pPr><w:pBdr><w:bottom w:val=\"single\" w:sz=\"4\" /></w:pBdr></w:pPr></w:p>"
            case .list(let start, let items):
                guard depth < 9 else { throw ExportError.unsupportedMarkdown("DOCX lists deeper than nine levels") }
                let id = lists.count + 1; lists.append((id, start, depth))
                for item in items {
                    var first = true
                    for child in item {
                        if first, case .paragraph(let a) = child { output += try paragraph(a, numbering: (id, depth)); first = false }
                        else { if first { output += try paragraph([], numbering: (id, depth)); first = false }; output += try self.blocks([child], depth: depth + 1, quote: quote) }
                    }
                    if first { output += try paragraph([], numbering: (id, depth)) }
                }
            case .table(let header, let rows, let alignments):
                output += "<w:tbl><w:tblPr><w:tblW w:w=\"0\" w:type=\"auto\" /><w:tblBorders>" + ["top", "left", "bottom", "right", "insideH", "insideV"].map { "<w:\($0) w:val=\"single\" w:sz=\"4\" />" }.joined() + "</w:tblBorders></w:tblPr>"
                for (index, row) in ([header] + rows).enumerated() { output += "<w:tr>\(index == 0 ? "<w:trPr><w:tblHeader /></w:trPr>" : "")"; for (column, cell) in row.enumerated() { output += "<w:tc><w:tcPr><w:tcW w:w=\"0\" w:type=\"auto\" /></w:tcPr>\(try paragraph(cell, alignment: column < alignments.count ? alignments[column] : nil))</w:tc>" }; output += "</w:tr>" }
                output += "</w:tbl>"
            }
        }
        return output
    }
    func styles() -> String {
        let font = theme.bodyFont.displayName
        let spacing = document.input.theme == nil ? (profile == .manuscript ? 480 : 320) : Int((theme.lineHeight * 240).rounded())
        let headings = (1...6).map { "<w:style w:type=\"paragraph\" w:styleId=\"Heading\($0)\"><w:name w:val=\"heading \($0)\" /><w:basedOn w:val=\"Normal\" /><w:next w:val=\"Normal\" /><w:pPr><w:keepNext /><w:outlineLvl w:val=\"\($0 - 1)\" /><w:spacing w:before=\"240\" w:after=\"120\" /></w:pPr><w:rPr><w:b /><w:color w:val=\"\(theme.headingColorHex)\" /><w:sz w:val=\"\(max(Int((theme.bodySizePoints * 2).rounded()), 40 - $0 * 3))\" /></w:rPr></w:style>" }.joined()
        // Style definitions remain declarative; document text is never HTML-fed.
        return declaration + "<w:styles xmlns:w=\"\(w)\"><w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii=\"\(font)\" w:hAnsi=\"\(font)\" /><w:sz w:val=\"\(Int((theme.bodySizePoints * 2).rounded()))\" /><w:lang w:val=\"\(escape(document.input.language))\" /></w:rPr></w:rPrDefault><w:pPrDefault><w:pPr><w:spacing w:after=\"\(Int((theme.paragraphSpacingPoints * 20).rounded()))\" w:line=\"\(spacing)\" w:lineRule=\"auto\" /></w:pPr></w:pPrDefault></w:docDefaults><w:style w:type=\"paragraph\" w:default=\"1\" w:styleId=\"Normal\"><w:name w:val=\"Normal\" /></w:style><w:style w:type=\"paragraph\" w:styleId=\"Title\"><w:name w:val=\"Title\" /><w:basedOn w:val=\"Normal\" /><w:rPr><w:b /><w:color w:val=\"\(theme.headingColorHex)\" /><w:sz w:val=\"\(Int((theme.bodySizePoints * 3).rounded()))\" /></w:rPr></w:style>\(headings)<w:style w:type=\"paragraph\" w:styleId=\"Code\"><w:name w:val=\"Code\" /><w:basedOn w:val=\"Normal\" /><w:rPr><w:rFonts w:ascii=\"Courier New\" w:hAnsi=\"Courier New\" /><w:sz w:val=\"20\" /></w:rPr></w:style><w:style w:type=\"character\" w:styleId=\"Hyperlink\"><w:name w:val=\"Hyperlink\" /><w:rPr><w:color w:val=\"164D88\" /><w:u w:val=\"single\" /></w:rPr></w:style><w:style w:type=\"character\" w:styleId=\"FootnoteReference\"><w:name w:val=\"Footnote Reference\" /><w:rPr><w:vertAlign w:val=\"superscript\" /></w:rPr></w:style></w:styles>"
    }
    func numbering() -> String {
        var xml = declaration + "<w:numbering xmlns:w=\"\(w)\">"
        for (id, start, depth) in lists {
            xml += "<w:abstractNum w:abstractNumId=\"\(id)\"><w:multiLevelType w:val=\"multilevel\" />"
            for level in 0...8 { xml += "<w:lvl w:ilvl=\"\(level)\"><w:start w:val=\"1\" /><w:numFmt w:val=\"\(start == nil ? "bullet" : "decimal")\" /><w:lvlText w:val=\"\(start == nil ? "•" : "%\(level + 1).")\" /><w:lvlJc w:val=\"left\" /><w:pPr><w:tabs><w:tab w:val=\"num\" w:pos=\"\((level + 1) * 720)\" /></w:tabs><w:ind w:left=\"\((level + 1) * 720)\" w:hanging=\"360\" /></w:pPr></w:lvl>" }
            xml += "</w:abstractNum><w:num w:numId=\"\(id)\"><w:abstractNumId w:val=\"\(id)\" /><w:lvlOverride w:ilvl=\"\(depth)\"><w:startOverride w:val=\"\(start ?? 1)\" /></w:lvlOverride></w:num>"
        }
        return xml + "</w:numbering>"
    }
}
