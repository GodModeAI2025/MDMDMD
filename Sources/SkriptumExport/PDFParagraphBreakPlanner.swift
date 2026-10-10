import Foundation
import CoreGraphics

/// Plans paragraph fragments before drawing. The caller measures CoreText lines
/// without retaining CTLine objects, then reserves/draws each planned fragment.
/// Impossible rules fail explicitly; callers must not silently lose text or
/// claim the requested widow/orphan policy was satisfied.
struct PDFParagraphBreakPlanner {
    enum PlanningError: Error, Equatable {
        case invalidGeometry, lineExceedsPage, infeasibleGrouping, pageLimitExceeded
    }
    struct Fragment: Equatable {
        let pageOffset: Int
        let lineRange: Range<Int>
        let height: CGFloat
    }
    let orphanLines: Int
    let widowLines: Int
    init(orphanLines: Int = 3, widowLines: Int = 3) throws {
        guard orphanLines > 0, widowLines > 0 else { throw PlanningError.invalidGeometry }
        self.orphanLines = orphanLines; self.widowLines = widowLines
    }

    func fragments(lineHeights: [CGFloat], firstPageHeight: CGFloat, pageHeight: CGFloat,
                   maximumPages: Int = 3000) throws -> [Fragment] {
        try Task.checkCancellation()
        guard firstPageHeight.isFinite, pageHeight.isFinite, firstPageHeight >= 0,
              pageHeight > 0, firstPageHeight <= pageHeight, maximumPages > 0 else { throw PlanningError.invalidGeometry }
        for height in lineHeights {
            try Task.checkCancellation()
            guard height.isFinite, height > 0 else { throw PlanningError.invalidGeometry }
            guard height <= pageHeight else { throw PlanningError.lineExceedsPage }
        }
        guard !lineHeights.isEmpty else { return [] }
        var prefix: [CGFloat] = [0]
        for height in lineHeights {
            try Task.checkCancellation()
            let total = prefix.last! + height
            guard total.isFinite else { throw PlanningError.invalidGeometry }
            prefix.append(total)
        }
        let count = lineHeights.count
        // Reject an impossible page budget before allocating the suffix tree.
        let totalCapacity = firstPageHeight + pageHeight * CGFloat(maximumPages - 1)
        guard prefix[count] <= totalCapacity else { throw PlanningError.pageLimitExceeded }
        if prefix[count] <= firstPageHeight {
            return [Fragment(pageOffset: 0, lineRange: 0..<count, height: prefix[count])]
        }
        func fittingEnd(_ start: Int, _ height: CGFloat) -> Int {
            var lower = start, upper = count
            while lower < upper {
                let middle = lower + (upper - lower + 1) / 2
                if prefix[middle] - prefix[start] <= height { lower = middle }
                else { upper = middle - 1 }
            }
            return lower
        }
        // Suffix dynamic programming minimizes page count. A range-minimum
        // tree finds a feasible future break without quadratic candidate scans.
        var choices = SuffixChoices(count: count)
        var nextBreak = [Int?](repeating: nil, count: count)
        for start in (0..<count).reversed() {
            try Task.checkCancellation()
            let end = fittingEnd(start, pageHeight)
            if end == count && (start == 0 || count - start >= widowLines) {
                nextBreak[start] = count
                choices.set(start, Choice(pages: 1, index: start))
            } else if end - start >= orphanLines,
                      let future = choices.best((start + orphanLines)..<min(end + 1, count)) {
                nextBreak[start] = future.index
                choices.set(start, Choice(pages: future.pages + 1, index: start))
            }
        }
        let firstEnd = fittingEnd(0, firstPageHeight)
        let firstChoice = firstEnd >= orphanLines
            ? choices.best(orphanLines..<min(firstEnd + 1, count)) : nil
        let fullPageChoice = choices.best(0..<1)
        var page: Int, end: Int
        if let firstChoice, firstChoice.pages <= (fullPageChoice?.pages ?? Int.max) {
            page = 0; end = firstChoice.index
        }
        else if let fullPageEnd = nextBreak[0] { page = 1; end = fullPageEnd }
        else { throw PlanningError.infeasibleGrouping }
        var result: [Fragment] = [], start = 0
        while start < count {
            try Task.checkCancellation()
            guard page < maximumPages else { throw PlanningError.pageLimitExceeded }
            let height = (start..<end).reduce(CGFloat(0)) { $0 + lineHeights[$1] }
            result.append(Fragment(pageOffset: page, lineRange: start..<end, height: height))
            start = end
            if start < count {
                guard let following = nextBreak[start] else { throw PlanningError.infeasibleGrouping }
                end = following; page += 1
            }
        }
        return result
    }

    private struct Choice {
        let pages: Int
        let index: Int
    }
    private struct SuffixChoices {
        private let capacity: Int
        private var tree: [Choice?]
        init(count: Int) {
            var capacity = 1
            while capacity < count { capacity *= 2 }
            self.capacity = capacity; tree = Array(repeating: nil, count: capacity * 2)
        }
        private func preferred(_ a: Choice?, _ b: Choice?) -> Choice? {
            guard let a else { return b }; guard let b else { return a }
            if a.pages != b.pages { return a.pages < b.pages ? a : b }
            return a.index > b.index ? a : b
        }
        mutating func set(_ index: Int, _ choice: Choice) {
            var node = index + capacity; tree[node] = choice
            while node > 1 {
                node /= 2; tree[node] = preferred(tree[node * 2], tree[node * 2 + 1])
            }
        }
        func best(_ range: Range<Int>) -> Choice? {
            guard !range.isEmpty else { return nil }
            var lower = range.lowerBound + capacity, upper = range.upperBound + capacity
            var result: Choice?
            while lower < upper {
                if lower % 2 == 1 { result = preferred(result, tree[lower]); lower += 1 }
                if upper % 2 == 1 { upper -= 1; result = preferred(result, tree[upper]) }
                lower /= 2; upper /= 2
            }
            return result
        }
    }
}
