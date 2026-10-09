import Foundation
#if canImport(SkriptumCore)
import SkriptumCore
#endif
#if canImport(SkriptumScheduling)
import SkriptumScheduling
#endif

enum LocalScheduleAuthorityError: Error { case unavailable, denied, sourceTooLarge }

/// Ephemeral captured content, deliberately not Codable or scheduling state.
struct LocalScheduledCapture: Sendable {
    let page: Page
    let sourceForProvider: String
    let sourceDigest: String
    let grant: ExecutionGrant
}

/// Native ownership authority for a fully owned WritingLibrary only. Shared
/// sessions have a separate type and cannot enter this boundary accidentally.
/// This admits document access; provider eligibility/pricing are separate gates.
@MainActor final class LocalScheduleAuthority {
    private weak var library: WritingLibrary?
    let ownerID: UUID, libraryID: UUID
    private let providerBindingID: UUID
    private let accountBudgets: [String: Int64]
    init(library: WritingLibrary, ownerID: UUID, providerBindingID: UUID, accountBudgets: [String: Int64]) throws {
        guard library.store != nil, accountBudgets.allSatisfy({ currency, amount in
            currency.utf8.count == 3 && currency.utf8.allSatisfy({ (65...90).contains($0) }) && amount >= 0
        }) else { throw LocalScheduleAuthorityError.unavailable }
        self.library = library; self.ownerID = ownerID; self.providerBindingID = providerBindingID; self.accountBudgets = accountBudgets
        libraryID = try Self.identity(library)
    }
    func scope(spaceID: UUID) -> SchedulingScope { .init(accountID: ownerID, libraryID: libraryID, spaceID: spaceID) }
    func capture(_ task: ScheduledTask, now: Date) throws -> LocalScheduledCapture {
        try task.validate()
        guard now.timeIntervalSince1970.isFinite, let library, let store = library.store,
              !store.hasActiveEdits, try Self.identity(library) == libraryID else { throw LocalScheduleAuthorityError.unavailable }
        guard task.scope.accountID == ownerID, task.scope.libraryID == libraryID,
              task.providerBindingID == providerBindingID, let monthly = accountBudgets[task.budget.currency],
              task.budget.monthlyMicros <= monthly,
              let page = store.snapshot.pages.first(where: { $0.id == task.pageID }),
              page.spaceID == task.scope.spaceID,
              store.snapshot.spaces.contains(where: { $0.id == page.spaceID }) else { throw LocalScheduleAuthorityError.denied }
        var ancestor: Page? = page, seen = Set<UUID>()
        while let current = ancestor {
            guard current.trashedAt == nil, seen.insert(current.id).inserted else { throw LocalScheduleAuthorityError.denied }
            if let parent = current.parentID {
                guard let value = store.snapshot.pages.first(where: { $0.id == parent }), value.spaceID == page.spaceID else { throw LocalScheduleAuthorityError.denied }
                ancestor = value
            } else { ancestor = nil }
        }
        let actual = Set(page.blocks.map(\.id))
        guard task.allowedBlockIDs.isSubset(of: actual) else { throw LocalScheduleAuthorityError.denied }
        let readable = task.action == .summary && task.allowedBlockIDs.isEmpty ? actual : task.allowedBlockIDs
        let source = page.blocks.filter { readable.contains($0.id) }.map(\.markdown).joined()
        guard page.markdown.utf8.count <= 8 * 1024 * 1024, source.utf8.count <= 8 * 1024 * 1024 else { throw LocalScheduleAuthorityError.sourceTooLarge }
        let grant = ExecutionGrant(scope: task.scope, taskID: task.id, generation: task.generation,
            accountMonthlyMicros: monthly, expiresAt: now.addingTimeInterval(60), role: .owner,
            readablePageIDs: [page.id], readableBlockIDs: readable)
        try grant.admit(task, now: now)
        return LocalScheduledCapture(page: page, sourceForProvider: source, sourceDigest: ScheduledProposal.digest(page.markdown), grant: grant)
    }
    private static func identity(_ library: WritingLibrary) throws -> UUID {
        switch try library.ownedWindowLocator() {
        case .primary: UUID(uuidString: "75BA73C5-4058-4F71-B810-CA49C7B17675")!
        case .imported(let id): id
        }
    }
}
