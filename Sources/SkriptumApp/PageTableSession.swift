import Foundation

/// A sheet has one immutable page/block identity. Its expected version advances
/// only after the durable domain commit succeeds, including Undo and Redo.
@MainActor final class PageTableSession: Identifiable {
    let id = UUID()
    let pageID: UUID
    let blockID: UUID
    var revision: UUID
    var source: String
    init(pageID: UUID, blockID: UUID, revision: UUID, source: String) {
        self.pageID = pageID; self.blockID = blockID
        self.revision = revision; self.source = source
    }
}
