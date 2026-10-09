import Foundation

/// A synchronous, main-actor store: every successful mutation has reached atomic disk storage.
@MainActor public final class LibraryStore {
    /// Receives only content successfully committed to disk, excluding open
    /// editor drafts. Observers must schedule work without reentering mutations.
    public var onDurableChange: (@MainActor (LibrarySnapshot) -> Void)?
    public private(set) var snapshot: LibrarySnapshot
    public let directory: URL
    private var edits: [UUID: EditJournal] = [:]
    private var journalDirectory: URL { directory.appendingPathComponent("edits", isDirectory: true) }
    private func journalFile(_ token: UUID) -> URL { journalDirectory.appendingPathComponent(token.uuidString).appendingPathExtension("json") }
    private var file: URL { directory.appendingPathComponent("library.json") }
    public init(directory: URL) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: directory.appendingPathComponent("library.json").path) {
            snapshot = try JSONDecoder().decode(LibrarySnapshot.self, from: Data(contentsOf: directory.appendingPathComponent("library.json")))
            guard snapshot.schemaVersion == 1 else { throw LibraryError.unsupportedSchema }
            try Self.validate(snapshot)
        } else { snapshot = LibrarySnapshot() }
        if FileManager.default.fileExists(atPath: journalDirectory.path) {
            let files = try FileManager.default.contentsOfDirectory(at: journalDirectory, includingPropertiesForKeys: nil).filter { $0.pathExtension == "json" }
            var recovered = snapshot
            for file in files {
                let journal = try JSONDecoder().decode(EditJournal.self, from: Data(contentsOf: file))
                guard let index = recovered.pages.firstIndex(where: { $0.id == journal.current.id }) else { throw LibraryError.invalidLibrary }
                if recovered.pages[index].revision == journal.baseline.revision {
                    recovered.pages[index] = journal.current
                } else if recovered.pages[index].revision != journal.current.revision { throw LibraryError.revisionConflict }
                if journal.current != journal.baseline, !recovered.revisions.contains(where: { $0.id == journal.baseline.revision }) { recovered.revisions.append(Revision(page: journal.baseline, author: "User", capturedAt: Date())) }
            }
            if recovered != snapshot { try commit(recovered) }
            for file in files { try FileManager.default.removeItem(at: file) }
        }
    }
    func commit(_ candidate: LibrarySnapshot, finalizing token: UUID? = nil) throws {
        try Self.validate(candidate)
        // An unrelated mutation must never publish an intermediate journal
        // revision: recovery compares disk baseline with the latest journal.
        var durable = candidate
        for (activeToken, journal) in edits where activeToken != token {
            guard let index = durable.pages.firstIndex(where: { $0.id == journal.baseline.id }) else { throw LibraryError.invalidLibrary }
            durable.pages[index] = journal.baseline
        }
        try Self.validate(durable)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(durable).write(to: file, options: .atomic)
        snapshot = candidate
        onDurableChange?(durable)
    }
    static func validate(_ state: LibrarySnapshot) throws {
        try ProposalReceipt.validate(state.proposalReceipts ?? [])
        guard Set(state.spaces.map(\.id)).count == state.spaces.count, Set(state.pages.map(\.id)).count == state.pages.count, Set(state.comments.map(\.id)).count == state.comments.count, Set(state.revisions.map(\.id)).count == state.revisions.count else { throw LibraryError.invalidLibrary }
        let spaces = Set(state.spaces.map(\.id)); let pages = Dictionary(uniqueKeysWithValues: state.pages.map { ($0.id, $0) })
        guard state.comments.allSatisfy({ pages[$0.pageID] != nil }) else { throw LibraryError.invalidLibrary }
        for space in state.spaces {
            guard Set((space.reusablePrompts ?? []).map(\.id)).count == (space.reusablePrompts ?? []).count else { throw LibraryError.invalidLibrary }
        }
        var knownAttachments: [UUID: MediaAttachment] = [:]
        for page in state.pages + state.revisions.map(\.page) {
            // Historical hierarchy is a snapshot of its own time; only local
            // metadata invariants apply, never today's parent/space membership.
            guard (page.wordGoal ?? 0) >= 0, Set(page.blocks.map(\.id)).count == page.blocks.count,
                  Set((page.attachments ?? []).map(\.id)).count == (page.attachments ?? []).count,
                  Set((page.reusablePrompts ?? []).map(\.id)).count == (page.reusablePrompts ?? []).count else { throw LibraryError.invalidLibrary }
            for attachment in page.attachments ?? [] {
                guard !attachment.filename.isEmpty, !attachment.filename.contains("/"), !attachment.filename.contains("\\"),
                      attachment.filename != ".", attachment.filename != "..",
                      ["image/png", "image/jpeg"].contains(attachment.mediaType),
                      attachment.byteCount > 0, attachment.byteCount <= MediaValidation.maximumBytes,
                      attachment.sha256.utf8.count == 64,
                      attachment.sha256.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
                      knownAttachments[attachment.id].map({ $0 == attachment }) ?? true else { throw LibraryError.invalidLibrary }
                knownAttachments[attachment.id] = attachment
            }
        }
        for page in state.pages {
            guard (page.wordGoal ?? 0) >= 0, spaces.contains(page.spaceID), Set(page.blocks.map(\.id)).count == page.blocks.count else { throw LibraryError.invalidLibrary }
            var visited: Set<UUID> = [page.id]; var parent = page.parentID
            while let id = parent {
                guard visited.insert(id).inserted else { throw LibraryError.hierarchyCycle }
                guard let ancestor = pages[id] else { throw LibraryError.missingPage }
                guard ancestor.spaceID == page.spaceID else { throw LibraryError.crossSpaceParent }
                parent = ancestor.parentID
            }
        }
    }
    @discardableResult public func createSpace(title: String) throws -> Space {
        var state = snapshot; let space = Space(title: title); state.spaces.append(space); try commit(state); return space
    }
    @discardableResult public func createPage(spaceID: UUID, parentID: UUID? = nil, title: String, markdown: String = "") throws -> Page {
        guard snapshot.spaces.contains(where: { $0.id == spaceID }) else { throw LibraryError.missingSpace }
        if let parentID, let parent = snapshot.pages.first(where: { $0.id == parentID }), parent.trashedAt != nil { throw LibraryError.trashedParent }
        var state = snapshot; let page = Page(spaceID: spaceID, parentID: parentID, title: title, markdown: markdown); state.pages.append(page); try commit(state); return page
    }
    func edit(_ id: UUID, author: String = "User", _ body: (inout Page) throws -> Void) throws {
        guard !edits.values.contains(where: { $0.current.id == id }) else { throw LibraryError.editInProgress }
        var state = snapshot; guard let index = state.pages.firstIndex(where: { $0.id == id }) else { throw LibraryError.missingPage }
        let old = state.pages[index]; try body(&state.pages[index]); guard !state.pages[index].storageEquals(old) else { return }; state.pages[index].revision = UUID(); state.pages[index].modifiedAt = Date(); state.revisions.append(Revision(page: old, author: author, capturedAt: Date())); try commit(state)
    }
    public func renamePage(_ id: UUID, title: String) throws { try edit(id) { $0.title = title } }
    public func renameSpace(_ id: UUID, title: String) throws { var state = snapshot; guard let index = state.spaces.firstIndex(where: { $0.id == id }) else { throw LibraryError.missingSpace }; let old = state.spaces[index]; state.spaces[index].title = title; guard !state.spaces[index].storageEquals(old) else { return }; try commit(state) }
    public func movePage(_ id: UUID, parentID: UUID?) throws { if let parentID, let parent = snapshot.pages.first(where: { $0.id == parentID }), parent.trashedAt != nil { throw LibraryError.trashedParent }; try edit(id) { $0.parentID = parentID } }
    public func setFavorite(_ id: UUID, value: Bool) throws { try edit(id) { $0.isFavorite = value } }
    public func setTags(_ id: UUID, tags: [String]) throws { try edit(id) { var seen: Set<Data> = []; $0.tags = tags.filter { seen.insert(Data($0.utf8)).inserted }.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) } } }
    public func setMarkdown(_ id: UUID, markdown: String, baseRevision: UUID) throws {
        try edit(id) { page in guard page.revision == baseRevision else { throw LibraryError.revisionConflict }; page.blocks = MarkdownReconciler.reconcile(markdown, previous: page.blocks) }
    }
    /// Preserves caller-provided IDs and order. Block strings concatenate verbatim;
    /// callers own separators and may submit an empty block array for an empty page.
    public func setBlocks(pageID: UUID, blocks: [Block], baseRevision: UUID) throws {
        guard Set(blocks.map(\.id)).count == blocks.count else { throw LibraryError.duplicateBlock }
        try edit(pageID) { page in
            guard page.revision == baseRevision else { throw LibraryError.revisionConflict }
            page.blocks = blocks
        }
    }
    /// Begin a coalesced typing session. Updates are durably journalled per page;
    /// finishing publishes a single historical baseline, never discarding versions.
    @discardableResult public func beginEditing(pageID: UUID, baseRevision: UUID) throws -> UUID {
        guard !edits.values.contains(where: { $0.current.id == pageID }) else { throw LibraryError.editInProgress }
        guard let page = snapshot.pages.first(where: { $0.id == pageID }) else { throw LibraryError.missingPage }
        guard page.revision == baseRevision else { throw LibraryError.revisionConflict }
        let token = UUID()
        try FileManager.default.createDirectory(at: journalDirectory, withIntermediateDirectories: true)
        let journal = EditJournal(token: token, baseline: page, current: page)
        try JSONEncoder().encode(journal).write(to: journalFile(token), options: .atomic)
        edits[token] = journal
        return token
    }
    public func updateEditing(_ token: UUID, markdown: String) throws {
        guard let journal = edits[token] else { throw LibraryError.missingEdit }
        guard !journal.current.markdown.utf8.elementsEqual(markdown.utf8) else { return }
        try updateEditing(token, blocks: MarkdownReconciler.reconcile(markdown, previous: journal.current.blocks))
    }
    /// Atomically journals exact block IDs, order and UTF-8 source. Identity-only
    /// reorders of duplicate text still count as edits and retain comment anchors.
    public func updateEditing(_ token: UUID, blocks: [Block]) throws {
        guard var journal = edits[token], let index = snapshot.pages.firstIndex(where: { $0.id == journal.current.id }) else { throw LibraryError.missingEdit }
        guard Set(blocks.map(\.id)).count == blocks.count else { throw LibraryError.duplicateBlock }
        var candidate = journal.current; candidate.blocks = blocks
        guard !candidate.storageEquals(journal.current) else { return }
        journal.current = candidate
        journal.current.revision = UUID(); journal.current.modifiedAt = Date()
        try JSONEncoder().encode(journal).write(to: journalFile(token), options: .atomic)
        snapshot.pages[index] = journal.current; edits[token] = journal
    }
    public func finishEditing(_ token: UUID) throws {
        guard let journal = edits[token] else { throw LibraryError.missingEdit }
        var state = snapshot
        if journal.current != journal.baseline { state.revisions.append(Revision(page: journal.baseline, author: "User", capturedAt: Date())) }
        try commit(state, finalizing: token)
        edits.removeValue(forKey: token)
        try FileManager.default.removeItem(at: journalFile(token))
    }
    public func trashPage(_ id: UUID) throws { try setTrash(id, date: Date()) }
    public func restorePage(_ id: UUID) throws { try setTrash(id, date: nil) }
    private func setTrash(_ id: UUID, date: Date?) throws {
        guard edits.isEmpty else { throw LibraryError.editInProgress }
        guard snapshot.pages.contains(where: { $0.id == id }) else { throw LibraryError.missingPage }
        var ids: Set<UUID> = [id]; var changed = true
        while changed { let count = ids.count; for page in snapshot.pages where page.parentID.map(ids.contains) == true { ids.insert(page.id) }; changed = count != ids.count }
        var state = snapshot
        for index in state.pages.indices where ids.contains(state.pages[index].id) { let old = state.pages[index]; state.revisions.append(Revision(page: old, author: "User", capturedAt: Date())); state.pages[index].trashedAt = date; state.pages[index].modifiedAt = Date(); state.pages[index].revision = UUID() }
        try commit(state)
    }
    public func apply(_ patch: PagePatch, author: String = "Assistant") throws {
        try edit(patch.pageID, author: author) { page in
            try Self.applyValidatedPatch(patch, to: &page)
        }
    }
    /// Receipt and mutation are published by the same atomic library commit.
    /// An exact retry returns the original outcome even after subsequent edits.
    @discardableResult public func applyProposal(_ proposalID: UUID, patch: PagePatch, author: String = "Assistant") throws -> ProposalReceipt {
        let fingerprint = patch.receiptFingerprint()
        if let receipt = snapshot.proposalReceipts?.first(where: { $0.proposalID == proposalID }) {
            guard receipt.pageID == patch.pageID, receipt.patchFingerprint == fingerprint,
                  receipt.author.utf8.elementsEqual(author.utf8) else { throw LibraryError.proposalConflict }
            return receipt
        }
        guard !author.isEmpty, author.utf8.count <= 1_024 else { throw LibraryError.invalidProposalMetadata }
        guard (snapshot.proposalReceipts?.count ?? 0) < ProposalReceipt.maximumCount else { throw LibraryError.receiptLimitExceeded }
        guard !edits.values.contains(where: { $0.current.id == patch.pageID }) else { throw LibraryError.editInProgress }
        var state = snapshot
        guard let index = state.pages.firstIndex(where: { $0.id == patch.pageID }) else { throw LibraryError.missingPage }
        let old = state.pages[index]
        try Self.applyValidatedPatch(patch, to: &state.pages[index])
        if !state.pages[index].storageEquals(old) {
            state.pages[index].revision = UUID()
            state.pages[index].modifiedAt = Date()
            state.revisions.append(Revision(page: old, author: author, capturedAt: Date()))
        }
        let receipt = ProposalReceipt(proposalID: proposalID, patch: patch, fingerprint: fingerprint,
                                      appliedRevision: state.pages[index].revision, author: author)
        state.proposalReceipts = (state.proposalReceipts ?? []) + [receipt]
        try commit(state)
        return receipt
    }
    private static func applyValidatedPatch(_ patch: PagePatch, to page: inout Page) throws {
        guard page.revision == patch.baseRevision else { throw LibraryError.revisionConflict }
        guard page.trashedAt == nil else { throw LibraryError.trashedPage }
        let originals = Set(page.blocks.map(\.id))
        guard patch.allowedBlockIDs.isSubset(of: originals) else { throw LibraryError.forbiddenBlock }
        for operation in patch.operations {
            let target: UUID
            switch operation { case .replace(let id, _), .delete(let id): target = id; case .insert(let id, _): target = id }
            guard patch.allowedBlockIDs.contains(target) else { throw LibraryError.forbiddenBlock }
            guard let index = page.blocks.firstIndex(where: { $0.id == target }) else { throw LibraryError.missingBlock }
            switch operation {
            case .replace(_, let text): page.blocks[index].markdown = text
            case .delete: page.blocks.remove(at: index)
            case .insert(_, let block): guard !page.blocks.contains(where: { $0.id == block.id }), !originals.contains(block.id) else { throw LibraryError.duplicateBlock }; page.blocks.insert(block, at: index + 1)
            }
        }
    }
    public func restoreRevision(pageID: UUID, revisionID: UUID, baseRevision: UUID) throws {
        guard let historical = snapshot.revisions.first(where: { $0.id == revisionID && $0.page.id == pageID }) else { throw LibraryError.revisionConflict }
        try edit(pageID) { page in
            guard page.revision == baseRevision else { throw LibraryError.revisionConflict }
            let currentParent = page.parentID
            page = historical.page
            page.parentID = currentParent
        }
    }
    public var hasActiveEdits: Bool { !edits.isEmpty }
    public func search(_ query: String, includeTrash: Bool = false) -> [Page] {
        snapshot.pages.filter { (includeTrash || $0.trashedAt == nil) && (query.isEmpty || $0.title.localizedStandardContains(query) || $0.markdown.localizedStandardContains(query) || $0.tags.contains(where: { $0.localizedStandardContains(query) })) }
    }
    public func addComment(_ comment: Comment) throws { var state = snapshot; guard let page = state.pages.first(where: { $0.id == comment.pageID }) else { throw LibraryError.missingPage }; if let id = comment.blockID, !page.blocks.contains(where: { $0.id == id }) { throw LibraryError.missingBlock }; state.comments.append(comment); try commit(state) }
}


extension LibraryStore {
    public func setPurpose(pageID: UUID, purpose: PagePurpose, baseRevision: UUID) throws {
        try edit(pageID) { page in
            guard page.revision == baseRevision else { throw LibraryError.revisionConflict }
            guard page.trashedAt == nil else { throw LibraryError.invalidTemplate }
            page.purpose = purpose
        }
    }
    /// Stable library order; callers select/reorder chapters without including research or templates.
    public func manuscriptPages(spaceID: UUID) -> [Page] {
        snapshot.pages.filter { $0.spaceID == spaceID && $0.trashedAt == nil && $0.effectivePurpose == .writing }
    }
    /// Uses the caller's document word counter, rather than treating Markdown tokens as prose.
    public func aggregateWordCount(spaceID: UUID, countWords: (String) -> Int) -> Int {
        manuscriptPages(spaceID: spaceID).reduce(0) { $0 + countWords($1.markdown) }
    }
    @discardableResult public func instantiateTemplate(pageID: UUID, baseRevision: UUID, spaceID: UUID, parentID: UUID? = nil) throws -> Page {
        guard !edits.values.contains(where: { $0.current.id == pageID }) else { throw LibraryError.editInProgress }
        guard let source = snapshot.pages.first(where: { $0.id == pageID }) else { throw LibraryError.missingPage }
        guard source.revision == baseRevision else { throw LibraryError.revisionConflict }
        guard source.trashedAt == nil, source.effectivePurpose == .template else { throw LibraryError.invalidTemplate }
        var draft = source
        draft.purpose = .writing
        draft.blocks = source.blocks.map { Block(markdown: $0.markdown) }
        return try createRecoveredPage(from: draft, spaceID: spaceID, parentID: parentID, mediaRoot: directory)
    }
}
