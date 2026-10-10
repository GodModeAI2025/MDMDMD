import Foundation
import CoreGraphics
import CoreText
import PDFKit
import Testing
@testable import SkriptumExport

@Test func pdfParagraphPlannerMovesWholeParagraphAndReservesFinalWidows() throws {
    let planner = try PDFParagraphBreakPlanner()
    let moved = try planner.fragments(lineHeights: [10, 10, 10, 10], firstPageHeight: 20, pageHeight: 100)
    #expect(moved == [.init(pageOffset: 1, lineRange: 0..<4, height: 40)])
    let split = try planner.fragments(lineHeights: Array(repeating: 10, count: 12), firstPageHeight: 100, pageHeight: 100)
    #expect(split == [.init(pageOffset: 0, lineRange: 0..<9, height: 90), .init(pageOffset: 1, lineRange: 9..<12, height: 30)])
}

@Test func pdfParagraphPlannerRejectsImpossibleRulesAndHonorsVariableMetrics() throws {
    let planner = try PDFParagraphBreakPlanner()
    #expect(throws: PDFParagraphBreakPlanner.PlanningError.infeasibleGrouping) {
        try planner.fragments(lineHeights: Array(repeating: 30, count: 5), firstPageHeight: 100, pageHeight: 100)
    }
    #expect(throws: PDFParagraphBreakPlanner.PlanningError.lineExceedsPage) {
        try planner.fragments(lineHeights: [101], firstPageHeight: 100, pageHeight: 100)
    }
    #expect(throws: PDFParagraphBreakPlanner.PlanningError.pageLimitExceeded) {
        try planner.fragments(lineHeights: Array(repeating: 10, count: 12), firstPageHeight: 100, pageHeight: 100, maximumPages: 1)
    }
    let heights: [CGFloat] = [12, 24, 12, 36, 18, 12, 24, 12, 18, 12, 36, 12]
    let fragments = try planner.fragments(lineHeights: heights, firstPageHeight: 100, pageHeight: 100)
    #expect(fragments.flatMap { Array($0.lineRange) } == Array(heights.indices))
    for fragment in fragments {
        #expect(fragment.lineRange.count >= 3)
        #expect(fragment.height <= 100)
        #expect(abs(fragment.height - fragment.lineRange.reduce(0) { $0 + heights[$1] }) < 0.001)
    }
}

@Test func pdfParagraphPlanDrawsAllUnicodeTextThroughItsPlannedBreaks() throws {
    let adapter = try PDFInlineAdapter(theme: .standard, footnoteIDs: [])
    let fragments = try adapter.fragments((0..<90).map { .text("Zeile \($0) 🦊\n") })
    guard case .text(let text) = fragments.first else { Issue.record("No text"); return }
    var measurement = try PDFTextTypesetter(text: text, availableWidth: 220, lineHeightMultiple: 1.65)
    var heights: [CGFloat] = []
    while let line = try measurement.nextLine() { heights.append(max(line.advance, line.ascent + line.descent)) }
    let planner = try PDFParagraphBreakPlanner()
    let pages = try planner.fragments(lineHeights: heights, firstPageHeight: 200, pageHeight: 200)
    let data = NSMutableData(); let consumer = try #require(CGDataConsumer(data: data))
    var paper = CGRect(x: 0, y: 0, width: 260, height: 240)
    let context = try #require(CGContext(consumer: consumer, mediaBox: &paper, nil))
    var layout = try PDFTextTypesetter(text: text, availableWidth: 220, lineHeightMultiple: 1.65)
    for fragment in pages {
        context.beginPDFPage(nil); var top: CGFloat = 220
        for _ in fragment.lineRange {
            let candidate = try layout.nextLine(); let line = try #require(candidate)
            try line.draw(in: context, baseline: CGPoint(x: 20, y: top - line.ascent))
            top -= max(line.advance, line.ascent + line.descent)
            #expect(top >= 20 - 0.001)
        }
        context.endPDFPage()
    }
    context.closePDF()
    let pdf = try #require(PDFDocument(data: data as Data)); let output = try #require(pdf.string)
    #expect(pdf.pageCount == pages.count)
    #expect(output.filter { $0 == "🦊" }.count == 90)
    for index in 0..<90 { #expect(output.contains("Zeile \(index) 🦊")) }
    for page in pages { #expect(page.lineRange.count >= 3) }
}

@Test func pdfParagraphPlannerFindsFeasibleBreaksThatGreedyFillingMisses() throws {
    let planner = try PDFParagraphBreakPlanner()
    let heights: [CGFloat] = [30, 30, 30, 10, 30, 30, 30, 10, 30]
    let fragments = try planner.fragments(lineHeights: heights, firstPageHeight: 100, pageHeight: 100)
    #expect(fragments.map(\.lineRange) == [0..<3, 3..<6, 6..<9])
    #expect(fragments.map(\.height) == [90, 70, 70])
}

@Test func pdfParagraphPlannerMatchesIndependentSmallPartitionSearch() throws {
    let planner = try PDFParagraphBreakPlanner()
    func feasible(_ heights: [CGFloat], firstHeight: CGFloat, maximumPages: Int) -> Bool {
        func visit(_ start: Int, _ page: Int, _ available: CGFloat) -> Bool {
            guard page < maximumPages else { return false }
            var sum: CGFloat = 0
            for end in (start + 1)...heights.count {
                sum += heights[end - 1]
                if sum > available { break }
                if end == heights.count {
                    if start == 0 || end - start >= 3 { return true }
                } else if end - start >= 3, visit(end, page + 1, 100) { return true }
            }
            return false
        }
        return visit(0, 0, firstHeight) || (firstHeight < 100 && visit(0, 1, 100))
    }
    for count in 1...9 {
        for mask in 0..<(1 << count) {
            let heights: [CGFloat] = (0..<count).map { mask & (1 << $0) == 0 ? 10 : 30 }
            for firstHeight: CGFloat in [0, 40, 100] {
                for maximumPages in [1, 3] {
                    let expected = feasible(heights, firstHeight: firstHeight, maximumPages: maximumPages)
                    do {
                        let result = try planner.fragments(lineHeights: heights, firstPageHeight: firstHeight, pageHeight: 100, maximumPages: maximumPages)
                        #expect(expected)
                        #expect(result.flatMap { Array($0.lineRange) } == Array(heights.indices))
                        for fragment in result {
                            #expect(fragment.pageOffset < maximumPages)
                            #expect(fragment.height <= (fragment.pageOffset == 0 ? firstHeight : 100))
                            if result.count > 1 { #expect(fragment.lineRange.count >= 3) }
                        }
                    } catch PDFParagraphBreakPlanner.PlanningError.infeasibleGrouping { #expect(!expected) }
                    catch PDFParagraphBreakPlanner.PlanningError.pageLimitExceeded { #expect(!expected) }
                    catch { Issue.record("Unexpected planning error: \(error)") }
                }
            }
        }
    }
}
