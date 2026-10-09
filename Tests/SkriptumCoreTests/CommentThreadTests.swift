import Foundation
import Testing
@testable import SkriptumCore

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
