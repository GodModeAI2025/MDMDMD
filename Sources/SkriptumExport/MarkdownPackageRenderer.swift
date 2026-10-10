import Foundation
import Markdown

/// Lossless source export. Each chapter owns its relative media namespace;
/// images in fenced/inline code do not cause an attachment to be exported.
enum MarkdownPackageRenderer {
    private static let maximumBytes = 512 * 1024 * 1024
    private struct Manifest: Codable {
        let schemaVersion: Int
        let title: String
        let author: String
        let language: String
        let chapters: [Chapter]
    }
    private struct Chapter: Codable { let title: String; let source: String; let media: [String] }
    static func archive(title: String, chapters: [ExportInput], single: Bool, author: String, language: String) throws -> ExportArtifact {
        guard !chapters.isEmpty, chapters.count <= 1000 else { throw ExportError.invalidMetadata("chapters") }
        var entries: [StoredZIP.Entry] = [], manifest: [Chapter] = [], warnings: [String] = []
        var total = 0
        var archiveNames = Set<String>()
        func append(_ name: String, _ data: Data) throws {
            guard archiveNames.insert(name.lowercased()).inserted else { throw ExportError.unsupportedAsset(name) }
            guard data.count <= maximumBytes - total else { throw ExportError.archiveTooLarge }
            total += data.count; entries.append(.init(name: name, data: data))
        }
        for (index, input) in chapters.enumerated() {
            try Task.checkCancellation()
            guard input.markdown.utf8.count <= 16 * 1024 * 1024 else { throw ExportError.archiveTooLarge }
            let prefix = single ? "" : String(format: "chapters/%03d/", index + 1)
            let sourcePath = prefix + "document.md"
            try append(sourcePath, Data(input.markdown.utf8))
            let document = Document(parsing: input.markdown)
            var stack: [any Markup] = [document], visited = 0, paths: [String] = [], seen = Set<String>()
            var rawHTML = false, relativeLinks = false
            while let node = stack.popLast() {
                try Task.checkCancellation(); visited += 1
                guard visited <= 200_000 else { throw ExportError.archiveTooLarge }
                if let image = node as? Markdown.Image {
                    let path = image.source ?? ""
                    guard safePath(path), !["document.md", "manifest.json", "readme.md"].contains(path.lowercased()) else { throw ExportError.unsupportedAsset(path) }
                    guard let asset = input.assets[path] else { throw ExportError.missingAsset(path) }
                    guard validImage(asset) else { throw ExportError.unsupportedAsset(path) }
                    if seen.insert(path).inserted { paths.append(path); try append(prefix + path, asset.data) }
                }
                if node is HTMLBlock || node is InlineHTML { rawHTML = true }
                if let link = node as? Markdown.Link, let target = link.destination,
                   !target.hasPrefix("#"), URLComponents(string: target)?.scheme == nil { relativeLinks = true }
                stack.append(contentsOf: node.children.reversed())
            }
            if rawHTML { warnings.append("\(input.title): Raw HTML remains in the original source; resources referenced only by HTML are not collected.") }
            if relativeLinks { warnings.append("\(input.title): Relative document links remain unchanged; linked documents are not automatically included.") }
            manifest.append(.init(title: input.title, source: sourcePath, media: paths.map { prefix + $0 }))
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        try append("manifest.json", encoder.encode(Manifest(schemaVersion: 1, title: title, author: author, language: language, chapters: manifest)))
        let index = manifest.enumerated().map { number, chapter in "\(number + 1). [\(label(chapter.title))](\(chapter.source))" }.joined(separator: "\n")
        try append("README.md", Data(("# " + label(title) + "\n\nOriginal Markdown and referenced images.\n\n" + index + "\n").utf8))
        return ExportArtifact(data: try StoredZIP.archive(entries), fileExtension: "zip", mediaType: "application/zip", warnings: warnings)
    }
    private static func label(_ text: String) -> String {
        text.components(separatedBy: .newlines).joined(separator: " ")
            .replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "[", with: "\\[").replacingOccurrences(of: "]", with: "\\]")
    }
    private static func safePath(_ path: String) -> Bool {
        guard path.utf8.count <= 4096 else { return false }
        var value = path
        for _ in 0..<5 {
            guard !value.isEmpty, !value.hasPrefix("/"), !value.hasSuffix("/"), !value.contains("\\"), !value.contains(":"),
                  !value.contains("//"), !value.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }),
                  !value.split(separator: "/").contains(where: { $0 == "." || $0 == ".." }),
                  let parsed = URLComponents(string: value), parsed.scheme == nil, parsed.host == nil,
                  parsed.query == nil, parsed.fragment == nil else { return false }
            guard let decoded = value.removingPercentEncoding else { return false }
            if decoded == value { return true }
            value = decoded
        }
        return false
    }
}

extension ExportEngine {
    public static func markdownPackage(_ input: ExportInput) throws -> ExportArtifact {
        try MarkdownPackageRenderer.archive(title: input.title, chapters: [input], single: true, author: input.author, language: input.language)
    }
    public static func markdownManuscriptPackage(title: String, chapters: [ExportInput], author: String = "", language: String = "de") throws -> ExportArtifact {
        try MarkdownPackageRenderer.archive(title: title, chapters: chapters, single: false, author: author, language: language)
    }
}
