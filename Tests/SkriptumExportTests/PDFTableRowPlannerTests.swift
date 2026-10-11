import Foundation
import CoreGraphics
import Testing
@testable import SkriptumExport

@Test func tallTableRowFragmentsPreserveEveryCellLineWithAlignedStarts() throws {
    let cells: [[PDFTableRowPlanner.Line]] = [
        (0..<100).map { .init(height: $0 % 2 == 0 ? 24 : 18, ascent: 15) },
        [.init(height: 30, ascent: 22)], [],
        (0..<50).map { _ in .init(height: 20, ascent: 12) }
    ]
    let plan = try PDFTableRowPlanner().fragments(cells: cells, firstPageHeight: 40, pageHeight: 100)
    #expect(plan.first?.pageOffset == 1)
    #expect(plan.count > 20)
    for column in cells.indices {
        let recovered = plan.flatMap { Array($0.cellRanges[column]) }
        #expect(recovered == Array(cells[column].indices))
    }
    for fragment in plan {
        #expect(fragment.height <= 100)
        for column in cells.indices {
            let range = fragment.cellRanges[column]
            guard let first = range.first else { continue }
            let required = range.reduce(CGFloat(0)) { $0 + cells[column][$1].height }
                + fragment.firstAscent - cells[column][first].ascent + 12
            #expect(required <= fragment.height)
        }
    }
}

@Test func tableRowPlannerRejectsImpossibleAlignmentAndBudgetWithoutPartialSuccess() throws {
    let planner = PDFTableRowPlanner()
    #expect(throws: PDFTableRowPlanner.PlanningError.lineExceedsPage) {
        try planner.fragments(cells: [[.init(height: 90, ascent: 10)], [.init(height: 70, ascent: 60)]],
                              firstPageHeight: 100, pageHeight: 100)
    }
    #expect(throws: PDFTableRowPlanner.PlanningError.pageLimitExceeded) {
        try planner.fragments(cells: [Array(repeating: .init(height: 30, ascent: 20), count: 100)],
                              firstPageHeight: 100, pageHeight: 100, maximumPages: 2)
    }
    let blank = try planner.fragments(cells: [[], []], firstPageHeight: 0, pageHeight: 100)
    #expect(blank.count == 1 && blank.first?.pageOffset == 1 && blank.first?.height == 12)
}
