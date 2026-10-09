import Foundation
import Darwin
#if canImport(SkriptumCore)
import SkriptumCore
#endif
#if canImport(SkriptumWorkspaceClient)
import SkriptumWorkspaceClient
#endif

enum WorkspaceAccountRuntimeAvailability: Equatable, Sendable { case notConfigured, configurationUnavailable, storageUnavailable, configured }
enum WorkspaceAccountRuntimeError: Error, Equatable, Sendable { case unknownWindow, capacity, presentationUnavailable, consentRequired, wrongDeployment, staleRegistration, storageUnavailable }
enum WorkspaceAccountRuntimeActionOutcome: Equatable, Sendable { case completed, consentRequired, unavailable, presentationUnavailable, superseded }
enum WorkspaceAccountRuntimeRestoreOutcome: Equatable, Sendable { case consentRequired, notConfigured, metadataMissing, restorationAttempted, unavailable, superseded }

/// Stable process-owned composition; no default account or Keychain enumeration.
@MainActor final class WorkspaceAccountRuntime {
    private struct Consent: Equatable { let origin: WorkspaceOrigin; let profile: String; let version: String }
    private final class Registration {
        let id = UUID(); let locator: OwnedLibraryLocator; weak var library: WritingLibrary?
        var consent: Consent?
        var restoredHandle: CloudConnectionHandle?
        init(locator: OwnedLibraryLocator, library: WritingLibrary) { self.locator = locator; self.library = library }
    }
    let availability: WorkspaceAccountRuntimeAvailability
    let deployment: WorkspaceDeploymentConfiguration?
    let connectionRegistry: CloudConnectionRegistry?
    private let coordinator: WorkspaceAccountCoordinator?
    private let libraryPicker: WorkspaceLibraryPickerCoordinator?
    private let proofProvider: WorkspaceRuntimeProofProvider
    private var registrations: [UUID: Registration] = [:]
    private var unavailablePresentations: [UUID: WorkspaceAccountPresentation] = [:]
    init(configuration: WorkspaceDeploymentBundleResult,
         systemSupportRoot: URL = WorkspaceSystemContainerRoots.applicationSupport,
         keychainService: String = "app.scriptum.workspace.sessions.v1",
         proofForWindow: @escaping (UUID) throws -> WorkspaceAccountProofAcquisition) {
        let provider = WorkspaceRuntimeProofProvider(factory: proofForWindow)
        proofProvider = provider
        switch configuration {
        case .notConfigured:
            availability = .notConfigured; deployment = nil; coordinator = nil; connectionRegistry = nil; libraryPicker = nil
        case .unavailable:
            availability = .configurationUnavailable; deployment = nil; coordinator = nil; connectionRegistry = nil; libraryPicker = nil
        case .configured(let deployment):
            self.deployment = deployment
            do {
                let registry = try CloudConnectionRegistry()
                let directory = try Self.privateDenialDirectory(systemSupportRoot)
                let context = try WorkspaceCredentialAdmissionContext.shared(denialDirectory: directory, keychainService: keychainService)
                let kernel = try WorkspaceAccountCoordinator.configured(deployment: deployment, context: context, connectionRegistry: registry, proofForWindow: { try provider.take($0) })
                coordinator = kernel; connectionRegistry = registry; availability = .configured
                libraryPicker = WorkspaceLibraryPickerCoordinator(accounts: kernel, registry: registry)
            } catch { availability = .storageUnavailable; coordinator = nil; connectionRegistry = nil; libraryPicker = nil }
        }
    }
    #if SWIFT_PACKAGE && DEBUG
    /// Injects the actual kernel for deterministic boundary tests only; the App
    /// production initializer always constructs its real configured adapters.
    init(deployment: WorkspaceDeploymentConfiguration, coordinator: WorkspaceAccountCoordinator,
         proofForWindow: @escaping (UUID) throws -> WorkspaceAccountProofAcquisition) throws {
        availability = .configured; self.deployment = deployment; self.coordinator = coordinator
        let registry = try CloudConnectionRegistry()
        connectionRegistry = registry
        libraryPicker = WorkspaceLibraryPickerCoordinator(accounts: coordinator, registry: registry)
        proofProvider = WorkspaceRuntimeProofProvider(factory: proofForWindow)
    }
    #endif
    @discardableResult func register(windowID: UUID, library: WritingLibrary) throws -> OwnedLibraryLocator {
        prune()
        let locator = try library.ownedWindowLocator()
        if let current = registrations[windowID], current.library === library, current.locator == locator { return locator }
        guard registrations[windowID] != nil || registrations.count < 64 else { throw WorkspaceAccountRuntimeError.capacity }
        proofProvider.cancel(windowID)
        libraryPicker?.unregister(windowID: windowID)
        coordinator?.detach(windowID: windowID)
        registrations[windowID] = Registration(locator: locator, library: library)
        unavailablePresentations.removeValue(forKey: windowID)
        return locator
    }
    func presentation(windowID: UUID) throws -> WorkspaceAccountPresentation {
        _ = try registration(windowID)
        if let coordinator { return try coordinator.observe(windowID: windowID) }
        if let existing = unavailablePresentations[windowID] { return existing }
        let state: WorkspaceAccountState = .unavailable(availability == .storageUnavailable ? .localDenialUnavailable : .deploymentNotConfigured)
        let model = WorkspaceAccountPresentation(windowID: windowID, state: state)
        unavailablePresentations[windowID] = model; return model
    }
    func acknowledgeOperator(windowID: UUID, expectedLocator: OwnedLibraryLocator? = nil, expectedFacadeID: UUID? = nil) throws {
        let current = try registration(windowID, expectedLocator: expectedLocator, expectedFacadeID: expectedFacadeID)
        guard let deployment, availability == .configured else { throw WorkspaceAccountRuntimeError.wrongDeployment }
        current.consent = Consent(origin: deployment.origin, profile: deployment.profileID, version: deployment.consentVersion)
    }
    func isOperatorAcknowledged(windowID: UUID, expectedLocator: OwnedLibraryLocator? = nil, expectedFacadeID: UUID? = nil) -> Bool {
        guard let current = registrations[windowID], let deployment else { return false }
        guard expectedLocator == nil || expectedLocator == current.locator, expectedFacadeID == nil || expectedFacadeID == current.library?.libraryIdentity else { return false }
        return current.consent == Consent(origin: deployment.origin, profile: deployment.profileID, version: deployment.consentVersion)
    }
    func restore(windowID: UUID, expectedLocator: OwnedLibraryLocator? = nil, expectedFacadeID: UUID? = nil) async -> WorkspaceAccountRuntimeRestoreOutcome {
        guard let deployment, let coordinator, let connectionRegistry else { return availability == .notConfigured ? .notConfigured : .unavailable }
        guard isOperatorAcknowledged(windowID: windowID, expectedLocator: expectedLocator, expectedFacadeID: expectedFacadeID) else { return .consentRequired }
        do {
            let current = try registration(windowID, expectedLocator: expectedLocator, expectedFacadeID: expectedFacadeID), id = current.id
            guard let library = current.library else { return .superseded }
            let repository = try library.cloudBindingRepository()
            guard repository.locator == current.locator else { throw WorkspaceAccountRuntimeError.staleRegistration }
            guard let metadata = try repository.load() else { return .metadataMissing }
            guard metadata.origin == deployment.origin.url.absoluteString, metadata.profileID == deployment.profileID else { throw WorkspaceAccountRuntimeError.wrongDeployment }
            guard let handle = try connectionRegistry.restore(repository) else { return .metadataMissing }
            let binding = try connectionRegistry.binding(for: handle)
            guard binding.origin == deployment.origin.url.absoluteString, binding.profileID == deployment.profileID else {
                connectionRegistry.invalidate(current.locator)
                throw WorkspaceAccountRuntimeError.wrongDeployment
            }
            current.restoredHandle = handle
            let scope = try WorkspaceAccountScope(origin: deployment.origin, profileID: deployment.profileID, accountID: binding.accountID)
            try coordinator.attach(windowID: windowID, scope: scope)
            await coordinator.restore(windowID: windowID)
            guard registrations[windowID]?.id == id, registrations[windowID]?.library === library else { return .superseded }
            if let libraryPicker, let access = try? coordinator.discoveryAccess(windowID: windowID), access.scope == scope {
                try libraryPicker.register(windowID: windowID, facadeID: library.libraryIdentity, repository: repository, acknowledged: true)
                try libraryPicker.adoptRestored(handle: handle, windowID: windowID, expectedFacadeID: library.libraryIdentity, expectedLocator: current.locator, scope: scope)
            }
            return .restorationAttempted
        } catch { return .unavailable }
    }
    func signIn(windowID: UUID, expectedLocator: OwnedLibraryLocator, expectedFacadeID: UUID? = nil) async -> WorkspaceAccountRuntimeActionOutcome {
        guard let coordinator else { return .unavailable }
        guard isOperatorAcknowledged(windowID: windowID, expectedLocator: expectedLocator, expectedFacadeID: expectedFacadeID) else { return .consentRequired }
        do {
            let current = try registration(windowID, expectedLocator: expectedLocator, expectedFacadeID: expectedFacadeID), id = current.id
            try proofProvider.prepare(windowID)
            defer { proofProvider.cancel(windowID) }
            await coordinator.signIn(windowID: windowID)
            guard registrations[windowID]?.id == id else { return .superseded }
            return .completed
        } catch { return .presentationUnavailable }
    }
    func cancel(windowID: UUID, expectedLocator: OwnedLibraryLocator, expectedFacadeID: UUID? = nil) {
        guard (try? registration(windowID, expectedLocator: expectedLocator, expectedFacadeID: expectedFacadeID)) != nil else { return }
        proofProvider.cancel(windowID)
        coordinator?.cancelSignIn(windowID: windowID); coordinator?.cancelAccountDeletion(windowID: windowID)
    }
    func logout(windowID: UUID, expectedLocator: OwnedLibraryLocator, expectedFacadeID: UUID? = nil, allSessions: Bool) async -> WorkspaceAccountRuntimeActionOutcome {
        guard let coordinator else { return .unavailable }
        do {
            let current = try registration(windowID, expectedLocator: expectedLocator, expectedFacadeID: expectedFacadeID), id = current.id
            guard let scope = Self.scope(coordinator.state(windowID: windowID)) else { return .unavailable }
            await coordinator.logout(scope: scope, allSessions: allSessions)
            return registrations[windowID]?.id == id ? .completed : .superseded
        } catch { return .superseded }
    }
    func deleteAccount(windowID: UUID, expectedLocator: OwnedLibraryLocator, expectedFacadeID: UUID? = nil) async -> WorkspaceAccountDeletionResult? {
        guard let coordinator, isOperatorAcknowledged(windowID: windowID, expectedLocator: expectedLocator, expectedFacadeID: expectedFacadeID) else { return nil }
        do {
            let current = try registration(windowID, expectedLocator: expectedLocator, expectedFacadeID: expectedFacadeID), id = current.id
            guard let scope = Self.scope(coordinator.state(windowID: windowID)) else { return nil }
            try proofProvider.prepare(windowID)
            defer { proofProvider.cancel(windowID) }
            let outcome = await coordinator.deleteAccount(windowID: windowID, scope: scope)
            return registrations[windowID]?.id == id ? outcome : .superseded
        } catch { return .authenticationUnavailable }
    }
    func retryDeletionLocalCleanup(windowID: UUID, expectedLocator: OwnedLibraryLocator, expectedFacadeID: UUID? = nil) async -> WorkspaceAccountRuntimeActionOutcome {
        guard let coordinator else { return .unavailable }
        do {
            let current = try registration(windowID, expectedLocator: expectedLocator, expectedFacadeID: expectedFacadeID), id = current.id
            guard let scope = coordinator.deletionCleanupScope(windowID: windowID) else { return .unavailable }
            await coordinator.retryDeletionLocalCleanup(scope: scope)
            return registrations[windowID]?.id == id ? .completed : .superseded
        } catch { return .superseded }
    }
    func refreshExpiredSession(windowID: UUID, expectedLocator: OwnedLibraryLocator, expectedFacadeID: UUID? = nil) async {
        guard let coordinator, isOperatorAcknowledged(windowID: windowID, expectedLocator: expectedLocator, expectedFacadeID: expectedFacadeID),
              (try? registration(windowID, expectedLocator: expectedLocator, expectedFacadeID: expectedFacadeID)) != nil,
              case .active(_, _, let expiry) = coordinator.state(windowID: windowID), expiry <= Date() else { return }
        await coordinator.restore(windowID: windowID)
    }
    private static func scope(_ state: WorkspaceAccountState) -> WorkspaceAccountScope? {
        switch state {
        case .active(let scope, _, _), .localDenied(let scope, _), .restoring(let scope), .signingOut(let scope), .deleting(let scope), .reauthenticatingForDeletion(let scope, _): scope
        default: nil
        }
    }
    func detach(windowID: UUID) {
        proofProvider.cancel(windowID)
        libraryPicker?.unregister(windowID: windowID)
        coordinator?.detach(windowID: windowID)
        registrations.removeValue(forKey: windowID); unavailablePresentations.removeValue(forKey: windowID)
    }
    func pickerPresentation(windowID: UUID, expectedLocator: OwnedLibraryLocator,
                            expectedFacadeID: UUID) throws -> WorkspaceLibraryPickerPresentation? {
        let current = try registration(windowID, expectedLocator: expectedLocator, expectedFacadeID: expectedFacadeID)
        guard let libraryPicker else { return nil }
        guard isOperatorAcknowledged(windowID: windowID, expectedLocator: expectedLocator, expectedFacadeID: expectedFacadeID) else {
            throw WorkspaceAccountRuntimeError.consentRequired
        }
        guard let library = current.library else { throw WorkspaceAccountRuntimeError.unknownWindow }
        try libraryPicker.register(windowID: windowID, facadeID: expectedFacadeID,
            repository: library.cloudBindingRepository(), acknowledged: true)
        if let handle = current.restoredHandle, let coordinator, let registry = connectionRegistry,
           let access = try? coordinator.discoveryAccess(windowID: windowID),
           let binding = try? registry.binding(for: handle),
           binding.accountID == access.scope.accountID, binding.origin == access.scope.origin.url.absoluteString,
           binding.profileID == access.scope.profileID {
            try libraryPicker.adoptRestored(handle: handle, windowID: windowID, expectedFacadeID: expectedFacadeID, expectedLocator: expectedLocator, scope: access.scope)
        }
        return try libraryPicker.observe(windowID: windowID)
    }
    func beginLibraryConsumer(windowID: UUID, expectedLocator: OwnedLibraryLocator,
                              expectedFacadeID: UUID, consumerID: UUID) throws {
        guard try pickerPresentation(windowID: windowID, expectedLocator: expectedLocator, expectedFacadeID: expectedFacadeID) != nil,
              let libraryPicker else { throw WorkspaceAccountRuntimeError.wrongDeployment }
        try libraryPicker.beginConsumer(windowID: windowID, expectedFacadeID: expectedFacadeID,
            expectedLocator: expectedLocator, consumerID: consumerID)
    }
    func loadLibraries(windowID: UUID, expectedLocator: OwnedLibraryLocator, expectedFacadeID: UUID, consumerID: UUID) async {
        guard (try? pickerPresentation(windowID: windowID, expectedLocator: expectedLocator, expectedFacadeID: expectedFacadeID)) != nil else { return }
        await libraryPicker?.load(windowID: windowID, expectedFacadeID: expectedFacadeID, expectedLocator: expectedLocator, consumerID: consumerID)
    }
    func nextLibraries(windowID: UUID, expectedLocator: OwnedLibraryLocator, expectedFacadeID: UUID, consumerID: UUID) async {
        guard (try? pickerPresentation(windowID: windowID, expectedLocator: expectedLocator, expectedFacadeID: expectedFacadeID)) != nil else { return }
        await libraryPicker?.next(windowID: windowID, expectedFacadeID: expectedFacadeID, expectedLocator: expectedLocator, consumerID: consumerID)
    }
    func previousLibraries(windowID: UUID, expectedLocator: OwnedLibraryLocator, expectedFacadeID: UUID, consumerID: UUID) async {
        guard (try? pickerPresentation(windowID: windowID, expectedLocator: expectedLocator, expectedFacadeID: expectedFacadeID)) != nil else { return }
        await libraryPicker?.previous(windowID: windowID, expectedFacadeID: expectedFacadeID, expectedLocator: expectedLocator, consumerID: consumerID)
    }
    func associateLibrary(id: UUID, windowID: UUID, expectedLocator: OwnedLibraryLocator,
                          expectedFacadeID: UUID, consumerID: UUID) async -> WorkspaceLibraryPickerOutcome {
        do {
            guard try pickerPresentation(windowID: windowID, expectedLocator: expectedLocator, expectedFacadeID: expectedFacadeID) != nil,
                  let libraryPicker else { return .unavailable }
            return await libraryPicker.select(libraryID: id, windowID: windowID,
                expectedFacadeID: expectedFacadeID, expectedLocator: expectedLocator, consumerID: consumerID)
        } catch WorkspaceAccountRuntimeError.staleRegistration { return .superseded }
        catch WorkspaceAccountRuntimeError.unknownWindow { return .superseded }
        catch { return .unavailable }
    }
    func cancelLibraryRequest(windowID: UUID, expectedLocator: OwnedLibraryLocator, expectedFacadeID: UUID, consumerID: UUID) {
        guard (try? registration(windowID, expectedLocator: expectedLocator, expectedFacadeID: expectedFacadeID)) != nil else { return }
        libraryPicker?.cancel(windowID: windowID, expectedFacadeID: expectedFacadeID, expectedLocator: expectedLocator, consumerID: consumerID)
    }
    private func registration(_ windowID: UUID, expectedLocator: OwnedLibraryLocator? = nil, expectedFacadeID: UUID? = nil) throws -> Registration {
        guard let current = registrations[windowID], let library = current.library,
              try library.ownedWindowLocator() == current.locator else { throw WorkspaceAccountRuntimeError.unknownWindow }
        guard expectedLocator == nil || expectedLocator == current.locator, expectedFacadeID == nil || expectedFacadeID == library.libraryIdentity else { throw WorkspaceAccountRuntimeError.staleRegistration }
        return current
    }
    private func prune() {
        for id in registrations.keys.filter({ registrations[$0]?.library == nil }) { detach(windowID: id) }
    }
    /// Caller provides canonical trusted Foundation root; no selected URL is
    /// resolved here. Missing parents are private, descriptor/no-follow owned.
    private static func privateDenialDirectory(_ root: URL) throws -> URL {
        guard root.isFileURL, root.path.hasPrefix("/") else { throw WorkspaceAccountRuntimeError.storageUnavailable }
        let components = root.path.split(separator: "/").map(String.init) + ["WorkspaceAccounts"]
        guard components.allSatisfy({ $0 != "." && $0 != ".." }) else { throw WorkspaceAccountRuntimeError.storageUnavailable }
        var fd = Darwin.open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw WorkspaceAccountRuntimeError.storageUnavailable }
        for component in components {
            var next = Darwin.openat(fd, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            if next < 0, errno == ENOENT {
                guard Darwin.mkdirat(fd, component, 0o700) == 0 || errno == EEXIST else { Darwin.close(fd); throw WorkspaceAccountRuntimeError.storageUnavailable }
                next = Darwin.openat(fd, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            }
            Darwin.close(fd)
            guard next >= 0 else { throw WorkspaceAccountRuntimeError.storageUnavailable }
            fd = next
        }
        defer { Darwin.close(fd) }
        var info = stat()
        guard Darwin.fstat(fd, &info) == 0, info.st_uid == getuid(), info.st_mode & 0o077 == 0 else { throw WorkspaceAccountRuntimeError.storageUnavailable }
        return root.appendingPathComponent("WorkspaceAccounts", isDirectory: true)
    }
}

@MainActor private final class WorkspaceRuntimeProofProvider {
    private let factory: (UUID) throws -> WorkspaceAccountProofAcquisition
    private var prepared: [UUID: WorkspaceAccountProofAcquisition] = [:]
    init(factory: @escaping (UUID) throws -> WorkspaceAccountProofAcquisition) { self.factory = factory }
    func prepare(_ window: UUID) throws {
        cancel(window)
        guard prepared.count < 64 else { throw WorkspaceAccountRuntimeError.capacity }
        prepared[window] = try factory(window)
    }
    func take(_ window: UUID) throws -> WorkspaceAccountProofAcquisition {
        if let value = prepared.removeValue(forKey: window) { return value }
        return try factory(window)
    }
    func cancel(_ window: UUID) { prepared.removeValue(forKey: window)?.cancel() }
}
