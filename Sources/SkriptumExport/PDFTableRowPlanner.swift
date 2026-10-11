import Foundation
import CoreGraphics

/// Plans a tall table row using scalar line metrics. Each cell advances
/// independently; finished cells stay empty on later fragments. Page height
/// supplied by the caller excludes the repeated table header.
struct PDFTableRowPlanner {
    struct Line: Equatable {
        let height: CGFloat
        let ascent: CGFloat
    }
    struct Fragment: Equatable {
        let pageOffset: Int
        let cellRanges: [Range<Int>]
        let height: CGFloat
        let firstAscent: CGFloat
    }
    enum PlanningError: Error, Equatable {
        case invalidGeometry, lineExceedsPage, pageLimitExceeded
    }

    func fragments(cells: [[Line]], firstPageHeight: CGFloat, pageHeight: CGFloat,
                   padding: CGFloat = 6, maximumPages: Int = 3000) throws -> [Fragment] {
        try Task.checkCancellation()
        guard !cells.isEmpty, padding.isFinite, padding >= 0,
              pageHeight.isFinite, pageHeight > padding * 2,
              firstPageHeight.isFinite, firstPageHeight >= 0, firstPageHeight <= pageHeight,
              maximumPages > 0 else { throw PlanningError.invalidGeometry }
        for cell in cells {
            for line in cell {
                try Task.checkCancellation()
                guard line.height.isFinite, line.ascent.isFinite, line.height > 0,
                      line.ascent >= 0, line.ascent <= line.height else { throw PlanningError.invalidGeometry }
            }
        }
        var offsets = cells.map { _ in 0 }, result: [Fragment] = [], page = 0
        while true {
            try Task.checkCancellation()
            guard page < maximumPages else { throw PlanningError.pageLimitExceeded }
            let firstAscent = cells.indices.compactMap { column -> CGFloat? in
                offsets[column] < cells[column].count ? cells[column][offsets[column]].ascent : nil
            }.max() ?? 0
            let minimum = cells.indices.map { column -> CGFloat in
                guard offsets[column] < cells[column].count else { return 0 }
                let line = cells[column][offsets[column]]
                return line.height + firstAscent - line.ascent
            }.max() ?? 0
            guard minimum + padding * 2 <= pageHeight else { throw PlanningError.lineExceedsPage }
            let available = page == 0 ? firstPageHeight : pageHeight
            if minimum + padding * 2 > available { page += 1; continue }
            var ranges: [Range<Int>] = [], tallest: CGFloat = 0
            for column in cells.indices {
                try Task.checkCancellation()
                let start = offsets[column]
                var height: CGFloat = start < cells[column].count ? firstAscent - cells[column][start].ascent : 0
                while offsets[column] < cells[column].count {
                    try Task.checkCancellation()
                    let next = cells[column][offsets[column]].height
                    if height + next + padding * 2 > available { break }
                    height += next; offsets[column] += 1
                }
                ranges.append(start..<offsets[column]); tallest = max(tallest, height)
            }
            result.append(Fragment(pageOffset: page, cellRanges: ranges,
                                   height: tallest + padding * 2, firstAscent: firstAscent))
            if !cells.indices.contains(where: { offsets[$0] < cells[$0].count }) { break }
            page += 1
        }
        return result
    }
}
