import Foundation

/// A Markdown URL destination and a filesystem name are different values.
/// Decode exactly once for disk/ZIP use; retain the original destination as the
/// page-local lookup key. Never turn an external URL into a filesystem request.
public enum MarkdownAssetPath {
    public static func filePath(for destination: String) -> String? {
        guard destination.utf8.count <= 4096, validURLPath(destination),
              let decoded = destination.removingPercentEncoding, validURLPath(decoded) else { return nil }
        // Also reject disguised traversal/control/scheme separators after a
        // subsequent decode, without using that decode as a different filename.
        var inspected = decoded
        for _ in 0..<5 {
            guard let next = inspected.removingPercentEncoding else { break }
            if next == inspected { break }
            guard validURLPath(next) else { return nil }
            inspected = next
        }
        let components = decoded.split(separator: "/", omittingEmptySubsequences: false)
            .filter { $0 != "." }
        guard !components.isEmpty else { return nil }
        return components.joined(separator: "/")
    }
    private static func validURLPath(_ value: String) -> Bool {
        !value.isEmpty && !value.hasPrefix("/") && !value.hasSuffix("/")
            && !value.contains("\\") && !value.contains(":") && !value.contains("//")
            && !value.contains("?") && !value.contains("#")
            && value.split(separator: "/", omittingEmptySubsequences: false).last != "."
            && !value.unicodeScalars.contains { $0.value < 32 || $0.value == 127 }
            && !value.split(separator: "/", omittingEmptySubsequences: false).contains { $0 == ".." || $0.isEmpty }
    }
}
