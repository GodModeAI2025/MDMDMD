import Foundation
import Testing
@testable import SkriptumWritingQuality

private func finding(_ word: String, in source: String) throws -> QualityFinding {
    try QualityFinding.make(document: QualityDocument(source: source, revision: UUID()),
        range: (source as NSString).range(of: word), message: "Hinweis", replacements: ["gut"],
        ruleID: "CONTEXT", kind: .style, engine: "Test")
}

@Test func correctionContextIdentifiesTheOccurrenceInItsParagraph() throws {
    let source = "# Kapitel\n\nDer erste Satz ist gut. Hier steht schlecht im zweiten Satz.\n\nAnderer Absatz."
    let result = try finding("schlecht", in: source)
    #expect(result.context.before == "Der erste Satz ist gut. Hier steht ")
    #expect(result.context.after == " im zweiten Satz.")
    #expect(!result.context.isTruncatedBefore && !result.context.isTruncatedAfter)
    #expect(result.context.before + result.original + result.context.after == "Der erste Satz ist gut. Hier steht schlecht im zweiten Satz.")
}

@Test func correctionContextBoundsLongLinesWithoutSplittingGraphemes() throws {
    let prefix = String(repeating: "🧑🏽‍💻e\u{301}", count: 100)
    let suffix = String(repeating: "🇩🇪日", count: 100)
    let result = try finding("schlecht", in: prefix + "schlecht" + suffix)
    #expect(result.context.before == String(prefix.suffix(80)))
    #expect(result.context.after == String(suffix.prefix(80)))
    #expect(result.context.before.count == 80 && result.context.after.count == 80)
    #expect(result.context.isTruncatedBefore && result.context.isTruncatedAfter)
}

@Test func correctionContextHandlesDocumentEdgesAndCRLF() throws {
    let start = try finding("schlecht", in: "schlecht am Anfang.")
    #expect(start.context.before.isEmpty && !start.context.isTruncatedBefore)
    let end = try finding("schlecht", in: "Am Ende schlecht")
    #expect(end.context.after.isEmpty && !end.context.isTruncatedAfter)
    let paragraph = try finding("schlecht", in: "Vorher.\r\nHier schlecht.\r\nNachher.")
    #expect(paragraph.context.before == "Hier ")
    #expect(paragraph.context.after == ".")
    #expect(!paragraph.context.isTruncatedBefore && !paragraph.context.isTruncatedAfter)
}

@Test func correctionContextKeepsMarkupLiteralAndExistingAdmission() throws {
    let source = "Ein **schlecht** formulierter Satz 🦊."
    let document = QualityDocument(source: source, revision: UUID())
    let result = try QualityFinding.make(document: document, range: (source as NSString).range(of: "schlecht"),
        message: "Hinweis", replacements: ["gut"], ruleID: "CONTEXT", kind: .style, engine: "Test")
    #expect(result.context.before == "Ein **")
    #expect(result.context.after == "** formulierter Satz 🦊.")
    #expect(try result.applying("gut", to: document) == "Ein **gut** formulierter Satz 🦊.")
    #expect(throws: QualityError.staleSource) {
        try result.applying("gut", to: QualityDocument(source: source + " Neu.", revision: document.revision))
    }
}
