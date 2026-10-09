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
        // Keep the remote record pending until every referenced asset has its
        // validated, durable local bytes. Metadata alone is not a complete page.
        for attachment in incoming.attachments ?? [] { _ = try attachmentData(attachment) }
        var candidate = snapshot
        guard let index = candidate.pages.firstIndex(where: { $0.id == incoming.id }) else {
            candidate.pages.append(incoming)
            try commit(candidate)
            return .inserted
        }
        let local = candidate.pages[index]
        if local.revision == incoming.revision {
            guard try Self.exactICloudPage(local, incoming) else { throw LibraryError.invalidLibrary }
            return .unchanged
        }
        if let historical = candidate.revisions.first(where: { $0.id == incoming.revision }) {
            guard try Self.exactICloudPage(historical.page, incoming) else { throw LibraryError.invalidLibrary }
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
    private static func exactICloudPage(_ lhs: Page, _ rhs: Page) throws -> Bool {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(lhs) == encoder.encode(rhs)
    }
}
