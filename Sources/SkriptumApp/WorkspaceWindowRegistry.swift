import Foundation
#if canImport(SkriptumCore)
import SkriptumCore
#endif

struct WorkspaceWindowRequest: Codable, Hashable, Sendable {
    let id: UUID
    let libraryID: UUID
    let pageID: UUID?
    let locator: OwnedLibraryLocator
}
enum WorkspaceWindowError: Error { case unavailableLibrary, tooManyPendingWindows }

/// Windows/default retain active facades; the cache is weak to release closed libraries.
/// Pending handoffs retain strongly and are bounded. Durable locators never contain paths.
@MainActor final class WorkspaceWindowRegistry {
    static let shared = WorkspaceWindowRegistry()
    private final class Cached {
        weak var library: WritingLibrary?
        init(_ library: WritingLibrary) { self.library = library }
    }
    private struct Pending {
        let request: WorkspaceWindowRequest
        let library: WritingLibrary
        let expires: Date
    }
    private var pending: [UUID: Pending] = [:]
    private var cache: [OwnedLibraryLocator: Cached] = [:]
    private let lifetime: TimeInterval
    private let capacity: Int
    private let documentRoot: URL
    private let supportRoot: URL
    private let preferences: UserDefaults
    init(lifetime: TimeInterval = 300, capacity: Int = 64,
         documentRoot: URL = WorkspaceSystemContainerRoots.documents, supportRoot: URL = WorkspaceSystemContainerRoots.applicationSupport,
         preferences: UserDefaults = .standard) {
        self.lifetime = max(1, lifetime); self.capacity = max(1, capacity)
        self.documentRoot = documentRoot; self.supportRoot = supportRoot; self.preferences = preferences
    }
    @discardableResult func register(_ library: WritingLibrary) throws -> WritingLibrary {
        guard let store = library.store else { throw WorkspaceWindowError.unavailableLibrary }
        let locator = try LibraryStoragePaths.locator(libraryDirectory: store.directory, documentRoot: documentRoot)
        cache = cache.filter { $0.value.library != nil }
        if let existing = cache[locator]?.library { return existing }
        cache[locator] = Cached(library)
        return library
    }
    func request(library: WritingLibrary, pageID: UUID?, now: Date = Date()) throws -> WorkspaceWindowRequest {
        pending = pending.filter { $0.value.expires > now }
        guard pending.count < capacity else { throw WorkspaceWindowError.tooManyPendingWindows }
        let owning = try register(library)
        guard owning === library else { throw WorkspaceWindowError.unavailableLibrary }
        let request = WorkspaceWindowRequest(id: UUID(), libraryID: library.libraryIdentity,
            pageID: pageID.flatMap { id in library.currentPage(id) == nil ? nil : id }, locator: try library.ownedWindowLocator())
        pending[request.id] = Pending(request: request, library: library, expires: now.addingTimeInterval(lifetime))
        return request
    }
    func resolve(_ request: WorkspaceWindowRequest, now: Date = Date()) -> WritingLibrary? {
        if let value = pending[request.id] {
            guard value.expires > now, value.request == request else { return nil }
            return value.library
        }
        // Runtime identity changes after process termination; only the durable
        // owned locator selects a cold scope. Never use page UUID or app default.
        if let existing = cache[request.locator]?.library { return existing }
        pending = pending.filter { $0.value.expires > now }
        guard pending.count < capacity else { return nil }
        do {
            let directory = try existingDirectory(request.locator)
            let library = try WritingLibrary(store: LibraryStore(directory: directory),
                documentRoot: documentRoot, supportRoot: supportRoot, preferences: preferences)
            let retained = try register(library)
            pending[request.id] = Pending(request: request, library: retained, expires: now.addingTimeInterval(lifetime))
            return retained
        } catch { return nil }
    }
    func claim(_ request: WorkspaceWindowRequest, now: Date = Date()) -> WritingLibrary? {
        guard let library = resolve(request, now: now) else { return nil }
        pending.removeValue(forKey: request.id)
        return library
    }
    /// Background work reuses the live facade, or opens exactly one existing
    /// owned locator. It never creates a replacement default library.
    func backgroundLibrary(_ locator: OwnedLibraryLocator) throws -> WritingLibrary {
        let directory = try existingDirectory(locator)
        let edits = directory.appendingPathComponent("edits", isDirectory: true)
        if FileManager.default.fileExists(atPath: edits.path) {
            guard try FileManager.default.contentsOfDirectory(at: edits, includingPropertiesForKeys: nil)
                .allSatisfy({ $0.pathExtension != "json" }) else { throw WorkspaceWindowError.unavailableLibrary }
        }
        if let existing = cache[locator]?.library { return existing }
        let library = try WritingLibrary(store: LibraryStore(directory: directory),
            documentRoot: documentRoot, supportRoot: supportRoot, preferences: preferences)
        return try register(library)
    }
    private func existingDirectory(_ locator: OwnedLibraryLocator) throws -> URL {
        let directory = try LibraryStoragePaths.libraryDirectory(locator: locator, documentRoot: documentRoot)
        if case .imported = locator { try validate(directory.deletingLastPathComponent(), directory: true) }
        try validate(directory, directory: true)
        try validate(directory.appendingPathComponent("library.json"), directory: false)
        let edits = directory.appendingPathComponent("edits", isDirectory: true)
        if FileManager.default.fileExists(atPath: edits.path) {
            try validate(edits, directory: true)
            let journals = try FileManager.default.contentsOfDirectory(at: edits, includingPropertiesForKeys: nil)
            guard journals.count <= 10_000 else { throw WorkspaceWindowError.unavailableLibrary }
            for file in journals where file.pathExtension == "json" { try validate(file, directory: false) }
        }
        let recoveries = directory.appendingPathComponent("Recoveries", isDirectory: true)
        if FileManager.default.fileExists(atPath: recoveries.path) {
            try validate(recoveries, directory: true)
            let records = try FileManager.default.contentsOfDirectory(at: recoveries, includingPropertiesForKeys: nil)
            guard records.count <= 10_000 else { throw WorkspaceWindowError.unavailableLibrary }
            for file in records where file.pathExtension == "json" { try validate(file, directory: false) }
        }
        return directory
    }
    private func validate(_ url: URL, directory: Bool) throws {
        let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey, .isDirectoryKey, .fileSizeKey])
        guard values.isSymbolicLink != true,
              directory ? values.isDirectory == true : values.isRegularFile == true else { throw WorkspaceWindowError.unavailableLibrary }
        if !directory { guard (values.fileSize ?? Int.max) <= 64 * 1024 * 1024 else { throw WorkspaceWindowError.unavailableLibrary } }
    }
}
