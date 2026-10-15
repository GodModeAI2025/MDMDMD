import Foundation
import Testing
@testable import SkriptumWritingQuality

struct EncodedProseBoundaryTests {
    @Test(arguments: ["caf&eacute;l&eacute;phant", "a&#104;b&#x301;c", "&eacute;\u{301}cole", "\u{1D400}&eacute;cole"])
    func multipleEntitiesAndScalarBoundariesKeepTheirOriginalBytes(_ encoded: String) throws {
        let source = "[\(encoded) wrod](../notes.md)"
        let projection = MarkdownProjection(source)
        let encodedRange = (source as NSString).range(of: encoded)
        #expect((projection.text as NSString).substring(with: encodedRange).trimmingCharacters(in: .whitespaces).isEmpty)
        let document = QualityDocument(source: source, revision: UUID())
        let finding = try QualityFinding.make(document: document, range: (source as NSString).range(of: "wrod"),
            message: "Spelling", replacements: ["word"], ruleID: "FIXTURE", kind: .spelling, engine: "Fixture")
        #expect(try Array(finding.applying("word", to: document).utf8) == Array(source.replacingOccurrences(of: "wrod", with: "word").utf8))
    }

    @Test func largePlainAndEncodedRunsRetainCorrectionOffsets() throws {
        let plain = String(repeating: "a", count: 100_000)
        let source = plain + "\n\n" + String(repeating: "\u{1D400}caf&eacute;l&eacute;phant ", count: 4_000) + "\n\n[wrod](../notes.md)"
        let projection = MarkdownProjection(source)
        #expect(projection.text.hasPrefix(plain))
        #expect(!projection.text.contains("phant"))
        #expect(!projection.text.contains("eacute"))
        #expect((source as NSString).length == (projection.text as NSString).length)
        let document = QualityDocument(source: source, revision: UUID())
        let finding = try QualityFinding.make(document: document, range: (source as NSString).range(of: "wrod"),
            message: "Spelling", replacements: ["word"], ruleID: "FIXTURE", kind: .spelling, engine: "Fixture")
        #expect(try Array(finding.applying("word", to: document).utf8) == Array(source.replacingOccurrences(of: "wrod", with: "word").utf8))
    }
}
