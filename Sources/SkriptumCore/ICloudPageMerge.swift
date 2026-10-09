import Foundation

public enum ICloudPageMergeOutcome: Equatable, Sendable {
    case inserted, advanced, unchanged, historical, conflictPreserved
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
            return .historical
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

public enum ICloudPageResolutionChoice: Sendable { case local, remote, mergedMarkdown(String) }
public struct ICloudPageResolution: Sendable {
    public let local: Page, remote: Page, resolved: Page
}
extension LibraryStore {
    public func prepareICloudPageResolution(remote: Page, expectedLocalRevision: UUID,
                                           choice: ICloudPageResolutionChoice) throws -> ICloudPageResolution {
        guard !hasActiveEdits else { throw LibraryError.editInProgress }
        guard let local = snapshot.pages.first(where: { $0.id == remote.id }) else { throw LibraryError.missingPage }
        guard local.revision == expectedLocalRevision, remote.revision != local.revision else { throw LibraryError.revisionConflict }
        for attachment in remote.attachments ?? [] { _ = try attachmentData(attachment) }
        var chosen: Page
        switch choice {
        case .local: chosen = local
        case .remote: chosen = remote
        case .mergedMarkdown(let markdown):
            chosen = local; chosen.blocks = MarkdownReconciler.reconcile(markdown, previous: local.blocks)
            var attachments = local.attachments ?? []
            for image in remote.attachments ?? [] {
                if let existing = attachments.first(where: { $0.id == image.id }) {
                    guard try exactAttachment(existing, image) else { throw LibraryError.invalidAttachment }
                } else { attachments.append(image) }
            }
            var referenceSnapshot = LibrarySnapshot(); referenceSnapshot.pages = [chosen]
            let needed = Set(AttachmentInventory(libraryID: UUID(), snapshot: referenceSnapshot).references(on: chosen.id).map(\.attachmentID))
            // Only this page's history can heal an older merge buffer's image
            // metadata. Other private pages are outside this automatic scope.
            let historicalImages = snapshot.revisions.filter { $0.page.id == local.id }.flatMap { $0.page.attachments ?? [] }
            for id in needed.sorted(by: { $0.uuidString < $1.uuidString }) {
                if let image = attachments.first(where: { $0.id == id }) { _ = try attachmentData(image); continue }
                let candidates = historicalImages.filter { $0.id == id }
                guard let image = candidates.first else { throw LibraryError.missingAttachment }
                for candidate in candidates { guard try exactAttachment(image, candidate) else { throw LibraryError.invalidAttachment } }
                _ = try attachmentData(image)
                attachments.append(image)
            }
            if local.attachments != nil || remote.attachments != nil || !attachments.isEmpty { chosen.attachments = attachments }
        }
        chosen.revision = UUID(); chosen.modifiedAt = Date()
        let resolution = ICloudPageResolution(local: local, remote: remote, resolved: chosen)
        _ = try resolutionSnapshot(resolution)
        return resolution
    }
    private func exactAttachment(_ first: MediaAttachment, _ second: MediaAttachment) throws -> Bool {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(first) == encoder.encode(second)
    }
    public func applyICloudPageResolution(_ resolution: ICloudPageResolution) throws {
        guard !hasActiveEdits else { throw LibraryError.editInProgress }
        guard let current = snapshot.pages.first(where: { $0.id == resolution.local.id }) else { throw LibraryError.missingPage }
        if current.revision == resolution.resolved.revision {
            guard try Self.exactICloudPage(current, resolution.resolved) else { throw LibraryError.invalidLibrary }
            return
        }
        guard try Self.exactICloudPage(current, resolution.local) else { throw LibraryError.revisionConflict }
        try commit(resolutionSnapshot(resolution))
    }
    private func resolutionSnapshot(_ resolution: ICloudPageResolution) throws -> LibrarySnapshot {
        guard resolution.local.id == resolution.remote.id, resolution.local.id == resolution.resolved.id,
              resolution.local.revision != resolution.remote.revision,
              resolution.resolved.revision != resolution.local.revision,
              resolution.resolved.revision != resolution.remote.revision else { throw LibraryError.invalidLibrary }
        var candidate = snapshot
        guard let index = candidate.pages.firstIndex(where: { $0.id == resolution.local.id }) else { throw LibraryError.missingPage }
        for page in [resolution.local, resolution.remote] {
            if let known = candidate.revisions.first(where: { $0.id == page.revision }) {
                guard try Self.exactICloudPage(known.page, page) else { throw LibraryError.invalidLibrary }
            } else {
                candidate.revisions.append(Revision(page: page, author: page.revision == resolution.local.revision ? "Local before iCloud resolution" : "iCloud before resolution", capturedAt: resolution.resolved.modifiedAt))
            }
        }
        candidate.pages[index] = resolution.resolved
        try Self.validate(candidate)
        return candidate
    }
}
