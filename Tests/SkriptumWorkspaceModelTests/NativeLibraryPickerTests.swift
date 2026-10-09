import Foundation
import XCTest
import SkriptumCore
@testable import SkriptumWorkspaceClient
@testable import SkriptumWorkspaceModel

/// Scheduling proof uses synthetic admission only; disk assertions use actual Core repositories.
@MainActor final class NativeLibraryPickerTests: XCTestCase {
    func testNP01ExactAdoptionAndConsentBeforeDiscovery() async throws {
        let f = try PickerFixture(); defer { f.cleanup() }
        try f.register(acknowledged: false)
        await f.load()
        XCTAssertEqual(f.driver.listCalls, 0)
        XCTAssertNil(try f.repository.load())
        try f.register()
        await f.load()
        XCTAssertEqual(f.driver.adopted?.credential.accountID, f.scope.accountID)
        XCTAssertTrue(f.driver.adopted?.ticket is PickerTicket)
        XCTAssertEqual(f.driver.listCalls, 1)
        await f.picker.load(windowID: f.window, expectedFacadeID: UUID(), expectedLocator: f.repository.locator)
        await f.picker.load(windowID: f.window, expectedFacadeID: f.facade, expectedLocator: .imported(UUID()))
        XCTAssertEqual(f.driver.listCalls, 1)
    }

    func testNP01UnlistedAndStalePageSelectionCannotIssueReadback() async throws {
        let f = try PickerFixture(); defer { f.cleanup() }; try f.register(); await f.load()
        _ = await f.picker.select(libraryID: UUID(), windowID: f.window, expectedFacadeID: f.facade, expectedLocator: f.repository.locator)
        XCTAssertTrue(f.driver.readCalls.isEmpty)
        await f.accounts.logout(scope: f.scope, allSessions: false)
        _ = await f.select()
        XCTAssertTrue(f.driver.readCalls.isEmpty)
        XCTAssertTrue(try f.picker.observe(windowID: f.window).rows.isEmpty)
        XCTAssertNil(try f.repository.load())
    }

    func testNP02OldSheetCancellationCannotCancelReplacementRegistration() async throws {
        let f = try PickerFixture(); defer { f.cleanup() }; try f.register(); await f.load()
        let replacement = UUID()
        try f.picker.register(windowID: f.window, facadeID: replacement, repository: f.repository, acknowledged: true)
        await f.picker.load(windowID: f.window, expectedFacadeID: replacement, expectedLocator: f.repository.locator)
        f.driver.readBarrier = PickerBarrier()
        let selection = Task { await f.picker.select(libraryID: f.driver.row.libraryID, windowID: f.window, expectedFacadeID: replacement, expectedLocator: f.repository.locator) }
        await f.driver.readBarrier!.waitUntilEntered()
        f.picker.cancel(windowID: f.window, expectedFacadeID: f.facade, expectedLocator: f.repository.locator)
        f.driver.readBarrier!.release()
        let outcome = await selection.value; XCTAssertEqual(outcome, .associated)
        XCTAssertNotNil(try f.repository.load())
    }

    func testNP02LateReadbackCannotBindAfterCancelDetachReplacementLogoutOrDeletion() async throws {
        for event in ["cancel", "detach", "replace", "logout", "delete"] {
            let f = try PickerFixture(); defer { f.cleanup() }; try f.register()
            await f.load(); let barrier = PickerBarrier(); f.driver.readBarrier = barrier
            let selection = Task { await f.select() }
            await barrier.waitUntilEntered()
            switch event {
            case "cancel": f.picker.cancel(windowID: f.window, expectedFacadeID: f.facade, expectedLocator: f.repository.locator)
            case "detach": f.picker.unregister(windowID: f.window); f.accounts.detach(windowID: f.window)
            case "replace": try f.picker.register(windowID: f.window, facadeID: UUID(), repository: f.repository, acknowledged: true)
            case "logout": await f.accounts.logout(scope: f.scope, allSessions: false)
            default: _ = await f.accounts.deleteAccount(windowID: f.window, scope: f.scope)
            }
            barrier.release(); _ = await selection.value
            XCTAssertNil(try f.repository.load(), event)
            XCTAssertEqual(try Data(contentsOf: f.documentURL), f.documentBytes, event)
        }
    }

    func testNP02AccountBRemainsUsableWhileAccountAReadbackIsFenced() async throws {
        let f = try PickerFixture(); defer { f.cleanup() }; try f.register()
        let b = PickerDriver(account: UUID()), bw = UUID(), bf = UUID()
        let bs = try WorkspaceAccountScope(origin: f.scope.origin, profileID: "native", accountID: b.session.accountID)
        f.appendDriver(b); try f.accounts.attach(windowID: bw, scope: bs); await f.accounts.restore(windowID: bw)
        let br = try CloudLibraryBindingRepository(locator: .imported(UUID()), documentRoot: f.documents, supportRoot: f.support)
        try f.picker.register(windowID: bw, facadeID: bf, repository: br, acknowledged: true)
        await f.load(); f.driver.readBarrier = PickerBarrier()
        let blocked = Task { await f.select() }; await f.driver.readBarrier!.waitUntilEntered()
        await f.accounts.logout(scope: f.scope, allSessions: true)
        await f.picker.load(windowID: bw, expectedFacadeID: bf, expectedLocator: br.locator)
        let result = await f.picker.select(libraryID: b.row.libraryID, windowID: bw, expectedFacadeID: bf, expectedLocator: br.locator)
        XCTAssertEqual(result, .associated)
        XCTAssertEqual(try br.load()?.accountID, bs.accountID)
        f.driver.readBarrier!.release(); _ = await blocked.value
        XCTAssertNil(try f.repository.load())
    }

    func testNP03PaginationKeepsEightRowsAndSixteenPreviousCursors() async throws {
        let f = try PickerFixture(); defer { f.cleanup() }; try f.register()
        f.driver.paginate = true; await f.load()
        let view = try f.picker.observe(windowID: f.window)
        for _ in 0..<24 {
            XCTAssertLessThanOrEqual(view.rows.count, 8)
            await f.picker.next(windowID: f.window, expectedFacadeID: f.facade, expectedLocator: f.repository.locator)
            XCTAssertLessThanOrEqual(view.previousCursors.count, 16)
        }
        XCTAssertEqual(view.rows.count, 8)
        XCTAssertEqual(view.previousCursors.count, 16)
        XCTAssertEqual(f.driver.listCalls, 25)
        let calls = f.driver.listCalls
        await f.picker.previous(windowID: f.window, expectedFacadeID: f.facade, expectedLocator: f.repository.locator)
        XCTAssertEqual(f.driver.listCalls, calls + 1)
        XCTAssertNil(try f.repository.load())
    }

    func testNP04ListingNeverSubstitutesExactFreshReadbackAndAdmission() async throws {
        for failure in ["wrongID", "readThrow", "denied", "afterReadDenied", "noneRole", "gatedThrow"] {
            let f = try PickerFixture(); defer { f.cleanup() }; try f.register(); await f.load()
            f.driver.failure = failure
            _ = await f.select()
            XCTAssertEqual(f.driver.readCalls, failure == "denied" ? [] : [f.driver.row.libraryID], failure)
            XCTAssertNil(try f.repository.load(), failure)
            XCTAssertEqual(try Data(contentsOf: f.documentURL), f.documentBytes, failure)
        }
        let f = try PickerFixture(); defer { f.cleanup() }; try f.register(); await f.load()
        f.driver.readTitle = "Fresh authenticated title"
        let associated = await f.select(); XCTAssertEqual(associated, .associated)
        XCTAssertEqual(f.driver.readCalls, [f.driver.row.libraryID])
        XCTAssertEqual(f.driver.gatedCommits, 1)
    }

    func testNP05CompetingWindowsCASAndSharedAssociationUseActualRepository() async throws {
        let f = try PickerFixture(); defer { f.cleanup() }; try f.register()
        let second = UUID(); try f.accounts.attach(windowID: second, scope: f.scope)
        try f.picker.register(windowID: second, facadeID: f.facade, repository: f.repository, acknowledged: true)
        await f.load(); await f.picker.load(windowID: second, expectedFacadeID: f.facade, expectedLocator: f.repository.locator)
        f.driver.readBarrier = PickerBarrier(); let first = Task { await f.select() }
        await f.driver.readBarrier!.waitUntilEntered()
        let external = try CloudLibraryBinding(locator: f.repository.locator, origin: f.scope.origin.url.absoluteString, profileID: "native", accountID: f.scope.accountID, remoteLibraryID: UUID())
        try f.repository.save(external, replacing: nil)
        let bytes = try Data(contentsOf: f.repository.fileURL)
        f.driver.readBarrier!.release()
        let conflicted = await first.value; XCTAssertEqual(conflicted, .conflict)
        XCTAssertEqual(try Data(contentsOf: f.repository.fileURL), bytes)
        // Fresh operation must begin from actual disk, preserve explicit replacement CAS.
        f.driver.readBarrier = nil
        await f.load(); let associated = await f.select(); XCTAssertEqual(associated, .associated)
        let a = try f.picker.observe(windowID: f.window), b = try f.picker.observe(windowID: second)
        XCTAssertEqual(a.association, b.association)
        XCTAssertEqual(a.association, try f.repository.load())
    }

    func testNP06RestartAssociationPreservesExactDocumentsAndHistoryAndNP07InvalidatesDisplay() async throws {
        let f = try PickerFixture(); defer { f.cleanup() }; try f.register(); await f.load()
        let associated = await f.select(); XCTAssertEqual(associated, .associated)
        let record = try XCTUnwrap(f.repository.load())
        XCTAssertEqual(record.accountID, f.scope.accountID)
        XCTAssertEqual(record.remoteLibraryID, f.driver.row.libraryID)
        let cold = try CloudConnectionRegistry(), handle = try XCTUnwrap(cold.restore(f.repository))
        XCTAssertEqual(try cold.binding(for: handle), record)
        XCTAssertEqual(try Data(contentsOf: f.documentURL), f.documentBytes)
        XCTAssertEqual(try Data(contentsOf: f.historyURL), f.historyBytes)
        await f.accounts.logout(scope: f.scope, allSessions: false)
        XCTAssertNil(try f.picker.observe(windowID: f.window).association)
        XCTAssertEqual(try f.repository.load(), record, "Historical metadata is not authority and need not be deleted")
    }
}

private struct PickerTicket: WorkspaceAccountAdmissionTicket { let scope: WorkspaceAccountScope }
@MainActor private final class PickerAdmission: WorkspaceAccountAdmission {
    func capture(scope: WorkspaceAccountScope) throws -> any WorkspaceAccountAdmissionTicket { PickerTicket(scope: scope) }
    func beginEnrollment(expected: any WorkspaceAccountAdmissionTicket) throws -> any WorkspaceAccountAdmissionTicket { expected }
    func deny(expected: any WorkspaceAccountAdmissionTicket, reason: WorkspaceAccountDenialReason) throws -> any WorkspaceAccountAdmissionTicket { expected }
    func load(expected: any WorkspaceAccountAdmissionTicket) async throws -> WorkspaceAccountLoadedCredential? {
        let scope = (expected as! PickerTicket).scope
        return .init(credential: try WorkspaceCredential(origin: scope.origin, accountID: scope.accountID, token: String(repeating: "a", count: 43), profileID: scope.profileID), ticket: expected)
    }
    func remove(expected: any WorkspaceAccountAdmissionTicket) async throws {}
}
@MainActor private final class PickerDriver: WorkspaceAccountIdentityDriver, WorkspaceLibraryDiscoveryDriver {
    let session: WorkspaceAccountVerifiedSession
    let row: WorkspaceLibraryMetadata
    var adopted: WorkspaceAccountLoadedCredential?, listCalls = 0, readCalls: [UUID] = [], gatedCommits = 0
    var readBarrier: PickerBarrier?, paginate = false, failure = "", readTitle: String?, admissionRevoked = false
    init(account: UUID) {
        session = .init(accountID: account, sessionID: UUID(), expiresAt: Date().addingTimeInterval(3600))
        row = .init(libraryID: UUID(), title: "<script>metadata only</script>", role: .owner)
    }
    func adopt(_ loaded: WorkspaceAccountLoadedCredential) throws { adopted = loaded }
    func restore() async throws -> WorkspaceAccountVerifiedSession { session }
    func enroll() async throws -> WorkspaceAccountVerifiedSession { session }
    func save(expected: any WorkspaceAccountAdmissionTicket) async throws -> any WorkspaceAccountAdmissionTicket { expected }
    func discardEnrollment() async -> WorkspaceLogoutOutcome { .confirmedRemoteRevocation }
    func logout(allSessions: Bool) async -> WorkspaceLogoutOutcome { .confirmedRemoteRevocation }
    func deleteFreshEnrollment() async throws -> WorkspaceAccountDeletionOutcome { .confirmedAccountTombstone }
    func invalidate() async {}
    func cancelProof() {}
    func listLibraries(after: UUID?) async throws -> WorkspaceLibraryMetadataPage {
        listCalls += 1
        if !paginate { return .init(libraries: [row], nextAfter: nil) }
        let rows = (0..<8).map { WorkspaceLibraryMetadata(libraryID: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", listCalls * 100 + $0))!, title: "Page \(listCalls) row \($0)", role: .viewer) }
        return .init(libraries: rows, nextAfter: rows.last!.libraryID)
    }
    func libraryMetadata(id: UUID) async throws -> WorkspaceLibraryMetadata {
        readCalls.append(id); await readBarrier?.enter()
        if failure == "readThrow" { throw WorkspaceClientError.unavailable }; if failure == "afterReadDenied" { admissionRevoked = true }
        return .init(libraryID: failure == "wrongID" ? UUID() : id, title: readTitle ?? row.title, role: failure == "noneRole" ? .none : .viewer)
    }
    func validateAdmission() throws { if failure == "denied" || admissionRevoked { throw WorkspaceClientError.unavailable } }
    func withAdmittedCredential<T>(_ body: () throws -> T) throws -> T {
        if failure == "gatedThrow" { throw WorkspaceClientError.unavailable }
        try validateAdmission(); gatedCommits += 1; return try body()
    }
}
@MainActor private final class PickerBarrier {
    private var entered = false, observers: [CheckedContinuation<Void, Never>] = []
    private var waiter: CheckedContinuation<Void, Never>?
    func enter() async { entered = true; observers.forEach { $0.resume() }; observers.removeAll(); await withCheckedContinuation { waiter = $0 } }
    func waitUntilEntered() async { if entered { return }; await withCheckedContinuation { observers.append($0) } }
    func release() { waiter?.resume(); waiter = nil }
}
@MainActor private final class PickerFixture {
    let root = URL(fileURLWithPath: "/private/tmp/NativePicker-" + UUID().uuidString)
    let documents: URL, support: URL, repository: CloudLibraryBindingRepository
    let documentURL: URL, historyURL: URL, documentBytes: Data, historyBytes: Data
    let window = UUID(), facade = UUID(), scope: WorkspaceAccountScope, driver: PickerDriver
    let accounts: WorkspaceAccountCoordinator, registry: CloudConnectionRegistry, picker: WorkspaceLibraryPickerCoordinator
    init() throws {
        documents = root.appendingPathComponent("Documents"); support = root.appendingPathComponent("Support")
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let directory = documents.appendingPathComponent("Skriptum")
        let store = try LibraryStore(directory: directory)
        let space = try store.createSpace(title: "Owned local library")
        let page = try store.createPage(spaceID: space.id, title: "Exact bytes", markdown: "e\u{301}\r\n🦊")
        try store.setBlocks(pageID: page.id, blocks: [Block(markdown: "e\u{301}\r\n🦊 preserved")], baseRevision: page.revision)
        documentURL = directory.appendingPathComponent("library.json"); historyURL = documentURL
        documentBytes = try Data(contentsOf: documentURL); historyBytes = documentBytes
        scope = try WorkspaceAccountScope(origin: WorkspaceOrigin("https://workspace.example"), profileID: "native", accountID: UUID())
        driver = PickerDriver(account: scope.accountID)
        repository = try CloudLibraryBindingRepository(locator: .primary, documentRoot: documents, supportRoot: support)
        registry = try CloudConnectionRegistry()
        let deployment = try WorkspaceDeploymentConfiguration(origin: "https://workspace.example", profileID: "native", consentVersion: "v1", operatorName: "Owned test", privacyURL: "https://workspace.example/privacy", serviceURL: "https://workspace.example/service", consentDisclosure: "Association only.")
        let queue = PickerDriverQueue(driver)
        accounts = try WorkspaceAccountCoordinator(deployment: deployment, admission: PickerAdmission(), makeIdentity: { _, _ in queue.next() })
        picker = WorkspaceLibraryPickerCoordinator(accounts: accounts, registry: registry)
        // queue is retained by account factory; appendDriver uses that queue below.
        driverQueue = queue
    }
    private let driverQueue: PickerDriverQueue
    func appendDriver(_ driver: PickerDriver) { driverQueue.drivers.append(driver) }
    func register(acknowledged: Bool = true) throws { try accounts.attach(windowID: window, scope: scope); try picker.register(windowID: window, facadeID: facade, repository: repository, acknowledged: acknowledged) }
    func load() async { if case .active = accounts.state(windowID: window) {} else { await accounts.restore(windowID: window) }; await picker.load(windowID: window, expectedFacadeID: facade, expectedLocator: repository.locator) }
    func select() async -> WorkspaceLibraryPickerOutcome { await picker.select(libraryID: driver.row.libraryID, windowID: window, expectedFacadeID: facade, expectedLocator: repository.locator) }
    func cleanup() { try? FileManager.default.removeItem(at: root) }
}
@MainActor private final class PickerDriverQueue {
    var drivers: [PickerDriver]; private let fallback: PickerDriver
    init(_ first: PickerDriver) { drivers = [first]; fallback = first }
    func next() -> PickerDriver { drivers.isEmpty ? fallback : drivers.removeFirst() }
}
