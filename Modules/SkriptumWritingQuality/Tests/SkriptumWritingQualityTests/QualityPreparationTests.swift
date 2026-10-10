import Foundation
import Testing
@testable import SkriptumWritingQuality

@Test func asynchronousQualityPreparationPreservesLongUnicodeSourceAndSyntax() async throws {
    let source = String(repeating: "Text e\u{301} 🦊 with **kept** markup.\r\n\r\n", count: 3000) + "```swift\nlet protected = 1\n```\n"
    let revision = UUID()
    let document = try await QualityDocument.prepare(source: source, revision: revision)
    #expect(document.source.utf8.elementsEqual(source.utf8))
    #expect(document.revision == revision)
    #expect(document == QualityDocument(source: source, revision: revision))
    let protected = (source as NSString).range(of: "protected")
    #expect(throws: QualityError.protectedSyntax) {
        try QualityFinding.make(document: document, range: protected, message: "test", replacements: ["changed"], ruleID: "TEST", kind: .style, engine: "test")
    }
}

@Test func qualityPreparationRejectsOversizedInputBeforeProjection() async {
    do {
        _ = try await QualityDocument.prepare(source: String(repeating: "a", count: 8 * 1024 * 1024 + 1), revision: UUID())
        Issue.record("Oversized review accepted")
    } catch { #expect(error as? QualityError == .inputTooLarge) }
}
