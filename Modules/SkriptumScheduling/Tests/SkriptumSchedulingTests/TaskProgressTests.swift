import Foundation
import Testing
@testable import SkriptumScheduling

struct TaskProgressTests {
  func fixture() throws -> ScheduledTask {
    var task = try StoreTests().fixture().0
    task.lifecycle = .active
    return task
  }
  func run(_ task: ScheduledTask, _ state: RunState, at time: TimeInterval = 100) -> ScheduledRun {
    var run = ScheduledRun(occurrence: .init(taskID: task.id, generation: task.generation,
      scheduledUTC: Date(timeIntervalSince1970: time)), scope: task.scope)
    run.state = state
    return run
  }
  @Test func exhaustedOneShotDistinguishesQueuedRunningAndFinished() throws {
    var task = try fixture()
    task.lastOccurrence = Date(timeIntervalSince1970: 100)
    task.occurrenceCount = 1
    for (runState, phase) in [(RunState.queued, ScheduledTaskProgress.Phase.queued),
      (.reserved, .running), (.dispatching, .running), (.running, .running),
      (.completed, .finished), (.proposalReady, .finished), (.failed, .finished),
      (.executionUncertain, .finished)] {
      let result = try ScheduledTaskProgress(task: task, runs: [run(task, runState)])
      #expect(result.phase == phase)
      #expect(result.nextOccurrence == nil)
      #expect(result.latestRunState == runState)
      #expect(result.canPause == (phase != .finished))
      #expect(result.canCancel == (phase != .finished))
    }
  }
  @Test func recurringCountAndEndSuppressImpossibleNextOccurrence() throws {
    var task = try fixture()
    task.rule = .daily(timeZone: "UTC", hour: 0, minute: 0)
    task.lastOccurrence = Date(timeIntervalSince1970: 86400)
    task.occurrenceCount = 2
    let success = run(task, .completed, at: 86400)
    let active = try ScheduledTaskProgress(task: task, runs: [success])
    #expect(active.phase == .scheduled)
    #expect(active.nextOccurrence == Date(timeIntervalSince1970: 172800))
    task.maximumOccurrences = 2
    #expect(try ScheduledTaskProgress(task: task, runs: [success]).phase == .finished)
    #expect(try ScheduledTaskProgress(task: task, runs: [success]).nextOccurrence == nil)
    task.maximumOccurrences = nil
    task.scheduleEndUTC = task.lastOccurrence
    #expect(try ScheduledTaskProgress(task: task, runs: [success]).phase == .finished)
    #expect(try ScheduledTaskProgress(task: task, runs: [success]).nextOccurrence == nil)
  }
  @Test func pendingRunPreventsFalseCompletionAndOldGenerationIsHistorical() throws {
    var task = try fixture()
    task.lastOccurrence = Date(timeIntervalSince1970: 100)
    task.occurrenceCount = 1
    let running = run(task, .running, at: 90)
    let finished = run(task, .completed)
    #expect(try ScheduledTaskProgress(task: task, runs: [finished, running]).phase == .running)
    task.generation += 1
    let result = try ScheduledTaskProgress(task: task, runs: [running, finished])
    #expect(result.phase == .finished)
    #expect(result.latestRunState == nil)
    #expect(try ScheduledTaskProgress(task: task, runs: [run(try fixture(), .running)]).phase == .finished)
  }
  @Test func explicitInactiveLifecyclesRemainDistinct() throws {
    var task = try fixture()
    for (lifecycle, phase) in [(TaskLifecycle.draft, ScheduledTaskProgress.Phase.draft),
      (.awaitingActivation, .awaitingActivation), (.paused, .paused), (.cancelled, .cancelled)] {
      task.lifecycle = lifecycle
      let result = try ScheduledTaskProgress(task: task, runs: [run(task, .running)])
      #expect(result.phase == phase)
      #expect(result.nextOccurrence == nil)
      #expect(!result.canPause)
      #expect(result.canCancel == (lifecycle != .cancelled))
    }
  }
  @Test func snapshotProjectionSurvivesRestartWithoutWriting() async throws {
    let memory = MemoryPersistence(), store = try SchedulingStore(persistence: MemoryPersistence())
    let (task, grant) = try StoreTests().fixture()
    try await store.add(task, expectedVersion: 0)
    try await store.activate(taskID: task.id, grant: grant, now: task.createdAt, expectedVersion: 1)
    let ids = try await store.enqueueDue(now: Date(timeIntervalSince1970: 100), expectedVersion: 2)
    let state = await store.snapshot()
    memory.data = try JSONEncoder().encode(state)
    let original = memory.data
    let restarted = try SchedulingStore(persistence: memory)
    let loaded = await restarted.snapshot()
    let progress = try ScheduledTaskProgress(task: loaded.tasks[task.id]!, runs: Array(loaded.runs.values))
    #expect(progress.phase == .queued && progress.latestRunState == .queued)
    #expect(loaded == state && memory.data == original && loaded.runs[ids[0]] != nil)
  }
}
