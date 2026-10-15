import Foundation

/// Engine provenance belongs to the caller, never to response-provided metadata.
enum RuleResponseEngine: String, Sendable {
    case ownServer = "Eigener LanguageTool-Regelserver"
    case bundledNative = "LanguageTool 6.6 · lokal"
}

enum RuleResponseDecoder {
    static func decode(_ data: Data, document: QualityDocument, submittedRange: NSRange,
                       engine: RuleResponseEngine) throws -> [QualityFinding] {
        guard submittedRange.location >= 0, submittedRange.length >= 0,
              submittedRange.location <= document.source.utf16.count,
              submittedRange.length <= document.source.utf16.count - submittedRange.location else { throw QualityError.invalidRange }
        guard data.count <= 2_000_000 else { throw QualityError.responseTooLarge }
        struct Response: Decodable {
            let matches: [Match]
            let warnings: Warnings?
            enum CodingKeys: String, CodingKey { case matches, warnings }
            init(from decoder: any Decoder) throws {
                let values = try decoder.container(keyedBy: CodingKeys.self)
                matches = try values.decode([Match].self, forKey: .matches)
                // Legacy responses may omit warnings. A present object must
                // provide a real Boolean; null or malformed status is invalid.
                warnings = values.contains(.warnings) ? try values.decode(Warnings.self, forKey: .warnings) : nil
            }
        }
        struct Warnings: Decodable { let incompleteResults: Bool }
        struct Match: Decodable {
            let offset: Int; let length: Int; let message: String; let replacements: [Replacement]; let rule: Rule
        }
        struct Replacement: Decodable { let value: String }
        struct Rule: Decodable { let id: String; let issueType: String; let category: Category }
        struct Category: Decodable { let id: String; let name: String }
        guard let response = try? JSONDecoder().decode(Response.self, from: data), response.matches.count <= 5000 else { throw QualityError.invalidResponse }
        guard response.warnings?.incompleteResults != true else { throw QualityError.incompleteResults }
        var findings: [QualityFinding] = []
        let projection = document.projection
        for match in response.matches {
            guard !match.rule.issueType.isEmpty, match.rule.issueType.utf8.count <= 64 else { throw QualityError.invalidResponse }
            guard !match.rule.id.isEmpty, !match.rule.category.id.isEmpty, match.rule.category.id.count <= 256, match.rule.category.name.count <= 1024, match.offset >= 0, match.length > 0, match.offset <= submittedRange.length, match.length <= submittedRange.length - match.offset else { throw QualityError.invalidRange }
            let range = NSRange(location: submittedRange.location + match.offset, length: match.length)
            guard Range(range, in: document.source) != nil else { throw QualityError.invalidRange }
            guard projection.allows(range) else { continue }
            let kind: QualityKind
            switch match.rule.issueType {
            case "misspelling": kind = .spelling
            case "grammar": kind = .grammar
            case "style", "register", "duplication": kind = .style
            case "uncategorized":
                // Some LanguageTool rules omit an ITS type but provide a
                // canonical category. Localized/custom category IDs cannot
                // establish that a finding is grammatical.
                switch match.rule.category.id {
                case "TYPOS": kind = .spelling
                case "GRAMMAR", "AGREEMENT", "GENDER_AGREEMENT": kind = .grammar
                case "STYLE": kind = .style
                default: kind = .other
                }
            default:
                // Valid types such as whitespace/typography, and future
                // bounded metadata, remain usable without inflating grammar
                // counts or failing the entire review.
                kind = .other
            }
            findings.append(try QualityFinding.make(document: document, range: range, message: match.message, replacements: match.replacements.map(\.value), ruleID: match.rule.id, kind: kind, engine: engine.rawValue))
        }
        return findings
    }
}
