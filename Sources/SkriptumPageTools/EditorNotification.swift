import Foundation

struct EditorNotificationResult {
    let token: UUID?
    let revision: UUID?
}

extension WritingLibrary {
    func processEditorNotification(previous: WritingPage, changed: WritingPage, currentDraft: WritingPage, token: UUID?) -> EditorNotificationResult? {
        // Queued SwiftUI notifications are descriptions of an earlier draft;
        // only the current visible value may enter a domain transaction.
        guard changed == currentDraft else { return nil }
        if currentPage(changed.id) == changed { return nil }
        if !previous.markdown.utf8.elementsEqual(changed.markdown.utf8) {
            guard let result = updateText(changed, token: token) else { return nil }
            return .init(token: result.token, revision: result.revision)
        } else if !previous.title.utf8.elementsEqual(changed.title.utf8) || previous.favorite != changed.favorite || previous.tags.count != changed.tags.count || !zip(previous.tags, changed.tags).allSatisfy({ $0.utf8.elementsEqual($1.utf8) }) || previous.trashed != changed.trashed || previous.wordGoal != changed.wordGoal || previous.effectivePurpose != changed.effectivePurpose {
            guard finishTyping(token) else { return nil }
            return .init(token: nil, revision: update(changed))
        }
        return nil
    }
}
