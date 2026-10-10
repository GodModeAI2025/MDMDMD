import Foundation
#if canImport(SkriptumCore)
import SkriptumCore
#endif

@MainActor
struct EditorNotificationResult {
    let token: UUID?
    let revision: UUID?
    private let mutation: EditorMutationReceipt?

    fileprivate init(token: UUID?, revision: UUID?, mutation: EditorMutationReceipt? = nil) {
        self.token = token; self.revision = revision; self.mutation = mutation
    }
    func confirmedSuccessor(store: LibraryStore, preceding: Page) -> Page? {
        guard let mutation, mutation.store === store, mutation.before.storageEquals(preceding),
              let actual = store.snapshot.pages.first(where: { $0.id == preceding.id }),
              actual.storageEquals(mutation.after) else { return nil }
        return actual
    }
}

/// Created only by the synchronous, revision-guarded editor transaction below.
/// A DTO, notification echo or provider result cannot manufacture a receipt.
@MainActor fileprivate final class EditorMutationReceipt {
    weak var store: LibraryStore?
    let before: Page, after: Page
    init(store: LibraryStore, before: Page, after: Page) {
        self.store = store; self.before = before; self.after = after
    }
}

extension WritingLibrary {
    func processEditorNotification(previous: WritingPage, changed: WritingPage, currentDraft: WritingPage, token: UUID?) -> EditorNotificationResult? {
        // Queued SwiftUI notifications are descriptions of an earlier draft;
        // only the current visible value may enter a domain transaction.
        guard changed == currentDraft else { return nil }
        if currentPage(changed.id) == changed { return nil }
        let previousCore = store?.snapshot.pages.first(where: { $0.id == changed.id })
        func receipt(revision: UUID?) -> EditorMutationReceipt? {
            guard let revision, let store, let previousCore,
                  let after = store.snapshot.pages.first(where: { $0.id == changed.id }),
                  after.revision == revision else { return nil }
            return EditorMutationReceipt(store: store, before: previousCore, after: after)
        }
        if !previous.markdown.utf8.elementsEqual(changed.markdown.utf8) {
            guard let result = updateText(changed, token: token) else { return nil }
            return .init(token: result.token, revision: result.revision, mutation: receipt(revision: result.revision))
        } else if !previous.title.utf8.elementsEqual(changed.title.utf8) || previous.favorite != changed.favorite || previous.tags.count != changed.tags.count || !zip(previous.tags, changed.tags).allSatisfy({ $0.utf8.elementsEqual($1.utf8) }) || previous.trashed != changed.trashed || previous.wordGoal != changed.wordGoal || previous.effectivePurpose != changed.effectivePurpose {
            guard finishTyping(token) else { return nil }
            let revision = update(changed)
            return .init(token: nil, revision: revision, mutation: receipt(revision: revision))
        }
        return nil
    }
}
