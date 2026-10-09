import Foundation
import Testing
import SkriptumCore
import SkriptumScheduling
@testable import SkriptumWorkspaceModel

@MainActor private struct LocalScheduleFixture {
    let root: URL, store: LibraryStore, library: WritingLibrary, authority: LocalScheduleAuthority
    let owner = UUID(), binding = UUID(), space: Space, page: Page
    let suite: String
    init(markdown: String = "Allowed e\u{301}\r\n🦊\n\nOutside selected context") throws {
        root = URL(fileURLWithPath: "/private/tmp/ScriptumLocalSchedule-" + UUID().uuidString)
        suite = "local.schedule.test." + UUID().uuidString
        let documents = root.appendingPathComponent("Documents")
        store = try LibraryStore(directory: documents.appendingPathComponent("Skriptum"))
        space = try store.createSpace(title: "Writing")
        page = try store.createPage(spaceID: space.id, title: "Target", markdown: markdown)
        library = try WritingLibrary(store: store, documentRoot: documents, supportRoot: root.appendingPathComponent("Support"), preferences: #require(UserDefaults(suiteName: suite)))
        authority = try LocalScheduleAuthority(library: library, ownerID: owner, providerBindingID: binding, accountBudgets: ["USD": 1_000_000])
    }
    func task(action: ScheduledAction = .summary, allowed: Set<UUID> = [], scope: SchedulingScope? = nil, bindingID: UUID? = nil) throws -> ScheduledTask {
        try ScheduledTask(scope: scope ?? authority.scope(spaceID: space.id), pageID: page.id, allowedBlockIDs: allowed,
            prompt: "Read only these authorized blocks", providerBindingID: bindingID ?? binding,
            rule: .oneShot(Date(timeIntervalSince1970: 2_000_000_000)),
            budget: BudgetPolicy(currency: "USD", perRunMicros: 100_000, monthlyMicros: 500_000, inputTokens: 32000, outputTokens: 2048),
            createdAt: Date(timeIntervalSince1970: 1_999_999_000), action: action)
    }
    func clean() { try? FileManager.default.removeItem(at: root); UserDefaults.standard.removePersistentDomain(forName: suite) }
}
@Test @MainActor func localScheduleCaptureReadsOnlyAllowedBlocksAndKeepsExactFullSourceDigest() throws {
    let f = try LocalScheduleFixture(); defer { f.clean() }
    let first = try #require(f.page.blocks.first)
    let task = try f.task(action: .proposal, allowed: [first.id])
    let capture = try f.authority.capture(task, now: task.createdAt)
    #expect(capture.sourceForProvider.utf8.elementsEqual(first.markdown.utf8))
    #expect(!capture.sourceForProvider.contains("Outside selected context"))
    #expect(capture.sourceDigest == ScheduledProposal.digest(f.page.markdown))
    #expect(capture.grant.readableBlockIDs == [first.id] && capture.grant.readablePageIDs == [f.page.id])
    #expect(capture.grant.scope == task.scope && capture.grant.generation == task.generation)
    #expect(capture.grant.expiresAt == task.createdAt.addingTimeInterval(60))
}
@Test @MainActor func localScheduleAuthorityRejectsForeignScopeProviderBudgetAndRemovedBlocks() throws {
    let f = try LocalScheduleFixture(); defer { f.clean() }
    let wrongOwner = SchedulingScope(accountID: UUID(), libraryID: f.authority.libraryID, spaceID: f.space.id)
    let wrongLibrary = SchedulingScope(accountID: f.owner, libraryID: UUID(), spaceID: f.space.id)
    let wrongSpace = SchedulingScope(accountID: f.owner, libraryID: f.authority.libraryID, spaceID: UUID())
    for scope in [wrongOwner, wrongLibrary, wrongSpace] {
        let task = try f.task(scope: scope)
        #expect(throws: (any Error).self) { try f.authority.capture(task, now: task.createdAt) }
    }
    let wrongBinding = try f.task(bindingID: UUID())
    #expect(throws: (any Error).self) { try f.authority.capture(wrongBinding, now: wrongBinding.createdAt) }
    let missingBlock = try f.task(action: .proposal, allowed: [UUID()])
    #expect(throws: (any Error).self) { try f.authority.capture(missingBlock, now: missingBlock.createdAt) }
    var overBudget = try f.task(); overBudget.budget.monthlyMicros = 2_000_000
    #expect(throws: (any Error).self) { try f.authority.capture(overBudget, now: overBudget.createdAt) }
}
@Test @MainActor func localSchedulesCannotCaptureOpenEditsOrTrashedTargetHierarchy() throws {
    let f = try LocalScheduleFixture(); defer { f.clean() }
    let task = try f.task()
    let token = try f.store.beginEditing(pageID: f.page.id, baseRevision: f.page.revision)
    #expect(throws: (any Error).self) { try f.authority.capture(task, now: task.createdAt) }
    try f.store.finishEditing(token)
    let parent = try f.store.createPage(spaceID: f.space.id, title: "Parent")
    try f.store.movePage(f.page.id, parentID: parent.id)
    try f.store.trashPage(parent.id)
    #expect(throws: (any Error).self) { try f.authority.capture(task, now: task.createdAt) }
}
@Test @MainActor func localScheduleAuthorityFeedsPersistentActivationWithoutServerOrSecrets() async throws {
    let f = try LocalScheduleFixture(); defer { f.clean() }
    let task = try f.task(), capture = try f.authority.capture(task, now: task.createdAt)
    let persistence = try FileSchedulingPersistence(url: f.root.appendingPathComponent("Schedules/state.json"))
    let queue = try SchedulingStore(persistence: persistence)
    try await queue.add(task, expectedVersion: 0)
    try await queue.activate(taskID: task.id, grant: capture.grant, now: task.createdAt, expectedVersion: 1)
    let restarted = try SchedulingStore(persistence: persistence)
    #expect(await restarted.snapshot().tasks[task.id]?.lifecycle == .active)
    let bytes = try Data(contentsOf: persistence.url)
    #expect(!String(decoding: bytes, as: UTF8.self).contains(f.page.markdown))
    let runs = try await restarted.enqueueDue(now: Date(timeIntervalSince1970: 2_000_000_000), expectedVersion: 2)
    #expect(runs.count == 1)
    #expect(await restarted.snapshot().runs[runs[0]]?.state == .queued)
}
@Test @MainActor func scheduledSourceDigestAcceptsExistingEightMiBDocumentBudgetWithoutTruncation() throws {
    let body = String(repeating: "x", count: 3 * 1024 * 1024) + "e\u{301}\r\n🦊"
    let f = try LocalScheduleFixture(markdown: body); defer { f.clean() }
    let task = try f.task(), capture = try f.authority.capture(task, now: task.createdAt)
    #expect(capture.sourceForProvider.utf8.elementsEqual(body.utf8))
    let summary = try ScheduledSummary(scope: task.scope, runID: UUID(), pageID: f.page.id, baseRevision: f.page.revision,
        source: body, text: "Fixture output", providerID: "fixture", modelID: "fixture", createdAt: task.createdAt)
    #expect(try summary.admit(scope: task.scope, pageID: f.page.id, revision: f.page.revision, source: body))
}
