import Foundation
import Testing
@testable import SkriptumWritingQuality

private func response(issueType: String, category: String) throws -> Data {
    try JSONSerialization.data(withJSONObject: ["matches": [[
        "offset": 0, "length": 4, "message": "Hinweis", "replacements": [["value": "good"]],
        "rule": ["id": "RULE", "issueType": issueType,
                 "category": ["id": category, "name": category]]
    ]]])
}

@Test(arguments: [
    ("misspelling", "TYPOS", "spelling"),
    ("grammar", "AGREEMENT", "grammar"),
    ("style", "STYLE", "style"),
    ("register", "REGISTER", "style"),
    ("duplication", "REPETITIONS", "style"),
    ("uncategorized", "GRAMMAR", "grammar"),
    ("uncategorized", "AGREEMENT", "grammar"),
    ("uncategorized", "GENDER_AGREEMENT", "grammar"),
    ("uncategorized", "TYPOS", "spelling"),
    ("uncategorized", "STYLE", "style"),
    ("uncategorized", "CAT1", "other"),
    ("typographical", "CASING", "other"),
    ("punctuation", "PUNCTUATION", "other"),
    ("whitespace", "TYPOGRAPHY", "other"),
    ("inconsistency", "SEMANTICS", "other"),
    ("formatting", "FORMAT", "other"),
    ("locale-violation", "LOCALE", "other"),
    ("numbers", "NUMBERS", "other"),
    ("future-server-type", "CUSTOM", "other")
])
func remoteRuleCategoriesKeepNonGrammarSeparate(_ value: (String, String, String)) throws {
    let document = QualityDocument(source: "baad text", revision: UUID())
    let result = try LanguageToolClient.decode(response(issueType: value.0, category: value.1), document: document)
    #expect(result.count == 1)
    #expect(result.first?.kind.rawValue == value.2)
    #expect(try result.first?.applying("good", to: document) == "good text")
}

@Test func ruleTypeMetadataMustRemainBounded() throws {
    let document = QualityDocument(source: "baad text", revision: UUID())
    for invalid in ["", String(repeating: "a", count: 65)] {
        #expect(throws: QualityError.invalidResponse) {
            try LanguageToolClient.decode(response(issueType: invalid, category: "CUSTOM"), document: document)
        }
    }
}

@Test func actualLanguageToolResponsesRemainUsableAcrossSyntheticLanguages() throws {
    let url = try #require(Bundle.module.url(forResource: "LanguageTool66SyntheticResponses", withExtension: "json"))
    let corpus = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    let records = try #require(corpus["records"] as? [[String: Any]])
    #expect(records.count == 29)
    var primaryLanguages = Set<String>()
    for record in records {
        let source = try #require(record["source"] as? String)
        let primaryLanguage = try #require(record["primaryLanguage"] as? String)
        let response = try #require(record["response"] as? [String: Any])
        let findings = try LanguageToolClient.decode(JSONSerialization.data(withJSONObject: response),
            document: QualityDocument(source: source, revision: UUID()))
        #expect(!findings.isEmpty, "Captured real-engine response must remain usable: \(primaryLanguage)")
        primaryLanguages.insert(primaryLanguage)
        if primaryLanguage == "el" || primaryLanguage == "fr" {
            #expect(findings.contains { $0.kind.rawValue == "grammar" })
        }
        if primaryLanguage == "fa" {
            let whitespace = try #require(findings.first { $0.ruleID == "ReplaceLettersInSameLangs" })
            #expect(whitespace.kind.rawValue == "other")
            #expect(whitespace.replacements.contains("کادو"))
        }
    }
    #expect(primaryLanguages.count == 29)
}
