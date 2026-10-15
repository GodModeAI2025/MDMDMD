import Foundation
import Testing
@testable import SkriptumWritingQuality

struct ManualReplacementTests {
    private func finding(_ source: String, original: String, replacement: String) throws -> (QualityDocument, QualityFinding) {
        let document = QualityDocument(source: source, revision: UUID())
        return (document, try QualityFinding.make(document: document,
            range: (source as NSString).range(of: original), message: "Regression", replacements: [replacement],
            ruleID: "FIXTURE", kind: .grammar, engine: "Fixture"))
    }

    @Test func swedishAcronymSuggestionIsManualRatherThanAnUnusableApplyAction() throws {
        let (document, value) = try finding("Med det nya APIs fördelar, kan du hitta nya lösningar.", original: "APIs", replacement: "API:s")
        #expect(value.requiresManualEditing("API:s"))
        #expect(throws: QualityError.protectedSyntax) { try value.applying("API:s", to: document) }
    }

    @Test func addressesAndMarkdownRemainProtectedButOrdinaryProseCanBeApplied() throws {
        for replacement in ["custom-scheme:payload", "https://example.invalid", "`code`", "[link]", "two\nlines"] {
            let (document, value) = try finding("A word remains.", original: "word", replacement: replacement)
            #expect(value.requiresManualEditing(replacement))
            #expect(throws: QualityError.protectedSyntax) { try value.applying(replacement, to: document) }
        }
        let (document, value) = try finding("Café 🦊 can stay.", original: "can", replacement: "could")
        #expect(!value.requiresManualEditing("could"))
        #expect(try value.applying("could", to: document) == "Café 🦊 could stay.")
    }

    @Test func presentationHintNeverBypassesFullStructuralOrRevisionAdmission() throws {
        let (document, value) = try finding("note", original: "note", replacement: "- item")
        #expect(!value.requiresManualEditing("- item"))
        #expect(throws: QualityError.protectedSyntax) { try value.applying("- item", to: document) }
        #expect(throws: QualityError.staleSource) {
            try value.applying("- item", to: QualityDocument(source: document.source, revision: UUID()))
        }
    }
}
