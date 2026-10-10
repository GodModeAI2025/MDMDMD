import Foundation
#if canImport(SkriptumCore)
import SkriptumCore
#endif
#if canImport(SkriptumWorkspaceClient)
import SkriptumWorkspaceClient
#endif

/// MainActor lifecycle fencing plus a synchronous admission → repository CAS commit.
/// No displayed metadata is reused as server permission or synchronization state.
@MainActor final class WorkspaceLibraryPickerCoordinator {
    @MainActor private final class Registration {
        let id = UUID()
        let facadeID: UUID
        let repository: CloudLibraryBindingRepository
        let acknowledged: Bool
        let presentation = WorkspaceLibraryPickerPresentation()
        var admittedScope: WorkspaceAccountScope?
        var consumerID: UUID?
        var request: UUID?
        var cursor: UUID?
        var history: [UUID?] = []
        init(facadeID: UUID, repository: CloudLibraryBindingRepository, acknowledged: Bool) {
            self.facadeID = facadeID; self.repository = repository; self.acknowledged = acknowledged
        }
    }
    private let accounts: WorkspaceAccountCoordinator
    private let registry: CloudConnectionRegistry
    private var registrations: [UUID: Registration] = [:]
    private var handles: [OwnedLibraryLocator: CloudConnectionHandle] = [:]
    private var observer: UUID?

    init(accounts: WorkspaceAccountCoordinator, registry: CloudConnectionRegistry) {
        self.accounts = accounts; self.registry = registry
        observer = try? accounts.addDiscoveryInvalidationObserver(owner: self) { [weak self] windowID in
            self?.invalidate(windowID: windowID)
        }
    }

    func register(windowID: UUID, facadeID: UUID, repository: CloudLibraryBindingRepository, acknowledged: Bool) throws {
        guard observer != nil else { throw CloudConnectionRegistryError.capacity }
        if let old = registrations[windowID], old.facadeID == facadeID,
           old.repository.locator == repository.locator, old.repository.fileURL == repository.fileURL,
           old.acknowledged == acknowledged { return }
        guard registrations[windowID] != nil || registrations.count < 64 else { throw CloudConnectionRegistryError.capacity }
        unregister(windowID: windowID)
        let value = Registration(facadeID: facadeID, repository: repository, acknowledged: acknowledged)
        registrations[windowID] = value
        publish(value)
    }

    func unregister(windowID: UUID) {
        guard let old = registrations.removeValue(forKey: windowID) else { return }
        old.request = nil
        old.presentation.publish(rows: [], history: [], next: nil, association: nil, busy: false, outcome: .superseded)
        pruneHandles()
    }

    func beginConsumer(windowID: UUID, expectedFacadeID: UUID, expectedLocator: OwnedLibraryLocator, consumerID: UUID) throws {
        guard let value = registrations[windowID], value.facadeID == expectedFacadeID,
              value.repository.locator == expectedLocator, value.acknowledged else { throw CloudConnectionRegistryError.wrongScope }
        _ = try accounts.discoveryAccess(windowID: windowID)
        value.consumerID = consumerID; value.request = nil; value.history = []; value.cursor = nil
        value.presentation.publish(rows: [], history: [], next: nil, association: association(value), busy: false, outcome: nil)
    }

    func adoptRestored(handle: CloudConnectionHandle, windowID: UUID, expectedFacadeID: UUID, expectedLocator: OwnedLibraryLocator, scope: WorkspaceAccountScope) throws {
        guard let value = registrations[windowID], value.facadeID == expectedFacadeID,
              value.repository.locator == expectedLocator, value.acknowledged else { throw CloudConnectionRegistryError.wrongScope }
        let access = try accounts.discoveryAccess(windowID: windowID)
        try access.validateCurrent(windowID: windowID)
        guard access.scope == scope else { throw CloudConnectionRegistryError.wrongScope }
        let binding = try registry.binding(for: handle)
        guard binding.locator == expectedLocator, binding.accountID == scope.accountID,
              binding.origin.utf8.elementsEqual(scope.origin.url.absoluteString.utf8),
              binding.profileID.utf8.elementsEqual(scope.profileID.utf8) else { throw CloudConnectionRegistryError.wrongScope }
        value.admittedScope = scope; handles[expectedLocator] = handle
        publishAssociation(locator: expectedLocator)
    }

    func observe(windowID: UUID) throws -> WorkspaceLibraryPickerPresentation {
        guard let value = registrations[windowID] else { throw CloudConnectionRegistryError.wrongScope }
        return value.presentation
    }

    func cancel(windowID: UUID, expectedFacadeID: UUID, expectedLocator: OwnedLibraryLocator, consumerID: UUID? = nil) {
        guard let value = matching(windowID, expectedFacadeID, expectedLocator, consumerID: consumerID) else { return }
        value.request = nil
        value.presentation.publish(rows: [], history: value.history, next: nil, association: association(value), busy: false, outcome: .superseded)
    }

    private func invalidate(windowID: UUID) {
        guard let value = registrations[windowID] else { return }
        value.request = nil; value.history = []; value.cursor = nil
        // The locator may be shared by scenes attached to different accounts.
        // Only the scope captured from actual kernel admission may revoke its handle.
        let oldScope = value.admittedScope; value.admittedScope = nil
        var revoked = false
        let siblingIsActive = oldScope.map { scope in
            registrations.contains { otherWindow, other in
                guard otherWindow != windowID, other.repository.locator == value.repository.locator,
                      let access = try? accounts.discoveryAccess(windowID: otherWindow) else { return false }
                return access.scope == scope
            }
        } ?? false
        if let scope = oldScope, !siblingIsActive, let binding = association(value),
           binding.origin.utf8.elementsEqual(scope.origin.url.absoluteString.utf8),
           binding.profileID.utf8.elementsEqual(scope.profileID.utf8), binding.accountID == scope.accountID {
            registry.invalidate(value.repository.locator)
            handles.removeValue(forKey: value.repository.locator)
            revoked = true
        }
        value.presentation.publish(rows: [], history: [], next: nil, association: nil, busy: false, outcome: .superseded)
        if revoked { publishAssociation(locator: value.repository.locator) }
    }

    private func matching(_ window: UUID, _ facade: UUID, _ locator: OwnedLibraryLocator, consumerID: UUID? = nil) -> Registration? {
        guard let value = registrations[window], value.facadeID == facade, value.repository.locator == locator, value.acknowledged, value.consumerID == consumerID else { return nil }
        return value
    }
    private func current(_ value: Registration, window: UUID, request: UUID, consumerID: UUID?, access: WorkspaceLibraryDiscoveryAccess) throws {
        guard registrations[window] === value, value.request == request, value.consumerID == consumerID, !Task.isCancelled else { throw CloudConnectionRegistryError.staleTicket }
        try access.validateCurrent(windowID: window)
    }
    private func association(_ value: Registration) -> CloudLibraryBinding? {
        guard let handle = handles[value.repository.locator] else { return nil }
        return try? registry.binding(for: handle)
    }
    private func publish(_ value: Registration, busy: Bool = false, outcome: WorkspaceLibraryPickerOutcome? = nil) {
        value.presentation.publish(rows: value.presentation.rows, history: value.history, next: value.presentation.nextAfter,
                                   association: association(value), busy: busy, outcome: outcome)
    }
    private func publishAssociation(locator: OwnedLibraryLocator) {
        for value in registrations.values where value.repository.locator == locator {
            publish(value, busy: value.presentation.isBusy, outcome: value.presentation.outcome)
        }
    }
    private func pruneHandles() {
        let owned = Set(registrations.values.map { $0.repository.locator })
        handles = handles.filter { owned.contains($0.key) }
    }

    func load(windowID: UUID, expectedFacadeID: UUID, expectedLocator: OwnedLibraryLocator, after: UUID? = nil, consumerID: UUID? = nil) async {
        await loadPage(windowID: windowID, facadeID: expectedFacadeID, locator: expectedLocator, after: after, history: [], consumerID: consumerID)
    }
    func next(windowID: UUID, expectedFacadeID: UUID, expectedLocator: OwnedLibraryLocator, consumerID: UUID? = nil) async {
        guard let value = matching(windowID, expectedFacadeID, expectedLocator, consumerID: consumerID), let after = value.presentation.nextAfter else { return }
        var history = value.history; history.append(value.cursor)
        if history.count > 16 { history.removeFirst(history.count - 16) }
        await loadPage(windowID: windowID, facadeID: expectedFacadeID, locator: expectedLocator, after: after, history: history, consumerID: consumerID)
    }
    func previous(windowID: UUID, expectedFacadeID: UUID, expectedLocator: OwnedLibraryLocator, consumerID: UUID? = nil) async {
        guard let value = matching(windowID, expectedFacadeID, expectedLocator, consumerID: consumerID), !value.history.isEmpty else { return }
        var history = value.history; let after = history.removeLast()
        await loadPage(windowID: windowID, facadeID: expectedFacadeID, locator: expectedLocator, after: after, history: history, consumerID: consumerID)
    }
    private func loadPage(windowID: UUID, facadeID: UUID, locator: OwnedLibraryLocator, after: UUID?, history: [UUID?], consumerID: UUID?) async {
        guard let value = matching(windowID, facadeID, locator, consumerID: consumerID) else { return }
        let request = UUID(); value.request = request; publish(value, busy: true)
        do {
            let access = try accounts.discoveryAccess(windowID: windowID)
            try current(value, window: windowID, request: request, consumerID: consumerID, access: access)
            value.admittedScope = access.scope
            try access.driver.validateAdmission()
            let page = try await access.driver.listLibraries(after: after)
            try current(value, window: windowID, request: request, consumerID: consumerID, access: access)
            try access.driver.validateAdmission()
            try Self.validate(page, after: after)
            value.request = nil; value.cursor = after; value.history = history
            value.presentation.publish(rows: page.libraries, history: history, next: page.nextAfter,
                                       association: association(value), busy: false, outcome: nil)
        } catch {
            guard registrations[windowID] === value, value.request == request else { return }
            value.request = nil
            value.presentation.publish(rows: [], history: value.history, next: nil, association: association(value), busy: false, outcome: .unavailable)
        }
    }

    func select(libraryID: UUID, windowID: UUID, expectedFacadeID: UUID, expectedLocator: OwnedLibraryLocator, consumerID: UUID? = nil) async -> WorkspaceLibraryPickerOutcome {
        guard let value = matching(windowID, expectedFacadeID, expectedLocator, consumerID: consumerID), !value.presentation.isBusy,
              value.presentation.rows.contains(where: { $0.libraryID == libraryID }) else { return .unavailable }
        let request = UUID(); value.request = request; publish(value, busy: true)
        var ticket: CloudConnectionTicket?
        defer { if let ticket { registry.cancel(ticket) } }
        do {
            let access = try accounts.discoveryAccess(windowID: windowID)
            try current(value, window: windowID, request: request, consumerID: consumerID, access: access)
            value.admittedScope = access.scope
            try access.driver.validateAdmission()
            let proposed = try CloudLibraryBinding(locator: expectedLocator, origin: access.scope.origin.url.absoluteString,
                                                  profileID: access.scope.profileID, accountID: access.scope.accountID, remoteLibraryID: libraryID)
            let pending = try registry.begin(proposed, replacing: value.repository.load()); ticket = pending
            let metadata = try await access.driver.libraryMetadata(id: libraryID)
            try current(value, window: windowID, request: request, consumerID: consumerID, access: access)
            try access.driver.validateAdmission()
            try Self.validate(metadata)
            guard metadata.libraryID == libraryID else { throw WorkspaceClientError.invalidResponse }
            let handle = try access.driver.withAdmittedCredential {
                // Kernel checks only: never reenter the admission gate held by the driver.
                try self.current(value, window: windowID, request: request, consumerID: consumerID, access: access)
                return try self.registry.complete(pending, repository: value.repository)
            }
            ticket = nil; value.request = nil; handles[expectedLocator] = handle
            publish(value, outcome: .associated); publishAssociation(locator: expectedLocator)
            return .associated
        } catch {
            guard registrations[windowID] === value, value.request == request else { return .superseded }
            value.request = nil
            let outcome: WorkspaceLibraryPickerOutcome
            if let error = error as? CloudLibraryBindingError, error == .conflict { outcome = .conflict }
            else if let error = error as? CloudConnectionRegistryError, error == .bindingConflict { outcome = .conflict }
            else { outcome = .unavailable }
            publish(value, outcome: outcome)
            return outcome
        }
    }

    private static func validate(_ value: WorkspaceLibraryMetadata) throws {
        guard value.role != .none, (1...4096).contains(value.title.utf8.count) else { throw WorkspaceClientError.invalidResponse }
    }
    private static func validate(_ page: WorkspaceLibraryMetadataPage, after: UUID?) throws {
        guard page.libraries.count <= 8 else { throw WorkspaceClientError.invalidResponse }
        var last = after
        for row in page.libraries {
            try validate(row)
            guard last.map({ row.libraryID.uuidString > $0.uuidString }) ?? true else { throw WorkspaceClientError.invalidResponse }
            last = row.libraryID
        }
        if let next = page.nextAfter {
            guard after.map({ next.uuidString > $0.uuidString }) ?? true,
                  last.map({ next.uuidString >= $0.uuidString }) ?? true else { throw WorkspaceClientError.invalidResponse }
        }
    }
}
