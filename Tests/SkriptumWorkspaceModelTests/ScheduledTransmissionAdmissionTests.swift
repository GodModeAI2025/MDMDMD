import Foundation
import Testing
import SkriptumCore
import SkriptumScheduling
import SkriptumAI
@testable import SkriptumWorkspaceModel

private final class TransmissionClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date
    init(_ value: Date) { self.value = value }
    func now() -> Date { lock.withLock { value } }
    func advance(_ seconds: TimeInterval) { lock.withLock { value = value.addingTimeInterval(seconds) } }
}
private actor TransmissionAccess {
    private(set) var checks = 0
    let hook: @Sendable () async throws -> Void
    init(hook: @escaping @Sendable () async throws -> Void) { self.hook = hook }
    func check() async throws {
        checks += 1
        if checks == 2 { try await hook() }
    }
}
private final class TransmissionProvider: AIProvider, @unchecked Sendable {
    let id = AIProviderID.openAIKey
    let capabilities = AICapabilities(textStreaming: true, requiresCredential: true, supportsOutputTokenLimit: true)
    private let lock = NSLock()
    private var recorded: [AIRequest] = []
    var requests: [AIRequest] { lock.withLock { recorded } }
    func stream(_ request: AIRequest) -> AsyncThrowingStream<AIEvent, any Error> {
        lock.withLock { recorded.append(request) }
        return AsyncThrowingStream { continuation in
            continuation.yield(.textDelta("Reviewed summary")); continuation.yield(.completed); continuation.finish()
        }
    }
}
private final class TransmissionBudgetPersistence: SchedulingPersistence, @unchecked Sendable {
    private let file: FileSchedulingPersistence
    private let onReservation: @Sendable () async throws -> Void
    private let lock = NSLock()
    private var writes = 0
    private var failure: (any Error)?
    init(file: FileSchedulingPersistence, onReservation: @escaping @Sendable () async throws -> Void) {
        self.file = file; self.onReservation = onReservation
    }
    func read() throws -> Data? { try file.read() }
    func write(_ data: Data) throws {
        try file.write(data)
        let reserved = lock.withLock { writes += 1; return writes == 3 }
        guard reserved else { return }
        let completed = DispatchSemaphore(value: 0)
        Task.detached {
            do { try await self.onReservation() }
            catch { self.lock.withLock { self.failure = error } }
            completed.signal()
        }
        guard completed.wait(timeout: .now() + 5) == .success else { throw SchedulingError.invalidTransition }
        if let error = lock.withLock({ failure }) { throw error }
    }
}
private enum TransmissionChange: CaseIterable, Sendable {
    case none, expiredQuote, monthRollover, cancel, pause, trash, cancelDuringReservation, pauseDuringReservation
}

@Test(arguments: TransmissionChange.allCases) @MainActor private func scheduledTransmissionRevalidatesAfterFinalAccessCheck(
    change: TransmissionChange
) async throws {
    let root = URL(fileURLWithPath: "/private/tmp/ScriptumTransmission-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let suite = "scriptum.transmission.test." + UUID().uuidString
    let preferences = try #require(UserDefaults(suiteName: suite))
    defer { preferences.removePersistentDomain(forName: suite) }
    let documents = root.appendingPathComponent("Documents")
    let documentStore = try LibraryStore(directory: documents.appendingPathComponent("Skriptum"))
    let space = try documentStore.createSpace(title: "Writing")
    let page = try documentStore.createPage(spaceID: space.id, title: "Manuscript", markdown: "Private e\u{301}\r\n🦊 manuscript")
    let library = try WritingLibrary(store: documentStore, documentRoot: documents,
        supportRoot: root.appendingPathComponent("Support"), preferences: preferences)
    let owner = UUID(), binding = UUID()
    let authority = try LocalScheduleAuthority(library: library, ownerID: owner,
        providerBindingID: binding, accountBudgets: ["USD": 500_000])
    let now = try #require(ISO8601DateFormatter().date(from:
        change == .monthRollover ? "2026-12-31T23:59:59Z" : "2026-12-15T12:00:00Z"))
    let clock = TransmissionClock(now)
    var created = try ScheduledTask(scope: authority.scope(spaceID: space.id), pageID: page.id,
        allowedBlockIDs: [], prompt: "Summarize", providerBindingID: binding, rule: .oneShot(now),
        budget: BudgetPolicy(currency: "USD", perRunMicros: 100_000, monthlyMicros: 500_000,
            inputTokens: 32_000, outputTokens: 2048), createdAt: now.addingTimeInterval(-60), action: .summary)
    created.contentPermissionVersion = ScheduledTask.currentContentPermissionVersion
    let task = created
    let queueFile = try FileSchedulingPersistence(url: root.appendingPathComponent("Queue/state.json"))
    let queue = try SchedulingStore(persistence: queueFile)
    try await queue.add(task, expectedVersion: 0)
    try await queue.activate(taskID: task.id, contentPermissionVersion: ScheduledTask.currentContentPermissionVersion,
        grant: authority.capture(task, now: now).grant, now: now, expectedVersion: 1)
    let budgetFile = try FileSchedulingPersistence(url: root.appendingPathComponent("Budget/state.json"))
    let grant = try authority.capture(task, now: now).grant
    let budgetPersistence = TransmissionBudgetPersistence(file: budgetFile) {
        guard change == .cancelDuringReservation || change == .pauseDuringReservation else { return }
        let snapshot = await queue.snapshot()
        if change == .cancelDuringReservation {
            try await queue.cancel(taskID: task.id, expectedGeneration: task.generation, expectedVersion: snapshot.version)
        } else {
            try await queue.pause(taskID: task.id, grant: grant, now: now,
                expectedGeneration: task.generation, expectedVersion: snapshot.version)
        }
    }
    let account = try LocalScheduleAccountBudgetStore(ownerID: owner, persistence: budgetPersistence)
    try await account.enroll(currency: "USD", monthlyMicros: 500_000)
    let access = TransmissionAccess {
        switch change {
        case .none, .cancelDuringReservation, .pauseDuringReservation: break
        case .expiredQuote: clock.advance(61)
        case .monthRollover: clock.advance(2)
        case .cancel:
            let snapshot = await queue.snapshot()
            try await queue.cancel(taskID: task.id, expectedGeneration: task.generation, expectedVersion: snapshot.version)
        case .pause:
            let snapshot = await queue.snapshot()
            let grant = try await MainActor.run { try authority.capture(task, now: clock.now()).grant }
            try await queue.pause(taskID: task.id, grant: grant, now: clock.now(),
                expectedGeneration: task.generation, expectedVersion: snapshot.version)
        case .trash: try await MainActor.run { try documentStore.trashPage(page.id) }
        }
    }
    let provider = TransmissionProvider()
    let executor = try ScheduledAIExecutor(bindingID: binding, provider: provider, modelID: "fixture",
        pricingVersion: "fixture-price", modes: [.foreground], accessCheck: { try await access.check() },
        quote: { task, upper, now in BudgetQuote(currency: "USD", maximumMicros: 10_000,
            inputTokens: upper, outputTokens: task.budget.outputTokens, version: "fixture-price",
            expiresAt: now.addingTimeInterval(60)) })
    let dispatcher = LocalScheduleDispatcher(store: queue, authority: authority, executor: executor,
        clock: { clock.now() }, accountBudget: account)
    if change == .none { try await dispatcher.runDue(mode: .foreground) }
    else { await #expect(throws: (any Error).self) { try await dispatcher.runDue(mode: .foreground) } }
    let cancelledDuringReservation = change == .cancelDuringReservation || change == .pauseDuringReservation
    #expect(await access.checks == (cancelledDuringReservation ? 1 : 2))
    let state = await queue.snapshot(), ledger = await account.snapshot()
    let run = try #require(state.runs.values.first)
    #expect(state.runs.count == 1)
    #expect(documentStore.snapshot.pages.first(where: { $0.id == page.id })?.markdown.utf8.elementsEqual(page.markdown.utf8) == true)
    if change == .none {
        #expect(provider.requests.count == 1 && state.summaries.count == 1)
        #expect(run.state == .completed && run.providerRequestReference != nil)
        #expect(state.ledger.reservations[run.id]?.state == .held)
        #expect(ledger.reservations[run.id]?.state == .held)
        try await dispatcher.runDue(mode: .foreground)
        #expect(provider.requests.count == 1)
    } else {
        #expect(provider.requests.isEmpty && state.summaries.isEmpty && state.proposals.isEmpty)
        #expect(run.providerRequestReference == nil)
        if cancelledDuringReservation {
            #expect(state.ledger.reservations[run.id] == nil)
            #expect(run.state == .cancelled)
        } else { #expect(state.ledger.reservations[run.id]?.state == .released) }
        #expect(ledger.reservations[run.id]?.state == .released)
        let restarted = try await SchedulingStore(persistence: queueFile).snapshot()
        let restartedBudget = try await LocalScheduleAccountBudgetStore(ownerID: owner, persistence: budgetFile).snapshot()
        #expect(restarted.runs[run.id] == run)
        #expect(restartedBudget.reservations[run.id]?.state == .released)
    }
}
