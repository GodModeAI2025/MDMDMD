import Foundation
import Testing
@testable import SkriptumWorkspaceClient

private let discoveryFirst = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
private let discoverySecond = UUID(uuidString: "00000000-0000-4000-8000-000000000002")!
private func discoveryRow(_ id: UUID = discoveryFirst, title: String = "e\u{301}\r\n🦊", role: String = "viewer") -> [String: Any] {
    ["libraryID": id.uuidString, "title": title, "role": role]
}
private func discoveryBytes(_ value: Any) throws -> Data {
    try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
}

@Test func wd03DiscoveryPaginationPreservesExactTextAndPermissionVocabulary() throws {
    let data = try discoveryBytes(["libraries": [discoveryRow(), discoveryRow(discoverySecond, role: "owner")], "nextAfter": discoverySecond.uuidString])
    let page = try WorkspaceLibraryWire.page(data, after: nil)
    #expect(page.libraries.count == 2)
    #expect(page.libraries[0].libraryID == discoveryFirst)
    #expect(page.libraries[0].title.utf8.elementsEqual("e\u{301}\r\n🦊".utf8))
    #expect(page.libraries[1].role == .owner)
    #expect(page.nextAfter == discoverySecond)
    let empty = try WorkspaceLibraryWire.page(discoveryBytes(["libraries": [], "nextAfter": discoverySecond.uuidString]), after: discoveryFirst)
    #expect(empty.libraries.isEmpty)
    #expect(empty.nextAfter == discoverySecond)
    #expect(try WorkspaceLibraryWire.page(discoveryBytes(["libraries": [], "nextAfter": NSNull()]), after: nil).nextAfter == nil)
}

@Test func wd03DiscoveryRejectsExcessDuplicateUnorderedAndNonadvancingPages() throws {
    let excessive = (1...9).map { number in
        discoveryRow(UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", number))!)
    }
    #expect(throws: WorkspaceClientError.invalidResponse) {
        try WorkspaceLibraryWire.page(discoveryBytes(["libraries": excessive, "nextAfter": NSNull()]), after: nil)
    }
    let invalid: [[String: Any]] = [
        ["libraries": [discoveryRow(), discoveryRow()], "nextAfter": NSNull()],
        ["libraries": [discoveryRow(discoverySecond), discoveryRow()], "nextAfter": NSNull()],
        ["libraries": [discoveryRow()], "nextAfter": discoveryFirst.uuidString],
        ["libraries": [], "nextAfter": discoveryFirst.uuidString],
        ["libraries": [discoveryRow(discoverySecond)], "nextAfter": discoveryFirst.uuidString],
        ["libraries": [], "nextAfter": false],
        ["libraries": [], "nextAfter": NSNull(), "token": "forbidden"]
    ]
    for row in invalid {
        #expect(throws: WorkspaceClientError.invalidResponse) {
            try WorkspaceLibraryWire.page(discoveryBytes(row), after: discoveryFirst)
        }
    }
}

@Test func wd04DiscoverySpecificMetadataRejectsWrongIDAndMalformedRows() throws {
    #expect(try WorkspaceLibraryWire.metadata(discoveryBytes(discoveryRow()), expectedID: discoveryFirst).role == .viewer)
    var extra = discoveryRow(); extra["accountID"] = UUID().uuidString
    var missing = discoveryRow(); missing.removeValue(forKey: "title")
    var malformed = discoveryRow(); malformed["libraryID"] = "not-a-uuid"
    var booleanTitle = discoveryRow(); booleanTitle["title"] = true
    for row in [extra, missing, malformed, booleanTitle, discoveryRow(discoverySecond), discoveryRow(role: "none"), discoveryRow(role: "admin"), discoveryRow(title: ""), discoveryRow(title: String(repeating: "x", count: 4097))] {
        #expect(throws: WorkspaceClientError.invalidResponse) {
            try WorkspaceLibraryWire.metadata(discoveryBytes(row), expectedID: discoveryFirst)
        }
    }
}

@Test func wd06DiscoveryEscapedTitleBudgetAndStructuralValidation() throws {
    let title = String(repeating: "\u{0001}", count: 4096)
    let rows = (1...8).map { number in
        discoveryRow(UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", number))!, title: title)
    }
    let bytes = try discoveryBytes(["libraries": rows, "nextAfter": NSNull()])
    #expect(bytes.count > 24_576)
    #expect(bytes.count < 256 * 1024)
    #expect(try WorkspaceLibraryWire.page(bytes, after: nil).libraries.count == 8)
    let duplicate = Data("{\"libraries\":[],\"libraries\":[],\"nextAfter\":null}".utf8)
    let nestedDuplicate = Data("{\"libraries\":[{\"libraryID\":\"\(discoveryFirst)\",\"title\":\"a\",\"title\":\"b\",\"role\":\"viewer\"}],\"nextAfter\":null}".utf8)
    for invalid in [duplicate, nestedDuplicate, Data(repeating: 32, count: 256 * 1024 + 1), Data([0xff])] {
        #expect(throws: WorkspaceClientError.invalidResponse) { try WorkspaceLibraryWire.page(invalid, after: nil) }
    }
}

@Test func wd05DiscoveryRequiresActualActorAdmission() async throws {
    let client = try WorkspaceIdentityClient(origin: WorkspaceOrigin("https://workspace.example"), profileID: "apple", consentVersion: "v1")
    do { _ = try await client.listLibraries(after: nil); Issue.record("Signed-out actor started metadata discovery") }
    catch { #expect(error as? WorkspaceClientError == .signedOut) }
    do { _ = try await client.libraryMetadata(id: discoveryFirst); Issue.record("Signed-out actor read metadata") }
    catch { #expect(error as? WorkspaceClientError == .signedOut) }
}

@Test(arguments: [false, true]) func wd05DiscoveryLogoutFencesHeldActualTransportReply(single: Bool) async throws {
    let fixture = try await OwnedDiscoveryFixture()
    defer { fixture.close() }
    let origin = try WorkspaceOrigin.loopbackForTesting(fixture.value.origin)
    let credential = try WorkspaceCredential(origin: origin, accountID: fixture.value.accountID, token: fixture.value.token, profileID: "apple")
    let client = try WorkspaceIdentityClient(origin: origin, profileID: "apple", consentVersion: "v1", credential: credential)
    let read = Task {
        if single { _ = try await client.libraryMetadata(id: discoveryFirst) }
        else { _ = try await client.listLibraries(after: nil) }
    }
    var pending = false
    for _ in 0..<100 {
        if try await fixture.control("/control/state")["pending"] as? Bool == true { pending = true; break }
        try await Task.sleep(for: .milliseconds(20))
    }
    #expect(pending, "Actual metadata request did not reach the owned transport barrier")
    guard pending else { read.cancel(); _ = try? await read.value; return }
    #expect(await client.logoutCurrentSession() == .confirmedRemoteRevocation)
    _ = try await fixture.control("/control/release")
    do { try await read.value; Issue.record("A reply captured before logout exposed metadata after admission was cleared") }
    catch { #expect(error as? WorkspaceClientError == .signedOut) }
    #expect(await client.admissionState == .signedOut)
}

private final class OwnedDiscoveryFixture {
    struct Value: Decodable { let origin: String; let accountID: UUID; let token: String }
    let value: Value
    private let directory: URL
    private let process: Process
    private let input: Pipe
    init() async throws {
        let directory = URL(fileURLWithPath: "/private/tmp").appendingPathComponent("ScriptumDiscovery-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let file = directory.appendingPathComponent("fixture.json")
        let script = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Verification/library-discovery-fixture.mjs")
        let process = Process(), input = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["node", script.path, file.path]
        process.standardInput = input
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            for _ in 0..<100 {
                if FileManager.default.fileExists(atPath: file.path) { break }
                try await Task.sleep(for: .milliseconds(20))
            }
            value = try JSONDecoder().decode(Value.self, from: Data(contentsOf: file))
        } catch {
            if process.isRunning { process.terminate(); process.waitUntilExit() }
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
        self.directory = directory; self.process = process; self.input = input
    }
    func control(_ path: String) async throws -> [String: Any] {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil; configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = 2; configuration.timeoutIntervalForResource = 2
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(from: #require(URL(string: value.origin + path)))
        guard data.count <= 1024, (response as? HTTPURLResponse)?.statusCode == 200,
              let row = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw WorkspaceClientError.invalidResponse }
        return row
    }
    func close() {
        if process.isRunning { process.terminate(); process.waitUntilExit() }
        try? FileManager.default.removeItem(at: directory)
    }
}
