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
    @ObservationIgnored private weak var library: WritingLibrary?
    @ObservationIgnored private var store: SchedulingStore?
    @ObservationIgnored private var directory: URL?
    @ObservationIgnored private var ownerID: UUID?
    @ObservationIgnored private var libraryID: UUID?
    init(library: WritingLibrary) { self.library = library }
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
            guard let store else { throw LocalScheduleSessionError.unavailable }
            let snapshot = await store.snapshot()
            guard snapshot.tasks.values.allSatisfy({ $0.scope.accountID == ownerID && $0.scope.libraryID == libraryID }) else { throw LocalScheduleSessionError.invalidConfiguration }
            state = snapshot; error = nil
        } catch { self.error = "Die Aufgaben konnten nicht geladen werden. Vorhandene Daten bleiben erhalten." }
    }
    func create(pageID: UUID, prompt: String, provider: AIProviderID, model: String, rule: ScheduleRule,
                action: ScheduledAction, budget: BudgetPolicy, end: Date?, count: Int?) async throws {
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
            scheduleEndUTC: end, maximumOccurrences: count)
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
