import Foundation
import Testing
import SkriptumCore
@testable import SkriptumWorkspaceModel

@MainActor struct CloudConnectionRegistryTests {
    func fixture(_ root: URL, locator: OwnedLibraryLocator = .imported(UUID()), account: UUID = UUID(), origin: String = "https://workspace.example", profile: String = "apple") throws -> (CloudLibraryBindingRepository, CloudLibraryBinding) {
        let repository = try CloudLibraryBindingRepository(locator: locator, documentRoot: root.appending(path: "Documents"), supportRoot: root.appending(path: "Support"))
        let binding = try CloudLibraryBinding(locator: locator, origin: origin, profileID: profile, accountID: account, remoteLibraryID: UUID())
        return (repository, binding)
    }
    @Test func coldLocatorRestoreReusesHandleAndRestartCannotAcceptOldTicket() throws {
        let root = URL(fileURLWithPath: "/private/tmp/CloudRegistry-" + UUID().uuidString); defer { try? FileManager.default.removeItem(at: root) }
        let (repository, binding) = try fixture(root)
        try repository.save(binding, replacing: nil)
        let registry = try CloudConnectionRegistry()
        let handle = try #require(try registry.restore(repository))
        #expect(try registry.binding(for: handle) == binding)
        #expect(try registry.restore(repository) === handle)
        let ticket = try registry.begin(binding, replacing: binding)
        let restarted = try CloudConnectionRegistry()
        #expect(try restarted.binding(for: #require(try restarted.restore(repository))) == binding)
        #expect(throws: CloudConnectionRegistryError.staleTicket) { try restarted.complete(ticket, repository: repository) }
    }
    @Test func cancelledAndInvalidatedCompletionsNeverPersistOrRevive() throws {
        let root = URL(fileURLWithPath: "/private/tmp/CloudRegistry-" + UUID().uuidString); defer { try? FileManager.default.removeItem(at: root) }
        let (repository, binding) = try fixture(root)
        let registry = try CloudConnectionRegistry()
        let cancelled = try registry.begin(binding, replacing: nil)
        registry.cancel(cancelled)
        #expect(throws: CloudConnectionRegistryError.staleTicket) { try registry.complete(cancelled, repository: repository) }
        #expect(try repository.load() == nil)
        let fresh = try registry.begin(binding, replacing: nil)
        let handle = try registry.complete(fresh, repository: repository)
        let bytes = try Data(contentsOf: repository.fileURL)
        let pending = try registry.begin(binding, replacing: binding)
        registry.invalidate(binding.locator)
        #expect(throws: CloudConnectionRegistryError.invalidated) { try registry.binding(for: handle) }
        #expect(throws: CloudConnectionRegistryError.invalidated) { try registry.restore(repository) }
        #expect(throws: CloudConnectionRegistryError.staleTicket) { try registry.complete(pending, repository: repository) }
        #expect(try Data(contentsOf: repository.fileURL) == bytes)
        let reconnect = try registry.begin(binding, replacing: binding)
        #expect(try registry.binding(for: registry.complete(reconnect, repository: repository)) == binding)
    }
    @Test func accountInvalidationIsExactAndSharedScenesRetainOtherScopes() throws {
        let root = URL(fileURLWithPath: "/private/tmp/CloudRegistry-" + UUID().uuidString); defer { try? FileManager.default.removeItem(at: root) }
        let account = UUID(), registry = try CloudConnectionRegistry()
        var fixtures: [(CloudLibraryBindingRepository, CloudLibraryBinding, CloudConnectionHandle)] = []
        for (origin, profile, identity) in [("https://workspace.example", "apple", account), ("https://workspace.example", "apple", account), ("https://other.example", "apple", account), ("https://workspace.example", "other", account), ("https://workspace.example", "apple", UUID())] {
            let (repository, binding) = try fixture(root, account: identity, origin: origin, profile: profile)
            let handle = try registry.complete(registry.begin(binding, replacing: nil), repository: repository)
            fixtures.append((repository, binding, handle))
        }
        let pending = try registry.begin(fixtures[0].1, replacing: fixtures[0].1)
        let matched = registry.invalidateAll(origin: fixtures[0].1.origin, profileID: "apple", accountID: account)
        #expect(Set(matched) == Set(fixtures.prefix(2).map { $0.1.locator }))
        #expect(throws: CloudConnectionRegistryError.staleTicket) { try registry.complete(pending, repository: fixtures[0].0) }
        for row in fixtures.prefix(2) { #expect(throws: CloudConnectionRegistryError.invalidated) { try registry.binding(for: row.2) } }
        for row in fixtures.dropFirst(2) { #expect(try registry.binding(for: row.2) == row.1) }
    }
    @Test func wrongRepositoryAndFailedCASPreserveMetadataAndDisk() throws {
        let root = URL(fileURLWithPath: "/private/tmp/CloudRegistry-" + UUID().uuidString); defer { try? FileManager.default.removeItem(at: root) }
        let (repository, binding) = try fixture(root), (other, _) = try fixture(root)
        let registry = try CloudConnectionRegistry(), ticket = try registry.begin(binding, replacing: nil)
        #expect(throws: CloudConnectionRegistryError.wrongScope) { try registry.complete(ticket, repository: other) }
        #expect(try other.load() == nil)
        try repository.save(binding, replacing: nil)
        let bytes = try Data(contentsOf: repository.fileURL)
        #expect(throws: CloudLibraryBindingError.conflict) { try registry.complete(ticket, repository: repository) }
        #expect(try Data(contentsOf: repository.fileURL) == bytes)
        registry.cancel(ticket)
    }
    @Test func boundedLiveWorkAllowsMoreThan64SequentialVisitsWithoutTicketRevival() throws {
        let root = URL(fileURLWithPath: "/private/tmp/CloudRegistry-" + UUID().uuidString); defer { try? FileManager.default.removeItem(at: root) }
        let registry = try CloudConnectionRegistry(capacity: 2)
        for _ in 0..<70 {
            let (repository, binding) = try fixture(root)
            try repository.save(binding, replacing: nil)
            do { let handle = try #require(try registry.restore(repository)); #expect(try registry.binding(for: handle) == binding) }
        }
        let (repository, binding) = try fixture(root)
        let old = try registry.begin(binding, replacing: nil); registry.cancel(old)
        let current = try registry.begin(binding, replacing: nil)
        #expect(throws: CloudConnectionRegistryError.staleTicket) { try registry.complete(old, repository: repository) }
        #expect(try registry.binding(for: registry.complete(current, repository: repository)) == binding)
        let a = try fixture(root), b = try fixture(root), c = try fixture(root)
        let held = try registry.begin(a.1, replacing: nil), second = try registry.begin(b.1, replacing: nil)
        #expect(throws: CloudConnectionRegistryError.capacity) { try registry.begin(c.1, replacing: nil) }
        registry.cancel(held); registry.cancel(second)
    }
}

extension CloudConnectionRegistryTests {
    @Test func actualWritingLibrariesWithIdenticalPageIDsSelectOnlyOwnedLocator() throws {
        let root = URL(fileURLWithPath: "/private/tmp/CloudRegistry-" + UUID().uuidString); defer { try? FileManager.default.removeItem(at: root) }
        let documents = root.appending(path: "Documents"), support = root.appending(path: "Support")
        let aLocator = OwnedLibraryLocator.imported(UUID()), bLocator = OwnedLibraryLocator.imported(UUID())
        let aDirectory = try LibraryStoragePaths.libraryDirectory(locator: aLocator, documentRoot: documents)
        let bDirectory = try LibraryStoragePaths.libraryDirectory(locator: bLocator, documentRoot: documents)
        let first = try LibraryStore(directory: aDirectory), space = try first.createSpace(title: "Writing")
        let page = try first.createPage(spaceID: space.id, title: "Draft", markdown: "e\u{301}\r\n🦊")
        try FileManager.default.copyItem(at: aDirectory, to: bDirectory)
        let prefs = UserDefaults(suiteName: UUID().uuidString)!
        let a = try WritingLibrary(store: first, documentRoot: documents, supportRoot: support, preferences: prefs)
        let b = try WritingLibrary(store: LibraryStore(directory: bDirectory), documentRoot: documents, supportRoot: support, preferences: prefs)
        #expect(a.pages[0].id == page.id && b.pages[0].id == page.id && a.libraryIdentity != b.libraryIdentity)
        let account = UUID(), registry = try CloudConnectionRegistry()
        var rows: [(CloudLibraryBindingRepository, CloudLibraryBinding, CloudConnectionHandle)] = []
        for library in [a, b] {
            let locator = try library.ownedWindowLocator()
            let repository = try CloudLibraryBindingRepository(locator: locator, documentRoot: documents, supportRoot: support)
            let binding = try CloudLibraryBinding(locator: locator, origin: "https://workspace.example", profileID: "apple", accountID: account, remoteLibraryID: UUID())
            let bytes = try Data(contentsOf: library.store!.directory.appending(path: "library.json"))
            let handle = try registry.complete(registry.begin(binding, replacing: nil), repository: repository)
            #expect(try Data(contentsOf: library.store!.directory.appending(path: "library.json")) == bytes)
            rows.append((repository, binding, handle))
        }
        registry.invalidate(aLocator)
        #expect(throws: CloudConnectionRegistryError.invalidated) { try registry.binding(for: rows[0].2) }
        #expect(try registry.binding(for: rows[1].2) == rows[1].1)
        #expect(try rows[0].0.load() == rows[0].1 && rows[1].0.load() == rows[1].1)
    }
    @Test func explicitMappingSwitchFencesPriorHandleAndOtherPendingResult() throws {
        let root = URL(fileURLWithPath: "/private/tmp/CloudRegistry-" + UUID().uuidString); defer { try? FileManager.default.removeItem(at: root) }
        let (repository, binding) = try fixture(root)
        let registry = try CloudConnectionRegistry()
        let oldHandle = try registry.complete(registry.begin(binding, replacing: nil), repository: repository)
        let oldPending = try registry.begin(binding, replacing: binding)
        let other = try CloudLibraryBinding(locator: binding.locator, origin: "https://other.example", profileID: "other", accountID: UUID(), remoteLibraryID: UUID())
        let ticket = try registry.begin(other, replacing: binding)
        let handle = try registry.complete(ticket, repository: repository)
        #expect(throws: CloudConnectionRegistryError.invalidated) { try registry.binding(for: oldHandle) }
        #expect(throws: CloudConnectionRegistryError.staleTicket) { try registry.complete(oldPending, repository: repository) }
        #expect(try registry.binding(for: handle) == other && repository.load() == other)
        #expect(registry.invalidateAll(origin: binding.origin, profileID: binding.profileID, accountID: binding.accountID).isEmpty)
        #expect(try registry.binding(for: handle) == other)
    }
}
