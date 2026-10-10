import Foundation

public struct Space: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var reusablePrompts: [ReusablePrompt]?
    public var assistantRules: String
    public var createdAt: Date
    public init(id: UUID = UUID(), title: String, assistantRules: String = "", createdAt: Date = Date()) { self.id = id; self.title = title; self.assistantRules = assistantRules; self.createdAt = createdAt }
}
public struct Block: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var markdown: String
    public init(id: UUID = UUID(), markdown: String) { self.id = id; self.markdown = markdown }
}
public enum PagePurpose: String, Codable, Sendable { case writing, material, template }

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
    public var assistantRules: String?
    public var reusablePrompts: [ReusablePrompt]?
    public var wordGoal: Int?
    public var attachments: [MediaAttachment]?
    public var purpose: PagePurpose?
    public var effectivePurpose: PagePurpose { purpose ?? .writing }
    public var markdown: String { blocks.map(\.markdown).joined() }
    public init(id: UUID = UUID(), spaceID: UUID, parentID: UUID? = nil, title: String, markdown: String = "") {
        self.id = id; self.spaceID = spaceID; self.parentID = parentID; self.title = title; blocks = MarkdownReconciler.reconcile(markdown, previous: []); revision = UUID(); tags = []; isFavorite = false; createdAt = Date(); modifiedAt = createdAt
    }
}
public struct Comment: Codable, Equatable, Identifiable, Sendable {
    public var parentCommentID: UUID?
    public var resolvedAt: Date?
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
    public var proposalReceipts: [ProposalReceipt]?
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
public enum LibraryError: Error, Equatable { case proposalConflict, receiptLimitExceeded, invalidProposalMetadata, invalidTemplate, invalidAttachment, invalidPackage, destinationExists, invalidWordGoal, missingAttachment, editInProgress, missingEdit, missingSpace, missingPage, trashedPage, trashedParent, hierarchyCycle, crossSpaceParent, forbiddenBlock, missingBlock, duplicateBlock, revisionConflict, unsupportedSchema, invalidLibrary }

extension Page {
    /// Swift String equality folds canonical Unicode equivalence. Storage must
    /// also compare bytes so an explicit normalization edit is never discarded.
    public func storageEquals(_ other: Page) -> Bool {
        self == other && title.utf8.elementsEqual(other.title.utf8)
        && (assistantRules ?? "").utf8.elementsEqual((other.assistantRules ?? "").utf8)
        && promptsStorageEqual(reusablePrompts, other.reusablePrompts)
        && zip(tags, other.tags).allSatisfy { $0.utf8.elementsEqual($1.utf8) }
        && zip(blocks, other.blocks).allSatisfy { $0.markdown.utf8.elementsEqual($1.markdown.utf8) }
    }
}
extension Space {
    func storageEquals(_ other: Space) -> Bool {
        self == other && title.utf8.elementsEqual(other.title.utf8)
        && assistantRules.utf8.elementsEqual(other.assistantRules.utf8)
        && promptsStorageEqual(reusablePrompts, other.reusablePrompts)
    }
}

public struct ReusablePrompt: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var text: String
    public init(id: UUID = UUID(), title: String, text: String) { self.id = id; self.title = title; self.text = text }
}
public struct MediaAttachment: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let filename: String
    public let mediaType: String
    public let byteCount: Int
    public let sha256: String
    public var relativePath: String { "media/" + id.uuidString }
    public init(id: UUID = UUID(), filename: String, mediaType: String, byteCount: Int, sha256: String) {
        self.id = id; self.filename = filename; self.mediaType = mediaType; self.byteCount = byteCount; self.sha256 = sha256
    }
}

private func promptsStorageEqual(_ lhs: [ReusablePrompt]?, _ rhs: [ReusablePrompt]?) -> Bool {
    guard lhs == rhs else { return false }
    return zip(lhs ?? [], rhs ?? []).allSatisfy { $0.title.utf8.elementsEqual($1.title.utf8) && $0.text.utf8.elementsEqual($1.text.utf8) }
}
