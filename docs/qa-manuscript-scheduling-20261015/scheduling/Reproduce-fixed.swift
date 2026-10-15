import Foundation
import SkriptumCore
import SkriptumScheduling
import SkriptumAI
@testable import SkriptumWorkspaceModel

final class ProbeClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date
    init(_ value: Date) { self.value = value }
    func now() -> Date { lock.withLock { value } }
    func advance(_ seconds: TimeInterval) { lock.withLock { value = value.addingTimeInterval(seconds) } }
}
actor ProbeAccess {
    var checks = 0
    let hook: @Sendable () async throws -> Void
    init(hook: @escaping @Sendable () async throws -> Void) { self.hook = hook }
    func check() async throws { checks += 1; if checks == 2 { try await hook() } }
}
final class ProbeProvider: AIProvider, @unchecked Sendable {
    let id = AIProviderID.openAIKey
    let capabilities = AICapabilities(textStreaming: true, requiresCredential: true, supportsOutputTokenLimit: true)
    let clock: ProbeClock
    private let lock = NSLock()
    private var sent: [(Date, String)] = []
    init(clock: ProbeClock) { self.clock = clock }
    var sends: [(Date, String)] { lock.withLock { sent } }
    func stream(_ request: AIRequest) -> AsyncThrowingStream<AIEvent, any Error> {
        lock.withLock { sent.append((clock.now(), request.prompt)) }
        return AsyncThrowingStream { continuation in continuation.yield(.textDelta("Summary")); continuation.yield(.completed); continuation.finish() }
    }
}
@main struct Reproduce {
    @MainActor static func main() async throws {
        for mode in ["expired_quote", "month_rollover", "cancel_during_access", "pause_during_access", "trash_during_access"] {
            let root = URL(fileURLWithPath: "/private/tmp/schedule-transmission-audit-" + UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let suite = "schedule.transmission.audit." + UUID().uuidString
            let preferences = UserDefaults(suiteName: suite)!
            defer { preferences.removePersistentDomain(forName: suite) }
            let docs = root.appendingPathComponent("Documents")
            let documents = try LibraryStore(directory: docs.appendingPathComponent("Skriptum"))
            let space = try documents.createSpace(title: "Probe")
            let page = try documents.createPage(spaceID: space.id, title: "Confidential source", markdown: "Private manuscript words")
            let library = try WritingLibrary(store: documents, documentRoot: docs, supportRoot: root.appendingPathComponent("Support"), preferences: preferences)
            let owner = UUID(), binding = UUID()
            let authority = try LocalScheduleAuthority(library: library, ownerID: owner, providerBindingID: binding, accountBudgets: ["USD": 500000])
            let now = ISO8601DateFormatter().date(from: mode == "month_rollover" ? "2026-12-31T23:59:59Z" : "2026-12-15T12:00:00Z")!
            let clock = ProbeClock(now)
            var task = try ScheduledTask(scope: authority.scope(spaceID: space.id), pageID: page.id, allowedBlockIDs: [], prompt: "Summarize", providerBindingID: binding, rule: .oneShot(now), budget: BudgetPolicy(currency: "USD", perRunMicros: 100000, monthlyMicros: 500000, inputTokens: 32000, outputTokens: 2048), createdAt: now.addingTimeInterval(-60), action: .summary)
            task.contentPermissionVersion = ScheduledTask.currentContentPermissionVersion
            let frozenTask = task
            let queue = try SchedulingStore(persistence: FileSchedulingPersistence(url: root.appendingPathComponent("Queue/state.json")))
            try await queue.add(task, expectedVersion: 0)
            try await queue.activate(taskID: task.id, contentPermissionVersion: ScheduledTask.currentContentPermissionVersion, grant: authority.capture(task, now: now).grant, now: now, expectedVersion: 1)
            let account = try LocalScheduleAccountBudgetStore(ownerID: owner, persistence: FileSchedulingPersistence(url: root.appendingPathComponent("Budget/state.json")))
            try await account.enroll(currency: "USD", monthlyMicros: 500000)
            let access = ProbeAccess {
                switch mode {
                case "expired_quote": clock.advance(61)
                case "month_rollover": clock.advance(2)
                case "cancel_during_access":
                    let current = await queue.snapshot()
                    try await queue.cancel(taskID: frozenTask.id, expectedGeneration: frozenTask.generation, expectedVersion: current.version)
                case "pause_during_access":
                    let current = await queue.snapshot()
                    let grant = try await MainActor.run { try authority.capture(frozenTask, now: clock.now()).grant }
                    try await queue.pause(taskID: frozenTask.id, grant: grant, now: clock.now(), expectedGeneration: frozenTask.generation, expectedVersion: current.version)
                case "trash_during_access": try await MainActor.run { try documents.trashPage(page.id) }
                default: break
                }
            }
            let provider = ProbeProvider(clock: clock)
            let executor = try ScheduledAIExecutor(bindingID: binding, provider: provider, modelID: "fixture", pricingVersion: "fixture-price", modes: [.foreground], accessCheck: { try await access.check() }, quote: { task, upper, now in BudgetQuote(currency: "USD", maximumMicros: 10000, inputTokens: upper, outputTokens: task.budget.outputTokens, version: "fixture-price", expiresAt: now.addingTimeInterval(60)) })
            var outcome = "completed"
            do { try await LocalScheduleDispatcher(store: queue, authority: authority, executor: executor, clock: { clock.now() }, accountBudget: account).runDue(mode: .foreground) } catch { outcome = String(describing: error) }
            let state = await queue.snapshot(), ledger = await account.snapshot()
            let sentAt = provider.sends.first?.0
            let record: [String: Any] = ["scenario": mode, "accessChecks": await access.checks, "providerCalls": provider.sends.count, "containsPrivateSource": provider.sends.first?.1.contains("Private manuscript words") ?? false, "outcome": outcome, "lifecycle": String(describing: state.tasks[task.id]!.lifecycle), "runState": String(describing: state.runs.values.first!.state), "reservedPeriod": ledger.reservations.values.first!.period, "sendPeriod": try sentAt.map { try BudgetLedger.month(for: $0) } ?? "none", "quoteExpiredAtSend": sentAt.map { $0 >= now.addingTimeInterval(60) } ?? false]
            print(String(decoding: try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]), as: UTF8.self))
            precondition(provider.sends.isEmpty, "Final admission must reject before any provider send")
        }
    }
}
