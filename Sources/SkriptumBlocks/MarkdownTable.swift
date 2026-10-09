import Foundation
import Markdown
public enum TableEditingError: Error, Equatable { case malformed, outOfBounds, invalidCell, lastColumn }
/// A single rectangular GFM table. Row zero in `cells` is the heading;
/// insert/remove row indexes address body rows only. Cell arguments are inline Markdown.
public struct MarkdownTable: Sendable {
    private struct Row: Sendable {
        var prefix: String; var fields: [String]; var suffix: String; var ending: String
        var text: String { prefix + fields.joined(separator: "|") + suffix + ending }
    }
    public let source: String
    private var rows: [Row]
    private let tail: String
    public var cells: [[String]] { rows.enumerated().filter { $0.offset != 1 }.map { $0.element.fields.map(Self.trim) } }
    public var columnCount: Int { rows[0].fields.count }
    public var bodyRowCount: Int { rows.count - 2 }
    public init(_ source: String) throws {
        self.source = source
        let bytes = Array(source.utf8); var lines: [(String, String)] = []; var start = 0
        while start < bytes.count {
            let end = bytes[start...].firstIndex(of: 10) ?? bytes.count
            let cr = end > start && bytes[end - 1] == 13
            lines.append((String(decoding: bytes[start..<(cr ? end - 1 : end)], as: UTF8.self), end < bytes.count ? (cr ? "\r\n" : "\n") : ""))
            start = end < bytes.count ? end + 1 : end
        }
        var suffix = ""
        while let last = lines.last, Self.trim(last.0).isEmpty { suffix = last.0 + last.1 + suffix; lines.removeLast() }
        guard lines.count >= 2 else { throw TableEditingError.malformed }
        rows = try lines.map { try Self.parse($0.0, ending: $0.1) }; tail = suffix
        guard rows.allSatisfy({ $0.fields.count == rows[0].fields.count }), !rows[0].fields.isEmpty,
            rows[1].fields.allSatisfy({ Self.trim($0).range(of: "^:?-{3,}:?$", options: .regularExpression) != nil }) else { throw TableEditingError.malformed }
        let semanticBlocks = Array(Document(parsing: source).children)
        guard semanticBlocks.count == 1, semanticBlocks.first is Markdown.Table else { throw TableEditingError.malformed }
    }
    private static func trim(_ text: String) -> String { text.trimmingCharacters(in: .whitespaces) }
    private static func parse(_ line: String, ending: String) throws -> Row {
        let bytes = Array(line.utf8)
        let indent = bytes.prefix(while: { $0 == 32 }).count
        guard indent <= 3, !bytes.contains(9), !bytes.contains(13) else { throw TableEditingError.malformed }
        var cuts: [Int] = []; var slash = 0; var tickRun = 0; var index = indent
        while index < bytes.count {
            let byte = bytes[index]
            if byte == 96 && slash % 2 == 0 {
                var end = index; while end < bytes.count && bytes[end] == 96 { end += 1 }
                let count = end - index
                if tickRun == 0 {
                    // Unmatched backticks are literal CommonMark text, not code.
                    var cursor = end, matchingClose = false
                    while cursor < bytes.count {
                        if bytes[cursor] == 96 {
                            var runEnd = cursor
                            while runEnd < bytes.count && bytes[runEnd] == 96 { runEnd += 1 }
                            if runEnd - cursor == count { matchingClose = true; break }
                            cursor = runEnd
                        } else { cursor += 1 }
                    }
                    if matchingClose { tickRun = count }
                } else if tickRun == count { tickRun = 0 }
                index = end; slash = 0; continue
            }
            if byte == 124 && slash % 2 == 0 {
                // GFM still requires escaped pipes in code. Reject this ambiguous input.
                let outerTrailingPipe = bytes[(index + 1)...].allSatisfy { $0 == 32 }
                guard tickRun == 0 || outerTrailingPipe else { throw TableEditingError.malformed }
                cuts.append(index)
            }
            slash = byte == 92 ? slash + 1 : 0; index += 1
        }
        guard !cuts.isEmpty else { throw TableEditingError.malformed }
        var begin = indent; var end = bytes.count
        var prefix = String(decoding: bytes[..<indent], as: UTF8.self); var suffix = ""
        if cuts.first == indent { prefix += "|"; begin = indent + 1; cuts.removeFirst() }
        if let last = cuts.last, bytes[(last + 1)...].allSatisfy({ $0 == 32 }) {
            suffix = String(decoding: bytes[last...], as: UTF8.self); end = last; cuts.removeLast()
        }
        var fields: [String] = []; var position = begin
        for cut in cuts { fields.append(String(decoding: bytes[position..<cut], as: UTF8.self)); position = cut + 1 }
        fields.append(String(decoding: bytes[position..<end], as: UTF8.self))
        return Row(prefix: prefix, fields: fields, suffix: suffix, ending: ending)
    }
    private static func validateCell(_ value: String) throws {
        guard !value.contains("\n"), !value.contains("\r"), !value.contains("\t"), Self.trim(value) == value else { throw TableEditingError.invalidCell }
        do { let row = try parse("|" + value + "|", ending: ""); guard row.fields.count == 1 else { throw TableEditingError.invalidCell } }
        catch { throw TableEditingError.invalidCell }
    }
    private static func padding(_ value: String) -> (String, String) {
        if trim(value).isEmpty { let split = value.count / 2; return (String(value.prefix(split)), String(value.dropFirst(split))) }
        return (String(value.prefix(while: { $0 == " " })), String(value.reversed().prefix(while: { $0 == " " }).reversed()))
    }
    private func output(_ changed: [Row]) throws -> String {
        let value = changed.map(\.text).joined() + tail
        if (try? Self(value)) != nil { return value }
        // An explicit cell edit can activate ATX/list/quote/fence/HTML syntax in
        // a pipe-less heading. Delimiters preserve the intended cell content.
        var delimited = changed
        for row in delimited.indices {
            if !delimited[row].prefix.hasSuffix("|") { delimited[row].prefix += "|" }
            if !delimited[row].suffix.hasPrefix("|") { delimited[row].suffix = "|" + delimited[row].suffix }
        }
        let repaired = delimited.map(\.text).joined() + tail
        _ = try Self(repaired)
        return repaired
    }
    public func replacingCell(row: Int, column: Int, markdown: String) throws -> String {
        let index = row == 0 ? 0 : row + 1
        guard row >= 0, rows.indices.contains(index), (0..<columnCount).contains(column) else { throw TableEditingError.outOfBounds }
        try Self.validateCell(markdown)
        var changed = rows; let old = changed[index].fields[column]
        if Self.trim(old).utf8.elementsEqual(markdown.utf8) { return source }
        let padding = Self.padding(old); let left = padding.0; let right = padding.1
        changed[index].fields[column] = String(left) + markdown + String(right)
        return try output(changed)
    }
    public func insertingRow(at index: Int, cells: [String]) throws -> String {
        guard (0...bodyRowCount).contains(index), cells.count == columnCount else { throw TableEditingError.outOfBounds }
        try cells.forEach(Self.validateCell)
        var changed = rows; var row = rows.count > 2 ? rows[2] : rows[0]
        row.fields = cells.enumerated().map { column, value in
            let old = row.fields[column]
            let padding = Self.padding(old)
            return padding.0 + value + padding.1
        }
        let newline = rows.first(where: { !$0.ending.isEmpty })?.ending ?? "\n"
        let insertion = index + 2
        if insertion == changed.count { row.ending = changed.last!.ending; changed[changed.count - 1].ending = newline }
        else { row.ending = newline }
        changed.insert(row, at: insertion); return try output(changed)
    }
    public func removingRow(at index: Int) throws -> String {
        guard (0..<bodyRowCount).contains(index) else { throw TableEditingError.outOfBounds }
        var changed = rows; let actual = index + 2
        if actual == changed.count - 1 { changed[actual - 1].ending = changed[actual].ending }
        changed.remove(at: actual); return try output(changed)
    }
    public func insertingColumn(at index: Int, heading: String, cells: [String]) throws -> String {
        guard (0...columnCount).contains(index), cells.count == bodyRowCount else { throw TableEditingError.outOfBounds }
        try ([heading] + cells).forEach(Self.validateCell)
        var changed = rows
        for row in changed.indices {
            let value = row == 0 ? heading : row == 1 ? "---" : cells[row - 2]
            changed[row].fields.insert(" " + value + " ", at: index)
        }
        return try output(changed)
    }
    public func removingColumn(at index: Int) throws -> String {
        guard (0..<columnCount).contains(index) else { throw TableEditingError.outOfBounds }
        guard columnCount > 1 else { throw TableEditingError.lastColumn }
        var changed = rows
        for row in changed.indices {
            changed[row].fields.remove(at: index)
            if changed[row].fields.count == 1 {
                // A pipe-less one-column row would parse as prose/Setext text.
                // This explicit structural edit adds delimiters, never rewrites
                // surviving field bytes, alignment, indentation or line endings.
                if !changed[row].prefix.hasSuffix("|") { changed[row].prefix += "|" }
                if !changed[row].suffix.hasPrefix("|") { changed[row].suffix = "|" + changed[row].suffix }
            }
        }
        return try output(changed)
    }
}
