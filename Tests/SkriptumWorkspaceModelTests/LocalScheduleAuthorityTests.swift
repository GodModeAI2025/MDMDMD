import Foundation
import Testing
import SkriptumCore
import SkriptumScheduling
import SkriptumAI
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

private actor FixtureScheduledExecutor: LocalScheduledExecutor {
    enum Behavior: Sendable { case summary(Int64?), proposal, preflightDenied, interrupted, changedModel }
    nonisolated let bindingID: UUID
    nonisolated let providerID = "fixture", modelID = "fixture-model", pricingVersion = "fixture-price-v1"
    let behavior: Behavior
    private(set) var calls = 0
    init(bindingID: UUID, behavior: Behavior) { self.bindingID = bindingID; self.behavior = behavior }
    func preflight(task: ScheduledTask, capture: LocalScheduledCapture, mode: LocalScheduledMode, now: Date) async throws -> BudgetQuote {
        if case .preflightDenied = behavior { throw SchedulingError.budgetDenied }
        return BudgetQuote(currency: "USD", maximumMicros: 100_000, inputTokens: 1000, outputTokens: 1000,
            version: pricingVersion, expiresAt: now.addingTimeInterval(120))
    }
    func execute(task: ScheduledTask, capture: LocalScheduledCapture, requestReference: String) async throws -> LocalScheduledResult {
        calls += 1
        if case .interrupted = behavior { throw SchedulingError.executionUncertain }
        let output: LocalScheduledOutput
        let cost: Int64?
        switch behavior {
        case .proposal: output = .proposal(Dictionary(uniqueKeysWithValues: task.allowedBlockIDs.map { ($0, "Fixture replacement") })); cost = 50_000
        case .summary(let amount): output = .summary("Fixture summary e\u{301}\r\n🦊"); cost = amount
        default: output = .summary("Fixture output"); cost = nil
        }
        return LocalScheduledResult(output: output, providerID: providerID,
            modelID: { if case .changedModel = behavior { "different-model" } else { modelID } }(), confirmedCostMicros: cost)
    }
}
@MainActor private func activatedSchedule(_ f: LocalScheduleFixture, task: ScheduledTask) async throws -> (SchedulingStore, FileSchedulingPersistence) {
    let persistence = try FileSchedulingPersistence(url: f.root.appendingPathComponent("Dispatcher/state.json"))
    let store = try SchedulingStore(persistence: persistence)
    try await store.add(task, expectedVersion: 0)
    try await store.activate(taskID: task.id, grant: f.authority.capture(task, now: task.createdAt).grant,
        now: task.createdAt, expectedVersion: 1)
    return (store, persistence)
}
@Test @MainActor func localDispatcherCompletesOnceWithCapturedRevisionAndConfirmedCost() async throws {
    let f = try LocalScheduleFixture(); defer { f.clean() }
    let task = try f.task(), (store, persistence) = try await activatedSchedule(f, task: task)
    let executor = FixtureScheduledExecutor(bindingID: f.binding, behavior: .summary(50_000))
    let dispatcher = LocalScheduleDispatcher(store: store, authority: f.authority, executor: executor,
        clock: { Date(timeIntervalSince1970: 2_000_000_000) })
    try await dispatcher.runDue(mode: .foreground)
    var state = await store.snapshot()
    let run = try #require(state.runs.values.first)
    #expect(run.state == .completed && run.providerRequestReference != nil)
    #expect(state.summaries.values.first?.baseRevision == f.page.revision)
    #expect(state.summaries.values.first?.text.utf8.elementsEqual("Fixture summary e\u{301}\r\n🦊".utf8) == true)
    #expect(state.ledger.reservations[run.id]?.state == .settled && state.ledger.reservations[run.id]?.actualMicros == 50_000)
    try await dispatcher.runDue(mode: .foreground)
    #expect(await executor.calls == 1)
    state = try await SchedulingStore(persistence: persistence).snapshot()
    #expect(state.runs[run.id]?.state == .completed)
}
@Test @MainActor func localDispatcherKeepsUncertainSentCallReservedAndNeverBlindlyRetries() async throws {
    let f = try LocalScheduleFixture(); defer { f.clean() }
    let task = try f.task(), (store, persistence) = try await activatedSchedule(f, task: task)
    let executor = FixtureScheduledExecutor(bindingID: f.binding, behavior: .interrupted)
    let dispatcher = LocalScheduleDispatcher(store: store, authority: f.authority, executor: executor,
        clock: { Date(timeIntervalSince1970: 2_000_000_000) })
    do { try await dispatcher.runDue(mode: .foreground); Issue.record("Interrupted request completed") } catch { }
    let state = await store.snapshot(), run = try #require(state.runs.values.first)
    #expect(run.state == .executionUncertain)
    #expect(state.ledger.reservations[run.id]?.state == .uncertain)
    let restarted = try SchedulingStore(persistence: persistence)
    let retry = LocalScheduleDispatcher(store: restarted, authority: f.authority, executor: executor,
        clock: { Date(timeIntervalSince1970: 2_000_000_000) })
    try await retry.runDue(mode: .foreground)
    #expect(await executor.calls == 1)
}
@Test @MainActor func localDispatcherPreflightDenialNeverSendsAndUnknownBillingStaysHeld() async throws {
    let denied = try LocalScheduleFixture(); defer { denied.clean() }
    let task = try denied.task(), (store, _) = try await activatedSchedule(denied, task: task)
    let executor = FixtureScheduledExecutor(bindingID: denied.binding, behavior: .preflightDenied)
    let dispatcher = LocalScheduleDispatcher(store: store, authority: denied.authority, executor: executor,
        clock: { Date(timeIntervalSince1970: 2_000_000_000) })
    do { try await dispatcher.runDue(mode: .foreground); Issue.record("Budget denied request completed") } catch { }
    let state = await store.snapshot()
    #expect(state.runs.values.first?.state == .budgetDenied && state.ledger.reservations.isEmpty)
    #expect(await executor.calls == 0)
    let held = try LocalScheduleFixture(); defer { held.clean() }
    let other = try held.task(), (queue, _) = try await activatedSchedule(held, task: other)
    let unknown = FixtureScheduledExecutor(bindingID: held.binding, behavior: .summary(nil))
    try await LocalScheduleDispatcher(store: queue, authority: held.authority, executor: unknown,
        clock: { Date(timeIntervalSince1970: 2_000_000_000) }).runDue(mode: .foreground)
    let result = await queue.snapshot(), run = try #require(result.runs.values.first)
    #expect(run.state == .completed && result.ledger.reservations[run.id]?.state == .held)
    #expect(result.ledger.reservations[run.id]?.actualMicros == nil)
}
@Test @MainActor func localDispatcherProposalKeepsScopeAndProvenanceWithoutApplyingDocument() async throws {
    let f = try LocalScheduleFixture(); defer { f.clean() }
    let block = try #require(f.page.blocks.first)
    let task = try f.task(action: .proposal, allowed: [block.id]), (store, _) = try await activatedSchedule(f, task: task)
    let executor = FixtureScheduledExecutor(bindingID: f.binding, behavior: .proposal)
    let bytes = try Data(contentsOf: f.store.directory.appendingPathComponent("library.json"))
    try await LocalScheduleDispatcher(store: store, authority: f.authority, executor: executor,
        clock: { Date(timeIntervalSince1970: 2_000_000_000) }).runDue(mode: .foreground)
    let state = await store.snapshot(), proposal = try #require(state.proposals.values.first)
    #expect(proposal.allowedBlockIDs == [block.id] && proposal.baseRevision == f.page.revision)
    #expect(proposal.providerID == "fixture" && proposal.modelID == "fixture-model")
    #expect(try Data(contentsOf: f.store.directory.appendingPathComponent("library.json")) == bytes)
}

@Test @MainActor func localDispatcherRejectsChangedProviderModelAfterSendWithoutPublishingResult() async throws {
    let f = try LocalScheduleFixture(); defer { f.clean() }
    let task = try f.task(), (store, _) = try await activatedSchedule(f, task: task)
    let executor = FixtureScheduledExecutor(bindingID: f.binding, behavior: .changedModel)
    let dispatcher = LocalScheduleDispatcher(store: store, authority: f.authority, executor: executor,
        clock: { Date(timeIntervalSince1970: 2_000_000_000) })
    do { try await dispatcher.runDue(mode: .foreground); Issue.record("Different model accepted") } catch { }
    let state = await store.snapshot(), run = try #require(state.runs.values.first)
    #expect(run.state == .executionUncertain && state.summaries.isEmpty)
    #expect(state.ledger.reservations[run.id]?.state == .uncertain)
}
@Test @MainActor func localSchedulingCanReleaseOnlyUndispatchedReservation() async throws {
    let f = try LocalScheduleFixture(); defer { f.clean() }
    let task = try f.task(), (store, _) = try await activatedSchedule(f, task: task)
    let now = Date(timeIntervalSince1970: 2_000_000_000)
    let ids = try await store.enqueueDue(now: now, expectedVersion: 2)
    let id = try #require(ids.first), lease = RunLease(workerID: UUID(), expiresAt: now.addingTimeInterval(120))
    try await store.claim(runID: id, lease: lease, now: now, expectedVersion: 3)
    let grant = try f.authority.capture(task, now: now).grant
    try await store.authorize(runID: id, fence: lease.fence, grant: grant, now: now, expectedVersion: 4)
    let quote = BudgetQuote(currency: "USD", maximumMicros: 100_000, inputTokens: 100, outputTokens: 100,
        version: "fixture-price", expiresAt: now.addingTimeInterval(60))
    try await store.reserve(runID: id, fence: lease.fence, quote: quote, expectedQuoteVersion: quote.version, now: now, expectedVersion: 5)
    try await store.rejectBeforeDispatch(runID: id, fence: lease.fence, reason: .denied, now: now, expectedVersion: 6)
    let rejected = await store.snapshot()
    #expect(rejected.runs[id]?.state == .denied && rejected.ledger.reservations[id]?.state == .released)
    // A second fixture tests the same API after a durable dispatch record.
    let g = try LocalScheduleFixture(); defer { g.clean() }
    let other = try g.task(), (queue, _) = try await activatedSchedule(g, task: other)
    let runs = try await queue.enqueueDue(now: now, expectedVersion: 2)
    let run = try #require(runs.first), token = RunLease(workerID: UUID(), expiresAt: now.addingTimeInterval(120))
    try await queue.claim(runID: run, lease: token, now: now, expectedVersion: 3)
    let permission = try g.authority.capture(other, now: now).grant
    try await queue.authorize(runID: run, fence: token.fence, grant: permission, now: now, expectedVersion: 4)
    try await queue.reserve(runID: run, fence: token.fence, quote: quote, expectedQuoteVersion: quote.version, now: now, expectedVersion: 5)
    try await queue.dispatch(runID: run, fence: token.fence, requestReference: "fixture-request", grant: permission,
        expectedQuoteVersion: quote.version, now: now, expectedVersion: 6)
    do { try await queue.rejectBeforeDispatch(runID: run, fence: token.fence, reason: .denied, now: now, expectedVersion: 7); Issue.record("Dispatched reservation released") } catch { }
    #expect(await queue.snapshot().runs[run]?.state == .dispatching)
    #expect(await queue.snapshot().ledger.reservations[run]?.state == .held)
}

private final class ScheduledFixtureAIProvider: AIProvider, @unchecked Sendable {
    let id = AIProviderID.openAIKey
    let capabilities = AICapabilities(textStreaming: true, requiresCredential: true)
    private let lock = NSLock()
    private var recorded: [AIRequest] = []
    private let events: [AIEvent]
    init(events: [AIEvent]) { self.events = events }
    var requests: [AIRequest] { lock.withLock { recorded } }
    func stream(_ request: AIRequest) -> AsyncThrowingStream<AIEvent, any Error> {
        lock.withLock { recorded.append(request) }
        return AsyncThrowingStream { continuation in
            for event in events { continuation.yield(event) }
            continuation.finish()
        }
    }
}
@MainActor private func scheduledAdapter(_ f: LocalScheduleFixture, provider: ScheduledFixtureAIProvider,
    access: @escaping @Sendable () async throws -> Void = {}) throws -> ScheduledAIExecutor {
    try ScheduledAIExecutor(bindingID: f.binding, provider: provider, modelID: "fixture-model", pricingVersion: "fixture-v1",
        modes: [.foreground], accessCheck: access, quote: { task, upper, now in
            BudgetQuote(currency: task.budget.currency, maximumMicros: 10_000, inputTokens: upper,
                outputTokens: task.budget.outputTokens, version: "fixture-v1", expiresAt: now.addingTimeInterval(60))
        })
}
@Test @MainActor func scheduledAIAdapterSendsOnlyAuthorizedBlocksAndPreservesStreamBytesWithoutInventedBilling() async throws {
    let f = try LocalScheduleFixture(); defer { f.clean() }
    let block = try #require(f.page.blocks.first)
    let task = try f.task(action: .summary, allowed: [block.id]), capture = try f.authority.capture(task, now: task.createdAt)
    let provider = ScheduledFixtureAIProvider(events: [.textDelta("e"), .textDelta("\u{301}\r\n🦊"), .completed])
    let adapter = try scheduledAdapter(f, provider: provider)
    let quote = try await adapter.preflight(task: task, capture: capture, mode: .foreground, now: task.createdAt)
    #expect(quote.outputTokens == task.budget.outputTokens)
    let result = try await adapter.execute(task: task, capture: capture, requestReference: "fixture-request")
    let request = try #require(provider.requests.first)
    #expect(request.model == "fixture-model" && request.maximumOutputTokens == task.budget.outputTokens)
    #expect(!request.prompt.contains("Outside selected context"))
    #expect(request.prompt.contains(block.id.uuidString.lowercased()))
    if case .summary(let text) = result.output { #expect(text.utf8.elementsEqual("e\u{301}\r\n🦊".utf8)) }
    else { Issue.record("Summary output missing") }
    #expect(result.confirmedCostMicros == nil)
}
@Test @MainActor func scheduledAIAdapterMissingAccessAndUnsupportedModeNeverReachProvider() async throws {
    let f = try LocalScheduleFixture(); defer { f.clean() }
    let task = try f.task(), capture = try f.authority.capture(task, now: task.createdAt)
    let provider = ScheduledFixtureAIProvider(events: [.textDelta("Should never stream"), .completed])
    let adapter = try scheduledAdapter(f, provider: provider, access: { throw AIError.missingCredential })
    do { _ = try await adapter.preflight(task: task, capture: capture, mode: .foreground, now: task.createdAt); Issue.record("Missing access admitted") } catch { }
    do { _ = try await adapter.preflight(task: task, capture: capture, mode: .background, now: task.createdAt); Issue.record("Unsupported background admitted") } catch { }
    #expect(provider.requests.isEmpty)
}
@Test @MainActor func scheduledAIAdapterRequiresExplicitCompletionAndRejectsEventsAfterEnd() async throws {
    let f = try LocalScheduleFixture(); defer { f.clean() }
    let task = try f.task(), capture = try f.authority.capture(task, now: task.createdAt)
    for events: [AIEvent] in [[.textDelta("Incomplete")], [.textDelta("Complete"), .completed, .textDelta("After end")]] {
        let provider = ScheduledFixtureAIProvider(events: events), adapter = try scheduledAdapter(f, provider: provider)
        do { _ = try await adapter.execute(task: task, capture: capture, requestReference: "fixture"); Issue.record("Invalid stream accepted") } catch { }
    }
}
@Test func scheduledProposalDecoderRejectsDuplicateKeysIDsUnknownFieldsAndOutsideTargets() throws {
    let id = UUID(), other = UUID()
    let valid = "{\"replacements\": [ {\"markdown\":\"é\\r\\n🦊\", \"blockID\":\"" + id.uuidString + "\"} ]}"
    let decoded = try ScheduledAIExecutor.replacements(valid, allowed: [id])
    #expect(decoded[id]?.utf8.elementsEqual("é\r\n🦊".utf8) == true)
    let item = "{\"blockID\":\"" + id.uuidString + "\",\"markdown\":\"x\"}"
    let duplicateID = "{\"replacements\":[" + item + "," + item + "]}"
    let duplicateKey = "{\"replacements\":[],\"replacements\":[" + item + "]}"
    let escapedDuplicate = "{\"replacements\":[],\"replace\\u006dents\":[" + item + "]}"
    let outside = "{\"replacements\":[{\"blockID\":\"" + other.uuidString + "\",\"markdown\":\"x\"}]}"
    let unknown = "{\"replacements\":[" + item + "],\"deletePage\":true}"
    for invalid in [duplicateID, duplicateKey, escapedDuplicate, outside, unknown] {
        #expect(throws: (any Error).self) { try ScheduledAIExecutor.replacements(invalid, allowed: [id]) }
    }
}

@Test @MainActor func scheduledAIAdapterRejectsExpandedContextAndInputBudgetBeforeStream() async throws {
    let f = try LocalScheduleFixture(); defer { f.clean() }
    let first = try #require(f.page.blocks.first)
    let task = try f.task(action: .summary, allowed: [first.id])
    let provider = ScheduledFixtureAIProvider(events: [.textDelta("Must not stream"), .completed])
    let adapter = try scheduledAdapter(f, provider: provider)
    let expanded = ExecutionGrant(scope: task.scope, taskID: task.id, generation: task.generation,
        accountMonthlyMicros: 1_000_000, expiresAt: task.createdAt.addingTimeInterval(60), role: .owner,
        readablePageIDs: [task.pageID], readableBlockIDs: Set(f.page.blocks.map(\.id)))
    let forged = LocalScheduledCapture(page: f.page, sourceForProvider: f.page.markdown,
        sourceDigest: ScheduledProposal.digest(f.page.markdown), grant: expanded)
    do { _ = try await adapter.preflight(task: task, capture: forged, mode: .foreground, now: task.createdAt); Issue.record("Expanded task scope accepted") } catch { }
    var tiny = task; tiny.budget.inputTokens = 10
    let capture = try f.authority.capture(tiny, now: tiny.createdAt)
    do { _ = try await adapter.preflight(task: tiny, capture: capture, mode: .foreground, now: tiny.createdAt); Issue.record("Oversized input accepted") } catch { }
    #expect(provider.requests.isEmpty)
}

@Test @MainActor func localTaskManagerPersistsDraftAndBindingThenCancelsWithoutDispatching() async throws {
    let f = try LocalScheduleFixture(); defer { f.clean() }
    let session = LocalScheduleSession(library: f.library)
    await session.load()
    #expect(session.error == nil && session.state.tasks.isEmpty)
    try await session.create(pageID: f.page.id, prompt: "Daily summary", provider: .openAIKey, model: "fixture-model",
        rule: .daily(timeZone: "Europe/Berlin", hour: 9, minute: 0), action: .summary,
        budget: BudgetPolicy(currency: "USD", perRunMicros: 100_000, monthlyMicros: 500_000, inputTokens: 32000, outputTokens: 2048),
        end: nil, count: 10)
    let task = try #require(session.state.tasks.values.first)
    #expect(task.lifecycle == .draft && session.state.runs.isEmpty)
    #expect(try session.binding(task).provider == .openAIKey)
    #expect(try session.binding(task).model == "fixture-model")
    let restart = LocalScheduleSession(library: f.library); await restart.load()
    #expect(restart.state.tasks[task.id]?.prompt == "Daily summary")
    try await restart.cancel(task)
    #expect(restart.state.tasks[task.id]?.lifecycle == .cancelled)
    #expect(restart.state.runs.isEmpty && restart.state.ledger.reservations.isEmpty)
}
@Test @MainActor func localTaskManagerInvalidIdentityOrTrashedPageNeverCreatesActiveWork() async throws {
    let f = try LocalScheduleFixture(); defer { f.clean() }
    f.library.preferences.set("broken-local-owner", forKey: "Scriptum.localSchedulingOwner")
    let invalid = LocalScheduleSession(library: f.library); await invalid.load()
    #expect(invalid.error != nil)
    do {
        try await invalid.create(pageID: f.page.id, prompt: "Must not run", provider: .applePCC, model: "fixture",
            rule: .oneShot(Date().addingTimeInterval(1000)), action: .summary,
            budget: BudgetPolicy(currency: "USD", perRunMicros: 0, monthlyMicros: 0, inputTokens: 32000, outputTokens: 2048), end: nil, count: nil)
        Issue.record("Invalid identity stored a task")
    } catch { }
    #expect(f.library.preferences.string(forKey: "Scriptum.localSchedulingOwner") == "broken-local-owner")
    f.library.preferences.set(UUID().uuidString, forKey: "Scriptum.localSchedulingOwner")
    let session = LocalScheduleSession(library: f.library); await session.load()
    try f.store.trashPage(f.page.id)
    do {
        try await session.create(pageID: f.page.id, prompt: "Must not run", provider: .applePCC, model: "fixture",
            rule: .oneShot(Date().addingTimeInterval(1000)), action: .summary,
            budget: BudgetPolicy(currency: "USD", perRunMicros: 0, monthlyMicros: 0, inputTokens: 32000, outputTokens: 2048), end: nil, count: nil)
        Issue.record("Trashed target stored a task")
    } catch { }
    #expect(session.state.tasks.isEmpty)
}

@MainActor private func acceptanceProposal(_ f: LocalScheduleFixture, task: ScheduledTask, replacements: [UUID: String], id: UUID = UUID(), source: String? = nil, provider: String = AIProviderID.openAIKey.rawValue, model: String = "fixture-model") throws -> ScheduledProposal {
    try ScheduledProposal(id: id, scope: task.scope, runID: UUID(), pageID: task.pageID, baseRevision: f.page.revision,
        allowedBlockIDs: task.allowedBlockIDs, source: source ?? f.page.markdown, replacementBlocks: replacements,
        providerID: provider, modelID: model)
}
@Test @MainActor func localScheduledAcceptanceReviewsExactBytesAndCommitsReceiptOnceAcrossRestart() throws {
    let f = try LocalScheduleFixture(); defer { f.clean() }
    let first = try #require(f.page.blocks.first), last = try #require(f.page.blocks.last)
    let task = try f.task(action: .proposal, allowed: [first.id])
    let binding = LocalScheduledBinding(id: f.binding, provider: .openAIKey, model: "fixture-model")
    let replacement = "Revised e\u{301}\r\n🦊\n\n"
    let proposal = try acceptanceProposal(f, task: task, replacements: [first.id: replacement])
    let disk = f.store.directory.appendingPathComponent("library.json"), before = try Data(contentsOf: disk)
    let review = try LocalScheduledProposalAcceptance.review(proposal, task: task, binding: binding, library: f.library, ownerID: f.owner)
    #expect(review.receipt == nil && review.changes.count == 1)
    #expect(review.changes[0].original.utf8.elementsEqual(first.markdown.utf8))
    #expect(review.changes[0].replacement.utf8.elementsEqual(replacement.utf8))
    #expect(try Data(contentsOf: disk) == before)
    let receipt = try LocalScheduledProposalAcceptance.accept(proposal, task: task, binding: binding, library: f.library, ownerID: f.owner)
    let applied = try #require(f.store.snapshot.pages.first(where: { $0.id == f.page.id }))
    #expect(applied.blocks.first?.markdown.utf8.elementsEqual(replacement.utf8) == true)
    #expect(applied.blocks.last?.markdown.utf8.elementsEqual(last.markdown.utf8) == true)
    #expect(f.store.snapshot.revisions.last?.page.revision == f.page.revision)
    #expect(f.store.snapshot.proposalReceipts?.first == receipt && applied.revision == receipt.appliedRevision)
    // A later user edit must survive a replay, including after opening disk anew.
    try f.store.setMarkdown(f.page.id, markdown: "Later user text", baseRevision: applied.revision)
    let reopened = try LibraryStore(directory: f.store.directory)
    let library = try WritingLibrary(store: reopened, documentRoot: f.root.appendingPathComponent("Documents"), supportRoot: f.root.appendingPathComponent("Support"), preferences: f.library.preferences)
    let later = try Data(contentsOf: disk)
    #expect(try LocalScheduledProposalAcceptance.accept(proposal, task: task, binding: binding, library: library, ownerID: f.owner) == receipt)
    #expect(try LocalScheduledProposalAcceptance.review(proposal, task: task, binding: binding, library: library, ownerID: f.owner).receipt == receipt)
    #expect(try Data(contentsOf: disk) == later)
}
@Test @MainActor func localScheduledAcceptanceRejectsStaleDigestRevisionAndProviderWithoutMutation() throws {
    let f = try LocalScheduleFixture(); defer { f.clean() }
    let first = try #require(f.page.blocks.first), task = try f.task(action: .proposal, allowed: [first.id])
    let binding = LocalScheduledBinding(id: f.binding, provider: .openAIKey, model: "fixture-model")
    let disk = f.store.directory.appendingPathComponent("library.json"), before = try Data(contentsOf: disk)
    for proposal in [
        try acceptanceProposal(f, task: task, replacements: [first.id: "New"], source: f.page.markdown.precomposedStringWithCanonicalMapping),
        try acceptanceProposal(f, task: task, replacements: [first.id: "New"], provider: AIProviderID.anthropicKey.rawValue),
        try acceptanceProposal(f, task: task, replacements: [first.id: "New"], model: "other-model")
    ] {
        #expect(throws: (any Error).self) { try LocalScheduledProposalAcceptance.accept(proposal, task: task, binding: binding, library: f.library, ownerID: f.owner) }
    }
    #expect(try Data(contentsOf: disk) == before)
    let proposal = try acceptanceProposal(f, task: task, replacements: [first.id: "New"])
    try f.store.renamePage(f.page.id, title: "Changed elsewhere")
    let changed = try Data(contentsOf: disk)
    #expect(throws: (any Error).self) { try LocalScheduledProposalAcceptance.accept(proposal, task: task, binding: binding, library: f.library, ownerID: f.owner) }
    #expect(try Data(contentsOf: disk) == changed)
}
@Test @MainActor func localScheduledAcceptanceRejectsOpenJournalTrashedHierarchyAndForeignOwner() throws {
    let f = try LocalScheduleFixture(); defer { f.clean() }
    let first = try #require(f.page.blocks.first), task = try f.task(action: .proposal, allowed: [first.id])
    let binding = LocalScheduledBinding(id: f.binding, provider: .openAIKey, model: "fixture-model")
    let proposal = try acceptanceProposal(f, task: task, replacements: [first.id: "New"])
    let token = try f.store.beginEditing(pageID: f.page.id, baseRevision: f.page.revision)
    #expect(throws: (any Error).self) { try LocalScheduledProposalAcceptance.accept(proposal, task: task, binding: binding, library: f.library, ownerID: f.owner) }
    try f.store.finishEditing(token)
    #expect(throws: (any Error).self) { try LocalScheduledProposalAcceptance.accept(proposal, task: task, binding: binding, library: f.library, ownerID: UUID()) }
    let parent = try f.store.createPage(spaceID: f.space.id, title: "Parent")
    try f.store.movePage(f.page.id, parentID: parent.id); try f.store.trashPage(parent.id)
    #expect(throws: (any Error).self) { try LocalScheduledProposalAcceptance.accept(proposal, task: task, binding: binding, library: f.library, ownerID: f.owner) }
    #expect(f.store.snapshot.proposalReceipts?.isEmpty ?? true)
}
@Test @MainActor func localScheduledAcceptanceRejectsChangedReplayPayloadWithoutOverwritingUserText() throws {
    let f = try LocalScheduleFixture(); defer { f.clean() }
    let first = try #require(f.page.blocks.first), task = try f.task(action: .proposal, allowed: [first.id])
    let binding = LocalScheduledBinding(id: f.binding, provider: .openAIKey, model: "fixture-model")
    let proposal = try acceptanceProposal(f, task: task, replacements: [first.id: "é"])
    _ = try LocalScheduledProposalAcceptance.accept(proposal, task: task, binding: binding, library: f.library, ownerID: f.owner)
    let altered = try acceptanceProposal(f, task: task, replacements: [first.id: "e\u{301}"], id: proposal.id)
    let disk = f.store.directory.appendingPathComponent("library.json"), before = try Data(contentsOf: disk)
    #expect(throws: (any Error).self) { try LocalScheduledProposalAcceptance.accept(altered, task: task, binding: binding, library: f.library, ownerID: f.owner) }
    #expect(try Data(contentsOf: disk) == before)
}

@Test @MainActor func localScheduledAcceptanceSessionUsesOnlyDurableProposalAndVerifiedBinding() async throws {
    let f = try LocalScheduleFixture(); defer { f.clean() }
    let initial = LocalScheduleSession(library: f.library); await initial.load()
    let anchor = Date().addingTimeInterval(10)
    try await initial.create(pageID: f.page.id, prompt: "Fixture revision", provider: .openAIKey, model: "fixture-model",
        rule: .oneShot(anchor), action: .proposal,
        budget: BudgetPolicy(currency: "USD", perRunMicros: 100_000, monthlyMicros: 500_000, inputTokens: 32000, outputTokens: 2048), end: nil, count: 1)
    let task = try #require(initial.state.tasks.values.first)
    let folders = try FileManager.default.contentsOfDirectory(at: f.library.localSchedulingDirectory(), includingPropertiesForKeys: nil)
    let folder = try #require(folders.first)
    let queue = try SchedulingStore(persistence: FileSchedulingPersistence(url: folder.appendingPathComponent("tasks-v1.json")))
    let authority = try LocalScheduleAuthority(library: f.library, ownerID: task.scope.accountID, providerBindingID: task.providerBindingID, accountBudgets: ["USD": 500_000])
    try await queue.activate(taskID: task.id, grant: authority.capture(task, now: anchor).grant, now: anchor, expectedVersion: 1)
    let first = try #require(f.page.blocks.first)
    let output = "{\"replacements\":[{\"blockID\":\"" + first.id.uuidString + "\",\"markdown\":\"Scheduled replacement\"}]}"
    let provider = ScheduledFixtureAIProvider(events: [.textDelta(output), .completed])
    let adapter = try ScheduledAIExecutor(bindingID: task.providerBindingID, provider: provider, modelID: "fixture-model", pricingVersion: "fixture-v1",
        modes: [.foreground], accessCheck: {}, quote: { task, upper, now in
            BudgetQuote(currency: "USD", maximumMicros: 10_000, inputTokens: upper, outputTokens: task.budget.outputTokens, version: "fixture-v1", expiresAt: now.addingTimeInterval(60))
        })
    try await LocalScheduleDispatcher(store: queue, authority: authority, executor: adapter, clock: { anchor }).runDue(mode: .foreground)
    let reloaded = LocalScheduleSession(library: f.library); await reloaded.load()
    let proposal = try #require(reloaded.state.proposals.values.first)
    #expect(try await reloaded.review(proposalID: proposal.id).changes.first?.original == first.markdown)
    do { _ = try await reloaded.accept(proposalID: UUID()); Issue.record("Unknown proposal accepted") } catch { }
    let receipt = try await reloaded.accept(proposalID: proposal.id)
    #expect(try await reloaded.review(proposalID: proposal.id).receipt == receipt)
    #expect(f.library.currentPage(f.page.id)?.markdown.contains("Scheduled replacement") == true)
    #expect(provider.requests.count == 1)
}

private actor ActivationFixtureExecutor: LocalScheduledExecutor {
    nonisolated let bindingID: UUID, modelID: String
    nonisolated let providerID = AIProviderID.openAIKey.rawValue, pricingVersion = "activation-fixture"
    var denied = false, maximum: Int64 = 10_000
    var nextPreflight: (@Sendable () async -> Void)?
    func onNextPreflight(_ action: @escaping @Sendable () async -> Void) { nextPreflight = action }
    private(set) var checks = 0, calls = 0
    init(bindingID: UUID, modelID: String = "fixture-model") { self.bindingID = bindingID; self.modelID = modelID }
    func deny() { denied = true }
    func increasePrice() { maximum = 20_000 }
    func preflight(task: ScheduledTask, capture: LocalScheduledCapture, mode: LocalScheduledMode, now: Date) async throws -> BudgetQuote {
        checks += 1
        guard !denied, mode == .foreground else { throw AIError.missingCredential }
        let hook = nextPreflight; nextPreflight = nil; await hook?()
        return BudgetQuote(currency: task.budget.currency, maximumMicros: maximum, inputTokens: 1024,
            outputTokens: task.budget.outputTokens, version: pricingVersion, expiresAt: now.addingTimeInterval(120))
    }
    func execute(task: ScheduledTask, capture: LocalScheduledCapture, requestReference: String) async throws -> LocalScheduledResult {
        calls += 1
        return LocalScheduledResult(output: .summary("Controlled activated result"), providerID: providerID, modelID: modelID, confirmedCostMicros: nil)
    }
}
@MainActor private func activationSession(_ f: LocalScheduleFixture, anchor: Date) async throws -> (LocalScheduleSession, ScheduledTask, ActivationFixtureExecutor) {
    let session = LocalScheduleSession(library: f.library); await session.load()
    try await session.create(pageID: f.page.id, prompt: "Controlled activation", provider: .openAIKey, model: "fixture-model",
        rule: .oneShot(anchor), action: .summary,
        budget: BudgetPolicy(currency: "USD", perRunMicros: 100_000, monthlyMicros: 500_000, inputTokens: 32000, outputTokens: 2048), end: nil, count: 1)
    let task = try #require(session.state.tasks.values.first)
    return (session, task, ActivationFixtureExecutor(bindingID: task.providerBindingID))
}
@Test @MainActor func localScheduleActivationRequiresTwoChecksPersistsAndRunsOnlyAfterConfirmation() async throws {
    let f = try LocalScheduleFixture(); defer { f.clean() }
    let now = Date(), anchor = now.addingTimeInterval(30)
    let (session, task, executor) = try await activationSession(f, anchor: anchor)
    let review = try await session.prepareActivation(taskID: task.id, executor: executor, accountMonthlyMicros: 500_000, mode: .foreground, clock: { now })
    #expect(review.taskID == task.id && review.provider == .openAIKey && review.model == "fixture-model")
    #expect(review.quote.maximumMicros == 10_000 && review.expiresAt == now.addingTimeInterval(60))
    #expect(session.state.tasks[task.id]?.lifecycle == .draft)
    #expect(await executor.calls == 0)
    try await session.activate(reviewID: review.id, clock: { now })
    #expect(session.state.tasks[task.id]?.lifecycle == .active)
    #expect(await executor.checks == 2)
    do { try await session.activate(reviewID: review.id, clock: { now }); Issue.record("Approval replayed") } catch { }
    let reload = LocalScheduleSession(library: f.library); await reload.load()
    #expect(reload.state.tasks[task.id]?.lifecycle == .active && reload.state.runs.isEmpty)
    try await reload.runDue(executor: executor, accountBudgets: ["USD": 500_000], mode: .foreground, clock: { anchor })
    #expect(await executor.calls == 1 && reload.state.summaries.values.first?.text == "Controlled activated result")
    #expect(reload.state.ledger.reservations.values.first?.state == .held)
}
@Test @MainActor func localScheduleActivationRejectsLostAccessIncreasedPriceExpiryAndRestartedApproval() async throws {
    for variant in 0...3 {
        let f = try LocalScheduleFixture(); defer { f.clean() }
        let now = Date(), (session, task, executor) = try await activationSession(f, anchor: now.addingTimeInterval(100))
        let review = try await session.prepareActivation(taskID: task.id, executor: executor, accountMonthlyMicros: 500_000, mode: .foreground, clock: { now })
        let target: LocalScheduleSession, time: Date
        switch variant {
        case 0: await executor.deny(); target = session; time = now
        case 1: await executor.increasePrice(); target = session; time = now
        case 2: target = session; time = now.addingTimeInterval(61)
        default: target = LocalScheduleSession(library: f.library); await target.load(); time = now
        }
        do { try await target.activate(reviewID: review.id, clock: { time }); Issue.record("Invalid activation accepted") } catch { }
        await target.load()
        #expect(target.state.tasks[task.id]?.lifecycle == .draft && target.state.runs.isEmpty)
        #expect(await executor.calls == 0)
    }
}
@Test @MainActor func localScheduleActivationRejectsChangedSourceAndCancellationWithoutSending() async throws {
    for cancel in [false, true] {
        let f = try LocalScheduleFixture(); defer { f.clean() }
        let now = Date(), (session, task, executor) = try await activationSession(f, anchor: now.addingTimeInterval(100))
        let review = try await session.prepareActivation(taskID: task.id, executor: executor, accountMonthlyMicros: 500_000, mode: .foreground, clock: { now })
        if cancel { try await session.cancel(task) }
        else { try f.store.renamePage(task.pageID, title: "Changed after review") }
        do { try await session.activate(reviewID: review.id, clock: { now }); Issue.record("Changed consent activated") } catch { }
        await session.load()
        #expect(session.state.tasks[task.id]?.lifecycle == (cancel ? .cancelled : .draft))
        #expect(await executor.calls == 0 && session.state.runs.isEmpty)
    }
}
@Test @MainActor func localScheduleDispatcherLeavesOtherProviderBindingsQueuedWithoutClaimingOrDenial() async throws {
    let f = try LocalScheduleFixture(); defer { f.clean() }
    let now = Date(), anchor = now.addingTimeInterval(30)
    let (session, first, executor) = try await activationSession(f, anchor: anchor)
    try await session.create(pageID: f.page.id, prompt: "Other binding", provider: .openAIKey, model: "different-model",
        rule: .oneShot(anchor), action: .summary,
        budget: BudgetPolicy(currency: "USD", perRunMicros: 100_000, monthlyMicros: 500_000, inputTokens: 32000, outputTokens: 2048), end: nil, count: 1)
    let second = try #require(session.state.tasks.values.first(where: { $0.id != first.id }))
    let other = ActivationFixtureExecutor(bindingID: second.providerBindingID, modelID: "different-model")
    for (task, adapter) in [(first, executor), (second, other)] {
        let review = try await session.prepareActivation(taskID: task.id, executor: adapter, accountMonthlyMicros: 500_000, mode: .foreground, clock: { now })
        try await session.activate(reviewID: review.id, clock: { now })
    }
    try await session.runDue(executor: executor, accountBudgets: ["USD": 500_000], mode: .foreground, clock: { anchor })
    let waiting = try #require(session.state.runs.values.first(where: { $0.occurrence.taskID == second.id }))
    #expect(waiting.state == .queued && waiting.lease == nil && waiting.providerRequestReference == nil)
    #expect(await executor.calls == 1)
    #expect(await other.calls == 0)
    try await session.runDue(executor: other, accountBudgets: ["USD": 500_000], mode: .foreground, clock: { anchor })
    #expect(await other.calls == 1 && session.state.summaries.count == 2)
}


private final class ActivationFixtureClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date
    init(_ value: Date) { self.value = value }
    func now() -> Date { lock.withLock { value } }
    func advance(_ seconds: TimeInterval) { lock.withLock { value = value.addingTimeInterval(seconds) } }
}
@Test @MainActor func localScheduleActivationRechecksRealClockAfterAsynchronousAccess() async throws {
    for duringConfirmation in [false, true] {
        let f = try LocalScheduleFixture(); defer { f.clean() }
        let now = Date(), clock = ActivationFixtureClock(now)
        let (session, task, executor) = try await activationSession(f, anchor: now.addingTimeInterval(500))
        if duringConfirmation {
            let review = try await session.prepareActivation(taskID: task.id, executor: executor, accountMonthlyMicros: 500_000, mode: .foreground, clock: { clock.now() })
            await executor.onNextPreflight { clock.advance(61) }
            do { try await session.activate(reviewID: review.id, clock: { clock.now() }); Issue.record("Approval expired during access check but activated") } catch { }
        } else {
            await executor.onNextPreflight { clock.advance(121) }
            do { _ = try await session.prepareActivation(taskID: task.id, executor: executor, accountMonthlyMicros: 500_000, mode: .foreground, clock: { clock.now() }); Issue.record("Quote expired during access check but accepted") } catch { }
        }
        await session.load()
        #expect(session.state.tasks[task.id]?.lifecycle == .draft && session.state.runs.isEmpty)
        #expect(await executor.calls == 0)
    }
}
@Test @MainActor func localScheduleActivationRechecksDocumentAfterAsynchronousAccess() async throws {
    let f = try LocalScheduleFixture(); defer { f.clean() }
    let now = Date(), (session, task, executor) = try await activationSession(f, anchor: now.addingTimeInterval(100))
    let store = f.store, pageID = f.page.id
    await executor.onNextPreflight { await MainActor.run { try? store.renamePage(pageID, title: "Changed during preflight") } }
    do { _ = try await session.prepareActivation(taskID: task.id, executor: executor, accountMonthlyMicros: 500_000, mode: .foreground, clock: { now }); Issue.record("Source changed during access check but approved") } catch { }
    #expect(session.state.tasks[task.id]?.lifecycle == .draft && session.state.runs.isEmpty)
    #expect(await executor.calls == 0)
}
