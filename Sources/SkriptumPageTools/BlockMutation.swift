import Foundation
#if canImport(SkriptumCore)
import SkriptumCore
#endif

extension WritingLibrary {
    func replaceBlock(pageID: UUID, baseRevision: UUID, blockID: UUID, expectedSource: String, replacement: String) -> WritingPage? {
        guard let store, let current = store.snapshot.pages.first(where: { $0.id == pageID }),
              current.revision == baseRevision,
              let index = current.blocks.firstIndex(where: { $0.id == blockID }),
              current.blocks[index].markdown.utf8.elementsEqual(expectedSource.utf8) else {
            saveError = "Die Seite oder der Block wurde inzwischen geändert. Bitte erneut öffnen."
            return nil
        }
        var blocks = current.blocks
        blocks[index].markdown = replacement
        do {
            try store.setBlocks(pageID: pageID, blocks: blocks, baseRevision: baseRevision)
            reload(); saveError = nil; lastSaved = Date()
            return currentPage(pageID)
        } catch {
            saveError = "Die Blockänderung konnte nicht gespeichert werden: \(error.localizedDescription)"
            return nil
        }
    }
}

private func correctionBlocksEqual(_ lhs: [Block], _ rhs: [Block]) -> Bool {
    lhs.count == rhs.count && zip(lhs, rhs).allSatisfy { $0.id == $1.id && $0.markdown.utf8.elementsEqual($1.markdown.utf8) }
}

extension WritingLibrary {
    /// Domain undo never reconstructs paragraphs or publishes against a stale page.
    func restoreCorrectionBlocks(pageID: UUID, baseRevision: UUID, expected: [Block], replacement: [Block]) -> WritingPage? {
        guard let store, let current = store.snapshot.pages.first(where: { $0.id == pageID }),
              current.revision == baseRevision, correctionBlocksEqual(current.blocks, expected) else {
            saveError = "Der Text wurde inzwischen geändert. Die Korrektur wird nicht überschrieben."
            return nil
        }
        do {
            try store.setBlocks(pageID: pageID, blocks: replacement, baseRevision: baseRevision)
            reload(); saveError = nil; lastSaved = Date()
            return currentPage(pageID)
        } catch {
            saveError = "Die Korrektur konnte nicht zurückgesetzt werden: \(error.localizedDescription)"
            return nil
        }
    }
}

/// View-owned correction undo/redo. Exact block identities and bytes are retained;
/// stacks advance only after the domain write succeeds. Durable versions remain
/// available independently of this bounded, in-memory sheet history.
@MainActor struct WritingCorrectionHistory {
    private struct Entry { let before: [Block]; let after: [Block]; let cost: Int }
    private var undoEntries: [Entry] = [], redoEntries: [Entry] = []
    private var pageID: UUID?, expectedRevision: UUID?
    private let maximumSteps: Int, maximumBytes: Int
    private(set) var isLimited = false
    var canUndo: Bool { !undoEntries.isEmpty }
    var canRedo: Bool { !redoEntries.isEmpty }
    var retainedBytes: Int { (undoEntries + redoEntries).reduce(0) { $0 + $1.cost } }
    init(maximumSteps: Int = 100, maximumBytes: Int = 32 * 1024 * 1024) {
        self.maximumSteps = max(1, min(maximumSteps, 100))
        self.maximumBytes = max(0, min(maximumBytes, Int.max / 2))
    }
    @discardableResult mutating func record(before: Page, after: Page) -> Bool {
        guard before.id == after.id else { return false }
        if correctionBlocksEqual(before.blocks, after.blocks) { return true }
        let latest = undoEntries.last?.after ?? redoEntries.last?.before
        if pageID != before.id || expectedRevision != before.revision || latest.map({ !correctionBlocksEqual($0, before.blocks) }) == true {
            undoEntries = []; redoEntries = []
        }
        pageID = after.id; expectedRevision = after.revision
        redoEntries = []
        var cost = 0
        for block in before.blocks + after.blocks {
            // Account source bytes and fixed per-block identity/storage overhead.
            let bytes = block.markdown.utf8.count
            guard bytes <= maximumBytes, cost <= maximumBytes - bytes,
                  maximumBytes - cost - bytes >= 64 else {
                undoEntries = []; isLimited = true; return false
            }
            cost += bytes + 64
        }
        undoEntries.append(Entry(before: before.blocks, after: after.blocks, cost: cost))
        while undoEntries.count > maximumSteps || retainedBytes > maximumBytes {
            undoEntries.removeFirst(); isLimited = true
        }
        return true
    }
    mutating func undo(library: WritingLibrary) -> WritingPage? {
        guard let entry = undoEntries.last, let pageID, let expectedRevision,
              let saved = library.restoreCorrectionBlocks(pageID: pageID, baseRevision: expectedRevision,
                  expected: entry.after, replacement: entry.before) else { return nil }
        undoEntries.removeLast(); redoEntries.append(entry); self.expectedRevision = saved.revision
        return saved
    }
    mutating func redo(library: WritingLibrary) -> WritingPage? {
        guard let entry = redoEntries.last, let pageID, let expectedRevision,
              let saved = library.restoreCorrectionBlocks(pageID: pageID, baseRevision: expectedRevision,
                  expected: entry.before, replacement: entry.after) else { return nil }
        redoEntries.removeLast(); undoEntries.append(entry); self.expectedRevision = saved.revision
        return saved
    }
}
