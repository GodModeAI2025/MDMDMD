import Foundation

public struct PageNavigationLocation: Equatable, Hashable, Sendable {
    public let pageID: UUID
    public let heading: String?
    public init(pageID: UUID, heading: String? = nil) { self.pageID = pageID; self.heading = heading }
}

/// Each window owns its own value. Resolve candidates and finish editing before
/// committing; a rejected candidate never changes the current history position.
public struct PageNavigationHistory: Sendable {
    public private(set) var libraryID: UUID
    public let capacity: Int
    private var locations: [PageNavigationLocation] = []
    private var position: Int?
    public init(libraryID: UUID, capacity: Int = 100) {
        self.libraryID = libraryID; self.capacity = min(100, max(1, capacity))
    }
    public var count: Int { locations.count }
    public var current: PageNavigationLocation? { position.map { locations[$0] } }
    public var backCandidate: PageNavigationLocation? {
        guard let position, position > 0 else { return nil }; return locations[position - 1]
    }
    public var forwardCandidate: PageNavigationLocation? {
        guard let position, position + 1 < locations.count else { return nil }; return locations[position + 1]
    }
    public mutating func visit(_ location: PageNavigationLocation) {
        guard current != location else { return }
        if let position, position + 1 < locations.count { locations.removeSubrange((position + 1)...) }
        locations.append(location)
        if locations.count > capacity { locations.removeFirst(locations.count - capacity) }
        position = locations.count - 1
    }
    @discardableResult public mutating func commitBack(to resolvedCandidate: PageNavigationLocation) -> Bool {
        guard backCandidate == resolvedCandidate, let currentPosition = position else { return false }
        position = currentPosition - 1; return true
    }
    @discardableResult public mutating func commitForward(to resolvedCandidate: PageNavigationLocation) -> Bool {
        guard forwardCandidate == resolvedCandidate, let currentPosition = position else { return false }
        position = currentPosition + 1; return true
    }
    public mutating func reset(for libraryID: UUID) {
        self.libraryID = libraryID; locations.removeAll(keepingCapacity: true); position = nil
    }
}

public extension PageLinkSourceSpan {
    /// Converts CommonMark one-based UTF-8 coordinates to UIKit UTF-16 offsets.
    /// Rejects positions inside scalars, line terminators, missing lines and
    /// reversed spans. Source revision must still be checked by the caller.
    func utf16Range(in source: String) -> NSRange? {
        let bytes = Array(source.utf8)
        var lines: [(start: Int, end: Int)] = []
        var start = 0, index = 0
        while index < bytes.count {
            if bytes[index] == 10 || bytes[index] == 13 {
                lines.append((start, index))
                if bytes[index] == 13 && index + 1 < bytes.count && bytes[index + 1] == 10 { index += 1 }
                start = index + 1
            }
            index += 1
        }
        lines.append((start, bytes.count))
        func offset(line: Int, column: Int) -> Int? {
            guard line > 0, line <= lines.count, column > 0 else { return nil }
            let bounds = lines[line - 1]
            guard column - 1 <= bounds.end - bounds.start else { return nil }
            let byteOffset = bounds.start + column - 1
            if byteOffset < bytes.count && (bytes[byteOffset] & 0xC0) == 0x80 { return nil }
            guard let prefix = String(bytes: bytes.prefix(byteOffset), encoding: .utf8) else { return nil }
            return prefix.utf16.count
        }
        guard let start = offset(line: startLine, column: startColumn),
              let end = offset(line: endLine, column: endColumn), end >= start else { return nil }
        return NSRange(location: start, length: end - start)
    }
}
