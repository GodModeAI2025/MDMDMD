import Foundation

/// A bounded, literal excerpt of the checked source. It is prepared with the
/// finding so showing a dialog never reparses a manuscript on the UI actor.
public struct QualityFindingContext: Sendable, Equatable {
    public let before: String
    public let after: String
    public let isTruncatedBefore: Bool
    public let isTruncatedAfter: Bool

    init(source: String, range: Range<String.Index>) {
        var start = range.lowerBound
        var end = range.upperBound
        for _ in 0..<80 {
            guard start > source.startIndex else { break }
            let previous = source.index(before: start)
            guard !source[previous].isNewline else { break }
            start = previous
        }
        for _ in 0..<80 {
            guard end < source.endIndex, !source[end].isNewline else { break }
            end = source.index(after: end)
        }
        before = String(source[start..<range.lowerBound])
        after = String(source[range.upperBound..<end])
        isTruncatedBefore = start > source.startIndex && !source[source.index(before: start)].isNewline
        isTruncatedAfter = end < source.endIndex && !source[end].isNewline
    }
}
