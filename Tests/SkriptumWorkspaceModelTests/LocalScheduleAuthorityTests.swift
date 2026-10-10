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
    let capabilities = AICapabilities(textStreaming: true, requiresCredential: true, supportsOutputTokenLimit: true)
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
    #expect(review.accountMonthlyMicros == 500_000 && review.nextOccurrence == anchor)
    #expect(review.prompt == task.prompt && review.action == .summary && review.wholePage)
    #expect(review.readableBlockCount == f.page.blocks.count && review.pageTitle == f.page.title)
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

@Test @MainActor func localAccountBudgetAggregatesTwoRealOwnedLibrariesBeforeAnySecondSend() async throws {
    let f = try LocalScheduleFixture(); defer { f.clean() }
    let documents = f.root.appendingPathComponent("Documents")
    let secondStore = try LibraryStore(directory: LibraryStoragePaths.libraryDirectory(locator: .imported(UUID()), documentRoot: documents))
    let space = try secondStore.createSpace(title: "Second library"), page = try secondStore.createPage(spaceID: space.id, title: "Second page", markdown: "Second source")
    let secondLibrary = try WritingLibrary(store: secondStore, documentRoot: documents, supportRoot: f.root.appendingPathComponent("Support"), preferences: f.library.preferences)
    let first = LocalScheduleSession(library: f.library), second = LocalScheduleSession(library: secondLibrary)
    await first.load(); await second.load()
    let anchor = Date().addingTimeInterval(30)
    let policy = BudgetPolicy(currency: "USD", perRunMicros: 10_000, monthlyMicros: 15_000, inputTokens: 32000, outputTokens: 2048)
    var fixtures: [(LocalScheduleSession, ScheduledTask, ActivationFixtureExecutor)] = []
    for (session, pageID) in [(first, f.page.id), (second, page.id)] {
        try await session.create(pageID: pageID, prompt: "Shared account budget", provider: .openAIKey, model: "fixture-model", rule: .oneShot(anchor), action: .summary, budget: policy, end: nil, count: 1)
        let task = try #require(session.state.tasks.values.first), executor = ActivationFixtureExecutor(bindingID: task.providerBindingID)
        let review = try await session.prepareActivation(taskID: task.id, executor: executor, accountMonthlyMicros: 15_000, mode: .foreground)
        try await session.activate(reviewID: review.id)
        fixtures.append((session, task, executor))
    }
    #expect(fixtures[0].1.scope.libraryID != fixtures[1].1.scope.libraryID)
    #expect(fixtures[0].1.scope.accountID == fixtures[1].1.scope.accountID)
    try await first.runDue(executor: fixtures[0].2, accountBudgets: ["USD": 15_000], mode: .foreground, clock: { anchor })
    do { try await second.runDue(executor: fixtures[1].2, accountBudgets: ["USD": 15_000], mode: .foreground, clock: { anchor }); Issue.record("Global monthly ceiling was bypassed by another library") } catch { }
    #expect(await fixtures[0].2.calls == 1)
    #expect(await fixtures[1].2.calls == 0)
    #expect(second.state.runs.values.first?.state == .budgetDenied && second.state.summaries.isEmpty)
    let restart = LocalScheduleSession(library: secondLibrary); await restart.load()
    #expect(restart.error == nil && restart.state.runs.values.first?.state == .budgetDenied)
}
private final class AccountBudgetFaultPersistence: SchedulingPersistence, @unchecked Sendable {
    private let lock = NSLock()
    private var bytes: Data?, failing = false
    func failWrites() { lock.withLock { failing = true } }
    func read() throws -> Data? { lock.withLock { bytes } }
    func write(_ data: Data) throws {
        try lock.withLock {
            guard !failing else { throw SchedulingError.unsafeFile }
            bytes = data
        }
    }
}
@Test @MainActor func localAccountBudgetPersistsUncertainCostAndNeverRefundsDispatchedWork() async throws {
    let f = try LocalScheduleFixture(); defer { f.clean() }
    let file = try FileSchedulingPersistence(url: f.root.appendingPathComponent("GlobalBudget/state.json"))
    let broker = try LocalScheduleAccountBudgetStore(ownerID: f.owner, persistence: file)
    try await broker.enroll(currency: "USD", monthlyMicros: 150_000)
    let task = try f.task(), now = task.createdAt, quote = BudgetQuote(currency: "USD", maximumMicros: 100_000, inputTokens: 1024, outputTokens: 2048, version: "fixture", expiresAt: now.addingTimeInterval(120))
    let permit = try await broker.reserve(runID: UUID(), task: task, fence: UUID(), quote: quote, now: now)
    try await broker.dispatched(permit, now: now); try await broker.uncertain(permit)
    let reopened = try LocalScheduleAccountBudgetStore(ownerID: f.owner, persistence: file)
    #expect(await reopened.snapshot().reservations[permit.runID]?.state == .uncertain)
    do { try await reopened.releaseBeforeDispatch(permit); Issue.record("Sent call was refunded") } catch { }
    do { _ = try await reopened.reserve(runID: UUID(), task: task, fence: UUID(), quote: quote, now: now); Issue.record("Restart forgot held account usage") } catch { }
    #expect(await reopened.snapshot().reservations.count == 1)
}
@Test @MainActor func localAccountBudgetAllowsOnlyConfirmedSettlementOrUnsentReleaseAndWritesBeforeAdmission() async throws {
    let f = try LocalScheduleFixture(); defer { f.clean() }
    let memory = AccountBudgetFaultPersistence(), broker = try LocalScheduleAccountBudgetStore(ownerID: f.owner, persistence: memory)
    try await broker.enroll(currency: "USD", monthlyMicros: 500_000)
    let task = try f.task(), now = task.createdAt, quote = BudgetQuote(currency: "USD", maximumMicros: 100_000, inputTokens: 1024, outputTokens: 2048, version: "fixture", expiresAt: now.addingTimeInterval(120))
    let unsent = try await broker.reserve(runID: UUID(), task: task, fence: UUID(), quote: quote, now: now)
    try await broker.releaseBeforeDispatch(unsent)
    #expect(await broker.snapshot().reservations[unsent.runID]?.state == .released)
    let confirmed = try await broker.reserve(runID: UUID(), task: task, fence: UUID(), quote: quote, now: now)
    try await broker.dispatched(confirmed, now: now); try await broker.completed(confirmed, actualMicros: 30_000)
    #expect(await broker.snapshot().reservations[confirmed.runID]?.actualMicros == 30_000)
    let before = await broker.snapshot(); memory.failWrites()
    do { _ = try await broker.reserve(runID: UUID(), task: task, fence: UUID(), quote: quote, now: now); Issue.record("Budget admission returned before durable write") } catch { }
    #expect(await broker.snapshot() == before)
    let reopened = try LocalScheduleAccountBudgetStore(ownerID: f.owner, persistence: AccountBudgetFaultPersistence())
    do { _ = try await reopened.reserve(runID: UUID(), task: task, fence: UUID(), quote: quote, now: now); Issue.record("Unenrolled ceiling admitted a call") } catch { }
}
@Test @MainActor func localAccountBudgetBootstrapsUnopenedLegacyLibraryHoldsAndRejectsConflictingCeilings() async throws {
    let f = try LocalScheduleFixture(); defer { f.clean() }
    let task = try f.task(), (queue, _) = try await activatedSchedule(f, task: task)
    let executor = FixtureScheduledExecutor(bindingID: f.binding, behavior: .summary(nil))
    let now = Date(timeIntervalSince1970: 2_000_000_000)
    try await LocalScheduleDispatcher(store: queue, authority: f.authority, executor: executor, clock: { now }).runDue(mode: .foreground)
    let legacy = await queue.snapshot()
    let oldFile = try FileSchedulingPersistence(url: f.library.localSchedulingDirectory().appendingPathComponent("unopened-legacy/tasks-v1.json"))
    try oldFile.write(JSONEncoder().encode(legacy))
    let broker = try await LocalAccountBudgetRegistry.open(ownerID: f.owner, directory: f.root.appendingPathComponent("Support/AccountBudgets"), localSchedules: f.library.localSchedulingDirectory())
    #expect(await broker.snapshot().reservations.values.first?.quote.maximumMicros == 100_000)
    do { try await broker.enroll(currency: "USD", monthlyMicros: 2_000_000); Issue.record("Another library reset the account ceiling") } catch { }
    var larger = task; larger.budget.perRunMicros = 950_000; larger.budget.monthlyMicros = 1_000_000
    let quote = BudgetQuote(currency: "USD", maximumMicros: 950_000, inputTokens: 1024, outputTokens: 2048, version: "fixture", expiresAt: now.addingTimeInterval(120))
    do { _ = try await broker.reserve(runID: UUID(), task: larger, fence: UUID(), quote: quote, now: now); Issue.record("Unopened legacy usage was forgotten") } catch { }
    #expect(await broker.snapshot().reservations.count == 1)
}

private func attemptAccountReservation(_ broker: LocalScheduleAccountBudgetStore, task: ScheduledTask, quote: BudgetQuote, now: Date) async -> Bool {
    do { _ = try await broker.reserve(runID: UUID(), task: task, fence: UUID(), quote: quote, now: now); return true } catch { return false }
}
@Test @MainActor func localAccountBudgetConcurrentLibrariesCannotBothSpendTheSameRemainingBudget() async throws {
    let f = try LocalScheduleFixture(); defer { f.clean() }
    let broker = try LocalScheduleAccountBudgetStore(ownerID: f.owner, persistence: AccountBudgetFaultPersistence())
    try await broker.enroll(currency: "USD", monthlyMicros: 100_000)
    let first = try f.task(), second = try f.task(scope: .init(accountID: f.owner, libraryID: UUID(), spaceID: UUID()))
    let now = first.createdAt, quote = BudgetQuote(currency: "USD", maximumMicros: 60_000, inputTokens: 1024, outputTokens: 2048, version: "fixture", expiresAt: now.addingTimeInterval(120))
    async let one = attemptAccountReservation(broker, task: first, quote: quote, now: now)
    async let two = attemptAccountReservation(broker, task: second, quote: quote, now: now)
    let results = await (one, two)
    #expect(results.0 != results.1)
    #expect(await broker.snapshot().reservations.count == 1)
}
private final class AccountBudgetNthWritePersistence: SchedulingPersistence, @unchecked Sendable {
    private let lock = NSLock()
    private var bytes: Data?, writes = 0
    private let failure: Int
    init(failure: Int) { self.failure = failure }
    func read() throws -> Data? { lock.withLock { bytes } }
    func write(_ data: Data) throws {
        try lock.withLock { writes += 1; guard writes != failure else { throw SchedulingError.unsafeFile }; bytes = data }
    }
}
@Test @MainActor func localAccountBudgetDispatcherReleasesOnlyAfterDurableLocalPreDispatchRejection() async throws {
    let f = try LocalScheduleFixture(); defer { f.clean() }
    let task = try f.task(), persistence = AccountBudgetNthWritePersistence(failure: 7)
    let queue = try SchedulingStore(persistence: persistence)
    try await queue.add(task, expectedVersion: 0)
    try await queue.activate(taskID: task.id, grant: f.authority.capture(task, now: task.createdAt).grant, now: task.createdAt, expectedVersion: 1)
    let broker = try LocalScheduleAccountBudgetStore(ownerID: f.owner, persistence: AccountBudgetFaultPersistence())
    try await broker.enroll(currency: "USD", monthlyMicros: 500_000)
    let executor = FixtureScheduledExecutor(bindingID: f.binding, behavior: .summary(nil))
    do { try await LocalScheduleDispatcher(store: queue, authority: f.authority, executor: executor, clock: { Date(timeIntervalSince1970: 2_000_000_000) }, accountBudget: broker).runDue(mode: .foreground); Issue.record("Local reservation persistence failure ignored") } catch { }
    #expect(await executor.calls == 0)
    #expect(await queue.snapshot().runs.values.first?.state == .denied)
    #expect(await broker.snapshot().reservations.values.first?.state == .released)
}
@Test @MainActor func localAccountBudgetDispatcherNeverSendsAfterGlobalDispatchPersistenceFailure() async throws {
    let f = try LocalScheduleFixture(); defer { f.clean() }
    let task = try f.task(), (queue, _) = try await activatedSchedule(f, task: task)
    let broker = try LocalScheduleAccountBudgetStore(ownerID: f.owner, persistence: AccountBudgetNthWritePersistence(failure: 4))
    try await broker.enroll(currency: "USD", monthlyMicros: 500_000)
    let executor = FixtureScheduledExecutor(bindingID: f.binding, behavior: .summary(nil))
    do { try await LocalScheduleDispatcher(store: queue, authority: f.authority, executor: executor, clock: { Date(timeIntervalSince1970: 2_000_000_000) }, accountBudget: broker).runDue(mode: .foreground); Issue.record("Global dispatch persistence failure ignored") } catch { }
    #expect(await executor.calls == 0)
    #expect(await queue.snapshot().runs.values.first?.state == .executionUncertain)
    #expect(await broker.snapshot().reservations.values.first?.state == .uncertain)
}


@Test @MainActor func localAccountBudgetConcurrentOpenUsesOneSharedActor() async throws {
    let f = try LocalScheduleFixture(); defer { f.clean() }
    let directory = f.root.appendingPathComponent("Support/AccountBudgets"), local = f.library.localSchedulingDirectory(), owner = f.owner
    async let one = LocalAccountBudgetRegistry.open(ownerID: owner, directory: directory, localSchedules: local)
    async let two = LocalAccountBudgetRegistry.open(ownerID: owner, directory: directory, localSchedules: local)
    let (first, second) = try await (one, two)
    #expect(first === second)
    try await first.enroll(currency: "USD", monthlyMicros: 100_000)
    #expect(await second.snapshot().accountCeilings.values.first == 100_000)
}


private final class AccountBudgetAdmissionClock: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Date]
    init(now: Date) { values = [now, now, now.addingTimeInterval(61)] }
    func now() -> Date { lock.withLock { if values.count > 1 { return values.removeFirst() }; return values[0] } }
}
@Test @MainActor func localAccountBudgetActivationRechecksApprovalAfterGlobalEnrollmentAwait() async throws {
    let f = try LocalScheduleFixture(); defer { f.clean() }
    let now = Date(), (session, task, executor) = try await activationSession(f, anchor: now.addingTimeInterval(100))
    let review = try await session.prepareActivation(taskID: task.id, executor: executor, accountMonthlyMicros: 500_000, mode: .foreground, clock: { now })
    let clock = AccountBudgetAdmissionClock(now: now)
    do { try await session.activate(reviewID: review.id, clock: { clock.now() }); Issue.record("Expired approval activated after global enrollment") } catch { }
    await session.load()
    #expect(session.state.tasks[task.id]?.lifecycle == .draft && session.state.runs.isEmpty)
    #expect(await executor.calls == 0)
}


private final class AccountBudgetClockPersistence: SchedulingPersistence, @unchecked Sendable {
    private let lock = NSLock()
    private var bytes: Data?, writes = 0
    private let clock: ActivationFixtureClock, seconds: TimeInterval
    init(clock: ActivationFixtureClock, seconds: TimeInterval) { self.clock = clock; self.seconds = seconds }
    func read() throws -> Data? { lock.withLock { bytes } }
    func write(_ data: Data) throws { lock.withLock { writes += 1; bytes = data; if writes == 4 { clock.advance(seconds) } } }
}
@Test @MainActor func localAccountBudgetRechecksPriceExpiryAndUTCMonthAfterDispatchPersistence() async throws {
    let formatter = ISO8601DateFormatter(), now = try #require(formatter.date(from: "2026-12-31T23:59:00Z"))
    for seconds: TimeInterval in [61, 150] {
        let f = try LocalScheduleFixture(); defer { f.clean() }
        let template = try f.task()
        let task = try ScheduledTask(scope: template.scope, pageID: template.pageID, allowedBlockIDs: [], prompt: "Boundary fixture", providerBindingID: f.binding,
            rule: .oneShot(now), budget: template.budget, createdAt: now.addingTimeInterval(-60), action: .summary)
        let (queue, _) = try await activatedSchedule(f, task: task)
        let clock = ActivationFixtureClock(now)
        let broker = try LocalScheduleAccountBudgetStore(ownerID: f.owner, persistence: AccountBudgetClockPersistence(clock: clock, seconds: seconds))
        try await broker.enroll(currency: "USD", monthlyMicros: 500_000)
        let executor = FixtureScheduledExecutor(bindingID: f.binding, behavior: .summary(nil))
        do { try await LocalScheduleDispatcher(store: queue, authority: f.authority, executor: executor, clock: { clock.now() }, accountBudget: broker).runDue(mode: .foreground); Issue.record("Expired or previous-month price reservation sent") } catch { }
        #expect(await executor.calls == 0)
        #expect(await broker.snapshot().reservations.values.first?.state == .uncertain)
        #expect(await queue.snapshot().runs.values.first?.state == .executionUncertain)
    }
}

private final class NativeScheduledCredentialFixture: @unchecked Sendable {
    private let lock = NSLock()
    private var key: String?, reads: [AIProviderID] = [], catalogs: [AIProviderID] = []
    init(_ key: String?) { self.key = key }
    func read(_ id: AIProviderID) -> String? { lock.withLock { reads.append(id); return key } }
    func rotate(_ value: String?) { lock.withLock { key = value } }
    func catalog(_ id: AIProviderID, model: String = "fixture-model", deprecated: Bool = false) throws -> [AIModelChoice] {
        lock.withLock { catalogs.append(id) }
        let payload = try JSONSerialization.data(withJSONObject: ["data": [["id": model, "lifecycle": deprecated ? "deprecated" : "active"]]])
        return try AIModelCatalog.decode(payload, provider: id)
    }
    var catalogCount: Int { lock.withLock { catalogs.count } }
    var readProviders: [AIProviderID] { lock.withLock { reads } }
}
@Test func nativeScheduledAccessBindsActualKeyAndExactModelThenDetectsRotationWithoutFallback() async throws {
    for provider in [AIProviderID.openAIKey, .anthropicKey] {
        let fixture = NativeScheduledCredentialFixture("fixture-api-key")
        let binding = LocalScheduledBinding(id: UUID(), provider: provider, model: "fixture-model")
        let access = try await NativeScheduledProviderAccess.resolve(binding, readCredential: { fixture.read($0) }, listModels: { id, _ in try fixture.catalog(id) })
        #expect(access.provider.id == provider && access.provider.capabilities.supportsOutputTokenLimit)
        try await access.check()
        #expect(fixture.catalogCount == 2 && fixture.readProviders.allSatisfy { $0 == provider })
        fixture.rotate("rotated-fixture-key")
        do { try await access.check(); Issue.record("Rotated key silently substituted") } catch { }
        #expect(fixture.catalogCount == 2)
    }
}
@Test func nativeScheduledAccessRejectsMissingMalformedUnknownAndDeprecatedBeforeAnyInference() async throws {
    for key in [nil, "", "fixture key", "fixture\nkey", "fixture\0key"] as [String?] {
        let fixture = NativeScheduledCredentialFixture(key)
        do { _ = try await NativeScheduledProviderAccess.resolve(.init(id: UUID(), provider: .openAIKey, model: "fixture-model"), readCredential: { fixture.read($0) }, listModels: { id, _ in try fixture.catalog(id) }); Issue.record("Invalid key admitted") } catch { }
        #expect(fixture.catalogCount == 0)
    }
    for deprecated in [false, true] {
        let fixture = NativeScheduledCredentialFixture("fixture-api-key")
        do { _ = try await NativeScheduledProviderAccess.resolve(.init(id: UUID(), provider: .anthropicKey, model: "fixture-model"), readCredential: { fixture.read($0) }, listModels: { id, _ in try fixture.catalog(id, model: deprecated ? "fixture-model" : "different-model", deprecated: deprecated) }); Issue.record("Unavailable model admitted") } catch { }
        #expect(fixture.catalogCount == 1)
    }
}
@Test func nativeScheduledAccessDetectsRotationDuringLookupAndPropagatesHTTPDenial() async throws {
    let fixture = NativeScheduledCredentialFixture("fixture-api-key")
    do { _ = try await NativeScheduledProviderAccess.resolve(.init(id: UUID(), provider: .openAIKey, model: "fixture-model"), readCredential: { fixture.read($0) }, listModels: { id, _ in fixture.rotate("new-fixture-key"); return try fixture.catalog(id) }); Issue.record("Key changed during lookup but bound") } catch { }
    let denied = NativeScheduledCredentialFixture("fixture-api-key")
    do { _ = try await NativeScheduledProviderAccess.resolve(.init(id: UUID(), provider: .anthropicKey, model: "fixture-model"), readCredential: { denied.read($0) }, listModels: { _, _ in throw AIError.http(403) }); Issue.record("HTTP denial bypassed") }
    catch { #expect(error as? AIError == .http(403)) }
}
@Test func nativeScheduledAccessDoesNotReadKeysForUnsupportedPlanOrInventedAppleModel() async throws {
    let fixture = NativeScheduledCredentialFixture("fixture-api-key")
    for (provider, model) in [(AIProviderID.chatGPTSubscription, "fixture-model"), (.applePCC, "invented-apple-model")] {
        do { _ = try await NativeScheduledProviderAccess.resolve(.init(id: UUID(), provider: provider, model: model), readCredential: { fixture.read($0) }, listModels: { id, _ in try fixture.catalog(id) }); Issue.record("Unsupported scheduled binding admitted") } catch { }
    }
    #expect(fixture.readProviders.isEmpty && fixture.catalogCount == 0)
}
private final class UnboundedScheduledFixtureProvider: AIProvider, @unchecked Sendable {
    let id = AIProviderID.chatGPTSubscription
    let capabilities = AICapabilities(textStreaming: true, requiresCredential: false)
    private let lock = NSLock()
    private var calls = 0
    var count: Int { lock.withLock { calls } }
    func stream(_ request: AIRequest) -> AsyncThrowingStream<AIEvent, any Error> {
        lock.withLock { calls += 1 }
        return AsyncThrowingStream { continuation in continuation.yield(.textDelta("Must not run")); continuation.yield(.completed); continuation.finish() }
    }
}
@Test @MainActor func scheduledAIAdapterRequiresAnActuallyEnforcedOutputTokenLimitBeforeAccessOrSend() async throws {
    let f = try LocalScheduleFixture(); defer { f.clean() }
    let task = try f.task(), capture = try f.authority.capture(task, now: task.createdAt), provider = UnboundedScheduledFixtureProvider()
    let adapter = try ScheduledAIExecutor(bindingID: f.binding, provider: provider, modelID: "fixture-model", pricingVersion: "fixture",
        modes: [.foreground], accessCheck: { Issue.record("Unbounded transport reached access check") }, quote: { _, _, _ in throw SchedulingError.denied })
    do { _ = try await adapter.preflight(task: task, capture: capture, mode: .foreground, now: task.createdAt); Issue.record("Unbounded provider preflight admitted") } catch { #expect(error as? AIError == .outputTokenLimitUnavailable) }
    do { _ = try await adapter.execute(task: task, capture: capture, requestReference: "fixture"); Issue.record("Unbounded provider executed directly") } catch { #expect(error as? AIError == .outputTokenLimitUnavailable) }
    #expect(provider.count == 0)
}

@Test @MainActor func scheduledTextRatesRoundUpExactlyAndRejectExpiredLongContextCurrencyAndOverflow() throws {
    let f = try LocalScheduleFixture(); defer { f.clean() }
    var task = try f.task(); task.budget.outputTokens = 1
    let now = task.createdAt, source = "https://developers.openai.com/api/docs/pricing"
    let rates = try ScheduledTextRateSnapshot(provider: .openAIKey, model: "fixture-model", source: source, checkedAt: now, expiresAt: now.addingTimeInterval(3600), inputNanoUSDPerToken: 125, outputNanoUSDPerToken: 500)
    let quote = try rates.quote(task: task, upperInput: 1, now: now)
    #expect(quote.maximumMicros == 1 && quote.inputTokens == 1 && quote.outputTokens == 1 && quote.expiresAt == now.addingTimeInterval(60))
    #expect(throws: (any Error).self) { try rates.quote(task: task, upperInput: 100001, now: now) }
    #expect(throws: (any Error).self) { try rates.quote(task: task, upperInput: 1, now: now.addingTimeInterval(3600)) }
    task.budget.currency = "EUR"
    #expect(throws: (any Error).self) { try rates.quote(task: task, upperInput: 1, now: now) }
    task.budget.currency = "USD"
    let overflow = try ScheduledTextRateSnapshot(provider: .openAIKey, model: "fixture-model", source: source, checkedAt: now, expiresAt: now.addingTimeInterval(60), inputNanoUSDPerToken: Int64.max, outputNanoUSDPerToken: Int64.max)
    #expect(throws: (any Error).self) { try overflow.quote(task: task, upperInput: 2, now: now) }
}
@Test @MainActor func scheduledTextRatesRejectUntrustedSourceInfiniteFreshnessAndBindVersionToExactModelAndRate() throws {
    let f = try LocalScheduleFixture(); defer { f.clean() }
    let now = Date(), source = "https://platform.claude.com/docs/en/about-claude/pricing"
    func rate(model: String, input: Int64) throws -> ScheduledTextRateSnapshot {
        try .init(provider: .anthropicKey, model: model, source: source, checkedAt: now, expiresAt: now.addingTimeInterval(3600), inputNanoUSDPerToken: input, outputNanoUSDPerToken: 10000)
    }
    #expect(try rate(model: "é", input: 2500).pricingVersion != rate(model: "e\u{301}", input: 2500).pricingVersion)
    #expect(try rate(model: "fixture-model", input: 2500).pricingVersion != rate(model: "fixture-model", input: 2501).pricingVersion)
    #expect(throws: (any Error).self) { try ScheduledTextRateSnapshot(provider: .anthropicKey, model: "fixture-model", source: "https://untrusted.invalid/pricing", checkedAt: now, expiresAt: now.addingTimeInterval(3600), inputNanoUSDPerToken: 1, outputNanoUSDPerToken: 1) }
    #expect(throws: (any Error).self) { try ScheduledTextRateSnapshot(provider: .anthropicKey, model: "fixture-model", source: source, checkedAt: now, expiresAt: now.addingTimeInterval(86401), inputNanoUSDPerToken: 1, outputNanoUSDPerToken: 1) }
}
@Test @MainActor func scheduledRequestsActuallyPinStandardTierAndProviderOutputLimit() throws {
    for (id, tier, field) in [(AIProviderID.openAIKey, "default", "max_output_tokens"), (.anthropicKey, "standard_only", "max_tokens")] {
        let provider = RemoteAIProvider(id: id, credential: "fixture-api-key")
        let request = try provider.makeRequest(AIRequest(model: "fixture-model", prompt: "Authorized text", maximumOutputTokens: 2048, serviceTier: .standard))
        let data = try #require(request.httpBody)
        let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(body["service_tier"] as? String == tier && body[field] as? Int == 2048)
        let interactive = try provider.makeRequest(AIRequest(model: "fixture-model", prompt: "Interactive text"))
        let defaultData = try #require(interactive.httpBody)
        let defaultBody = try #require(JSONSerialization.jsonObject(with: defaultData) as? [String: Any])
        #expect(defaultBody["service_tier"] == nil)
    }
}

private let fixtureOpenAIPriceHeader = "| Model | Short context input | Short context cached input | Short context cache writes | Short context output | Long context input | Long context cached input | Long context cache writes | Long context output |\n| --- | --- | --- | --- | --- | --- | --- | --- | --- |"
private func fixtureOpenAIPriceDoc(_ rows: String) -> Data {
    Data(("Prices per 1M tokens.\n### Standard pricing data\n" + fixtureOpenAIPriceHeader + "\n" + rows + "\n### Batch pricing data\n").utf8)
}
private let fixtureAnthropicPriceHeader = "| Model | Base input tokens | 5m cache writes | 1h cache writes | Cache hits and refreshes | Output tokens |\n| --- | --- | --- | --- | --- | --- |"
@Test func scheduledPriceParserUsesExactModelStandardSectionAndLargestCacheWriteRate() throws {
    let data = fixtureOpenAIPriceDoc("| fixture-model | $2 | $0.2 | $2.50 | $10 | $4 | $0.4 | $5 | $15 |")
    let value = try ScheduledTextPriceFetcher.parse(data, provider: .openAIKey, model: "fixture-model", displayName: "ignored")
    #expect(value.input == 2500 && value.output == 10000)
    #expect(throws: (any Error).self) { try ScheduledTextPriceFetcher.parse(data, provider: .openAIKey, model: "fixture", displayName: "ignored") }
    let annotated = fixtureOpenAIPriceDoc("| fixture-model (<272K context length) | $2 | - | - | $10 | $4 | - | - | $15 |")
    #expect(try ScheduledTextPriceFetcher.parse(annotated, provider: .openAIKey, model: "fixture-model", displayName: "ignored").input == 2000)
}
@Test func scheduledPriceParserRejectsAmbiguityChangedColumnsWrongCurrencyInvalidNumbersAndOverflow() throws {
    let row = "| fixture-model | $2 | $0.2 | $2.50 | $10 | $4 | $0.4 | $5 | $15 |"
    let good = fixtureOpenAIPriceDoc(row), string = String(decoding: good, as: UTF8.self)
    let variants = [
        fixtureOpenAIPriceDoc(row + "\n" + row),
        Data(string.replacingOccurrences(of: "Short context input", with: "New input category").utf8),
        Data(string.replacingOccurrences(of: "Prices per 1M tokens.", with: "EUR per token.").utf8),
        Data(string.replacingOccurrences(of: "$2.50", with: "$2e3").utf8),
        Data(string.replacingOccurrences(of: "$2.50", with: "$-2.50").utf8),
        Data(string.replacingOccurrences(of: "$2.50", with: "$9223372036854775807").utf8),
        Data((string + "\n### Standard pricing data\n" + fixtureOpenAIPriceHeader + "\n" + row).utf8),
        Data("<html>Prices per 1M tokens.</html>".utf8)
    ]
    for invalid in variants { #expect(throws: (any Error).self) { try ScheduledTextPriceFetcher.parse(invalid, provider: .openAIKey, model: "fixture-model", displayName: "ignored") } }
}
@Test func scheduledPriceParserMapsAnthropicActualDisplayNameAndSelectsOnlyShortContextRow() throws {
    let rows = "| Claude Fixture (for prompts up to 100,000 tokens) | $0.1 / MTok | $0.125 / MTok | $0.2 / MTok | $0.01 / MTok | $0.5 / MTok<sup>2</sup> |\n| Claude Fixture (for prompts over 100,000 tokens) | $0.5 / MTok | $0.625 / MTok | $1 / MTok | $0.05 / MTok | $2.5 / MTok |"
    let data = Data(("All prices are in USD.\n## Model pricing\n" + fixtureAnthropicPriceHeader + "\n" + rows + "\n## Other pricing\n").utf8)
    let value = try ScheduledTextPriceFetcher.parse(data, provider: .anthropicKey, model: "claude-fixture-id", displayName: "Claude Fixture")
    #expect(value.input == 200 && value.output == 500)
    #expect(throws: (any Error).self) { try ScheduledTextPriceFetcher.parse(data, provider: .anthropicKey, model: "claude-fixture-id", displayName: "Claude Fixtur") }
    let tiny = fixtureOpenAIPriceDoc("| fixture-model | $0.000000001 | - | - | $0.0005 | - | - | - | - |")
    let rounded = try ScheduledTextPriceFetcher.parse(tiny, provider: .openAIKey, model: "fixture-model", displayName: "unused")
    #expect(rounded.input == 1 && rounded.output == 1)
}
private actor FixturePriceDocumentTransport: ScheduledPriceDocumentTransport {
    let data: Data
    private(set) var requests: [URL] = []
    init(_ data: Data) { self.data = data }
    func fetch(_ url: URL) async throws -> Data { requests.append(url); return data }
}
@Test func scheduledPriceFetcherUsesOnlyFixedPublicURLAndExpiresAfterTenMinutes() async throws {
    let transport = FixturePriceDocumentTransport(fixtureOpenAIPriceDoc("| fixture-model | $2 | - | $2.5 | $10 | - | - | - | - |"))
    let fetcher = ScheduledTextPriceFetcher(transport: transport), now = Date()
    let rates = try await fetcher.fetch(binding: .init(id: UUID(), provider: .openAIKey, model: "fixture-model"), displayName: "unused", clock: { now })
    #expect(rates.inputNanoUSDPerToken == 2500 && rates.outputNanoUSDPerToken == 10000 && rates.expiresAt == now.addingTimeInterval(600))
    #expect(await transport.requests == [URL(string: "https://developers.openai.com/api/docs/pricing.md")!])
    do { _ = try await fetcher.fetch(binding: .init(id: UUID(), provider: .applePCC, model: "Apple Private Cloud Compute"), displayName: "unused"); Issue.record("PCC assigned API prices") } catch { }
    #expect(await transport.requests.count == 1)
}
@Test(.enabled(if: ProcessInfo.processInfo.environment["SCRIPTUM_TEST_PRICE_DOCUMENTS"] != nil)) func scheduledPriceCapturedOfficialDocumentsParseWithoutPersistingFullPagesInRepository() throws {
    guard let path = ProcessInfo.processInfo.environment["SCRIPTUM_TEST_PRICE_DOCUMENTS"] else { return }
    let root = URL(fileURLWithPath: path)
    let open = try ScheduledTextPriceFetcher.parse(Data(contentsOf: root.appendingPathComponent("openai-pricing.md")), provider: .openAIKey, model: "gpt-6.1-sol", displayName: "unused")
    let claude = try ScheduledTextPriceFetcher.parse(Data(contentsOf: root.appendingPathComponent("anthropic-pricing.md")), provider: .anthropicKey, model: "claude-sonnet-5-5", displayName: "Claude Sonnet 5.5")
    #expect(open.input > 0 && open.output > 0 && claude.input > 0 && claude.output > 0)
    print("CAPTURED_PRICING_NANO_USD: OpenAI input=\(open.input) output=\(open.output); Anthropic input=\(claude.input) output=\(claude.output)")
}
@Test(.enabled(if: ProcessInfo.processInfo.environment["SCRIPTUM_TEST_LIVE_PRICE_HTTP"] == "1")) func scheduledPriceLivePublicHTTPTransportAndParser() async throws {
    guard ProcessInfo.processInfo.environment["SCRIPTUM_TEST_LIVE_PRICE_HTTP"] == "1" else { return }
    let fetcher = ScheduledTextPriceFetcher()
    for (provider, model, title) in [(AIProviderID.openAIKey, "gpt-6.1-sol", "unused"), (.anthropicKey, "claude-sonnet-5-5", "Claude Sonnet 5.5")] {
        let rates = try await fetcher.fetch(binding: .init(id: UUID(), provider: provider, model: model), displayName: title)
        #expect(rates.inputNanoUSDPerToken > 0 && rates.outputNanoUSDPerToken > 0)
        print("LIVE_PRICE_HTTP: \(provider.rawValue) \(model) inputNanoUSD=\(rates.inputNanoUSDPerToken) outputNanoUSD=\(rates.outputNanoUSDPerToken)")
    }
}

@Test func nativeScheduledAccessRejectsChangedModelDisplayNameBeforeReusingPriceBinding() async throws {
    let fixture = NativeScheduledCredentialFixture("fixture-api-key")
    let names = NativeScheduledModelNameFixture()
    let access = try await NativeScheduledProviderAccess.resolve(.init(id: UUID(), provider: .anthropicKey, model: "fixture-model"), readCredential: { fixture.read($0) }, listModels: { _, _ in
        let name = names.next()
        return try AIModelCatalog.decode(JSONSerialization.data(withJSONObject: ["data": [["id": "fixture-model", "display_name": name]]]), provider: .anthropicKey)
    })
    #expect(access.modelDisplayName == "Initial model name")
    do { try await access.check(); Issue.record("Changed provider name reused old price mapping") } catch { #expect(error as? AIError == .invalidRequest) }
}
private final class NativeScheduledModelNameFixture: @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0
    func next() -> String { lock.withLock { calls += 1; return calls == 1 ? "Initial model name" : "Different model name" } }
}

@Test @MainActor func localForegroundRunsOnlyConfirmedDueTasksWithoutIdleAccessOrDuplicateDispatch() async throws {
    let f = try LocalScheduleFixture(); defer { f.clean() }
    let now = Date(), anchor = now.addingTimeInterval(60)
    let (session, task, executor) = try await activationSession(f, anchor: anchor)
    var resolutions = 0, nestedResolutions = 0
    let factory: @MainActor (UUID) async throws -> any LocalScheduledExecutor = { _ in
        resolutions += 1
        try await session.runNativeDue(clock: { anchor }, executorFactory: { _ in
            nestedResolutions += 1; return executor
        })
        return executor
    }
    try await session.runNativeDue(clock: { anchor }, executorFactory: factory)
    #expect(resolutions == 0 && session.state.runs.isEmpty) // Draft never resolves access.
    let review = try await session.prepareActivation(taskID: task.id, executor: executor, accountMonthlyMicros: 500_000, mode: .foreground, clock: { now })
    try await session.activate(reviewID: review.id, clock: { now })
    try await session.runNativeDue(clock: { now }, executorFactory: factory)
    #expect(resolutions == 0) // Active, but future: no catalog/price traffic.
    try await session.runNativeDue(clock: { anchor }, executorFactory: factory)
    try await session.runNativeDue(clock: { anchor }, executorFactory: factory)
    #expect(resolutions == 1 && nestedResolutions == 0)
    #expect(await executor.calls == 1)
    #expect(session.state.summaries.count == 1 && session.executionMessages.isEmpty)
    #expect(f.store.snapshot.pages.first(where: { $0.id == f.page.id })?.markdown == f.page.markdown)
    let restored = LocalScheduleSession(library: f.library); await restored.load()
    try await restored.runNativeDue(clock: { anchor }, executorFactory: factory)
    #expect(resolutions == 1 && restored.state.summaries.count == 1)
}

@Test @MainActor func localForegroundPreservesBlockedBindingAndExecutesAnotherWithoutFallback() async throws {
    let f = try LocalScheduleFixture(); defer { f.clean() }
    let now = Date(), anchor = now.addingTimeInterval(60)
    let (session, blocked, firstExecutor) = try await activationSession(f, anchor: anchor)
    let firstReview = try await session.prepareActivation(taskID: blocked.id, executor: firstExecutor, accountMonthlyMicros: 500_000, mode: .foreground, clock: { now })
    try await session.activate(reviewID: firstReview.id, clock: { now })
    try await session.create(pageID: f.page.id, prompt: "Second binding", provider: .openAIKey, model: "second-model", rule: .oneShot(anchor), action: .summary,
        budget: BudgetPolicy(currency: "USD", perRunMicros: 100_000, monthlyMicros: 500_000, inputTokens: 32000, outputTokens: 2048), end: nil, count: 1)
    let second = try #require(session.state.tasks.values.first(where: { $0.id != blocked.id }))
    let executor = ActivationFixtureExecutor(bindingID: second.providerBindingID, modelID: "second-model")
    let secondReview = try await session.prepareActivation(taskID: second.id, executor: executor, accountMonthlyMicros: 500_000, mode: .foreground, clock: { now })
    try await session.activate(reviewID: secondReview.id, clock: { now })
    try await session.runNativeDue(clock: { anchor }, executorFactory: { id in
        if id == blocked.id { throw AIError.missingCredential }
        return executor
    })
    #expect(session.executionMessages[blocked.providerBindingID] != nil)
    #expect(session.executionMessages[second.providerBindingID] == nil)
    #expect(await executor.calls == 1)
    #expect(await firstExecutor.calls == 0)
    #expect(session.state.tasks[blocked.id]?.lifecycle == .active && session.state.summaries.count == 1)
    #expect(session.state.ledger.reservations.count == 1)
}

@Test @MainActor func localForegroundDoesNotResolveAccessForOpenEditorJournal() async throws {
    let f = try LocalScheduleFixture(); defer { f.clean() }
    let now = Date(), anchor = now.addingTimeInterval(60)
    let (session, task, executor) = try await activationSession(f, anchor: anchor)
    let review = try await session.prepareActivation(taskID: task.id, executor: executor, accountMonthlyMicros: 500_000, mode: .foreground, clock: { now })
    try await session.activate(reviewID: review.id, clock: { now })
    let token = try f.store.beginEditing(pageID: f.page.id, baseRevision: f.page.revision)
    var calls = 0
    try await session.runNativeDue(clock: { anchor }, executorFactory: { _ in calls += 1; return executor })
    #expect(calls == 0 && session.state.runs.isEmpty && session.executionMessages[task.providerBindingID] != nil)
    try f.store.finishEditing(token)
    try await session.runNativeDue(clock: { anchor }, executorFactory: { _ in calls += 1; return executor })
    #expect(calls == 1 && session.state.summaries.count == 1 && session.executionMessages.isEmpty)
}

@Test @MainActor func scheduledExecutionCancelledDuringAccessNeverStartsProviderStream() async throws {
    let f = try LocalScheduleFixture(); defer { f.clean() }
    let task = try f.task(), capture = try f.authority.capture(task, now: task.createdAt)
    let provider = ScheduledFixtureAIProvider(events: [.textDelta("Must not send"), .completed])
    let executor = try ScheduledAIExecutor(bindingID: task.providerBindingID, provider: provider, modelID: "fixture-model", pricingVersion: "cancel-test", modes: [.foreground],
        accessCheck: { withUnsafeCurrentTask { $0?.cancel() } }, quote: { _, _, _ in throw AIError.invalidRequest })
    let work = Task { @MainActor in try await executor.execute(task: task, capture: capture, requestReference: "cancelled") }
    do { _ = try await work.value; Issue.record("Cancelled access proceeded") } catch is CancellationError { } catch { Issue.record("Wrong error: \(error)") }
    #expect(provider.requests.isEmpty)
}
