import Foundation
#if canImport(SkriptumCore)
import SkriptumCore
#endif

public enum WritingBlockKind: String, CaseIterable, Identifiable, Sendable {
    case paragraph, heading, list, checklist, quote, code, table, image
    public var id: String { rawValue }
    public var title: String {
        switch self { case .paragraph: "Absatz"; case .heading: "Überschrift"; case .list: "Liste"; case .checklist: "Checkliste"; case .quote: "Zitat"; case .code: "Code"; case .table: "Tabelle"; case .image: "Bild" }
    }
    public var template: String {
        switch self {
        case .paragraph: return "Text\n\n"
        case .heading: return "## Heading\n\n"
        case .list: return "- Item\n\n"
        case .checklist: return "- [ ] Task\n\n"
        case .quote: return "> Quote\n\n"
        case .code: return "```\nCode\n```\n\n"
        case .table: return "| Column | Column |\n| --- | --- |\n| Value | Value |\n\n"
        case .image: return "" // Images require the real media picker, never a template.
        }
    }
}

public struct BlockImageReference: Equatable, Sendable {
    public let altText: String
    public let target: String
    public init?(_ source: String) {
        let body = BlockProjection.imageBody(source)
        guard !body.isEmpty else { return nil }
        guard let expression = try? NSRegularExpression(pattern: #"^!\[((?:\\.|[^\]])*)\]\((media/[^\s)]+)\)$"#),
            let match = expression.firstMatch(in: body, range: NSRange(location: 0, length: body.utf16.count)),
            let altRange = Range(match.range(at: 1), in: body), let targetRange = Range(match.range(at: 2), in: body) else { return nil }
        altText = String(body[altRange]).replacingOccurrences(of: "\\]", with: "]").replacingOccurrences(of: "\\[", with: "[").replacingOccurrences(of: "\\\\", with: "\\")
        target = String(body[targetRange])
        guard UUID(uuidString: String(target.dropFirst("media/".count))) != nil else { return nil }
    }
}

/// A reversible projection of a single block. Only edited content is rebuilt;
/// original line endings, syntax prefixes, and paragraph separators survive.
public struct BlockProjection: Sendable {
    public let kind: WritingBlockKind
    public let headingLevel: Int
    public let text: String
    public let suffix: String
    private let prefixes: [String]
    private let endings: [String]
    private let opening: String
    private let closing: String
    private let original: String

    fileprivate static func imageBody(_ source: String) -> String {
        // Only strip the block's trailing separators for classification.
        // The reversible projection continues to own their original bytes.
        let lines = source.components(separatedBy: "\n")
        guard let first = lines.first, lines.dropFirst().allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { return "" }
        return first.hasSuffix("\r") ? String(first.dropLast()) : first
    }

    public init(_ markdown: String) {
        original = markdown
        var lines: [(String, String)] = []
        // CRLF is one Swift Character, so searching Character("\n") misses
        // it entirely. Split at the ASCII LF byte, never at grapheme boundaries.
        let bytes = Array(markdown.utf8)
        var position = 0
        while position < bytes.count {
            let end = bytes[position...].firstIndex(of: 10) ?? bytes.count
            let carriageReturn = end > position && bytes[end - 1] == 13
            let contentEnd = carriageReturn ? end - 1 : end
            let content = String(decoding: bytes[position..<contentEnd], as: UTF8.self)
            let ending = (carriageReturn ? "\r" : "") + (end < bytes.count ? "\n" : "")
            lines.append((content, ending))
            position = end < bytes.count ? end + 1 : end
        }
        var tail = ""
        while let last = lines.last, last.0.trimmingCharacters(in: .whitespaces).isEmpty {
            tail = last.0 + last.1 + tail; lines.removeLast()
        }
        if let last = lines.last { tail = last.1 + tail; lines[lines.count - 1].1 = "" }
        suffix = tail
        let first = lines.first?.0 ?? ""
        let fence = first.prefix(while: { $0 == "`" || $0 == "~" })
        var start = "", finish = "", detected = WritingBlockKind.paragraph, level = 0
        if fence.count >= 3 {
            detected = .code; start = first + (lines.first?.1 ?? "\n"); lines.removeFirst()
            if let last = lines.last, last.0.hasPrefix(String(fence)) {
                finish = (lines.count > 1 ? lines[lines.count - 2].1 : (start.hasSuffix("\r\n") ? "\r\n" : "\n")) + last.0
                lines.removeLast()
                if !lines.isEmpty { lines[lines.count - 1].1 = "" }
            }
        } else if lines.count == 1, BlockImageReference(first) != nil { detected = .image }
        else if first.hasPrefix("|") && lines.count > 1 && lines[1].0.contains("---") { detected = .table }
        else if let match = first.range(of: "^#{1,6} ", options: .regularExpression) {
            detected = .heading; level = first[match].count - 1
        } else if first.range(of: "^\\s*[-+*] \\[[ xX]\\] ", options: .regularExpression) != nil { detected = .checklist }
        else if first.range(of: "^\\s*(?:[-+*]|[0-9]+[.)]) ", options: .regularExpression) != nil { detected = .list }
        else if first.hasPrefix("> ") { detected = .quote }
        kind = detected; headingLevel = level; opening = start; closing = finish
        var content: [String] = [], markers: [String] = [], separators: [String] = []
        for line in lines {
            let pattern: String?
            switch detected {
            case .heading: pattern = "^#{1,6} "
            case .checklist: pattern = "^\\s*[-+*] \\[[ xX]\\] "
            case .list: pattern = "^\\s*(?:[-+*]|[0-9]+[.)]) "
            case .quote: pattern = "^> ?"
            default: pattern = nil
            }
            let prefix = pattern.flatMap { line.0.range(of: $0, options: .regularExpression) }.map { String(line.0[$0]) } ?? ""
            markers.append(prefix); separators.append(line.1); content.append(String(line.0.dropFirst(prefix.count)))
        }
        prefixes = markers; endings = separators; text = content.joined(separator: "\n")
    }

    public func replacingText(_ value: String) -> String {
        if value.utf8.elementsEqual(text.utf8) { return original }
        let lines = value.components(separatedBy: "\n")
        let fallback: String
        switch kind {
        case .heading: fallback = String(repeating: "#", count: max(1, headingLevel)) + " "
        case .list: fallback = "- "
        case .checklist: fallback = "- [ ] "
        case .quote: fallback = "> "
        default: fallback = ""
        }
        let newline = endings.first(where: { !$0.isEmpty }) ?? (suffix.contains("\r\n") ? "\r\n" : "\n")
        return opening + lines.enumerated().map { index, line in
            let prefix = index < prefixes.count ? prefixes[index] : fallback
            let ending = index == lines.count - 1 ? "" : (index < endings.count && !endings[index].isEmpty ? endings[index] : newline)
            return prefix + line + ending
        }.joined() + closing + suffix
    }

    /// Maps a selection in the visible content to the UTF-16 source coordinate.
    public func sourceOffset(for offset: Int) -> Int {
        var visible = 0, source = opening.utf16.count
        let lines = text.components(separatedBy: "\n")
        for (index, line) in lines.enumerated() {
            source += index < prefixes.count ? prefixes[index].utf16.count : 0
            let length = line.utf16.count
            if offset <= visible + length { return source + max(0, offset - visible) }
            visible += length + 1
            source += length + (index < endings.count ? endings[index].utf16.count : 1)
        }
        return source
    }
}

public enum BlockEditing {
    /// A failed domain transaction never changes the local canonical draft.
    public static func acceptedProposal(_ proposed: [Block], accept: (([Block]) -> Bool)?) -> [Block]? {
        guard accept?(proposed) ?? true else { return nil }
        return proposed
    }
    /// Use persisted identity verbatim whenever the canonical bytes agree.
    /// Reconcile only a genuinely changed external source against its old IDs.
    public static func initialBlocks(markdown: String, stored: [Block]?) -> [Block] {
        if let stored, !stored.isEmpty, stored.map(\.markdown).joined().utf8.elementsEqual(markdown.utf8) { return stored }
        return MarkdownReconciler.reconcile(markdown, previous: stored ?? [])
    }
    public static func replacing(_ blocks: [Block], id: UUID, text: String) -> [Block] {
        var result = blocks
        guard let index = result.firstIndex(where: { $0.id == id }) else { return result }
        result[index].markdown = BlockProjection(result[index].markdown).replacingText(text)
        return result
    }
    public static func moving(_ blocks: [Block], id: UUID, before destination: UUID) -> [Block] {
        guard id != destination, let source = blocks.firstIndex(where: { $0.id == id }) else { return blocks }
        var result = blocks; let block = result.remove(at: source)
        guard let index = result.firstIndex(where: { $0.id == destination }) else { return blocks }
        result.insert(block, at: index); return boundaries(result)
    }
    public static func moving(_ blocks: [Block], id: UUID, direction: Int) -> [Block] {
        guard let source = blocks.firstIndex(where: { $0.id == id }), blocks.indices.contains(source + direction) else { return blocks }
        var result = blocks; result.swapAt(source, source + direction); return boundaries(result)
    }
    public static func duplicating(_ blocks: [Block], id: UUID) -> [Block] {
        guard let source = blocks.firstIndex(where: { $0.id == id }) else { return blocks }
        var result = blocks; result.insert(Block(markdown: separatedCopy(blocks[source].markdown)), at: source + 1); return boundaries(result)
    }
    public static func deleting(_ blocks: [Block], id: UUID) -> [Block] {
        let result = blocks.filter { $0.id != id }; return result.isEmpty ? [Block(markdown: "")] : result
    }
    public static func inserting(_ blocks: [Block], after id: UUID?, markdown: String) -> [Block] {
        var result = blocks
        let index = id.flatMap { id in result.firstIndex(where: { $0.id == id }) }.map { $0 + 1 } ?? result.count
        if index > 0, !result[index - 1].markdown.isEmpty {
            result[index - 1].markdown = separatedCopy(result[index - 1].markdown)
        }
        result.insert(Block(markdown: markdown), at: index); return result
    }
    private static func separatedCopy(_ source: String) -> String {
        if source.hasSuffix("\n\n") || source.hasSuffix("\r\n\r\n") { return source }
        let newline = source.contains("\r\n") ? "\r\n" : "\n"
        return source + (source.hasSuffix(newline) ? newline : newline + newline)
    }
    private static func boundaries(_ blocks: [Block]) -> [Block] {
        var result = blocks
        for index in result.indices.dropLast() where !result[index].markdown.isEmpty {
            result[index].markdown = separatedCopy(result[index].markdown)
        }
        return result
    }
    public static func togglingTask(_ blocks: [Block], id: UUID, line: Int) -> [Block] {
        guard let index = blocks.firstIndex(where: { $0.id == id }) else { return blocks }
        var lines = blocks[index].markdown.components(separatedBy: "\n")
        guard lines.indices.contains(line), let range = lines[line].range(of: "(?<=\\[)[ xX](?=\\])", options: .regularExpression),
            lines[line].range(of: "^\\s*[-+*] \\[[ xX]\\] ", options: .regularExpression) != nil else { return blocks }
        lines[line].replaceSubrange(range, with: lines[line][range] == " " ? "x" : " ")
        var result = blocks; result[index].markdown = lines.joined(separator: "\n"); return result
    }
}
