import Foundation

/// A missing dictionary must not silently become an unrelated language or
/// another writing system. The actual selected dictionary remains visible.
public enum SpellingLanguageChoice {
    public static func suggested(detected: String?, system: String, dictionaries: [String]) -> String? {
        func normalized(_ value: String) -> String { value.replacingOccurrences(of: "_", with: "-").lowercased() }
        func primary(_ value: String) -> Substring? { value.split(separator: "-").first }
        func script(_ value: String) -> Substring? {
            value.split(separator: "-").dropFirst().first { $0.count == 4 && $0.allSatisfy(\.isLetter) }
        }
        let wanted = normalized(detected ?? system), preferred = normalized(system)
        guard let language = primary(wanted) else { return nil }
        let candidates = dictionaries.filter {
            let candidate = normalized($0)
            return primary(candidate) == language && (script(wanted) == nil || script(candidate) == script(wanted))
        }
        if wanted == String(language), primary(preferred) == language,
           let local = candidates.first(where: { normalized($0) == preferred }) { return local }
        if let exact = candidates.first(where: { normalized($0) == wanted }) { return exact }
        if primary(preferred) == language, let local = candidates.first(where: { normalized($0) == preferred }) { return local }
        return candidates.first
    }
}
