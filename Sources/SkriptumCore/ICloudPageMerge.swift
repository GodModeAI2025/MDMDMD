import Foundation

public enum ICloudPageMergeOutcome: Equatable, Sendable {
    case inserted, advanced, unchanged, conflictPreserved
}

extension LibraryStore {
    /// Remote content never replaces an open edit journal. Divergent revisions
    /// remain recoverable through the same durable history as local revisions.
    @discardableResult public func mergeICloudPage(_ incoming: Page,
        basedOn baseline: UUID?) throws -> ICloudPageMergeOutcome {
        guard !hasActiveEdits else { throw LibraryError.editInProgress }
        var candidate = snapshot
        guard let index = candidate.pages.firstIndex(where: { $0.id == incoming.id }) else {
            guard baseline == nil else { throw LibraryError.revisionConflict }
            candidate.pages.append(incoming)
            try commit(candidate)
            return .inserted
        }
        let local = candidate.pages[index]
        if local.revision == incoming.revision {
            guard local == incoming else { throw LibraryError.invalidLibrary }
            return .unchanged
        }
        if let historical = candidate.revisions.first(where: { $0.id == incoming.revision }) {
            guard historical.page == incoming else { throw LibraryError.invalidLibrary }
            return .unchanged
        }
        if baseline == local.revision {
            if !candidate.revisions.contains(where: { $0.id == local.revision }) {
                candidate.revisions.append(Revision(page: local, author: "Local", capturedAt: Date()))
            }
            candidate.pages[index] = incoming
            try commit(candidate)
            return .advanced
        }
        candidate.revisions.append(Revision(page: incoming, author: "iCloud conflict", capturedAt: Date()))
        try commit(candidate)
        return .conflictPreserved
    }
}
