import Foundation
#if canImport(SkriptumScheduling)
import SkriptumScheduling
#endif

enum LocalScheduledMode: Sendable { case foreground, background }
enum LocalScheduledOutput: Sendable { case summary(String), proposal([UUID: String]) }
struct LocalScheduledResult: Sendable {
    let output: LocalScheduledOutput
    let providerID: String, modelID: String
    /// Nil means billing has not been confirmed; the reservation stays held.
    let confirmedCostMicros: Int64?
}
protocol LocalScheduledExecutor: Sendable {
    var bindingID: UUID { get }
    var providerID: String { get }
    var modelID: String { get }
    var pricingVersion: String { get }
    func preflight(task: ScheduledTask, capture: LocalScheduledCapture, mode: LocalScheduledMode, now: Date) async throws -> BudgetQuote
    func execute(task: ScheduledTask, capture: LocalScheduledCapture, requestReference: String) async throws -> LocalScheduledResult
}

/// Serial local orchestration. The provider adapter supplies real eligibility,
/// prices and execution; this type never invents those facts or edits documents.
@MainActor final class LocalScheduleDispatcher {
    private let store: SchedulingStore, authority: LocalScheduleAuthority
    private let executor: any LocalScheduledExecutor
    private let clock: @Sendable () -> Date
    private let workerID = UUID()
    private var working = false
    init(store: SchedulingStore, authority: LocalScheduleAuthority, executor: any LocalScheduledExecutor,
         clock: @escaping @Sendable () -> Date = { Date() }) {
        self.store = store; self.authority = authority; self.executor = executor; self.clock = clock
    }
    func runDue(mode: LocalScheduledMode) async throws {
        guard !working else { return }; working = true; defer { working = false }
        var state = await store.snapshot()
        try await store.recoverExpired(now: clock(), expectedVersion: state.version)
        state = await store.snapshot()
        _ = try await store.enqueueDue(now: clock(), expectedVersion: state.version)
        state = await store.snapshot()
        let due = state.runs.values.filter {
            [.queued, .leased, .authorized, .reserved].contains($0.state) &&
            ($0.lease?.expiresAt ?? .distantPast) <= clock()
        }.sorted { $0.occurrence.scheduledUTC < $1.occurrence.scheduledUTC }
        for run in due { try Task.checkCancellation(); try await perform(run.id, mode: mode) }
    }
    private func perform(_ id: UUID, mode: LocalScheduledMode) async throws {
        var state = await store.snapshot()
        guard let run = state.runs[id], let task = state.tasks[run.occurrence.taskID], task.lifecycle == .active,
              task.generation == run.occurrence.generation else { return }
        let lease = RunLease(workerID: workerID, expiresAt: clock().addingTimeInterval(900))
        try await store.claim(runID: id, lease: lease, now: clock(), expectedVersion: state.version)
        var dispatched = false
        do {
            guard task.providerBindingID == executor.bindingID else { throw SchedulingError.denied }
            let capture = try authority.capture(task, now: clock())
            let quote = try await executor.preflight(task: task, capture: capture, mode: mode, now: clock())
            guard quote.version == executor.pricingVersion else { throw SchedulingError.budgetDenied }
            try Task.checkCancellation()
            let fresh = try authority.capture(task, now: clock())
            guard fresh.page.revision == capture.page.revision, fresh.sourceDigest == capture.sourceDigest,
                  fresh.sourceForProvider.utf8.elementsEqual(capture.sourceForProvider.utf8) else { throw SchedulingError.staleProposal }
            state = await store.snapshot()
            try await store.authorize(runID: id, fence: lease.fence, grant: fresh.grant, now: clock(), expectedVersion: state.version)
            state = await store.snapshot()
            try await store.reserve(runID: id, fence: lease.fence, quote: quote, expectedQuoteVersion: executor.pricingVersion,
                now: clock(), expectedVersion: state.version)
            let admitted = try authority.capture(task, now: clock())
            guard admitted.page.revision == capture.page.revision, admitted.sourceDigest == capture.sourceDigest else { throw SchedulingError.staleProposal }
            try Task.checkCancellation()
            let reference = "scriptum-scheduled-" + id.uuidString.lowercased()
            state = await store.snapshot()
            try await store.dispatch(runID: id, fence: lease.fence, requestReference: reference,
                grant: admitted.grant, expectedQuoteVersion: executor.pricingVersion, now: clock(), expectedVersion: state.version)
            dispatched = true
            state = await store.snapshot()
            try await store.started(runID: id, fence: lease.fence, now: clock(), expectedVersion: state.version)
            let result = try await executor.execute(task: task, capture: admitted, requestReference: reference)
            try Task.checkCancellation()
            guard result.providerID.utf8.elementsEqual(executor.providerID.utf8),
                  result.modelID.utf8.elementsEqual(executor.modelID.utf8) else { throw SchedulingError.denied }
            let final = try authority.capture(task, now: clock())
            state = await store.snapshot()
            switch result.output {
            case .summary(let text):
                guard task.action == .summary else { throw SchedulingError.denied }
                let summary = try ScheduledSummary(scope: task.scope, runID: id, pageID: task.pageID,
                    baseRevision: capture.page.revision, source: capture.page.markdown, text: text,
                    providerID: result.providerID, modelID: result.modelID, createdAt: clock())
                try await store.recordSummary(summary, fence: lease.fence, grant: final.grant, now: clock(), expectedVersion: state.version)
            case .proposal(let blocks):
                guard task.action == .proposal else { throw SchedulingError.denied }
                let proposal = try ScheduledProposal(scope: task.scope, runID: id, pageID: task.pageID,
                    baseRevision: capture.page.revision, allowedBlockIDs: task.allowedBlockIDs,
                    source: capture.page.markdown, replacementBlocks: blocks,
                    providerID: result.providerID, modelID: result.modelID)
                try await store.recordProposal(proposal, fence: lease.fence, grant: final.grant, now: clock(), expectedVersion: state.version)
            }
            if let cost = result.confirmedCostMicros {
                state = await store.snapshot()
                try await store.settle(runID: id, actualMicros: cost, expectedVersion: state.version)
            }
        } catch {
            state = await store.snapshot()
            if let current = state.runs[id], [.leased, .authorized, .reserved].contains(current.state), !dispatched {
                try await store.rejectBeforeDispatch(runID: id, fence: lease.fence,
                    reason: error as? SchedulingError == .budgetDenied ? .budgetDenied : .denied,
                    now: clock(), expectedVersion: state.version)
            } else if let current = state.runs[id], [.dispatching, .running].contains(current.state) {
                if current.lease?.expiresAt ?? .distantPast <= clock() { try await store.recoverExpired(now: clock(), expectedVersion: state.version) }
                else { try await store.uncertain(runID: id, fence: lease.fence, now: clock(), expectedVersion: state.version) }
            }
            throw error
        }
    }
}
