import Foundation
import Markdown
import ImageIO

public struct ExportAsset: Sendable {
    public var data: Data
    public var mediaType: String
    public init(data: Data, mediaType: String) { self.data = data; self.mediaType = mediaType }
}
public struct ExportInput: Sendable {
    public var title: String
    public var markdown: String
    public var author: String
    public var language: String
    /// Exact relative Markdown paths, resolved by the caller inside its document.
    /// No network fetches or filesystem traversal occur during export.
    public var assets: [String: ExportAsset]
    public init(title: String, markdown: String, author: String = "", language: String = "de", assets: [String: ExportAsset] = [:]) { self.title = title; self.markdown = markdown; self.author = author; self.language = language; self.assets = assets }
}
public enum ExportFormat: String, Sendable, CaseIterable { case html, docx, epub }
public enum ExportProfile: String, Sendable, CaseIterable { case standard, manuscript, ebook }
public struct ExportArtifact: Sendable {
    public var data: Data
    public var fileExtension: String
    public var mediaType: String
    public var warnings: [String]
}
public enum ExportError: Error, Equatable {
    case unsafeURL(String), missingAsset(String), unsupportedAsset(String), unsupportedMarkdown(String), missingFootnote(String), duplicateFootnote(String), invalidMetadata(String), archiveTooLarge
}
indirect enum Inline {
    case text(String), emphasis([Inline]), strong([Inline]), strike([Inline]), code(String), link(String, [Inline]), image(String, String), lineBreak, softBreak, footnote(String)
    var plain: String {
        switch self { case .text(let s), .code(let s): s; case .emphasis(let a), .strong(let a), .strike(let a), .link(_, let a): a.map(\.plain).joined(); case .image(_, let alt): alt; case .lineBreak, .softBreak: "\n"; case .footnote(let id): "[\(id)]" }
    }
}
indirect enum SemanticBlock {
    case paragraph([Inline]), heading(Int, [Inline]), code(String, String?), quote([SemanticBlock]), list(Int?, [[SemanticBlock]]), table([[Inline]], [[[Inline]]], [String?]), rule
}
struct SemanticDocument {
    var input: ExportInput
    var blocks: [SemanticBlock]
    var footnotes: [(String, [SemanticBlock])]
    var warnings: [String]
    var imagePaths: [String]
}
struct SemanticParser {
    var definitions: [String: String] = [:]
    var footnoteOrder: [String] = []
    var warnings: [String] = []
    var images: [String] = []
    var escapedNotes: [String: String] = [:]
    let input: ExportInput
    mutating func parse() throws -> SemanticDocument {
        for (name, value) in [("title", input.title), ("author", input.author), ("markdown", input.markdown)] {
            guard value.unicodeScalars.allSatisfy({ $0.value == 9 || $0.value == 10 || $0.value == 13 || (0x20...0xD7FF).contains($0.value) || (0xE000...0xFFFD).contains($0.value) || (0x10000...0x10FFFF).contains($0.value) }) else { throw ExportError.invalidMetadata(name + " contains XML-incompatible characters") }
        }
        guard !input.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ExportError.invalidMetadata("title") }
        guard !input.language.isEmpty, input.language.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) || $0 == "-" }) else { throw ExportError.invalidMetadata("language") }
        let source = try protectEscapedNotes(extractFootnotes(input.markdown))
        let blocks = try Document(parsing: source).children.map { try block($0) }
        var notes: [(String, [SemanticBlock])] = []
        for id in definitions.keys.sorted() where !footnoteOrder.contains(id) { warnings.append("Unreferenced footnote retained: \(id)"); footnoteOrder.append(id) }
        var index = 0
        while index < footnoteOrder.count {
            let id = footnoteOrder[index]; guard let body = definitions[id] else { throw ExportError.missingFootnote(id) }
            notes.append((id, try Document(parsing: try protectEscapedNotes(body)).children.map { try block($0) })); index += 1
        }
        return SemanticDocument(input: input, blocks: blocks, footnotes: notes, warnings: warnings, imagePaths: images)
    }
    mutating func extractFootnotes(_ source: String) throws -> String {
        let lines = source.components(separatedBy: "\n"); var kept: [String] = []; var i = 0; var fence: String?
        let regex = try NSRegularExpression(pattern: "^ {0,3}\\[\\^([^\\]]+)\\]:[ \\t]*(.*)$")
        while i < lines.count {
            let line = lines[i], trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") { let marker = String(trimmed.prefix(3)); if fence == nil { fence = marker } else if fence == marker { fence = nil }; kept.append(line); i += 1; continue }
            if fence == nil, let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)), let idRange = Range(match.range(at: 1), in: line), let bodyRange = Range(match.range(at: 2), in: line) {
                let id = String(line[idRange]); guard definitions[id] == nil else { throw ExportError.duplicateFootnote(id) }
                var body = String(line[bodyRange]); i += 1
                while i < lines.count {
                    if lines[i].hasPrefix("    ") || lines[i].hasPrefix("\t") { body += "\n" + (lines[i].hasPrefix("\t") ? String(lines[i].dropFirst()) : String(lines[i].dropFirst(4))); i += 1; continue }
                    if lines[i].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        var next = i + 1
                        while next < lines.count && lines[next].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { next += 1 }
                        if next < lines.count && (lines[next].hasPrefix("    ") || lines[next].hasPrefix("\t")) { body += String(repeating: "\n", count: next - i); i = next; continue }
                    }
                    break
                }
                definitions[id] = body; kept.append(""); continue
            }
            kept.append(line); i += 1
        }
        return kept.joined(separator: "\n")
    }
    mutating func block(_ node: any Markup) throws -> SemanticBlock {
        switch node {
        case let h as Heading: return .heading(h.level, try inlines(h))
        case let p as Paragraph: return .paragraph(try inlines(p))
        case let c as CodeBlock: return .code(restoreRaw(c.code), c.language)
        case let q as BlockQuote: return .quote(try q.children.map { try block($0) })
        case let l as OrderedList: return .list(Int(l.startIndex), try l.children.map { try listItem($0) })
        case let l as UnorderedList: return .list(nil, try l.children.map { try listItem($0) })
        case let t as Table:
            let header = try t.children.first(where: { $0 is Table.Head })?.children.map { try inlines($0) } ?? []
            let rows = try t.children.first(where: { $0 is Table.Body })?.children.map { row in try row.children.map { try inlines($0) } } ?? []
            return .table(header, rows, t.columnAlignments.map { $0.map { String(describing: $0) } })
        case is ThematicBreak: return .rule
        case let raw as HTMLBlock: warnings.append("Raw HTML exported as visible text."); return .paragraph([.text(restoreRaw(raw.rawHTML))])
        default: throw ExportError.unsupportedMarkdown(String(describing: type(of: node)))
        }
    }
    mutating func listItem(_ node: any Markup) throws -> [SemanticBlock] {
        var result = try node.children.map { try block($0) }
        if let item = node as? ListItem, let check = item.checkbox {
            let status = Inline.text(check == .checked ? "☑ " : "☐ ")
            if case .paragraph(let content)? = result.first { result[0] = .paragraph([status] + content) }
            else { result.insert(.paragraph([status]), at: 0) }
        }
        return result
    }
    mutating func inlines(_ node: any Markup) throws -> [Inline] { try node.children.flatMap { try inline($0) } }
    mutating func inline(_ node: any Markup) throws -> [Inline] {
        switch node {
        case let text as Text: return try footnoteText(text.string)
        case let code as InlineCode: return [.code(restoreRaw(code.code))]
        case let e as Emphasis: return [.emphasis(try inlines(e))]
        case let s as Strong: return [.strong(try inlines(s))]
        case let s as Strikethrough: return [.strike(try inlines(s))]
        case is LineBreak: return [.lineBreak]
        case is SoftBreak: return [.softBreak]
        case let h as InlineHTML: warnings.append("Raw HTML exported as visible text."); return [.text(restoreRaw(h.rawHTML))]
        case let l as Link:
            let destination = l.destination ?? ""; let label = try inlines(l)
            guard safeLink(destination) else { throw ExportError.unsafeURL(destination) }
            if URLComponents(string: destination)?.scheme == "scriptum" { warnings.append("Dieser Seitenverweis öffnet sich in Scriptum: " + destination) }
            if !destination.hasPrefix("#"), URLComponents(string: destination)?.scheme == nil { warnings.append("Relative document link retained; caller must export its target: \(destination)") }
            return [.link(destination, label)]
        case let image as Image:
            let path = image.source ?? ""
            guard !path.isEmpty, !path.hasPrefix("/"), !path.split(separator: "/").contains(".."), URLComponents(string: path)?.scheme == nil else { throw ExportError.unsupportedAsset(path) }
            guard let asset = input.assets[path] else { throw ExportError.missingAsset(path) }
            guard validImage(asset) else { throw ExportError.unsupportedAsset(path) }
            if !images.contains(path) { images.append(path) }
            return [.image(path, image.plainText)]
        default: throw ExportError.unsupportedMarkdown(String(describing: type(of: node)))
        }
    }
    mutating func protectEscapedNotes(_ source: String) throws -> String {
        let regex = try NSRegularExpression(pattern: #"\\\[\^[^\]]+\]"#)
        var result = source
        for match in regex.matches(in: source, range: NSRange(source.startIndex..., in: source)).reversed() {
            guard let range = Range(match.range, in: source) else { continue }
            var preceding = 0, cursor = range.lowerBound
            while cursor > source.startIndex { cursor = source.index(before: cursor); if source[cursor] == "\\" { preceding += 1 } else { break } }
            guard preceding % 2 == 0 else { continue }
            let token = "SKRIPTUMESCAPEDFOOTNOTE" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
            escapedNotes[token] = String(source[range])
            result.replaceSubrange(range, with: token)
        }
        return result
    }
    func restoreRaw(_ text: String) -> String { escapedNotes.reduce(text) { $0.replacingOccurrences(of: $1.key, with: $1.value) } }
    mutating func footnoteText(_ text: String) throws -> [Inline] {
        for (token, original) in escapedNotes {
            if let range = text.range(of: token) {
                let before = try footnoteText(String(text[..<range.lowerBound]))
                let after = try footnoteText(String(text[range.upperBound...]))
                return before + [.text(String(original.dropFirst()))] + after
            }
        }

        let regex = try NSRegularExpression(pattern: "\\[\\^([^\\]]+)\\]")
        var result: [Inline] = [], start = text.startIndex
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(match.range, in: text), let idRange = Range(match.range(at: 1), in: text) else { continue }
            if start < range.lowerBound { result.append(.text(String(text[start..<range.lowerBound]))) }
            let id = String(text[idRange]); guard definitions[id] != nil else { throw ExportError.missingFootnote(id) }
            if !footnoteOrder.contains(id) { footnoteOrder.append(id) }; result.append(.footnote(id)); start = range.upperBound
        }
        if start < text.endIndex { result.append(.text(String(text[start...]))) }
        return result
    }
}
func safeLink(_ string: String) -> Bool {
    guard !string.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }), !string.contains("\\") else { return false }
    guard let components = URLComponents(string: string) else { return false }
    if let scheme = components.scheme {
        if scheme.lowercased() == "scriptum" { return components.host == "page" && components.user == nil && components.password == nil && components.port == nil && components.query == nil && UUID(uuidString: String(components.path.dropFirst())) != nil }
        return ["https", "http", "mailto", "tel"].contains(scheme.lowercased())
    }
    return !string.hasPrefix("//") && !string.hasPrefix("/") && !string.split(separator: "/").contains("..")
}
func validImage(_ asset: ExportAsset) -> Bool {
    let b = [UInt8](asset.data.prefix(8))
    let signature = asset.mediaType == "image/png" && b == [137,80,78,71,13,10,26,10] || asset.mediaType == "image/jpeg" && b.starts(with: [255,216,255])
    guard signature, asset.data.count <= 50_000_000, let source = CGImageSourceCreateWithData(asset.data as CFData, nil), CGImageSourceGetStatus(source) == .statusComplete, let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any], let width = properties[kCGImagePropertyPixelWidth] as? NSNumber, let height = properties[kCGImagePropertyPixelHeight] as? NSNumber else { return false }
    return width.doubleValue > 0 && height.doubleValue > 0 && width.doubleValue * height.doubleValue <= 50_000_000
}
func escape(_ string: String) -> String {
    string.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;").replacingOccurrences(of: "'", with: "&#39;")
}
