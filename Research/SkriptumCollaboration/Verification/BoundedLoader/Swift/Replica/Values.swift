import Foundation

public struct ReplicaIdentity: Codable, Hashable, Sendable {
    public let libraryID: UUID
    public let spaceID: UUID
    public let pageID: UUID
    public init(libraryID: UUID, spaceID: UUID, pageID: UUID) { self.libraryID = libraryID; self.spaceID = spaceID; self.pageID = pageID }
}
public struct ReplicaSeedBlock: Codable, Sendable {
    public let id: UUID
    public let markdown: String
    public init(id: UUID = UUID(), markdown: String) { self.id = id; self.markdown = markdown }
}
public struct UTF16Range: Codable, Hashable, Sendable {
    public let location: Int
    public let length: Int
    public init(location: Int, length: Int) { self.location = location; self.length = length }
}
public struct ReplicaLimits: Sendable {
    public let maximumIncomingBytes: Int
    public let maximumSavedBytes: Int
    public let maximumTextBytes: Int
    public let maximumBlocks: Int
    public init(maximumIncomingBytes: Int = 8_388_608, maximumSavedBytes: Int = 16_777_216, maximumTextBytes: Int = 8_388_608, maximumBlocks: Int = 10_000) { self.maximumIncomingBytes = maximumIncomingBytes; self.maximumSavedBytes = maximumSavedBytes; self.maximumTextBytes = maximumTextBytes; self.maximumBlocks = maximumBlocks }
}
public struct ReplicaVersion: Codable, Hashable, Sendable {
    public let heads: Data
    public init(heads: Data) { self.heads = heads }
}
public struct ReplicaBlock: Codable, Equatable, Sendable {
    public let id: UUID
    public let markdown: String
    public let isDeleted: Bool
    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id && lhs.isDeleted == rhs.isDeleted && lhs.markdown.utf8.elementsEqual(rhs.markdown.utf8) }
}
public enum ReplicaConflict: Equatable, Sendable {
    case deletionEdit(blockID: UUID, recoverableMarkdown: String)
    case deletionState(blockID: UUID)
    case ordering(blockID: UUID, anchors: [String])
    case orderingCycle([UUID])
    case concurrentPlacement(anchor: UUID?, blocks: [UUID])
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case let (.deletionEdit(a, textA), .deletionEdit(b, textB)): a == b && textA.utf8.elementsEqual(textB.utf8)
        case let (.deletionState(a), .deletionState(b)): a == b
        case let (.ordering(a, x), .ordering(b, y)): a == b && x == y
        case let (.orderingCycle(a), .orderingCycle(b)): a == b
        case let (.concurrentPlacement(a, x), .concurrentPlacement(b, y)): a == b && x == y
        default: false
        }
    }
}
public struct ReplicaSnapshot: Equatable, Sendable {
    public let identity: ReplicaIdentity
    /// Includes tombstoned records so recovery text is never discarded.
    public let blocks: [ReplicaBlock]
    public let conflicts: [ReplicaConflict]
    public let version: ReplicaVersion
    public var activeBlocks: [ReplicaBlock] { blocks.filter { !$0.isDeleted } }
    public var markdown: String { activeBlocks.map(\.markdown).joined() }
}
public enum ReplicaError: Error, Equatable, Sendable {
    case identityMismatch, invalidSchema, invalidVersion, invalidUTF16Range, missingBlock, duplicateBlock, deletedBlock, invalidOrder, limitExceeded
}
