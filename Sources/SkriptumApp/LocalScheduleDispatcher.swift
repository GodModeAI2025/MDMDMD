import Foundation
#if canImport(SkriptumScheduling)
import SkriptumScheduling
#endif

enum LocalScheduledMode: Sendable, Hashable { case foreground, background }
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
    private let accountBudget: LocalScheduleAccountBudgetStore?
    private let clock: @Sendable () -> Date
    private let workerID = UUID()
    private var working = false
    init(store: SchedulingStore, authority: LocalScheduleAuthority, executor: any LocalScheduledExecutor,
         clock: @escaping @Sendable () -> Date = { Date() }, accountBudget: LocalScheduleAccountBudgetStore? = nil) {
        self.store = store; self.authority = authority; self.executor = executor; self.clock = clock
        self.accountBudget = accountBudget
    }
    func runDue(mode: LocalScheduledMode) async throws {
        guard !working else { return }; working = true; defer { working = false }
        var state = await store.snapshot()
        try await store.recoverExpired(now: clock(), expectedVersion: state.version)
        state = await store.snapshot()
        _ = try await store.enqueueDue(now: clock(), expectedVersion: state.version)
        state = await store.snapshot()
        let due = state.runs.values.filter { run in
            guard let task = state.tasks[run.occurrence.taskID],
                  task.providerBindingID == executor.bindingID,
                  mode == .foreground || task.executionPolicy == .backgroundAllowed,
                  task.scope == authority.scope(spaceID: task.scope.spaceID) else { return false }
            return [.queued, .leased, .authorized, .reserved].contains(run.state) &&
            (run.lease?.expiresAt ?? .distantPast) <= clock()
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
        var accountPermit: LocalAccountBudgetPermit?
        do {
            guard task.providerBindingID == executor.bindingID,
                  mode == .foreground || task.executionPolicy == .backgroundAllowed else { throw SchedulingError.denied }
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
            if let accountBudget {
                accountPermit = try await accountBudget.reserve(runID: id, task: task, fence: lease.fence, quote: quote, now: clock())
            }
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
            if let accountBudget, let accountPermit { try await accountBudget.dispatched(accountPermit, now: clock()) }
            state = await store.snapshot()
            try await store.started(runID: id, fence: lease.fence, now: clock(), expectedVersion: state.version)
            let sendAt = clock()
            let sendPeriod = try BudgetLedger.month(for: sendAt)
            guard quote.expiresAt > sendAt,
                  accountPermit == nil || accountPermit?.period == sendPeriod else { throw SchedulingError.budgetDenied }
            let sending = try authority.capture(task, now: sendAt)
            guard sending.page.revision == capture.page.revision, sending.sourceDigest == capture.sourceDigest else { throw SchedulingError.staleProposal }
            let result = try await executor.execute(task: task, capture: sending, requestReference: reference)
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
            if let accountBudget, let accountPermit { try await accountBudget.completed(accountPermit, actualMicros: result.confirmedCostMicros) }
        } catch {
            state = await store.snapshot()
            if let current = state.runs[id], [.leased, .authorized, .reserved].contains(current.state), !dispatched {
                try await store.rejectBeforeDispatch(runID: id, fence: lease.fence,
                    reason: error as? SchedulingError == .budgetDenied ? .budgetDenied : .denied,
                    now: clock(), expectedVersion: state.version)
                if let accountBudget, let accountPermit { try await accountBudget.releaseBeforeDispatch(accountPermit) }
            } else if let current = state.runs[id], [.dispatching, .running].contains(current.state) {
                if current.lease?.expiresAt ?? .distantPast <= clock() { try await store.recoverExpired(now: clock(), expectedVersion: state.version) }
                else { try await store.uncertain(runID: id, fence: lease.fence, now: clock(), expectedVersion: state.version) }
            }
            if dispatched, let accountBudget, let accountPermit { try await accountBudget.uncertain(accountPermit) }
            throw error
        }
    }
}


struct LocalAccountBudgetPermit: Sendable {
    let runID: UUID, fence: UUID
    let period: String
}
private enum LocalAccountBudgetPhase: String, Codable { case legacy, reserved, dispatched, completed, uncertain, released }
private struct LocalAccountBudgetRun: Codable {
    let fence: UUID?
    var phase: LocalAccountBudgetPhase
}
private struct LocalAccountBudgetState: Codable {
    var schemaVersion = 1, version = 0
    let ownerID: UUID
    var ledger = BudgetLedger()
    var runs: [UUID: LocalAccountBudgetRun] = [:]
    func validate() throws {
        try ledger.validate()
        guard schemaVersion == 1, version >= 0, version < Int.max,
              ledger.accountCeilings.keys.allSatisfy({ $0.accountID == ownerID }),
              ledger.reservations.values.allSatisfy({ $0.scope.accountID == ownerID }),
              Set(runs.keys) == Set(ledger.reservations.keys) else { throw SchedulingError.denied }
        for (id, run) in runs {
            guard let reservation = ledger.reservations[id],
                  run.phase == .legacy || run.fence != nil,
                  run.phase != .released || reservation.state == .released,
                  run.phase != .uncertain || reservation.state == .uncertain,
                  run.phase != .completed || [.held, .settled].contains(reservation.state),
                  run.phase != .reserved && run.phase != .dispatched || reservation.state == .held else { throw SchedulingError.invalidValue }
        }
    }
    mutating func mergeLegacy(_ incoming: BudgetLedger) throws {
        guard incoming.accountCeilings.keys.allSatisfy({ $0.accountID == ownerID }) else { throw SchedulingError.denied }
        try ledger.mergeConservatively(incoming)
        for (id, reservation) in ledger.reservations {
            guard var run = runs[id] else { runs[id] = .init(fence: nil, phase: .legacy); continue }
            if run.phase != .legacy {
                switch reservation.state {
                case .uncertain: run.phase = .uncertain
                case .settled: run.phase = .completed
                case .released: run.phase = .released
                case .held: if run.phase == .released { run = .init(fence: nil, phase: .legacy) }
                }
                runs[id] = run
            }
        }
    }
}
/// One device-local owner ledger across all owned libraries. Every actor
/// mutation is synchronous inside its isolation and reaches atomic persistence
/// before it returns. It is not a distributed/iCloud account budget.
actor LocalScheduleAccountBudgetStore {
    private var state: LocalAccountBudgetState
    private let persistence: any SchedulingPersistence
    init(ownerID: UUID, persistence: any SchedulingPersistence, legacy: [BudgetLedger] = []) throws {
        self.persistence = persistence
        if let data = try persistence.read() {
            guard data.count <= SchedulingState.maximumFileBytes else { throw SchedulingError.persistenceTooLarge }
            state = try JSONDecoder().decode(LocalAccountBudgetState.self, from: data)
            guard state.ownerID == ownerID else { throw SchedulingError.denied }
            try state.validate()
        } else { state = LocalAccountBudgetState(ownerID: ownerID) }
        for ledger in legacy { try state.mergeLegacy(ledger) }
        try state.validate()
        // Bootstrap is durable before any new run can obtain a reservation.
        try persistence.write(JSONEncoder().encode(state))
    }
    func snapshot() -> BudgetLedger { state.ledger }
    private func transact(_ operation: (inout LocalAccountBudgetState) throws -> Void) throws {
        var candidate = state; try operation(&candidate)
        guard candidate.version < Int.max - 1 else { throw SchedulingError.invalidValue }
        candidate.version += 1; try candidate.validate()
        let data = try JSONEncoder().encode(candidate)
        guard data.count <= SchedulingState.maximumFileBytes else { throw SchedulingError.persistenceTooLarge }
        try persistence.write(data); state = candidate
    }
    func checkCeiling(currency: String, monthlyMicros: Int64) throws {
        guard monthlyMicros >= 0 else { throw SchedulingError.denied }
        if let current = state.ledger.accountCeilings.first(where: { $0.key.currency == currency })?.value {
            guard current == monthlyMicros else { throw SchedulingError.denied }
        }
    }
    func enroll(currency: String, monthlyMicros: Int64) throws {
        try transact { candidate in
            try candidate.ledger.enrollAccountCeiling(accountID: candidate.ownerID, currency: currency, monthlyMicros: monthlyMicros)
        }
    }
    func importLegacy(_ ledger: BudgetLedger) throws {
        try transact { candidate in
            try candidate.mergeLegacy(ledger)
        }
    }
    func reserve(runID: UUID, task: ScheduledTask, fence: UUID, quote: BudgetQuote, now: Date) throws -> LocalAccountBudgetPermit {
        try transact { candidate in
            try task.validate()
            guard task.scope.accountID == candidate.ownerID, candidate.runs[runID] == nil else { throw SchedulingError.denied }
            _ = try candidate.ledger.reserve(runID: runID, taskID: task.id, scope: task.scope,
                period: BudgetLedger.month(for: now), policy: task.budget, quote: quote, now: now, expectedQuoteVersion: quote.version)
            candidate.runs[runID] = .init(fence: fence, phase: .reserved)
        }
        return .init(runID: runID, fence: fence, period: try BudgetLedger.month(for: now))
    }
    private static func admitted(_ permit: LocalAccountBudgetPermit, _ state: LocalAccountBudgetState) throws -> LocalAccountBudgetRun {
        guard let run = state.runs[permit.runID], run.fence == permit.fence,
              state.ledger.reservations[permit.runID]?.period == permit.period else { throw SchedulingError.denied }; return run
    }
    func dispatched(_ permit: LocalAccountBudgetPermit, now: Date) throws {
        try transact { candidate in
            var run = try Self.admitted(permit, candidate); guard run.phase == .reserved else { throw SchedulingError.invalidTransition }
            guard permit.period == (try BudgetLedger.month(for: now)),
                  candidate.ledger.reservations[permit.runID]?.quote.expiresAt ?? .distantPast > now else { throw SchedulingError.budgetDenied }
            run.phase = .dispatched; candidate.runs[permit.runID] = run
        }
    }
    /// Called only after the local fenced rejectBeforeDispatch commit succeeded.
    func releaseBeforeDispatch(_ permit: LocalAccountBudgetPermit) throws {
        try transact { candidate in
            var run = try Self.admitted(permit, candidate); guard run.phase == .reserved else { throw SchedulingError.executionUncertain }
            try candidate.ledger.release(runID: permit.runID); run.phase = .released; candidate.runs[permit.runID] = run
        }
    }
    func completed(_ permit: LocalAccountBudgetPermit, actualMicros: Int64?) throws {
        try transact { candidate in
            var run = try Self.admitted(permit, candidate); guard run.phase == .dispatched else { throw SchedulingError.invalidTransition }
            if let actualMicros { try candidate.ledger.settle(runID: permit.runID, actualMicros: actualMicros) }
            run.phase = .completed; candidate.runs[permit.runID] = run
        }
    }
    func uncertain(_ permit: LocalAccountBudgetPermit) throws {
        try transact { candidate in
            var run = try Self.admitted(permit, candidate)
            if candidate.ledger.reservations[permit.runID]?.state == .settled { return }
            guard run.phase != .released else { throw SchedulingError.invalidTransition }
            try candidate.ledger.markUncertain(runID: permit.runID); run.phase = .uncertain; candidate.runs[permit.runID] = run
        }
    }
}
@MainActor private final class LocalAccountBudgetWeakEntry {
    weak var value: LocalScheduleAccountBudgetStore?
    init(_ value: LocalScheduleAccountBudgetStore) { self.value = value }
}
@MainActor enum LocalAccountBudgetRegistry {
    private static var entries: [URL: LocalAccountBudgetWeakEntry] = [:]
    private struct PendingOpen {
        let id = UUID()
        let task: Task<LocalScheduleAccountBudgetStore, any Error>
    }
    private static var opening: [URL: PendingOpen] = [:]
    static func open(ownerID: UUID, directory: URL, localSchedules: URL) async throws -> LocalScheduleAccountBudgetStore {
        let file = directory.appendingPathComponent(ownerID.uuidString.lowercased() + ".json")
        if let existing = entries[file]?.value { return existing }
        let pending: PendingOpen
        if let existing = opening[file] { pending = existing }
        else {
            pending = PendingOpen(task: Task.detached(priority: .utility) { try bootstrap(ownerID: ownerID, file: file, localSchedules: localSchedules) })
            opening[file] = pending
        }
        do {
            let value = try await pending.task.value
            entries[file] = LocalAccountBudgetWeakEntry(value)
            if opening[file]?.id == pending.id { opening[file] = nil }
            return value
        } catch {
            if opening[file]?.id == pending.id { opening[file] = nil }
            throw error
        }
    }
    nonisolated private static func bootstrap(ownerID: UUID, file: URL, localSchedules: URL) throws -> LocalScheduleAccountBudgetStore {
        var legacy: [BudgetLedger] = []
        if FileManager.default.fileExists(atPath: localSchedules.path) {
            let folders = try FileManager.default.contentsOfDirectory(at: localSchedules, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard folders.count <= 1000 else { throw SchedulingError.persistenceTooLarge }
            for entry in folders {
                try Task.checkCancellation()
                let attributes = try entry.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                guard attributes.isSymbolicLink != true else { throw SchedulingError.unsafeFile }
                if attributes.isRegularFile == true { continue }
                // Rebuild from the pinned root. FileManager may return /tmp
                // aliases for /private/tmp, which no-follow I/O must reject.
                let folder = localSchedules.appendingPathComponent(entry.lastPathComponent, isDirectory: true)
                guard let bytes = try FileSchedulingPersistence(url: folder.appendingPathComponent("tasks-v1.json")).read() else { continue }
                let snapshot = try JSONDecoder().decode(SchedulingState.self, from: bytes); try snapshot.validate()
                if snapshot.tasks.values.contains(where: { $0.scope.accountID == ownerID }) || snapshot.ledger.accountCeilings.keys.contains(where: { $0.accountID == ownerID }) {
                    guard snapshot.tasks.values.allSatisfy({ $0.scope.accountID == ownerID }),
                          snapshot.ledger.accountCeilings.keys.allSatisfy({ $0.accountID == ownerID }) else { throw SchedulingError.denied }
                    legacy.append(snapshot.ledger)
                }
            }
        }
        return try LocalScheduleAccountBudgetStore(ownerID: ownerID, persistence: FileSchedulingPersistence(url: file), legacy: legacy)
    }
}
