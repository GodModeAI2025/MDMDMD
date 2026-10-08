import Foundation

public struct Space: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var assistantRules: String
    public var createdAt: Date
    public init(id: UUID = UUID(), title: String, assistantRules: String = "", createdAt: Date = Date()) { self.id = id; self.title = title; self.assistantRules = assistantRules; self.createdAt = createdAt }
}
public struct Block: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var markdown: String
    public init(id: UUID = UUID(), markdown: String) { self.id = id; self.markdown = markdown }
}
public struct Page: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var spaceID: UUID
    public var parentID: UUID?
    public var title: String
    public var blocks: [Block]
    public var revision: UUID
    public var tags: [String]
    public var isFavorite: Bool
    public var createdAt: Date
    public var modifiedAt: Date
    public var trashedAt: Date?
    public var markdown: String { blocks.map(\.markdown).joined() }
    public init(id: UUID = UUID(), spaceID: UUID, parentID: UUID? = nil, title: String, markdown: String = "") {
        self.id = id; self.spaceID = spaceID; self.parentID = parentID; self.title = title; blocks = MarkdownReconciler.reconcile(markdown, previous: []); revision = UUID(); tags = []; isFavorite = false; createdAt = Date(); modifiedAt = createdAt
    }
}
public struct Comment: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var pageID: UUID
    public var blockID: UUID?
    public var quotedText: String
    public var body: String
    public var author: String
    public var createdAt: Date
    public init(id: UUID = UUID(), pageID: UUID, blockID: UUID?, quotedText: String = "", body: String, author: String, createdAt: Date = Date()) { self.id = id; self.pageID = pageID; self.blockID = blockID; self.quotedText = quotedText; self.body = body; self.author = author; self.createdAt = createdAt }
}
public struct Revision: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID { page.revision }
    public var page: Page
    public var author: String
    public var capturedAt: Date
}
public struct LibrarySnapshot: Codable, Equatable, Sendable {
    public var schemaVersion = 1
    public var spaces: [Space] = []
    public var pages: [Page] = []
    public var comments: [Comment] = []
    public var revisions: [Revision] = []
    public init() {}
}
public enum PatchOperation: Codable, Equatable, Sendable {
    case replace(blockID: UUID, markdown: String)
    case delete(blockID: UUID)
    case insert(afterBlockID: UUID, block: Block)
}
public struct PagePatch: Codable, Equatable, Sendable {
    public var pageID: UUID
    public var baseRevision: UUID
    public var allowedBlockIDs: Set<UUID>
    public var operations: [PatchOperation]
    public init(pageID: UUID, baseRevision: UUID, allowedBlockIDs: Set<UUID>, operations: [PatchOperation]) { self.pageID = pageID; self.baseRevision = baseRevision; self.allowedBlockIDs = allowedBlockIDs; self.operations = operations }
}
public enum LibraryError: Error, Equatable { case editInProgress, missingEdit, missingSpace, missingPage, trashedParent, hierarchyCycle, crossSpaceParent, forbiddenBlock, missingBlock, duplicateBlock, revisionConflict, unsupportedSchema, invalidLibrary }
