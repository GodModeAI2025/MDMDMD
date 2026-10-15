import Foundation

struct QualityTextChunk: Sendable {
    let text: String
    let range: NSRange
    let continuesSentence: Bool
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
            let continuesSentence = cursor != text.endIndex && paragraph == nil && sentence == nil
            if cursor == text.endIndex { end = cursor; length = count }
            else if let preferred = preferSentences ? (paragraph ?? sentence ?? boundary) : boundary { end = preferred.0; length = preferred.1 }
            else { throw QualityError.inputTooLarge }
            guard end > start else { throw QualityError.inputTooLarge }
            result.append(QualityTextChunk(text: String(text[start..<end]), range: NSRange(location: offset, length: length), continuesSentence: continuesSentence))
            offset += length; start = end
        }
        return result
    }

    /// Context is only needed at forced word cuts. Each finding belongs to the
    /// nonoverlapping core where it starts; overlap never duplicates a correction.
    static func reviewWindows(_ text: String) throws -> [(request: QualityTextChunk, ownedRange: NSRange)] {
        let contextLimit = 256
        let chunks: [QualityTextChunk]
        do { chunks = try make(text, maximumUTF16: 16_384 - 2 * contextLimit, preferSentences: true) }
        catch QualityError.inputTooLarge {
            // Keep the existing single-word limit; unusually long words leave less context budget.
            chunks = try make(text, preferSentences: true)
        }
        return try chunks.enumerated().map { index, chunk in
            try Task.checkCancellation()
            guard let core = Range(chunk.range, in: text) else { throw QualityError.invalidRange }
            var start = core.lowerBound, end = core.upperBound, count = 0
            let needsLeft = index > 0 && chunks[index - 1].continuesSentence
            let budget = 16_384 - chunk.range.length
            let leftLimit = needsLeft ? min(contextLimit, chunk.continuesSentence ? budget / 2 : budget) : 0
            let rightLimit = chunk.continuesSentence ? min(contextLimit, budget - leftLimit) : 0
            if needsLeft {
                while start > text.startIndex {
                    let previous = text.index(before: start), size = text[previous..<start].utf16.count
                    guard size <= leftLimit - count else { break }
                    start = previous; count += size
                }
                // Never submit a fragment of the context's first word.
                while start < core.lowerBound && start > text.startIndex && !text[text.index(before: start)].isWhitespace && !text[start].isWhitespace {
                    start = text.index(after: start)
                }
            }
            count = 0
            if chunk.continuesSentence {
                while end < text.endIndex {
                    let next = text.index(after: end), size = text[end..<next].utf16.count
                    guard size <= rightLimit - count else { break }
                    end = next; count += size
                }
                while end > core.upperBound && end < text.endIndex && !text[end].isWhitespace && !text[text.index(before: end)].isWhitespace {
                    end = text.index(before: end)
                }
            }
            let range = NSRange(start..<end, in: text)
            return (QualityTextChunk(text: String(text[start..<end]), range: range, continuesSentence: chunk.continuesSentence), chunk.range)
        }
    }

}
