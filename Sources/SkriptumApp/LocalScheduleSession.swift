import Foundation
import Observation
import CryptoKit
#if canImport(SkriptumCore)
import SkriptumCore
#endif
#if canImport(SkriptumAI)
import SkriptumAI
#endif
#if canImport(SkriptumScheduling)
import SkriptumScheduling
#endif

struct LocalScheduledBinding: Codable, Equatable, Sendable {
    let id: UUID, provider: AIProviderID, model: String
}
enum LocalScheduleSessionError: Error { case unavailable, invalidConfiguration }

@MainActor @Observable final class LocalScheduleSession {
    private(set) var state = SchedulingState()
    private(set) var error: String?
    private(set) var executionMessages: [UUID: String] = [:]
    private(set) var runtimeError: String?
    @ObservationIgnored private var checkingDue = false
    @ObservationIgnored private var dispatching = false
    @ObservationIgnored private weak var library: WritingLibrary?
    @ObservationIgnored private var store: SchedulingStore?
    @ObservationIgnored private var accountBudget: LocalScheduleAccountBudgetStore?
    @ObservationIgnored private var directory: URL?
    @ObservationIgnored private var ownerID: UUID?
    @ObservationIgnored private var libraryID: UUID?
    @ObservationIgnored private var pendingActivations: [UUID: PendingLocalScheduleActivation] = [:]
    @ObservationIgnored private var pendingBudgetReviews: [UUID: LocalOwnerBudgetReview] = [:]
    init(library: WritingLibrary) { self.library = library }
    func reportRuntimeFailure() { runtimeError = "Die Aufgabenprüfung konnte nicht sicher abgeschlossen werden. Vorhandene Daten bleiben erhalten." }
    func load() async {
        do {
            guard let library else { throw LocalScheduleSessionError.unavailable }
            if store == nil {
                let owner: UUID
                if let value = library.preferences.string(forKey: "Scriptum.localSchedulingOwner") {
                    guard let parsed = UUID(uuidString: value) else { throw LocalScheduleSessionError.invalidConfiguration }; owner = parsed
                } else { owner = UUID(); library.preferences.set(owner.uuidString, forKey: "Scriptum.localSchedulingOwner") }
                let id: UUID
                switch try library.ownedWindowLocator() {
                case .primary: id = UUID(uuidString: "75BA73C5-4058-4F71-B810-CA49C7B17675")!
                case .imported(let imported): id = imported
                }
                let key = Self.digest(owner.uuidString + ":" + id.uuidString)
                let folder = library.localSchedulingDirectory().appendingPathComponent(key, isDirectory: true)
                store = try SchedulingStore(persistence: FileSchedulingPersistence(url: folder.appendingPathComponent("tasks-v1.json")))
                directory = folder; ownerID = owner; libraryID = id
            }
            guard let store, let ownerID else { throw LocalScheduleSessionError.unavailable }
            if accountBudget == nil {
                accountBudget = try await LocalAccountBudgetRegistry.open(ownerID: ownerID,
                    directory: library.localSchedulingDirectory().deletingLastPathComponent().appendingPathComponent("AccountBudgets"),
                    localSchedules: library.localSchedulingDirectory())
            }
            let snapshot = await store.snapshot()
            guard snapshot.tasks.values.allSatisfy({ $0.scope.accountID == ownerID && $0.scope.libraryID == libraryID }) else { throw LocalScheduleSessionError.invalidConfiguration }
            guard let accountBudget else { throw LocalScheduleSessionError.unavailable }
            try await accountBudget.importLegacy(snapshot.ledger)
            let authoritative = await accountBudget.snapshot()
            for (key, ceiling) in authoritative.accountCeilings where key.accountID == ownerID {
                let current = await store.snapshot()
                if current.ledger.accountCeilings[key] != ceiling {
                    try await store.adoptOwnerCeiling(accountID: ownerID, currency: key.currency, monthlyMicros: ceiling, expectedVersion: current.version)
                }
            }
            state = await store.snapshot(); error = nil
        } catch { self.error = "Die Aufgaben konnten nicht geladen werden. Vorhandene Daten bleiben erhalten." }
    }
    func create(pageID: UUID, prompt: String, provider: AIProviderID, model: String, rule: ScheduleRule,
                action: ScheduledAction, budget: BudgetPolicy, end: Date?, count: Int?, executionPolicy: ScheduledExecutionPolicy = .foregroundOnly) async throws {
        guard let library, let raw = library.store, !raw.hasActiveEdits,
              let page = raw.snapshot.pages.first(where: { $0.id == pageID }), page.trashedAt == nil,
              error == nil, let store, let directory, let ownerID, let libraryID else { throw LocalScheduleSessionError.unavailable }
        guard !model.isEmpty, model.utf8.count <= 128 else { throw LocalScheduleSessionError.invalidConfiguration }
        let bindingID = Self.bindingID(provider: provider, model: model)
        let binding = LocalScheduledBinding(id: bindingID, provider: provider, model: model)
        let files = try ICloudSyncEngine.Files(directory: directory, name: "binding-" + bindingID.uuidString.lowercased() + ".json", createParents: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(binding)
        if let existing = try files.read() {
            guard existing == bytes else { throw LocalScheduleSessionError.invalidConfiguration }
        } else { try files.write(bytes) }
        let task = try ScheduledTask(scope: .init(accountID: ownerID, libraryID: libraryID, spaceID: page.spaceID),
            pageID: pageID, allowedBlockIDs: action == .proposal ? Set(page.blocks.map(\.id)) : [],
            prompt: prompt, providerBindingID: bindingID, rule: rule, budget: budget, createdAt: Date(), action: action,
            scheduleEndUTC: end, maximumOccurrences: count, executionPolicy: executionPolicy)
        // Document admission is checked now; runtime/access/quote activation is a
        // separate step. A saved task remains draft until those gates are proven.
        let authority = try LocalScheduleAuthority(library: library, ownerID: ownerID, providerBindingID: bindingID,
            accountBudgets: [budget.currency: budget.monthlyMicros])
        _ = try authority.capture(task, now: task.createdAt)
        let current = await store.snapshot()
        try await store.add(task, expectedVersion: current.version)
        await load()
    }
    func pause(_ task: ScheduledTask) async throws {
        guard error == nil, let store, let library, let ownerID, task.scope.accountID == ownerID, task.scope.libraryID == libraryID else { throw LocalScheduleSessionError.unavailable }
        let snapshot = await store.snapshot()
        let ceiling = snapshot.ledger.accountCeilings.first(where: { $0.key.accountID == ownerID && $0.key.currency == task.budget.currency })?.value ?? task.budget.monthlyMicros
        let authority = try LocalScheduleAuthority(library: library, ownerID: ownerID, providerBindingID: task.providerBindingID, accountBudgets: [task.budget.currency: ceiling])
        let now = Date(), grant = try authority.capture(task, now: now).grant
        try await store.pause(taskID: task.id, grant: grant, now: now, expectedGeneration: task.generation, expectedVersion: snapshot.version)
        await load()
    }
    func cancel(_ task: ScheduledTask) async throws {
        guard error == nil, let store, task.scope.accountID == ownerID, task.scope.libraryID == libraryID else { throw LocalScheduleSessionError.unavailable }
        let snapshot = await store.snapshot()
        try await store.cancel(taskID: task.id, expectedGeneration: task.generation, expectedVersion: snapshot.version)
        await load()
    }
    func binding(_ task: ScheduledTask) throws -> LocalScheduledBinding {
        guard let directory, task.scope.accountID == ownerID, task.scope.libraryID == libraryID else { throw LocalScheduleSessionError.unavailable }
        let files = try ICloudSyncEngine.Files(directory: directory, name: "binding-" + task.providerBindingID.uuidString.lowercased() + ".json")
        guard let bytes = try files.read() else { throw LocalScheduleSessionError.invalidConfiguration }
        let binding = try JSONDecoder().decode(LocalScheduledBinding.self, from: bytes)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        guard try encoder.encode(binding) == bytes, binding.id == task.providerBindingID,
              binding.id == Self.bindingID(provider: binding.provider, model: binding.model) else { throw LocalScheduleSessionError.invalidConfiguration }
        return binding
    }
    func activationAccountMonthly(taskID: UUID) async throws -> Int64 {
        guard error == nil, let store, let accountBudget else { throw LocalScheduleSessionError.unavailable }
        let snapshot = await store.snapshot()
        guard let task = snapshot.tasks[taskID], task.scope.accountID == ownerID,
              task.scope.libraryID == libraryID else { throw SchedulingError.denied }
        let ledger = await accountBudget.snapshot()
        return ledger.accountCeilings.first(where: { $0.key.currency == task.budget.currency })?.value ?? task.budget.monthlyMicros
    }
    private func budgetAuthority() throws -> (UUID, LocalScheduleAccountBudgetStore) {
        guard error == nil, let library, let ownerID, let accountBudget,
              library.preferences.string(forKey: "Scriptum.localSchedulingOwner") == ownerID.uuidString else { throw LocalScheduleSessionError.unavailable }
        let actual: UUID
        switch try library.ownedWindowLocator() { case .primary: actual = LocalScheduleBackgroundCatalog.primaryID; case .imported(let id): actual = id }
        guard actual == libraryID else { throw SchedulingError.denied }
        return (ownerID, accountBudget)
    }
    func ownerBudget(currency: String = "USD", now: Date = Date()) async throws -> LocalOwnerBudgetSnapshot {
        let (owner, budget) = try budgetAuthority(), ledger = await budget.snapshot()
        return .init(currency: currency, ceiling: ledger.accountCeilings[AccountBudgetKey(accountID: owner, currency: currency)],
            committed: try ledger.committed(accountID: owner, currency: currency, now: now), period: try BudgetLedger.month(for: now))
    }
    func prepareBudgetChange(currency: String, monthlyMicros: Int64, now: Date = Date()) async throws -> LocalOwnerBudgetReview {
        let (owner, budget) = try budgetAuthority()
        var ledger = await budget.snapshot()
        let old = ledger.accountCeilings[AccountBudgetKey(accountID: owner, currency: currency)]
        try ledger.changeAccountCeiling(accountID: owner, currency: currency, expected: old, monthlyMicros: monthlyMicros, now: now)
        let snapshot = LocalOwnerBudgetSnapshot(currency: currency, ceiling: old,
            committed: try ledger.committed(accountID: owner, currency: currency, now: now), period: try BudgetLedger.month(for: now))
        pendingBudgetReviews = pendingBudgetReviews.filter { $0.value.expiresAt > now }
        guard pendingBudgetReviews.count < 64 else { throw SchedulingError.invalidValue }
        let review = LocalOwnerBudgetReview(id: UUID(), previous: snapshot, monthlyMicros: monthlyMicros, expiresAt: now.addingTimeInterval(60))
        pendingBudgetReviews[review.id] = review; return review
    }
    func confirmBudgetChange(id: UUID, now: Date = Date()) async throws {
        guard let review = pendingBudgetReviews.removeValue(forKey: id), now < review.expiresAt else { throw SchedulingError.denied }
        let (_, budget) = try budgetAuthority()
        try await budget.changeCeiling(currency: review.previous.currency, expected: review.previous.ceiling,
            monthlyMicros: review.monthlyMicros, period: review.previous.period, now: now)
        pendingActivations.removeAll()
        await load()
    }
    func nativeExecutor(taskID: UUID) async throws -> ScheduledAIExecutor {
        guard error == nil, let store else { throw LocalScheduleSessionError.unavailable }
        let snapshot = await store.snapshot()
        guard let task = snapshot.tasks[taskID], task.scope.accountID == ownerID,
              task.scope.libraryID == libraryID else { throw SchedulingError.denied }
        return try await ScheduledAIExecutor.native(binding: binding(task))
    }
    /// Resolve only the immutable binding of a scoped durable task. Model
    /// lookup sends no manuscript; the price policy is application-owned input.
    func nativeExecutor(taskID: UUID, pricingVersion: String,
        quote: @escaping @Sendable (ScheduledTask, Int, Date) async throws -> BudgetQuote) async throws -> ScheduledAIExecutor {
        guard error == nil, let store else { throw LocalScheduleSessionError.unavailable }
        let snapshot = await store.snapshot()
        guard let task = snapshot.tasks[taskID], task.scope.accountID == ownerID,
              task.scope.libraryID == libraryID else { throw SchedulingError.denied }
        return try await ScheduledAIExecutor.native(binding: binding(task), pricingVersion: pricingVersion, quote: quote)
    }
    /// The caller supplies a trusted provider/access/quote policy. A task or
    /// document cannot construct its own execution eligibility from metadata.
    func prepareActivation(taskID: UUID, executor: any LocalScheduledExecutor,
                           accountMonthlyMicros: Int64, mode: LocalScheduledMode,
                           clock: @Sendable () -> Date = { Date() }) async throws -> LocalScheduleActivationReview {
        let now = clock()
        let (store, library, task, binding, version, authority) = try await activationContext(taskID,
            executor: executor, accountMonthlyMicros: accountMonthlyMicros)
        guard let accountBudget else { throw LocalScheduleSessionError.unavailable }
        try await accountBudget.checkCeiling(currency: task.budget.currency, monthlyMicros: accountMonthlyMicros)
        let captured = try authority.capture(task, now: now)
        let quote = try await Self.activationQuote(task: task, capture: captured, executor: executor, mode: mode, now: now)
        let verifiedAt = clock()
        try Self.validateActivationQuote(quote, task: task, executor: executor, now: verifiedAt)
        let fresh = try authority.capture(task, now: verifiedAt)
        guard fresh.page.revision == captured.page.revision, fresh.sourceDigest == captured.sourceDigest,
              (await store.snapshot()).version == version else { throw SchedulingError.staleVersion }
        pendingActivations = pendingActivations.filter { $0.value.review.expiresAt > verifiedAt }
        guard pendingActivations.count < 64 else { throw SchedulingError.invalidValue }
        guard let next = try task.rule.next(after: task.lastOccurrence ?? task.scheduleAnchor.addingTimeInterval(-0.001)),
              task.maximumOccurrences.map({ task.occurrenceCount < $0 }) ?? true,
              task.scheduleEndUTC.map({ next <= $0 }) ?? true else { throw SchedulingError.invalidTransition }
        let review = LocalScheduleActivationReview(id: UUID(), taskID: task.id,
            pageID: task.pageID, pageTitle: fresh.page.title, provider: binding.provider, model: binding.model,
            mode: mode, executionPolicy: task.executionPolicy, budget: task.budget, quote: quote, accountMonthlyMicros: accountMonthlyMicros, nextOccurrence: next,
            prompt: task.prompt, action: task.action, readableBlockCount: fresh.grant.readableBlockIDs.count,
            wholePage: task.action == .summary && task.allowedBlockIDs.isEmpty,
            expiresAt: min(quote.expiresAt, verifiedAt.addingTimeInterval(60)))
        pendingActivations[review.id] = PendingLocalScheduleActivation(review: review, task: task,
            sourceRevision: fresh.page.revision, sourceDigest: fresh.sourceDigest,
            version: version, accountMonthlyMicros: accountMonthlyMicros, executor: executor)
        _ = library // Context keeps the actual owner library alive across admission.
        return review
    }
    /// One-shot confirmation; reconnecting a view cannot replay an old approval.
    func activate(reviewID: UUID, clock: @Sendable () -> Date = { Date() }) async throws {
        let now = clock()
        guard let pending = pendingActivations.removeValue(forKey: reviewID),
              now < pending.review.expiresAt else { throw SchedulingError.denied }
        let (store, _, task, _, version, authority) = try await activationContext(pending.task.id,
            executor: pending.executor, accountMonthlyMicros: pending.accountMonthlyMicros)
        guard version == pending.version, task == pending.task,
              task.prompt.utf8.elementsEqual(pending.task.prompt.utf8) else { throw SchedulingError.staleVersion }
        let captured = try authority.capture(task, now: now)
        guard captured.page.revision == pending.sourceRevision,
              captured.sourceDigest == pending.sourceDigest else { throw SchedulingError.staleProposal }
        let quote = try await Self.activationQuote(task: task, capture: captured, executor: pending.executor,
            mode: pending.review.mode, now: now)
        let verifiedAt = clock()
        guard verifiedAt < pending.review.expiresAt else { throw SchedulingError.denied }
        try Self.validateActivationQuote(quote, task: task, executor: pending.executor, now: verifiedAt)
        guard quote.version == pending.review.quote.version,
              quote.maximumMicros <= pending.review.quote.maximumMicros,
              quote.inputTokens == pending.review.quote.inputTokens,
              quote.outputTokens == pending.review.quote.outputTokens else { throw SchedulingError.budgetDenied }
        let fresh = try authority.capture(task, now: verifiedAt)
        guard fresh.page.revision == pending.sourceRevision, fresh.sourceDigest == pending.sourceDigest else { throw SchedulingError.staleProposal }
        try Task.checkCancellation()
        guard let accountBudget else { throw LocalScheduleSessionError.unavailable }
        try await accountBudget.enroll(currency: task.budget.currency, monthlyMicros: pending.accountMonthlyMicros)
        let admittedAt = clock()
        guard admittedAt < pending.review.expiresAt, admittedAt < quote.expiresAt else { throw SchedulingError.denied }
        let admitted = try authority.capture(task, now: admittedAt)
        guard admitted.page.revision == pending.sourceRevision, admitted.sourceDigest == pending.sourceDigest else { throw SchedulingError.staleProposal }
        try await store.activate(taskID: task.id, grant: admitted.grant, now: admittedAt, expectedVersion: version)
        await load()
    }
    func runDue(executor: any LocalScheduledExecutor, accountBudgets: [String: Int64],
                mode: LocalScheduledMode, clock: @escaping @Sendable () -> Date = { Date() }) async throws {
        guard !dispatching else { return }
        dispatching = true; defer { dispatching = false }
        guard error == nil, let store, let library, let ownerID, let accountBudget,
              library.preferences.string(forKey: "Scriptum.localSchedulingOwner") == ownerID.uuidString else { throw LocalScheduleSessionError.unavailable }
        let snapshot = await store.snapshot()
        for task in snapshot.tasks.values where task.providerBindingID == executor.bindingID {
            let value = try binding(task)
            guard value.provider.rawValue.utf8.elementsEqual(executor.providerID.utf8),
                  value.model.utf8.elementsEqual(executor.modelID.utf8) else { throw SchedulingError.denied }
        }
        let authority = try LocalScheduleAuthority(library: library, ownerID: ownerID,
            providerBindingID: executor.bindingID, accountBudgets: accountBudgets)
        defer { pendingActivations.removeAll() }
        do { try await LocalScheduleDispatcher(store: store, authority: authority, executor: executor, clock: clock, accountBudget: accountBudget).runDue(mode: mode) }
        catch { await load(); throw error }
        await load()
    }
    /// The native caller supplies an active-scene or OS-granted background
    /// mode; task metadata cannot itself grant OS execution time. Empty/future/
    /// draft queues do not resolve credentials, catalogs or prices.
    func runNativeDue(mode: LocalScheduledMode = .foreground, clock: @escaping @Sendable () -> Date = { Date() },
        executorFactory: (@MainActor (UUID) async throws -> any LocalScheduledExecutor)? = nil) async throws {
        guard !checkingDue, !dispatching else { return }
        checkingDue = true; defer { checkingDue = false }
        if store == nil { await load() }
        guard error == nil, let store, let library, let ownerID, let accountBudget,
              library.preferences.string(forKey: "Scriptum.localSchedulingOwner") == ownerID.uuidString else { throw LocalScheduleSessionError.unavailable }
        try Task.checkCancellation()
        runtimeError = nil
        var snapshot = await store.snapshot()
        let now = clock()
        // Recover ambiguous sent work without resolving a provider or retrying it.
        if snapshot.runs.values.contains(where: { [.dispatching, .running].contains($0.state) && ($0.lease?.expiresAt ?? .distantFuture) <= now }) {
            try await store.recoverExpired(now: now, expectedVersion: snapshot.version)
            snapshot = await store.snapshot(); state = snapshot
        }
        let tasks = try snapshot.tasks.values.filter { task in
            guard task.lifecycle == .active, mode == .foreground || task.executionPolicy == .backgroundAllowed else { return false }
            if snapshot.runs.values.contains(where: {
                $0.occurrence.taskID == task.id && $0.occurrence.generation == task.generation &&
                [.queued, .leased, .authorized, .reserved].contains($0.state) && ($0.lease?.expiresAt ?? .distantPast) <= now
            }) { return true }
            guard task.maximumOccurrences.map({ task.occurrenceCount < $0 }) ?? true,
                  let next = try task.rule.next(after: task.lastOccurrence ?? task.scheduleAnchor.addingTimeInterval(-0.001)) else { return false }
            return next <= now && (task.scheduleEndUTC.map { next <= $0 } ?? true)
        }.sorted { $0.id.uuidString < $1.id.uuidString }
        var handled = Set<UUID>()
        for task in tasks {
            try Task.checkCancellation()
            guard !handled.contains(task.providerBindingID) else { continue }
            do {
                let ledger = await accountBudget.snapshot()
                let budgets = Dictionary(uniqueKeysWithValues: ledger.accountCeilings.filter { $0.key.accountID == ownerID }.map { ($0.key.currency, $0.value) })
                let authority = try LocalScheduleAuthority(library: library, ownerID: ownerID,
                    providerBindingID: task.providerBindingID, accountBudgets: budgets)
                // Never fetch provider access for a trashed/stale/foreign source
                // or an editor journal that has not been committed.
                _ = try authority.capture(task, now: clock())
                let executor: any LocalScheduledExecutor
                if let executorFactory { executor = try await executorFactory(task.id) }
                else { executor = try await nativeExecutor(taskID: task.id) }
                try Task.checkCancellation()
                handled.insert(task.providerBindingID)
                try await runDue(executor: executor, accountBudgets: budgets, mode: mode, clock: clock)
                executionMessages.removeValue(forKey: task.providerBindingID)
            } catch is CancellationError { throw CancellationError() }
            catch {
                if let failure = error as? AIError { executionMessages[task.providerBindingID] = failure.localizedDescription }
                else if let sourceError = error as? LocalScheduleAuthorityError, case .unavailable = sourceError {
                    executionMessages[task.providerBindingID] = "Ausführung wartet auf einen gespeicherten Textstand."
                } else {
                    executionMessages[task.providerBindingID] = "Die fällige Aufgabe konnte nicht sicher ausgeführt werden. Prüfe Seite, Zugang und Budgets. Ein unklarer Versand wird nicht automatisch wiederholt."
                }
            }
        }
        state = await store.snapshot()
    }
    private func activationContext(_ id: UUID, executor: any LocalScheduledExecutor, accountMonthlyMicros: Int64) async throws -> (SchedulingStore, WritingLibrary, ScheduledTask, LocalScheduledBinding, Int, LocalScheduleAuthority) {
        guard error == nil, let store, let library, let ownerID, accountMonthlyMicros >= 0 else { throw LocalScheduleSessionError.unavailable }
        let snapshot = await store.snapshot()
        guard let task = snapshot.tasks[id], [.draft, .awaitingActivation, .paused].contains(task.lifecycle),
              task.scope.accountID == ownerID, task.scope.libraryID == libraryID,
              library.preferences.string(forKey: "Scriptum.localSchedulingOwner") == ownerID.uuidString else { throw SchedulingError.denied }
        let binding = try binding(task)
        guard executor.bindingID == binding.id,
              executor.providerID.utf8.elementsEqual(binding.provider.rawValue.utf8),
              executor.modelID.utf8.elementsEqual(binding.model.utf8) else { throw SchedulingError.denied }
        if let ceiling = snapshot.ledger.accountCeilings.first(where: { $0.key.accountID == ownerID && $0.key.currency == task.budget.currency })?.value {
            guard ceiling == accountMonthlyMicros else { throw SchedulingError.denied }
        }
        let authority = try LocalScheduleAuthority(library: library, ownerID: ownerID,
            providerBindingID: binding.id, accountBudgets: [task.budget.currency: accountMonthlyMicros])
        return (store, library, task, binding, snapshot.version, authority)
    }
    private static func validateActivationQuote(_ quote: BudgetQuote, task: ScheduledTask,
        executor: any LocalScheduledExecutor, now: Date) throws {
        guard now.timeIntervalSince1970.isFinite, quote.expiresAt.timeIntervalSince1970.isFinite,
              quote.expiresAt > now, quote.version == executor.pricingVersion,
              !quote.version.isEmpty, quote.version.utf8.count <= 128,
              quote.currency == task.budget.currency,
              (0...task.budget.perRunMicros).contains(quote.maximumMicros),
              (1...task.budget.inputTokens).contains(quote.inputTokens),
              quote.outputTokens == task.budget.outputTokens else { throw SchedulingError.budgetDenied }
    }
    private static func activationQuote(task: ScheduledTask, capture: LocalScheduledCapture,
        executor: any LocalScheduledExecutor, mode: LocalScheduledMode, now: Date) async throws -> BudgetQuote {
        guard mode == .foreground || task.executionPolicy == .backgroundAllowed else { throw SchedulingError.denied }
        let first = try await executor.preflight(task: task, capture: capture, mode: mode, now: now)
        try validateActivationQuote(first, task: task, executor: executor, now: now)
        guard task.executionPolicy == .backgroundAllowed else { return first }
        let other = try await executor.preflight(task: task, capture: capture,
            mode: mode == .foreground ? .background : .foreground, now: now)
        try validateActivationQuote(other, task: task, executor: executor, now: now)
        guard first.currency == other.currency, first.version == other.version,
              first.inputTokens == other.inputTokens, first.outputTokens == other.outputTokens else { throw SchedulingError.budgetDenied }
        return BudgetQuote(currency: first.currency, maximumMicros: max(first.maximumMicros, other.maximumMicros),
            inputTokens: first.inputTokens, outputTokens: first.outputTokens, version: first.version,
            expiresAt: min(first.expiresAt, other.expiresAt))
    }
    /// Reads only a proposal already validated by the durable scheduling store.
    /// Review never runs the provider or changes the document.
    func review(proposalID: UUID) async throws -> LocalScheduledProposalReview {
        let (proposal, task, binding, library, owner) = try await proposalContext(proposalID)
        return try LocalScheduledProposalAcceptance.review(proposal, task: task, binding: binding, library: library, ownerID: owner)
    }
    @discardableResult func accept(proposalID: UUID) async throws -> ProposalReceipt {
        let (proposal, task, binding, library, owner) = try await proposalContext(proposalID)
        // No suspension between fresh document admission and its atomic commit.
        let receipt = try LocalScheduledProposalAcceptance.accept(proposal, task: task, binding: binding, library: library, ownerID: owner)
        library.lastSaved = Date(); library.saveError = nil; library.reload()
        return receipt
    }
    private func proposalContext(_ id: UUID) async throws -> (ScheduledProposal, ScheduledTask, LocalScheduledBinding, WritingLibrary, UUID) {
        guard error == nil, let store, let library, let ownerID else { throw LocalScheduleSessionError.unavailable }
        let snapshot = await store.snapshot()
        guard let proposal = snapshot.proposals[id], let run = snapshot.runs[proposal.runID],
              let task = snapshot.tasks[run.occurrence.taskID], proposal.scope == task.scope,
              proposal.scope.accountID == ownerID, proposal.scope.libraryID == libraryID else { throw SchedulingError.denied }
        return (proposal, task, try binding(task), library, ownerID)
    }
    private static func bindingID(provider: AIProviderID, model: String) -> UUID {
        var bytes = Array(SHA256.hash(data: Data((provider.rawValue + "\0" + model).utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x50; bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (bytes[0],bytes[1],bytes[2],bytes[3],bytes[4],bytes[5],bytes[6],bytes[7],bytes[8],bytes[9],bytes[10],bytes[11],bytes[12],bytes[13],bytes[14],bytes[15]))
    }
    private static func digest(_ text: String) -> String { SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined() }
}
extension WritingLibrary {
    func localSchedulingDirectory() -> URL {
        iCloudStorageDirectory().deletingLastPathComponent().appendingPathComponent("LocalSchedules", isDirectory: true)
    }
}


struct LocalScheduledProposalReview: Sendable {
    struct Change: Identifiable, Sendable {
        let id: UUID, original: String, replacement: String
    }
    let proposalID: UUID, pageID: UUID, baseRevision: UUID
    let changes: [Change]
    let receipt: ProposalReceipt?
}

/// Document admission for explicitly accepted local results. Scheduling state
/// remains an output ledger; the library's atomic receipt is the acceptance truth.
@MainActor enum LocalScheduledProposalAcceptance {
    static func review(_ proposal: ScheduledProposal, task: ScheduledTask, binding: LocalScheduledBinding,
                       library: WritingLibrary, ownerID: UUID) throws -> LocalScheduledProposalReview {
        let context = try prepare(proposal, task: task, binding: binding, library: library, ownerID: ownerID)
        return context.review
    }
    @discardableResult static func accept(_ proposal: ScheduledProposal, task: ScheduledTask, binding: LocalScheduledBinding,
                                         library: WritingLibrary, ownerID: UUID) throws -> ProposalReceipt {
        let context = try prepare(proposal, task: task, binding: binding, library: library, ownerID: ownerID)
        guard let store = library.store else { throw LocalScheduleSessionError.unavailable }
        return try store.applyProposal(proposal.id, patch: context.patch, author: context.author)
    }
    private static func prepare(_ proposal: ScheduledProposal, task: ScheduledTask, binding: LocalScheduledBinding,
                                library: WritingLibrary, ownerID: UUID) throws -> (review: LocalScheduledProposalReview, patch: PagePatch, author: String) {
        try proposal.validate(); try task.validate()
        guard let store = library.store, task.action == .proposal,
              proposal.scope == task.scope, proposal.scope.accountID == ownerID,
              proposal.pageID == task.pageID, proposal.allowedBlockIDs.isSubset(of: task.allowedBlockIDs),
              binding.id == task.providerBindingID,
              proposal.providerID?.utf8.elementsEqual(binding.provider.rawValue.utf8) == true,
              proposal.modelID?.utf8.elementsEqual(binding.model.utf8) == true else { throw SchedulingError.denied }
        let authority = try LocalScheduleAuthority(library: library, ownerID: ownerID,
            providerBindingID: binding.id, accountBudgets: [task.budget.currency: task.budget.monthlyMicros])
        guard proposal.scope.libraryID == authority.libraryID else { throw SchedulingError.denied }
        // Stable operation order makes an exact replay independent of later edits.
        let patch = PagePatch(pageID: proposal.pageID, baseRevision: proposal.baseRevision,
            allowedBlockIDs: proposal.allowedBlockIDs,
            operations: proposal.replacementBlocks.keys.sorted { $0.uuidString < $1.uuidString }.map {
                .replace(blockID: $0, markdown: proposal.replacementBlocks[$0]!)
            })
        let author = "Scheduled AI · " + binding.provider.rawValue + " · " + binding.model
        if let receipt = store.snapshot.proposalReceipts?.first(where: { $0.proposalID == proposal.id }) {
            // The core verifies fingerprint and author, then returns this receipt
            // without a write even if the current page has subsequently changed.
            let verified = try store.applyProposal(proposal.id, patch: patch, author: author)
            guard verified == receipt else { throw LibraryError.proposalConflict }
            return (LocalScheduledProposalReview(proposalID: proposal.id, pageID: proposal.pageID,
                baseRevision: proposal.baseRevision, changes: [], receipt: receipt), patch, author)
        }
        let capture = try authority.capture(task, now: Date())
        _ = try proposal.admit(scope: capture.grant.scope, pageID: capture.page.id,
            revision: capture.page.revision, source: capture.page.markdown, readableBlockIDs: capture.grant.readableBlockIDs)
        let changes = capture.page.blocks.compactMap { block -> LocalScheduledProposalReview.Change? in
            guard let replacement = proposal.replacementBlocks[block.id] else { return nil }
            return .init(id: block.id, original: block.markdown, replacement: replacement)
        }
        let candidateBytes = capture.page.blocks.reduce(0) { total, block in
            total + (proposal.replacementBlocks[block.id] ?? block.markdown).utf8.count
        }
        guard candidateBytes <= 8 * 1024 * 1024 else { throw SchedulingError.invalidValue }
        return (LocalScheduledProposalReview(proposalID: proposal.id, pageID: proposal.pageID,
            baseRevision: proposal.baseRevision, changes: changes, receipt: nil), patch, author)
    }
}


/// Ephemeral UI consent data; intentionally not Codable and contains no key.
struct LocalScheduleActivationReview: Identifiable, Sendable {
    let id: UUID, taskID: UUID, pageID: UUID
    let pageTitle: String, provider: AIProviderID, model: String
    let mode: LocalScheduledMode, executionPolicy: ScheduledExecutionPolicy, budget: BudgetPolicy, quote: BudgetQuote, accountMonthlyMicros: Int64, nextOccurrence: Date
    let prompt: String, action: ScheduledAction, readableBlockCount: Int, wholePage: Bool, expiresAt: Date
}
private struct PendingLocalScheduleActivation {
    let review: LocalScheduleActivationReview, task: ScheduledTask
    let sourceRevision: UUID, sourceDigest: String, version: Int, accountMonthlyMicros: Int64
    let executor: any LocalScheduledExecutor
}

struct LocalScheduleBackgroundTarget: Sendable, Equatable {
    let locator: OwnedLibraryLocator
    let earliestUTC: Date
}
/// Read-only bounded discovery from pinned application storage. A filename or
/// task's UUID never supplies an arbitrary document URL or provider credential.
enum LocalScheduleBackgroundCatalog {
    static let primaryID = UUID(uuidString: "75BA73C5-4058-4F71-B810-CA49C7B17675")!
    static func discover(ownerID: UUID, directory: URL, now: Date) throws -> [LocalScheduleBackgroundTarget] {
        guard now.timeIntervalSince1970.isFinite else { throw SchedulingError.invalidValue }
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        let rootValues = try directory.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
        guard rootValues.isSymbolicLink != true, rootValues.isDirectory == true else { throw SchedulingError.unsafeFile }
        let entries = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isSymbolicLinkKey, .isDirectoryKey, .isRegularFileKey])
        guard entries.count <= 1000 else { throw SchedulingError.persistenceTooLarge }
        var results: [LocalScheduleBackgroundTarget] = [], totalBytes = 0
        for entry in entries {
            try Task.checkCancellation()
            let attributes = try entry.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey, .isRegularFileKey])
            guard attributes.isSymbolicLink != true else { throw SchedulingError.unsafeFile }
            if attributes.isRegularFile == true { continue }
            guard attributes.isDirectory == true else { throw SchedulingError.unsafeFile }
            let file = directory.appendingPathComponent(entry.lastPathComponent, isDirectory: true).appendingPathComponent("tasks-v1.json")
            guard let bytes = try FileSchedulingPersistence(url: file).read() else { continue }
            guard bytes.count <= 256 * 1024 * 1024 - totalBytes else { throw SchedulingError.persistenceTooLarge }
            totalBytes += bytes.count
            let state = try JSONDecoder().decode(SchedulingState.self, from: bytes); try state.validate()
            guard let first = state.tasks.values.first else { continue }
            let account = first.scope.accountID, library = first.scope.libraryID
            guard state.tasks.values.allSatisfy({ $0.scope.accountID == account && $0.scope.libraryID == library }) else { throw SchedulingError.denied }
            let expected = SHA256.hash(data: Data((account.uuidString + ":" + library.uuidString).utf8)).map { String(format: "%02x", $0) }.joined()
            guard entry.lastPathComponent == expected else { throw SchedulingError.unsafeFile }
            guard account == ownerID else { continue }
            var next: Date?
            for task in state.tasks.values where task.lifecycle == .active && task.executionPolicy == .backgroundAllowed {
                var attempts: [Date] = []
                for run in state.runs.values where run.occurrence.taskID == task.id && run.occurrence.generation == task.generation {
                    if [.queued, .leased, .authorized, .reserved].contains(run.state) { attempts.append(max(now, run.lease?.expiresAt ?? now)) }
                    else if [.dispatching, .running].contains(run.state), let lease = run.lease { attempts.append(max(now, lease.expiresAt)) }
                }
                if task.maximumOccurrences.map({ task.occurrenceCount < $0 }) ?? true,
                   let date = try task.rule.next(after: task.lastOccurrence ?? task.scheduleAnchor.addingTimeInterval(-0.001)),
                   task.scheduleEndUTC.map({ date <= $0 }) ?? true { attempts.append(max(now, date)) }
                if let date = attempts.min() { next = min(next ?? date, date) }
            }
            if let next { results.append(.init(locator: library == primaryID ? .primary : .imported(library), earliestUTC: next)) }
        }
        return results.sorted {
            if $0.earliestUTC != $1.earliestUTC { return $0.earliestUTC < $1.earliestUTC }
            func key(_ locator: OwnedLibraryLocator) -> String {
                switch locator { case .primary: ""; case .imported(let id): id.uuidString }
            }
            return key($0.locator) < key($1.locator)
        }
    }
}
struct LocalScheduleBackgroundReport: Sendable {
    let checkedLibraries: Int
    let failedLibraries: Int
    var success: Bool { failedLibraries == 0 }
}
@MainActor final class LocalScheduleBackgroundWorker {
    private let registry: WorkspaceWindowRegistry
    private let supportRoot: URL
    private let preferences: UserDefaults
    private var running = false
    init(registry: WorkspaceWindowRegistry = .shared,
         supportRoot: URL = WorkspaceSystemContainerRoots.applicationSupport, preferences: UserDefaults = .standard) {
        self.registry = registry; self.supportRoot = supportRoot; self.preferences = preferences
    }
    func plan(now: Date = Date()) async throws -> [LocalScheduleBackgroundTarget] {
        try Task.checkCancellation()
        guard let raw = preferences.string(forKey: "Scriptum.localSchedulingOwner") else { return [] }
        guard let owner = UUID(uuidString: raw) else { throw LocalScheduleSessionError.invalidConfiguration }
        let directory = supportRoot.appendingPathComponent("LocalSchedules", isDirectory: true)
        let scan = Task.detached(priority: .utility) { try LocalScheduleBackgroundCatalog.discover(ownerID: owner, directory: directory, now: now) }
        let targets = try await withTaskCancellationHandler(operation: { try await scan.value }, onCancel: { scan.cancel() })
        try Task.checkCancellation()
        return targets
    }
    func run(clock: @escaping @Sendable () -> Date = { Date() },
             executorFactory: (@MainActor (UUID, WritingLibrary) async throws -> any LocalScheduledExecutor)? = nil) async throws -> LocalScheduleBackgroundReport {
        guard !running else { throw LocalScheduleSessionError.unavailable }
        running = true; defer { running = false }
        let targets = try await plan(now: clock())
        let dueTargets = targets.filter { $0.earliestUTC <= clock() }
        guard !dueTargets.isEmpty else { return .init(checkedLibraries: 0, failedLibraries: 0) }
        guard let rawOwner = preferences.string(forKey: "Scriptum.localSchedulingOwner"), let owner = UUID(uuidString: rawOwner) else { throw LocalScheduleSessionError.invalidConfiguration }
        let budget = try await LocalAccountBudgetRegistry.open(ownerID: owner,
            directory: supportRoot.appendingPathComponent("AccountBudgets"), localSchedules: supportRoot.appendingPathComponent("LocalSchedules"))
        // Retain the one owner ledger across cold libraries instead of rescanning
        // every library's history whenever a temporary facade leaves scope.
        defer { withExtendedLifetime(budget) {} }
        var checked = 0, failed = 0
        for target in dueTargets {
            try Task.checkCancellation()
            do {
                let library = try registry.backgroundLibrary(target.locator)
                let session = library.scheduleSession ?? LocalScheduleSession(library: library)
                library.scheduleSession = session
                let factory: (@MainActor (UUID) async throws -> any LocalScheduledExecutor)?
                if let executorFactory { factory = { id in try await executorFactory(id, library) } }
                else { factory = nil }
                try await session.runNativeDue(mode: .background, clock: clock, executorFactory: factory)
                checked += 1
                if session.error != nil || session.runtimeError != nil || !session.executionMessages.isEmpty { failed += 1 }
            } catch is CancellationError { throw CancellationError() }
            catch { failed += 1 }
        }
        return .init(checkedLibraries: checked, failedLibraries: failed)
    }
}

/// Expiration can arrive off the main actor or before its operation is installed.
/// Cancel outside the lock because cancellation handlers may run synchronously.
final class LocalBackgroundCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var operation: Task<Void, Never>?
    private var expired = false
    func install(_ task: Task<Void, Never>) {
        let state = lock.withLock { () -> (Bool, Task<Void, Never>?) in
            if let old = operation { expired = true; return (true, old) }
            operation = task; return (expired, nil)
        }
        state.1?.cancel()
        if state.0 { task.cancel() }
    }
    func cancel() {
        let task = lock.withLock { expired = true; return operation }
        task?.cancel()
    }
}

struct LocalOwnerBudgetSnapshot: Sendable {
    let currency: String
    let ceiling: Int64?
    let committed: Int64
    let period: String
}
struct LocalOwnerBudgetReview: Identifiable, Sendable {
    let id: UUID
    let previous: LocalOwnerBudgetSnapshot
    let monthlyMicros: Int64
    let expiresAt: Date
}
