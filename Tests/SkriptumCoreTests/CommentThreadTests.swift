import Foundation
import Testing
@testable import SkriptumCore

@Test @MainActor func commentThreadCanBeAnsweredAfterItsQuotedBlockWasRemoved() throws {
    let directory = URL(fileURLWithPath: "/private/tmp/CommentThreads-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try LibraryStore(directory: directory)
    let space = try store.createSpace(title: "Writing")
    let page = try store.createPage(spaceID: space.id, title: "Page", markdown: "Quoted source")
    let root = Comment(pageID: page.id, blockID: page.blocks.first?.id, quotedText: "Quoted source", body: "Discuss", author: "A")
    try store.addComment(root)
    let edit = try store.beginEditing(pageID: page.id, baseRevision: page.revision)
    try store.updateEditing(edit, blocks: [Block(markdown: "Replacement")])
    try store.finishEditing(edit)
    let reply = try store.replyToComment(root.id, body: "Still relevant", author: "B")
    #expect(reply.parentCommentID == root.id)
    #expect(reply.blockID == nil)
    #expect(reply.quotedText == root.quotedText)
    #expect(store.snapshot.pages.first?.markdown == "Replacement")
    #expect(try LibraryStore(directory: directory).snapshot.comments.count == 2)
}

@Test func legacyCommentsDecodeWithoutThreadFields() throws {
    let comment = Comment(pageID: UUID(), blockID: nil, body: "Legacy", author: "A")
    let bytes = try JSONEncoder().encode(comment)
    var object = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
    object.removeValue(forKey: "parentCommentID"); object.removeValue(forKey: "resolvedAt")
    let legacy = try JSONSerialization.data(withJSONObject: object)
    let restored = try JSONDecoder().decode(SkriptumCore.Comment.self, from: legacy)
    #expect(restored.id == comment.id && restored.body == comment.body)
    #expect(restored.parentCommentID == nil && restored.resolvedAt == nil)
}

@Test @MainActor func commentRepliesAndResolutionSurviveRestartWithoutChangingPage() throws {
    let directory = URL(fileURLWithPath: "/private/tmp/CommentThreads-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try LibraryStore(directory: directory)
    let space = try store.createSpace(title: "Writing")
    let page = try store.createPage(spaceID: space.id, title: "Page", markdown: "Original")
    let comment = Comment(pageID: page.id, blockID: page.blocks.first?.id, quotedText: "Original", body: "Clarify", author: "Author A")
    try store.addComment(comment)
    let reply = try store.replyToComment(comment.id, body: "Answer", author: "Author B")
    let second = try store.replyToComment(reply.id, body: "Follow-up", author: "Author A")
    try store.setCommentResolved(reply.id, resolved: true)
    let reopened = try LibraryStore(directory: directory)
    #expect(reopened.snapshot.comments.count == 3)
    #expect(reply.parentCommentID == comment.id && second.parentCommentID == comment.id)
    #expect(reopened.snapshot.comments.first?.resolvedAt != nil)
    #expect(reopened.snapshot.pages == [page])
    try reopened.setCommentResolved(comment.id, resolved: false)
    #expect(reopened.snapshot.comments.first?.resolvedAt == nil)
    #expect(throws: LibraryError.invalidLibrary) { try reopened.replyToComment(UUID(), body: "Wrong", author: "A") }
}
