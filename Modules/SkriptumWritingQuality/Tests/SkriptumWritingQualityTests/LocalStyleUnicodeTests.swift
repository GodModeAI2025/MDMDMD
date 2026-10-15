import Foundation
import Testing
@testable import SkriptumWritingQuality

@Test func repeatedWordsIncludeCombiningMarksAndKeepExactSource() throws {
    for word in ["cafe\u{301}", "fu\u{308}r", "हिन्दी", "বাংলা", "Ελλα\u{301}δα"] {
        let source = "Vorwort 🧑🏽‍💻\r\n" + word + "\t" + word + " danach."
        let document = QualityDocument(source: source, revision: UUID())
        let findings = LocalStyleReviewer.check(document)
        let finding = try #require(findings.first)
        #expect(findings.count == 1)
        #expect(finding.original == "\t" + word)
        #expect(try finding.applying("", to: document).utf8.elementsEqual(("Vorwort 🧑🏽‍💻\r\n" + word + " danach.").utf8))
    }
}

@Test func repeatedWordRuleKeepsMarkdownAndWordBoundariesProtected() {
    for source in ["`cafe\u{301} cafe\u{301}`", "cafe\u{301} cafe", "cafe\u{301} cafeteria", "fu\u{308}r\nfu\u{308}r", "[Link](https://example.com/cafe/cafe)"] {
        #expect(LocalStyleReviewer.check(QualityDocument(source: source, revision: UUID())).isEmpty)
    }
}
