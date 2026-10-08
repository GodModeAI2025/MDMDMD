import Foundation

/// Lossless paragraph segmentation. Delimiters remain attached to the preceding
/// paragraph; fenced code is a single block even when it contains blank lines.
public enum MarkdownReconciler {
    public static func fragments(_ source: String) -> [String] {
        guard !source.isEmpty else { return [""] }
        var result: [String] = [], current = "", fence: Character?, fenceLength = 0, separatorPending = false
        let bytes = Array(source.utf8)
        var position = 0
        while position < bytes.count {
            let end = bytes[position...].firstIndex(of: 10).map { $0 + 1 } ?? bytes.count
            let line = String(decoding: bytes[position..<end], as: UTF8.self); position = end
            let wasOutsideFence = fence == nil
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let marker = trimmed.first
            if marker == "`" || marker == "~" {
                let length = trimmed.prefix(while: { $0 == marker }).count
                if length >= 3 {
                    if fence == nil { fence = marker; fenceLength = length }
                    else if marker == fence && length >= fenceLength && trimmed.dropFirst(length).isEmpty { fence = nil }
                }
            }
            let blank = trimmed.isEmpty
            if !blank, wasOutsideFence, separatorPending, !current.isEmpty { result.append(current); current = "" }
            separatorPending = blank && fence == nil
            current += line
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    /// Ordered diff matches repeated paragraphs without reusing an ID. Modified
    /// paragraphs retain a corresponding old ID in each unmatched gap.
    public static func reconcile(_ source: String, previous: [Block]) -> [Block] {
        let fragments = fragments(source)
        let oldText = previous.map { Data($0.markdown.utf8) }
        let newText = fragments.map { Data($0.utf8) }
        let difference = newText.difference(from: oldText)
        var matched: [Int: Int] = [:]
        var oldIndex = 0, newIndex = 0
        let removed = Set(difference.removals.map { change -> Int in if case .remove(let offset, _, _) = change { return offset }; return -1 })
        let inserted = Set(difference.insertions.map { change -> Int in if case .insert(let offset, _, _) = change { return offset }; return -1 })
        while oldIndex < previous.count || newIndex < fragments.count {
            if removed.contains(oldIndex) { oldIndex += 1; continue }
            if inserted.contains(newIndex) { newIndex += 1; continue }
            guard oldIndex < previous.count, newIndex < fragments.count else { break }
            matched[newIndex] = oldIndex; oldIndex += 1; newIndex += 1
        }
        // LCS treats moves as delete/insert. Match only uniquely identifiable,
        // byte-identical fragments globally before assigning changed-gap IDs.
        let oldGroups = Dictionary(grouping: previous.indices, by: { oldText[$0] })
        let newGroups = Dictionary(grouping: fragments.indices, by: { newText[$0] })
        var moved: [Int: Int] = [:]
        let anchoredOld = Set(matched.values)
        for (bytes, newIndices) in newGroups where newIndices.count == 1 {
            guard let oldIndices = oldGroups[bytes], oldIndices.count == 1,
                  matched[newIndices[0]] == nil, !anchoredOld.contains(oldIndices[0]) else { continue }
            moved[newIndices[0]] = oldIndices[0]
        }
        var result = fragments.map { Block(markdown: $0) }
        let anchors = [(-1, -1)] + matched.sorted(by: { $0.key < $1.key }).map { ($0.key, $0.value) } + [(fragments.count, previous.count)]
        for (new, old) in matched.merging(moved, uniquingKeysWith: { first, _ in first }) { result[new].id = previous[old].id }
        let movedOld = Set(moved.values)
        for index in 0..<(anchors.count - 1) {
            let start = anchors[index], end = anchors[index + 1]
            let newGap = (start.0 + 1)..<end.0, oldGap = (start.1 + 1)..<end.1
            for (new, old) in zip(newGap.filter { moved[$0] == nil }, oldGap.filter { !movedOld.contains($0) }) { result[new].id = previous[old].id }
        }
        return result
    }
}
