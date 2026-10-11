import Foundation

struct QualityTextChunk: Sendable {
    let text: String
    let range: NSRange
}

/// Contiguous, lossless chunks; whitespace boundaries preserve whole words and
/// Character indices never split a surrogate pair or combining sequence.
enum QualityTextChunks {
    static func make(_ text: String, maximumUTF16: Int = 16_384, preferSentences: Bool = false) throws -> [QualityTextChunk] {
        guard maximumUTF16 > 0 else { throw QualityError.invalidConfiguration }
        var result: [QualityTextChunk] = [], start = text.startIndex, offset = 0
        while start < text.endIndex {
            try Task.checkCancellation()
            var cursor = start, count = 0
            var boundary: (String.Index, Int)?
            var paragraph: (String.Index, Int)?, sentence: (String.Index, Int)?
            var whitespaceSinceNewline = false
            while cursor < text.endIndex {
                let next = text.index(after: cursor), size = text[cursor..<next].utf16.count
                if count + size > maximumUTF16 { break }
                count += size
                if text[cursor].unicodeScalars.allSatisfy({ CharacterSet.whitespacesAndNewlines.contains($0) }) { boundary = (next, count) }
                if preferSentences {
                    let character = text[cursor]
                    let newline = character.unicodeScalars.contains { CharacterSet.newlines.contains($0) }
                    if newline {
                        if whitespaceSinceNewline { paragraph = (next, count) }
                        whitespaceSinceNewline = true
                    } else if !character.isWhitespace { whitespaceSinceNewline = false }
                    if "。！？".contains(character) || (".!?".contains(character) && (next == text.endIndex || text[next].isWhitespace)) {
                        sentence = (next, count)
                    }
                }
                cursor = next
            }
            let end: String.Index, length: Int
            if cursor == text.endIndex { end = cursor; length = count }
            else if let preferred = preferSentences ? (paragraph ?? sentence ?? boundary) : boundary { end = preferred.0; length = preferred.1 }
            else { throw QualityError.inputTooLarge }
            guard end > start else { throw QualityError.inputTooLarge }
            result.append(QualityTextChunk(text: String(text[start..<end]), range: NSRange(location: offset, length: length)))
            offset += length; start = end
        }
        return result
    }
}
