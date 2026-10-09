import Foundation

extension LibraryStore {
    @discardableResult public func replyToComment(_ id: UUID, body: String, author: String) throws -> Comment {
        guard let selected = snapshot.comments.first(where: { $0.id == id }) else { throw LibraryError.invalidLibrary }
        let rootID = selected.parentCommentID ?? selected.id
        guard let root = snapshot.comments.first(where: { $0.id == rootID }), root.parentCommentID == nil,
              !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw LibraryError.invalidLibrary }
        var reply = Comment(pageID: root.pageID, blockID: root.blockID, quotedText: root.quotedText, body: body, author: author)
        reply.parentCommentID = root.id
        try addComment(reply)
        return reply
    }
    public func setCommentResolved(_ id: UUID, resolved: Bool) throws {
        guard let selected = snapshot.comments.first(where: { $0.id == id }) else { throw LibraryError.invalidLibrary }
        let rootID = selected.parentCommentID ?? selected.id
        var next = snapshot
        guard let index = next.comments.firstIndex(where: { $0.id == rootID && $0.parentCommentID == nil }) else { throw LibraryError.invalidLibrary }
        next.comments[index].resolvedAt = resolved ? (next.comments[index].resolvedAt ?? Date()) : nil
        try commit(next)
    }
}
