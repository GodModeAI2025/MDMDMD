import Foundation

public enum QualityError: Error, Sendable, Equatable, LocalizedError {
    case invalidConfiguration, inputTooLarge, responseTooLarge, invalidResponse, invalidRange, protectedSyntax, staleSource, unofferedReplacement, http(Int), unsupportedLanguage
    public var errorDescription: String? {
        switch self {
        case .invalidConfiguration: "Für diesen Dienst muss ein eigener HTTPS-Endpunkt konfiguriert werden."
        case .inputTooLarge: "Der Text überschreitet die Größe einer Prüfung."
        case .responseTooLarge: "Die Prüfantwort überschreitet die erlaubte Größe."
        case .invalidResponse: "Die Prüfantwort ist ungültig."
        case .invalidRange: "Der Korrekturbereich ist ungültig."
        case .protectedSyntax: "Die Korrektur würde geschützte Markdown-Syntax verändern."
        case .staleSource: "Der Text wurde seit der Prüfung geändert. Bitte erneut prüfen."
        case .unofferedReplacement: "Diese Ersetzung wurde nicht als Korrektur angeboten."
        case .http(let code): "Der eigene Prüfdienst meldet HTTP \(code)."
        case .unsupportedLanguage: "Die Sprache ist vom gewählten Prüfdienst nicht bestätigt."
        }
    }
}
public struct QualityDocument: Sendable, Equatable {
    public let source: String
    public let revision: UUID
    let sourceBytes: Data
    let projection: MarkdownProjection
    public init(source: String, revision: UUID) { self.source = source; self.revision = revision; sourceBytes = Data(source.utf8); projection = MarkdownProjection(source) }
    public static func == (lhs: QualityDocument, rhs: QualityDocument) -> Bool { lhs.revision == rhs.revision && lhs.sourceBytes == rhs.sourceBytes }
}
public enum QualityKind: String, Codable, Sendable { case spelling, grammar, style }
public struct QualityFinding: Identifiable, Sendable {
    public let id: UUID
    public let revision: UUID
    public let range: NSRange
    public let original: String
    public let message: String
    public let replacements: [String]
    public let ruleID: String
    public let kind: QualityKind
    public let engine: String
    private let sourceBytes: Data
    public static func make(document: QualityDocument, range: NSRange, message: String, replacements: [String], ruleID: String, kind: QualityKind, engine: String) throws -> QualityFinding {
        guard range.location >= 0, range.length > 0, range.location <= (document.source as NSString).length, range.length <= (document.source as NSString).length - range.location, Range(range, in: document.source) != nil, safeUTF16Range(range, in: document.source) else { throw QualityError.invalidRange }
        guard document.projection.allows(range) else { throw QualityError.protectedSyntax }
        guard message.utf8.count <= 8192, ruleID.utf8.count <= 512, replacements.count <= 50, replacements.allSatisfy({ $0.utf8.count <= 8192 && !$0.contains("\0") }) else { throw QualityError.invalidResponse }
        return QualityFinding(id: UUID(), revision: document.revision, range: range, original: (document.source as NSString).substring(with: range), message: message, replacements: replacements, ruleID: ruleID, kind: kind, engine: engine, sourceBytes: document.sourceBytes)
    }
    public func applying(_ replacement: String, to document: QualityDocument) throws -> String {
        guard revision == document.revision, sourceBytes == document.sourceBytes else { throw QualityError.staleSource }
        guard replacement.rangeOfCharacter(from: CharacterSet(charactersIn: "\n\r`*_~[]<>\\")) == nil else { throw QualityError.protectedSyntax }
        guard replacements.contains(where: { $0.utf8.elementsEqual(replacement.utf8) }) else { throw QualityError.unofferedReplacement }
        guard document.projection.allows(range), Range(range, in: document.source) != nil, safeUTF16Range(range, in: document.source) else { throw QualityError.protectedSyntax }
        return (document.source as NSString).replacingCharacters(in: range, with: replacement)
    }
}
/// Masking preserves every UTF-16 offset. Syntax is replaced with spaces (newlines retained).
public struct MarkdownProjection: Sendable {
    public let text: String
    private let protected: [Bool]
    public init(_ source: String) {
        let ns = source as NSString
        var mask = Array(repeating: false, count: ns.length)
        func mark(_ range: NSRange) { guard range.location != NSNotFound else { return }; for i in range.location..<min(NSMaxRange(range), mask.count) { mask[i] = true } }
        // Conservative protection: code fences, inline code, URLs, HTML, link destinations and markup punctuation.
        let patterns = ["(?ms)^ {0,3}(`{3,}|~{3,})[^\\n]*\\n.*?(?:^ {0,3}\\1[ \\t]*(?:\\n|$)|\\z)", "(?s)`+[^`]*`+", "https?://[^\\s<>]+", "<[^>]*>", "!?\\[[^\\]\\n]*\\]\\([^\\n)]*\\)", "(?m)^ {0,3}(?:#{1,6}[ \\t]+|>[ \\t]?|[-+*][ \\t]+|[0-9]+[.)][ \\t]+)", "[*_~\\[\\]{}|\\\\]", "(?m)^ {0,3}\\[[^\\]]+\\]:[^\\n]*$", "(?m)^(?: {4}|\\t)[^\\n]*$"]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern) { for match in regex.matches(in: source, range: NSRange(location: 0, length: ns.length)) { mark(match.range) } }
        }
        var units = Array(source.utf16)
        for i in units.indices where mask[i] && units[i] != 10 && units[i] != 13 { units[i] = 32 }
        text = String(decoding: units, as: UTF16.self); protected = mask
    }
    public func allows(_ range: NSRange) -> Bool {
        guard range.location >= 0, range.length > 0, range.location <= protected.count, range.length <= protected.count - range.location else { return false }
        return !protected[range.location..<NSMaxRange(range)].contains(true)
    }
}
public enum LocalStyleReviewer {
    public static func check(_ document: QualityDocument) -> [QualityFinding] {
        let projected = document.projection.text
        guard let rule = try? NSRegularExpression(pattern: "(?i)\\b([\\p{L}]+)([ \\t]+)\\1\\b") else { return [] }
        return rule.matches(in: projected, range: NSRange(location: 0, length: (projected as NSString).length)).compactMap { match in
            let first = match.range(at: 1)
            let duplicate = NSRange(location: NSMaxRange(first), length: NSMaxRange(match.range) - NSMaxRange(first))
            return try? QualityFinding.make(document: document, range: duplicate, message: "Wort unmittelbar wiederholt. Lokale Basis-Stilregel; Kontext prüfen.", replacements: [""], ruleID: "BASIC_REPEATED_WORD", kind: .style, engine: "Lokale Basis-Stilregeln")
        }
    }
}
public struct QualityLanguage: Codable, Sendable, Equatable {
    public let name: String
    public let code: String
    public let longCode: String
    public init(name: String, code: String, longCode: String) { self.name = name; self.code = code; self.longCode = longCode }
}
public struct LanguageCatalog: Sendable {
    public let languages: [QualityLanguage]
    public var distinctLanguageCount: Int { Set(languages.map { $0.code.split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map(String.init) ?? $0.code }).count }
    public init(_ languages: [QualityLanguage]) { self.languages = languages }
}

func safeUTF16Range(_ range: NSRange, in source: String) -> Bool {
    let units = Array(source.utf16)
    func boundary(_ i: Int) -> Bool {
        i == 0 || i == units.count || !(0xDC00...0xDFFF).contains(units[i]) || !(0xD800...0xDBFF).contains(units[i - 1])
    }
    guard range.location >= 0, range.length >= 0, range.location <= units.count, range.length <= units.count - range.location else { return false }
    return boundary(range.location) && boundary(NSMaxRange(range))
}
