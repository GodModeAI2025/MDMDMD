import Foundation

/// The iOS27 Quartz serializer writes Figure alternative text as /AltText.
/// Normalize only that top-level structure dictionary key, never strings,
/// nested dictionaries or streams. Replacement has identical byte length.
enum PDFStructureAttributeNormalizer {
    static func normalize(_ data: Data, objectStarts: [Int], xrefOffset: Int) throws -> Data {
        let bytes = [UInt8](data)
        let starts = objectStarts.sorted()
        var result = data
        for (index, start) in starts.enumerated() {
            try Task.checkCancellation()
            let end = index + 1 < starts.count ? starts[index + 1] : xrefOffset
            guard start >= 0, end <= bytes.count, start < end else {
                throw PDFCrossReferenceFinalizer.ValidationError.invalidEntry
            }
            let names = try topLevelNames(bytes, range: start..<end)
            guard let role = names.firstIndex(where: { $0.name == "S" }), role + 1 < names.count,
                  names[role + 1].name == "Figure", !names.contains(where: { $0.name == "Alt" }) else { continue }
            for token in names where token.name == "AltText" {
                result.replaceSubrange(token.range, with: Data("/Alt    ".utf8))
            }
        }
        return result
    }
    private struct Name {
        let name: String
        let range: Range<Int>
    }
    private static func topLevelNames(_ bytes: [UInt8], range: Range<Int>) throws -> [Name] {
        var i = range.lowerBound, depth = 0, names: [Name] = []
        func delimiter(_ byte: UInt8) -> Bool {
            [0, 9, 10, 12, 13, 32, 40, 41, 60, 62, 91, 93, 123, 125, 47, 37].contains(byte)
        }
        while i < range.upperBound {
            if i & 4095 == 0 { try Task.checkCancellation() }
            switch bytes[i] {
            case 37: // comment
                while i < range.upperBound && bytes[i] != 10 && bytes[i] != 13 { i += 1 }
            case 40: // literal string, including escaped/nested parentheses
                i += 1; var parentheses = 1
                while i < range.upperBound && parentheses > 0 {
                    if bytes[i] == 92 { i = min(range.upperBound, i + 2); continue }
                    if bytes[i] == 40 { parentheses += 1 }
                    if bytes[i] == 41 { parentheses -= 1 }
                    i += 1
                }
            case 60:
                if i + 1 < range.upperBound && bytes[i + 1] == 60 { depth += 1; i += 2 }
                else { i += 1; while i < range.upperBound && bytes[i] != 62 { i += 1 }; i += 1 }
            case 62:
                if i + 1 < range.upperBound && bytes[i + 1] == 62 { depth -= 1; i += 2 }
                else { i += 1 }
            case 47:
                let start = i; i += 1
                while i < range.upperBound && !delimiter(bytes[i]) { i += 1 }
                if depth == 1 { names.append(Name(name: String(decoding: bytes[(start + 1)..<i], as: UTF8.self), range: start..<i)) }
            default:
                if delimiter(bytes[i]) { i += 1; continue }
                let start = i
                while i < range.upperBound && !delimiter(bytes[i]) { i += 1 }
                if String(decoding: bytes[start..<i], as: UTF8.self) == "stream" { return [] }
            }
        }
        return names
    }
}
