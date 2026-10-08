import Foundation

struct HTMLRenderer {
    let document: SemanticDocument
    let profile: ExportProfile
    let packaged: Bool
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
            case .footnote(let id): return "<sup><a href=\"#note-\(noteNumber(id))\"\(packaged ? " epub:type=\"noteref\"" : "")>\(noteNumber(id))</a></sup>"
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
            }
        }.joined()
    }
    mutating func content() -> String {
        var body = blocks(document.blocks)
        if !document.footnotes.isEmpty {
            body += "<section\(packaged ? " epub:type=\"footnotes\"" : "") aria-label=\"Footnotes\"><hr />"
            for (index, note) in document.footnotes.enumerated() { body += "<aside id=\"note-\(index + 1)\"\(packaged ? " epub:type=\"footnote\"" : "")><p>\(index + 1).</p>\(blocks(note.1))</aside>" }
            body += "</section>"
        }
        return body
    }
    mutating func html() -> String {
        let body = content()
        let csp = packaged ? "" : "<meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'none'; img-src data:; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'\" />"
        return """
        \(packaged ? "<?xml version=\"1.0\" encoding=\"UTF-8\"?>" : "<!DOCTYPE html>")
        <html xmlns="http://www.w3.org/1999/xhtml"\(packaged ? " xmlns:epub=\"http://www.idpf.org/2007/ops\"" : "") lang="\(escape(document.input.language))" xml:lang="\(escape(document.input.language))"><head><meta charset="utf-8" /><meta name="viewport" content="width=device-width, initial-scale=1" />\(csp)<title>\(escape(document.input.title))</title>\(packaged ? "<link rel=\"stylesheet\" type=\"text/css\" href=\"style.css\" />" : "<style>\(css(profile))</style>")</head><body><main>\(body)</main></body></html>
        """
    }
}
func css(_ profile: ExportProfile) -> String {
    let font = profile == .manuscript ? "monospace" : "Georgia,serif"
    let spacing = profile == .manuscript ? "2" : "1.65"
    return "body{font-family:\(font);line-height:\(spacing);max-width:42rem;margin:2rem auto;padding:0 1.2rem;color:#17202a;background:#fff}h1,h2,h3,h4,h5,h6{line-height:1.25;break-after:avoid}pre{white-space:pre-wrap;background:#f3f4f5;padding:1rem}code{font-family:monospace}blockquote{border-left:3px solid #889;padding-left:1rem;margin-left:0}table{border-collapse:collapse;width:100%}th,td{border:1px solid #aaa;padding:.4rem;text-align:left}img{max-width:100%;height:auto}aside{font-size:.9em}a{color:#164d88}"
}
public enum ExportEngine {
    public static func renderHTML(_ input: ExportInput, profile: ExportProfile = .standard) throws -> ExportArtifact { try export(input, format: .html, profile: profile) }
    public static func export(_ input: ExportInput, format: ExportFormat, profile: ExportProfile = .standard) throws -> ExportArtifact {
        var parser = SemanticParser(input: input); let document = try parser.parse()
        switch format {
        case .html: var renderer = HTMLRenderer(document: document, profile: profile, packaged: false); return ExportArtifact(data: Data(renderer.html().utf8), fileExtension: "html", mediaType: "text/html", warnings: document.warnings)
        case .docx: return ExportArtifact(data: try DOCXRenderer(document: document, profile: profile).archive(), fileExtension: "docx", mediaType: "application/vnd.openxmlformats-officedocument.wordprocessingml.document", warnings: document.warnings)
        case .epub: return ExportArtifact(data: try EPUBRenderer(document: document, profile: profile).archive(), fileExtension: "epub", mediaType: "application/epub+zip", warnings: document.warnings)
        }
    }
}
