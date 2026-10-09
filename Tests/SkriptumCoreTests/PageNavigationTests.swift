import Foundation
import Testing
@testable import SkriptumCore
struct PageNavigationTests {
    @Test func failedMovesDoNotConsumeHistory() {
        let library = UUID(), a = PageNavigationLocation(pageID: UUID()), b = PageNavigationLocation(pageID: UUID()), c = PageNavigationLocation(pageID: UUID())
        var history = PageNavigationHistory(libraryID: library)
        history.visit(a); history.visit(b); history.visit(c)
        #expect(history.backCandidate == b)
        let rejected = history.commitBack(to: a)
        #expect(!rejected)
        #expect(history.current == c)
        let accepted = history.commitBack(to: b)
        #expect(accepted)
        #expect(history.current == b)
        #expect(history.forwardCandidate == c)
        let rejectedForward = history.commitForward(to: a)
        #expect(!rejectedForward && history.current == b)
        let acceptedForward = history.commitForward(to: c)
        #expect(acceptedForward && history.current == c)
        let backAgain = history.commitBack(to: b)
        #expect(backAgain)
        history.visit(a)
        #expect(history.forwardCandidate == nil)
        history.visit(a)
        #expect(history.count == 3)
    }
    @Test func boundedAndLibraryReset() {
        let library = UUID()
        var history = PageNavigationHistory(libraryID: library, capacity: 3)
        let locations = (0..<5).map { _ in PageNavigationLocation(pageID: UUID()) }
        for location in locations { history.visit(location) }
        #expect(history.count == 3)
        let firstBack = history.commitBack(to: locations[3])
        #expect(firstBack)
        let secondBack = history.commitBack(to: locations[2])
        #expect(secondBack)
        #expect(history.backCandidate == nil)
        let newLibrary = UUID()
        history.reset(for: newLibrary)
        #expect(history.libraryID == newLibrary)
        #expect(history.current == nil && history.count == 0)
        var maximum = PageNavigationHistory(libraryID: library, capacity: 999)
        for _ in 0..<110 { maximum.visit(PageNavigationLocation(pageID: UUID())) }
        #expect(maximum.count == 100 && maximum.capacity == 100)
    }
    @Test func utf8CoordinatesAreFailClosed() {
        let source = "😀 e\u{301}\r\nZ\n"
        let span = PageLinkSourceSpan(startLine: 1, startColumn: 1, endLine: 1, endColumn: 5)
        #expect(span.utf16Range(in: source) == NSRange(location: 0, length: 2))
        #expect(PageLinkSourceSpan(startLine: 2,startColumn: 1,endLine: 2,endColumn: 2).utf16Range(in: source) == NSRange(location: 7,length: 1))
        #expect(PageLinkSourceSpan(startLine: 1,startColumn: 2,endLine: 1,endColumn: 5).utf16Range(in: source) == nil)
        #expect(PageLinkSourceSpan(startLine: 1,startColumn: 10,endLine: 2,endColumn: 1).utf16Range(in: source) == nil)
        #expect(PageLinkSourceSpan(startLine: 3,startColumn: 1,endLine: 3,endColumn: 1).utf16Range(in: source) == NSRange(location: 9,length: 0))
        #expect(PageLinkSourceSpan(startLine: 2,startColumn: 2,endLine: 1,endColumn: 1).utf16Range(in: source) == nil)
        #expect(PageLinkSourceSpan(startLine: 4,startColumn: 1,endLine: 4,endColumn: 1).utf16Range(in: source) == nil)
    }
}
