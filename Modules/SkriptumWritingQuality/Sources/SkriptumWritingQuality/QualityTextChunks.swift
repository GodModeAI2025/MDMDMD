import Foundation

struct QualityTextChunk: Sendable {
    let text: String
    let range: NSRange
}

/// Contiguous, lossless chunks; whitespace boundaries preserve whole words and
/// Character indices never split a surrogate pair or combining sequence.
enum QualityTextChunks {
    static func make(_ text: String, maximumUTF16: Int = 16_384) throws -> [QualityTextChunk] {
        guard maximumUTF16 > 0 else { throw QualityError.invalidConfiguration }
        var result: [QualityTextChunk] = [], start = text.startIndex, offset = 0
        while start < text.endIndex {
            var cursor = start, count = 0
            var boundary: (String.Index, Int)?
            while cursor < text.endIndex {
                let next = text.index(after: cursor), size = text[cursor..<next].utf16.count
                if count + size > maximumUTF16 { break }
                count += size
                if text[cursor].unicodeScalars.allSatisfy({ CharacterSet.whitespacesAndNewlines.contains($0) }) { boundary = (next, count) }
                cursor = next
            }
            let end: String.Index, length: Int
            if cursor == text.endIndex { end = cursor; length = count }
            else if let boundary { end = boundary.0; length = boundary.1 }
            else { throw QualityError.inputTooLarge }
            guard end > start else { throw QualityError.inputTooLarge }
            result.append(QualityTextChunk(text: String(text[start..<end]), range: NSRange(location: offset, length: length)))
            offset += length; start = end
        }
        return result
    }
}
