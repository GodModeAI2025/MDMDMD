import Foundation

/// Cumulative model snapshots must retain the exact UTF-8 prefix. Grapheme counts
/// are not offsets: a later combining accent can extend a previously sent glyph.
enum AIStreamingSnapshot {
    static func delta(from previous: String, to current: String) throws -> String {
        let old = Data(previous.utf8), new = Data(current.utf8)
        guard new.starts(with: old) else { throw AIError.malformedStream }
        return String(decoding: new.dropFirst(old.count), as: UTF8.self)
    }
}
