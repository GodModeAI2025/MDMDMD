import Foundation
import CloudKit
import Testing
import SkriptumCore
@testable import SkriptumWorkspaceModel

@MainActor private struct SharePresentationFixture {
    let directory: URL
    let library: WritingLibrary
    init() throws {
        directory = URL(fileURLWithPath: "/private/tmp/ScriptumSharePresentation-" + UUID().uuidString)
        let documents = directory.appendingPathComponent("Documents")
        let store = try LibraryStore(directory: documents.appendingPathComponent("Skriptum"))
        _ = try store.createSpace(title: "Writing")
        library = try WritingLibrary(store: store, documentRoot: documents,
            supportRoot: directory.appendingPathComponent("Support"))
    }
    func remove() { try? FileManager.default.removeItem(at: directory) }
}

@Test @MainActor func sharePresentationDoneAndExplicitUserCancelDoNotBecomeSyncFailures() throws {
    let fixture = try SharePresentationFixture(); defer { fixture.remove() }
    let library = fixture.library
    for error: (any Error)? in [nil, CocoaError(.userCancelled)] {
        let operation = library.beginICloudSharePresentation()
        #expect(library.confirmICloudSharePresentation(operation))
        #expect(library.completeICloudSharePresentation(operation, error: error))
        #expect(library.iCloudShareError == nil)
        #expect(library.saveError == nil)
        // Completion retires its token, so a delayed duplicate cannot revive it.
        #expect(!library.completeICloudSharePresentation(operation, error: CKError(.networkFailure)))
        #expect(library.iCloudShareError == nil)
    }
}

@Test(arguments: ["same-code-other-domain", "cloud-cancel", "url-cancel", "configuration", "permission", "storage"])
func sharePresentationOnlySuppressesDocumentedFoundationUserCancellation(kind: String) throws {
    let secret = "private-record /private/account/path"
    let error: any Error
    switch kind {
    case "same-code-other-domain": error = NSError(domain: "OtherErrorDomain", code: 3072, userInfo: [NSLocalizedDescriptionKey: secret])
    case "cloud-cancel": error = CKError(.operationCancelled, userInfo: [NSLocalizedDescriptionKey: secret])
    case "url-cancel": error = URLError(.cancelled, userInfo: [NSLocalizedDescriptionKey: secret])
    case "configuration": error = NSError(domain: NSCocoaErrorDomain, code: 67072, userInfo: [NSLocalizedDescriptionKey: secret])
    case "permission": error = CKError(.permissionFailure, userInfo: [NSLocalizedDescriptionKey: secret])
    default: error = CocoaError(.fileWriteUnknown, userInfo: [NSLocalizedDescriptionKey: secret])
    }
    let message = try #require(ICloudSharePresentationFailure.message(error))
    #expect(!message.contains(secret))
    #expect(!message.contains("Die Synchronisation konnte nicht abgeschlossen werden"))
    if kind == "permission" { #expect(message == ICloudFailureDiagnostic.describe(error).message) }
    #expect(ICloudSharePresentationFailure.message(CocoaError(.userCancelled)) == nil)
}

@Test @MainActor func sharePresentationRetryClearsOnlyConfirmedShareErrorAndPreservesLocalFailure() throws {
    let fixture = try SharePresentationFixture(); defer { fixture.remove() }
    let library = fixture.library
    let failed = library.beginICloudSharePresentation()
    #expect(library.completeICloudSharePresentation(failed, error: NSError(domain: "NativeShare", code: 1)))
    let sharingFailure = try #require(library.iCloudShareError)
    #expect(sharingFailure.contains("iCloud-Freigabe"))
    library.saveError = "Current unsaved document failure"
    let retry = library.beginICloudSharePresentation()
    #expect(library.iCloudShareError == sharingFailure)
    // Opening a confirmed share resolves its own earlier failure, regardless
    // of independent editing or synchronization activity.
    #expect(library.confirmICloudSharePresentation(retry))
    #expect(library.iCloudShareError == nil)
    #expect(library.saveError == "Current unsaved document failure")
    #expect(library.completeICloudSharePresentation(retry, error: nil))
    #expect(library.saveError == "Current unsaved document failure")
}

@Test @MainActor func sharePresentationRealFailureDoesNotOverwriteStorageFailureOrDisappearOnLocalSave() throws {
    let fixture = try SharePresentationFixture(); defer { fixture.remove() }
    let library = fixture.library
    library.saveError = "Local file write failed"
    let operation = library.beginICloudSharePresentation()
    #expect(library.completeICloudSharePresentation(operation, error: CKError(.quotaExceeded)))
    let sharingFailure = try #require(library.iCloudShareError)
    #expect(sharingFailure.contains("Speicher ist voll"))
    #expect(library.saveError == "Local file write failed")
    library.saveError = nil
    #expect(library.iCloudShareError == sharingFailure)
    let retry = library.beginICloudSharePresentation()
    #expect(library.completeICloudSharePresentation(retry, error: CocoaError(.userCancelled)))
    // Cancelling before a new share is confirmed cannot dismiss an unresolved
    // failure from the previous attempt.
    #expect(library.iCloudShareError == sharingFailure)
}

@Test @MainActor func sharePresentationOldCallbacksCannotAlterCurrentOrAnotherLibrary() throws {
    let fixture = try SharePresentationFixture(); defer { fixture.remove() }
    let other = try SharePresentationFixture(); defer { other.remove() }
    let library = fixture.library
    let old = library.beginICloudSharePresentation()
    let current = library.beginICloudSharePresentation()
    #expect(!library.completeICloudSharePresentation(old, error: CKError(.permissionFailure)))
    #expect(!other.library.confirmICloudSharePresentation(current))
    #expect(!other.library.completeICloudSharePresentation(current, error: CKError(.permissionFailure)))
    #expect(library.iCloudShareError == nil && other.library.iCloudShareError == nil)
    #expect(library.completeICloudSharePresentation(current, error: CKError(.networkFailure)))
    let failure = try #require(library.iCloudShareError)
    #expect(!library.confirmICloudSharePresentation(old))
    #expect(!library.completeICloudSharePresentation(old, error: nil))
    #expect(library.iCloudShareError == failure)
}

@Test func sharePresentationKeepsSpecificSessionFailureMessage() throws {
    let error = ICloudTransportFailure(diagnostic: .init(message: "An actionable current session failure", code: "Transport.fixture"))
    #expect(ICloudSharePresentationFailure.message(error) == error.diagnostic.message)
    #expect(ICloudSharePresentationFailure.message(ICloudOwnerPresentationError.pendingChanges)?.contains("alle Änderungen übertragen") == true)
    for error: any Error in [ICloudAccountAvailability.noAccount, ICloudShareOwnerError.accountChanged,
                            ICloudShareOwnerError.changedManifest, ICloudShareOwnerError.invalidReceipt] {
        #expect(ICloudSharePresentationFailure.message(error) == ICloudFailureDiagnostic.describe(error).message)
    }
}

@Test @MainActor func sharePresentationConnectionRevisionInvalidatesOldDialogOnStopAndReconnect() async throws {
    let fixture = try SharePresentationFixture(); defer { fixture.remove() }
    let session = ICloudLibrarySession(library: fixture.library, provisioned: true,
        accountLookup: { throw ICloudAccountAvailability.noAccount })
    fixture.library.iCloudSession = session
    let original = session.connectionRevision
    await session.stop(rememberDisconnect: false)
    let stopped = session.connectionRevision
    #expect(stopped != original)
    #expect(fixture.library.iCloudSession === session)
    await session.activate()
    #expect(session.connectionRevision != stopped && session.connectionRevision != original)
    #expect(fixture.library.iCloudSession === session)
    #expect(session.status == .failed && session.failureCode == "Account.noAccount")
    #expect(!FileManager.default.fileExists(atPath: fixture.library.iCloudStorageDirectory().path))
}
