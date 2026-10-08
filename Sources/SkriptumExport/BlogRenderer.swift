import Foundation

public struct BlogContent: Equatable, Sendable {
    public let html: String
    public let plainText: String
    public let warnings: [String]
}

extension ExportEngine {
    /// Clipboard-ready semantic fragment. Relative media references require the blog ZIP.
    /// The caller chooses where to paste; this API never publishes or accesses a service.
    public static func blogContent(_ input: ExportInput, profile: ExportProfile = .standard) throws -> BlogContent {
        var parser = SemanticParser(input: input)
        let document = try parser.parse()
        return BlogRenderer(document: document, profile: profile).content()
    }
}

struct BlogRenderer {
    let document: SemanticDocument
    let profile: ExportProfile
    private struct Metadata: Encodable {
        let title: String
        let author: String
        let language: String
        let theme: ExportTheme
        let media: [String]
        let warnings: [String]
    }
    func content() -> BlogContent {
        var renderer = HTMLRenderer(document: document, profile: profile, packaged: true, blog: true)
        let fragment = "<article lang=\"\(escape(document.input.language))\">\(renderer.content())</article>"
        var warnings = document.warnings
        if !document.imagePaths.isEmpty { warnings.append("Images use package-relative paths. A clipboard paste cannot upload media; use the blog ZIP and import its assets into the destination platform.") }
        let theme = document.input.theme ?? .preset(for: profile)
        var text = theme.includeTitle ? document.input.title + "\n\n" : ""
        text += plain(document.blocks)
        for (index, note) in document.footnotes.enumerated() { text += "\n\n[\(index + 1)] " + plain(note.1) }
        return BlogContent(html: fragment, plainText: text, warnings: warnings)
    }
    private func plain(_ blocks: [SemanticBlock]) -> String {
        blocks.map { block in
            switch block {
            case .paragraph(let items), .heading(_, let items): items.map(\.plain).joined()
            case .code(let text, _): text
            case .quote(let children): plain(children)
            case .list(let start, let items): items.enumerated().map { index, item in "\(start.map { String($0 + index) + "." } ?? "•") " + plain(item) }.joined(separator: "\n")
            case .table(let header, let rows, _): ([header] + rows).map { row in row.map { $0.map(\.plain).joined() }.joined(separator: "\t") }.joined(separator: "\n")
            case .toc: exportHeadings(document.blocks).map(\.text).joined(separator: "\n")
            case .rule: "—"
            }
        }.joined(separator: "\n\n")
    }
    func archive() throws -> Data {
        var renderer = HTMLRenderer(document: document, profile: profile, packaged: true, blog: true)
        let fragment = "<article lang=\"\(escape(document.input.language))\">\(renderer.content())</article>"
        let theme = document.input.theme ?? .preset(for: profile)
        let metadata = Metadata(title: document.input.title, author: document.input.author, language: document.input.language, theme: theme, media: document.imagePaths.map(renderer.imageName), warnings: document.warnings)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        var entries = [StoredZIP.Entry(name: "article.html", data: Data(fragment.utf8)), .init(name: "styles.css", data: Data(themeCSS(theme).utf8)), .init(name: "metadata.json", data: try encoder.encode(metadata))]
        for path in document.imagePaths { entries.append(.init(name: renderer.imageName(path), data: document.input.assets[path]!.data)) }
        return try StoredZIP.archive(entries)
    }
}
