import Foundation
import CloudKit
import Testing
import SkriptumCore
@testable import SkriptumWorkspaceModel

@Test func iCloudDiagnosticsDistinguishAccountStorageAndServiceFailuresWithoutLeakingPayloads() throws {
    try ICloudAccountAvailability.require(.available)
    for status in [CKAccountStatus.noAccount, .restricted, .temporarilyUnavailable, .couldNotDetermine] {
        #expect(throws: ICloudAccountAvailability.self) { try ICloudAccountAvailability.require(status) }
    }
    let secret = "private-document-record /private/user/path account-id"
    let storage = ICloudFailureDiagnostic.describe(ICloudSyncEngineError.storage).message
    #expect(storage.contains("lokalen Synchronisationsspeicher"))
    #expect(!storage.contains("Prüfe dein iCloud-Konto"))
    for code in [CKError.Code.networkFailure, .quotaExceeded, .missingEntitlement, .serviceUnavailable] {
        let message = ICloudFailureDiagnostic.describe(CKError(code, userInfo: [NSLocalizedDescriptionKey: secret])).message
        #expect(!message.contains(secret))
        #expect(message != storage)
    }
    #expect(ICloudFailureDiagnostic.describe(CKError(.quotaExceeded)).message.contains("Speicher ist voll"))
    #expect(ICloudFailureDiagnostic.describe(CKError(.missingEntitlement)).message.contains("App-Einrichtung"))
    #expect(ICloudFailureDiagnostic.describe(CKError(.missingEntitlement)).code == "CloudKit.\(CKError.Code.missingEntitlement.rawValue)")
    #expect(ICloudFailureDiagnostic.describe(ICloudLibraryJournalBridgeError.persistence).code == "Projection.persistence")
    #expect(ICloudFailureDiagnostic.describe(ICloudLibraryJournalBridgeError.persistence).message.contains("lokalen Synchronisationsspeicher"))
    for error: any Error in [ICloudSyncEngineError.capacity, ICloudSyncJournalError.capacityExceeded,
                            ICloudLibraryJournalBridgeError.capacityExceeded] {
        #expect(ICloudFailureDiagnostic.describe(error).message.contains("Synchronisationsgrenze"))
    }
    #expect(ICloudFailureDiagnostic.describe(ICloudSyncEngineError.invalidRecord).code == "Transport.invalidRecord")
    let unknown = NSError(domain: secret, code: 123, userInfo: [NSLocalizedDescriptionKey: secret])
    #expect(ICloudFailureDiagnostic.describe(unknown).code == "unknown")
    #expect(ICloudFailureDiagnostic.describe(ICloudOwnerPresentationError.unresolvedConflicts).message.contains("Seitenkonflikte"))
    #expect(ICloudFailureDiagnostic.describe(ICloudOwnerPresentationError.pendingChanges).message.contains("alle Änderungen übertragen"))
    let nested = CKError(.partialFailure, userInfo: [CKPartialErrorsByItemIDKey: [secret: CKError(.quotaExceeded)]])
    #expect(ICloudFailureDiagnostic.describe(nested).message == ICloudFailureDiagnostic.describe(CKError(.quotaExceeded)).message)
    #expect(ICloudFailureDiagnostic.describe(nested).code == "CloudKit.2[\(CKError.Code.quotaExceeded.rawValue)]")
}

@Test func iCloudEngineFilesTraverseAncestorsWithoutDirectoryReadPermission() throws {
    let root = URL(fileURLWithPath: "/private/tmp/ScriptumSearchOnly-" + UUID().uuidString)
    let leaf = root.appendingPathComponent("State")
    try FileManager.default.createDirectory(at: leaf, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    defer {
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
        try? FileManager.default.removeItem(at: root)
    }
    try FileManager.default.setAttributes([.posixPermissions: 0o111], ofItemAtPath: root.path)
    let files = try ICloudSyncEngine.Files(directory: leaf, name: "checkpoint.json")
    let bytes = Data("preserve-checkpoint".utf8)
    try files.write(bytes)
    #expect(try files.read() == bytes)
    #expect(try files.siblingNames(prefix: "checkpoint") == ["checkpoint.json"])
}

@Test @MainActor func unprovisionedICloudSessionCannotActivateAfterStopOrCreateSyncFiles() async throws {
    let root = URL(fileURLWithPath: "/private/tmp/ICloudSession-" + UUID().uuidString)
    let suite = "test.icloudsession." + UUID().uuidString
    defer { try? FileManager.default.removeItem(at: root); UserDefaults.standard.removePersistentDomain(forName: suite) }
    let documents = root.appendingPathComponent("Documents"), support = root.appendingPathComponent("Support")
    let store = try LibraryStore(directory: documents.appendingPathComponent("Skriptum"))
    let space = try store.createSpace(title: "Local")
    _ = try store.createPage(spaceID: space.id, title: "Page", markdown: "e\u{301}\r\n🦊")
    let library = try WritingLibrary(store: store, documentRoot: documents, supportRoot: support,
        preferences: #require(UserDefaults(suiteName: suite)))
    let bytes = try Data(contentsOf: store.directory.appendingPathComponent("library.json"))
    let session = ICloudLibrarySession(library: library)
    #expect(session.status == .notConfigured)
    #expect(session.diagnosticReport.contains("Status: notConfigured"))
    #expect(!session.diagnosticReport.contains(store.directory.path))
    #expect(!session.diagnosticReport.contains("🦊"))
    await session.activate(); await session.stop(); await session.activate()
    let activeScene = library.iCloudForegroundScenes.register()
    activeScene.update(active: true); session.setForegroundActive(library.iCloudForegroundScenes.isActive)
    await session.receiveCloudChangeHint()
    activeScene.close(); session.setForegroundActive(library.iCloudForegroundScenes.isActive)
    await session.synchronize()
    do { _ = try await session.createShare(scope: .space(space.id)); Issue.record("Unprovisioned share created") }
    catch { #expect(error is ICloudOwnerPresentationError) }
    let local = store.snapshot.pages[0]
    var remote = local; remote.revision = UUID(); remote.title = "Remote title"
    let conflict = try ICloudPageConflict(scope: ICloudSyncScope(accountID: "unused", libraryID: UUID()), local: local,
        change: ICloudSyncChange(recordID: .init(kind: .page, id: local.id), revisionID: remote.revision,
            operation: .upsert, payload: ICloudPagePayload(page: remote, baseRevision: nil).encoded()))
    #expect(try await session.pageConflicts().isEmpty)
    #expect(!session.canResolve(conflict))
    #expect(throws: (any Error).self) { try session.reviewStore(for: conflict) }
    do { try await session.resolve(conflict, choice: .remote); Issue.record("Unprovisioned conflict resolved") }
    catch { #expect(error is ICloudPageConflictError) }
    #expect(session.status == .notConfigured)
    #expect(session.pendingCount == 0)
    #expect(session.incomingCount == 0 && session.conflictCount == 0 && session.lastSynchronized == nil)
    #expect(!FileManager.default.fileExists(atPath: library.iCloudStorageDirectory().path))
    #expect(try Data(contentsOf: store.directory.appendingPathComponent("library.json")) == bytes)
}
