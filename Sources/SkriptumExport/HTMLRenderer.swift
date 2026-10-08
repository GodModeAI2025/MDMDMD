import Foundation

struct HTMLRenderer {
    let document: SemanticDocument
    let profile: ExportProfile
    let packaged: Bool
    var blog = false
    var theme: ExportTheme { document.input.theme ?? .preset(for: profile) }
    var headings: [ExportHeading] { exportHeadings(document.blocks) }
    func toc() -> String { "<nav aria-label=\"Contents\"><ol>" + headings.map { "<li><a href=\"#\($0.htmlID)\">\(escape($0.text))</a></li>" }.joined() + "</ol></nav>" }
    var headingIndex = 0
    var navigation: [(String, String)] = []
    func imageName(_ path: String) -> String { "assets/image\((document.imagePaths.firstIndex(of: path) ?? 0) + 1).\(document.input.assets[path]?.mediaType == "image/png" ? "png" : "jpg")" }
    func noteNumber(_ id: String) -> Int { (document.footnotes.firstIndex(where: { $0.0 == id }) ?? 0) + 1 }
    func inline(_ items: [Inline]) -> String {
        items.map { item in
            switch item {
            case .text(let s): return escape(s)
            case .emphasis(let a): return "<em>\(inline(a))</em>"
            case .strong(let a): return "<strong>\(inline(a))</strong>"
            case .strike(let a): return "<del>\(inline(a))</del>"
            case .code(let s): return "<code>\(escape(s))</code>"
            case .link(let url, let a): return "<a href=\"\(escape(url))\">\(inline(a))</a>"
            case .image(let path, let alt):
                let source: String
                if packaged { source = imageName(path) }
                else if let asset = document.input.assets[path] { source = "data:\(asset.mediaType);base64,\(asset.data.base64EncodedString())" }
                else { source = "" }
                return "<img src=\"\(escape(source))\" alt=\"\(escape(alt))\" />"
            case .lineBreak: return "<br />\n"
            case .softBreak: return "\n"
            case .footnote(let id): return "<sup><a href=\"#note-\(noteNumber(id))\"\(packaged && !blog ? " epub:type=\"noteref\"" : "")>\(noteNumber(id))</a></sup>"
            }
        }.joined()
    }
    mutating func blocks(_ blocks: [SemanticBlock]) -> String {
        blocks.map { block in
            switch block {
            case .paragraph(let items): return "<p>\(inline(items))</p>\n"
            case .heading(let level, let items): headingIndex += 1; let id = "heading-\(headingIndex)"; navigation.append((id, items.map(\.plain).joined())); return "<h\(level) id=\"\(id)\">\(inline(items))</h\(level)>\n"
            case .code(let text, let language): return "<pre><code\(language.map { " class=\"language-\(escape($0))\"" } ?? "")>\(escape(text))</code></pre>\n"
            case .quote(let children): return "<blockquote>\(self.blocks(children))</blockquote>\n"
            case .list(let start, let items): let tag = start == nil ? "ul" : "ol"; let attribute = start.map { " start=\"\($0)\"" } ?? ""; return "<\(tag)\(attribute)>\n" + items.map { "<li>\(self.blocks($0))</li>\n" }.joined() + "</\(tag)>\n"
            case .table(let head, let rows, let alignments):
                func row(_ cells: [[Inline]], tag: String) -> String { cells.enumerated().map { index, cell in let alignment = index < alignments.count ? alignments[index].map { " style=\"text-align:\($0)\"" } ?? "" : ""; return "<\(tag)\(alignment)>\(inline(cell))</\(tag)>" }.joined() }
                return "<table><thead><tr>" + row(head, tag: "th") + "</tr></thead><tbody>" + rows.map { "<tr>" + row($0, tag: "td") + "</tr>" }.joined() + "</tbody></table>\n"
            case .rule: return "<hr />\n"
            case .toc: return toc()
            }
        }.joined()
    }
    mutating func content() -> String {
        var body = theme.includeTitle ? "<header><h1 class=\"document-title\">\(escape(document.input.title))</h1></header>" : ""
        if theme.includeTOC && !hasTOCMarker(document.blocks) { body += toc() }
        body += blocks(document.blocks)
        if !document.footnotes.isEmpty {
            body += "<section\(packaged && !blog ? " epub:type=\"footnotes\"" : "") aria-label=\"Footnotes\"><hr />"
            for (index, note) in document.footnotes.enumerated() { body += "<aside id=\"note-\(index + 1)\"\(packaged && !blog ? " epub:type=\"footnote\"" : "")><p>\(index + 1).</p>\(blocks(note.1))</aside>" }
            body += "</section>"
        }
        return body
    }
    mutating func html() -> String {
        let body = content()
        let csp = packaged ? "" : "<meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'none'; img-src data:; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'\" />"
        return """
        \(packaged ? "<?xml version=\"1.0\" encoding=\"UTF-8\"?>" : "<!DOCTYPE html>")
        <html xmlns="http://www.w3.org/1999/xhtml"\(packaged ? " xmlns:epub=\"http://www.idpf.org/2007/ops\"" : "") lang="\(escape(document.input.language))" xml:lang="\(escape(document.input.language))"><head><meta charset="utf-8" /><meta name="viewport" content="width=device-width, initial-scale=1" />\(csp)<title>\(escape(document.input.title))</title>\(packaged ? "<link rel=\"stylesheet\" type=\"text/css\" href=\"style.css\" />" : "<style>\(themeCSS(theme))</style>")</head><body><main>\(body)</main></body></html>
        """
    }
}
func css(_ profile: ExportProfile) -> String {
    let font = profile == .manuscript ? "monospace" : "Georgia,serif"
    let spacing = profile == .manuscript ? "2" : "1.65"
    return "body{font-family:\(font);line-height:\(spacing);max-width:42rem;margin:2rem auto;padding:0 1.2rem;color:#17202a;background:#fff}h1,h2,h3,h4,h5,h6{line-height:1.25;break-after:avoid-page;page-break-after:avoid;page-break-inside:avoid}p{widows:3;orphans:3}tr{break-inside:avoid;page-break-inside:avoid}pre{white-space:pre-wrap;background:#f3f4f5;padding:1rem}code{font-family:monospace}blockquote{border-left:3px solid #889;padding-left:1rem;margin-left:0}table{border-collapse:collapse;width:100%}th,td{border:1px solid #aaa;padding:.4rem;text-align:left}img{max-width:100%;height:auto}aside{font-size:.9em}a{color:#164d88}"
}
public enum ExportEngine {
    public static func renderHTML(_ input: ExportInput, profile: ExportProfile = .standard) throws -> ExportArtifact { try export(input, format: .html, profile: profile) }
    public static func export(_ input: ExportInput, format: ExportFormat, profile: ExportProfile = .standard) throws -> ExportArtifact {
        var parser = SemanticParser(input: input); let document = try parser.parse()
        return try render(document, format: format, profile: profile)
    }
    /// Parse chapters independently: an unfinished code fence or identically named
    /// footnote in one page must never consume another chapter's content.
    public static func exportManuscript(title: String, chapters: [ExportInput], author: String = "", language: String = "de", format: ExportFormat, profile: ExportProfile = .manuscript, theme: ExportTheme? = nil) throws -> ExportArtifact {
        guard !chapters.isEmpty, chapters.count <= 1000 else { throw ExportError.invalidMetadata("chapters") }
        var metadataParser = SemanticParser(input: ExportInput(title: title, markdown: "", author: author, language: language, theme: theme))
        var combined = try metadataParser.parse()
        for (index, input) in chapters.enumerated() {
            var parser = SemanticParser(input: input)
            let chapter = try parser.parse()
            let prefix = "chapter-\(index + 1)/"
            let mapping = ManuscriptNamespace(prefix: prefix)
            combined.blocks.append(.heading(1, [.text(input.title)]))
            combined.blocks += chapter.blocks.map(mapping.block)
            combined.footnotes += chapter.footnotes.map { (prefix + $0.0, $0.1.map(mapping.block)) }
            combined.warnings += chapter.warnings.map { input.title + ": " + $0 }
            for path in chapter.imagePaths {
                combined.imagePaths.append(prefix + path)
                combined.input.assets[prefix + path] = input.assets[path]
            }
        }
        return try render(combined, format: format, profile: profile)
    }
    private static func render(_ document: SemanticDocument, format: ExportFormat, profile: ExportProfile) throws -> ExportArtifact {
        switch format {
        case .html: var renderer = HTMLRenderer(document: document, profile: profile, packaged: false); return ExportArtifact(data: Data(renderer.html().utf8), fileExtension: "html", mediaType: "text/html", warnings: document.warnings)
        case .docx: return ExportArtifact(data: try DOCXRenderer(document: document, profile: profile).archive(), fileExtension: "docx", mediaType: "application/vnd.openxmlformats-officedocument.wordprocessingml.document", warnings: document.warnings)
        case .blog: return ExportArtifact(data: try BlogRenderer(document: document, profile: profile).archive(), fileExtension: "zip", mediaType: "application/zip", warnings: document.warnings)
        case .epub: return ExportArtifact(data: try EPUBRenderer(document: document, profile: profile).archive(), fileExtension: "epub", mediaType: "application/epub+zip", warnings: document.warnings)
        }
    }
}

private struct ManuscriptNamespace {
    let prefix: String
    func inline(_ value: Inline) -> Inline {
        switch value {
        case .emphasis(let items): return .emphasis(items.map(inline))
        case .strong(let items): return .strong(items.map(inline))
        case .strike(let items): return .strike(items.map(inline))
        case .link(let url, let items): return .link(url, items.map(inline))
        case .image(let path, let alt): return .image(prefix + path, alt)
        case .footnote(let id): return .footnote(prefix + id)
        default: return value
        }
    }
    func block(_ value: SemanticBlock) -> SemanticBlock {
        switch value {
        case .paragraph(let items): return .paragraph(items.map(inline))
        case .heading(let level, let items): return .heading(level, items.map(inline))
        case .quote(let blocks): return .quote(blocks.map(block))
        case .list(let start, let items): return .list(start, items.map { $0.map(block) })
        case .table(let header, let rows, let alignment): return .table(header.map { $0.map(inline) }, rows.map { $0.map { $0.map(inline) } }, alignment)
        default: return value
        }
    }
}
