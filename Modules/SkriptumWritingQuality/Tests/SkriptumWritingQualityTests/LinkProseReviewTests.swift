import Foundation
import Testing
@testable import SkriptumWritingQuality

struct LinkProseReviewTests {
    private func finding(_ source: String, original: String = "wrod", replacement: String = "word") throws -> (QualityDocument, QualityFinding) {
        let document = QualityDocument(source: source, revision: UUID())
        let range = (source as NSString).range(of: original)
        return (document, try QualityFinding.make(document: document, range: range,
            message: "Spelling correction", replacements: [replacement], ruleID: "FIXTURE",
            kind: .spelling, engine: "Fixture"))
    }

    @Test(arguments: [
        "See [wrod](https://example.invalid/page).",
        "See [wrod](../notes/chapter.md \"Original title\").",
        "See [wrod](../notes/chapter(one).md).",
        "See [wrod](<../notes/chapter one.md> 'Original title').",
        "See [a **wrod** in emphasis](../notes.md).",
        #"See [escaped \[label\] wrod](../notes.md)."#,
        #"See [wrod \] label](a(b(c)).md "Original title")."#,
        "See [a `protected` code and wrod](../notes.md).",
        "See [a nested [label] wrod](../notes.md).",
        "🦊 e\u{301} [wrod](../notes.md)\r\n",
        "> See [wrod](../notes.md).\r\n",
        "See [wrod\ncontinued](../notes.md).",
        "See [wrod][reference].\n\n[reference]: ../notes.md \"Original title\"\n",
        "![A wrod picture](../image.png \"Original title\")",
        "![A wrod picture][image]\n\n[image]: ../image.png\n",
        "[![A wrod picture](../image.png)](../outer.md)"
    ])
    func visibleLinkAndImageProseCanBeCorrectedWithoutChangingMetadata(_ source: String) async throws {
        let range = (source as NSString).range(of: "wrod")
        let projection = MarkdownProjection(source)
        #expect((projection.text as NSString).length == (source as NSString).length)
        #expect((projection.text as NSString).substring(with: range) == "wrod")
        let (document, value) = try finding(source)
        let prepared = try await value.prepareCorrection("word", source: source, revision: document.revision)
        let result = try prepared.admitting(source: source, revision: document.revision)
        let expected = (source as NSString).replacingCharacters(in: range, with: "word")
        #expect(Array(result.utf8) == Array(expected.utf8))
        #expect(throws: QualityError.staleSource) {
            try prepared.admitting(source: source, revision: UUID())
        }
    }

    @Test func localStyleReviewFindsDuplicateWordsInsideVisibleLinkText() throws {
        let source = "See [the the guide](../private/the-the.md \"the the title\")."
        let document = QualityDocument(source: source, revision: UUID())
        let findings = LocalStyleReviewer.check(document)
        #expect(findings.count == 1)
        let value = try #require(findings.first)
        #expect(try value.applying("", to: document) == "See [the guide](../private/the-the.md \"the the title\").")
    }

    @Test func destinationsTitlesCodeAndAutolinksRemainProtected() throws {
        let examples: [(String, String)] = [
            ("[label](../wrod.md)", "wrod"),
            ("[label](<../wrod file.md>)", "wrod"),
            ("[label](../chapter(wrod).md)", "wrod"),
            (#"[label](../chapter\(wrod\).md)"#, "wrod"),
            ("[label](../notes.md \"wrod title\")", "wrod"),
            ("[label](../notes.md 'wrod title')", "wrod"),
            ("[label](../notes.md (wrod title))", "wrod"),
            ("![label](../wrod.png \"title\")", "wrod"),
            ("[label][wrod]\n\n[wrod]: ../notes.md", "wrod"),
            ("[label][ref]\n\n[ref]: ../wrod.md", "wrod"),
            ("[label][ref]\n\n[ref]: ../notes.md \"wrod title\"", "wrod"),
            ("[`wrod` label](../notes.md)", "wrod"),
            ("`[wrod](../notes.md)`", "wrod"),
            ("> ```md\n> [wrod](../notes.md)\n> ```", "wrod"),
            ("<https://example.invalid/wrod>", "wrod"),
            ("<wrod@example.invalid>", "wrod"),
            ("<mailto:wrod@example.invalid>", "wrod"),
            ("[wrod](../notes.md)", "rod](../"),
            ("![wrod](../image.png)", "rod](../")
        ]
        for (source, original) in examples {
            #expect(throws: QualityError.protectedSyntax, Comment(rawValue: source)) {
                try finding(source, original: original)
            }
        }
    }

    @Test func labelChangesCannotBreakImplicitReferencesOrCreateLinkSyntax() throws {
        for source in ["[wrod][]\n\n[wrod]: ../notes.md", "[wrod]\n\n[wrod]: ../notes.md"] {
            #expect(throws: QualityError.protectedSyntax) {
                let (document, value) = try finding(source)
                _ = try value.applying("word", to: document)
            }
        }
        for replacement in ["](../other.md)", "[another]", "`code`", "https://other.invalid", "**word**"] {
            let (document, value) = try finding("[wrod](../notes.md)", replacement: replacement)
            #expect(throws: QualityError.protectedSyntax) { try value.applying(replacement, to: document) }
        }
    }

    @Test(arguments: ["&CounterClockwiseContourIntegral;", "&#104;", "&#x1F98A;", "caf&eacute;", "&Ouml;sterreich"])
    func encodedCharactersRemainProtectedWhileNeighboringProseCanBeCorrected(_ encoded: String) throws {
        for source in ["🦊 \(encoded) wrod e\u{301}\r\n", "[\(encoded) wrod](../notes.md)", "![\(encoded) wrod](../image.png)"] {
            let encodedRange = (source as NSString).range(of: encoded)
            #expect((MarkdownProjection(source).text as NSString).substring(with: encodedRange).trimmingCharacters(in: .whitespaces).isEmpty)
            #expect(throws: QualityError.protectedSyntax) {
                try finding(source, original: encoded, replacement: "changed")
            }
            let (document, value) = try finding(source)
            #expect(try value.applying("word", to: document) == source.replacingOccurrences(of: "wrod", with: "word"))
        }
    }
}
