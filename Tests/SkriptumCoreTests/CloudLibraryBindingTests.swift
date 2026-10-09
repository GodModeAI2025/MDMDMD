import Foundation
import Testing
@testable import SkriptumCore

struct CloudLibraryBindingTests {
    func fixture() throws -> (URL, CloudLibraryBindingRepository, CloudLibraryBinding) {
        let root = URL(fileURLWithPath: "/private/tmp/CloudBinding-" + UUID().uuidString, isDirectory: true)
        let locator = OwnedLibraryLocator.imported(UUID())
        let repository = try CloudLibraryBindingRepository(locator: locator, documentRoot: root.appending(path: "Documents"), supportRoot: root.appending(path: "Support"))
        let binding = try CloudLibraryBinding(locator: locator, origin: "https://workspace.example", profileID: "apple-native", accountID: UUID(), remoteLibraryID: UUID())
        return (root, repository, binding)
    }
    @Test func restartExplicitCASAndScopedRemoval() throws {
        let (root, repository, binding) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        #expect(try repository.load() == nil)
        try repository.save(binding, replacing: nil)
        let reopened = try CloudLibraryBindingRepository(locator: binding.locator, documentRoot: root.appending(path: "Documents"), supportRoot: root.appending(path: "Support"))
        #expect(try reopened.load() == binding)
        let changed = try CloudLibraryBinding(locator: binding.locator, origin: binding.origin, profileID: binding.profileID, accountID: UUID(), remoteLibraryID: UUID())
        let bytes = try Data(contentsOf: repository.fileURL)
        #expect(throws: CloudLibraryBindingError.conflict) { try reopened.save(changed, replacing: nil) }
        #expect(try Data(contentsOf: repository.fileURL) == bytes)
        try reopened.save(changed, replacing: binding)
        #expect(throws: CloudLibraryBindingError.conflict) { try repository.remove(expected: binding) }
        try repository.remove(expected: changed)
        #expect(try repository.load() == nil)
    }
    @Test func primaryAndTwoImportsAreIsolated() throws {
        let (root, _, _) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let account = UUID(), remote = UUID()
        var records: [(CloudLibraryBindingRepository, CloudLibraryBinding)] = []
        for locator in [OwnedLibraryLocator.primary, .imported(UUID()), .imported(UUID())] {
            let repository = try CloudLibraryBindingRepository(locator: locator, documentRoot: root.appending(path: "Documents"), supportRoot: root.appending(path: "Support"))
            let value = try CloudLibraryBinding(locator: locator, origin: "https://workspace.example", profileID: "p", accountID: account, remoteLibraryID: remote)
            #expect(try repository.load() == nil); try repository.save(value, replacing: nil)
            #expect(try repository.load() == value)
            records.append((repository, value))
        }
        try records[1].0.remove(expected: records[1].1)
        #expect(try records[1].0.load() == nil)
        #expect(try records[0].0.load() == records[0].1)
        #expect(try records[2].0.load() == records[2].1)
    }
    @Test func malformedWrongScopeAndOversizePreserveBytes() throws {
        let (root, repository, binding) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        try repository.save(binding, replacing: nil)
        let valid = try Data(contentsOf: repository.fileURL)
        var object = try #require(JSONSerialization.jsonObject(with: valid) as? [String: Any])
        for field in ["schemaVersion", "profileID", "origin", "locator", "token"] {
            var bad = object
            switch field {
            case "schemaVersion": bad[field] = 2
            case "profileID": bad[field] = ""
            case "origin": bad[field] = "http://workspace.example"
            case "locator": bad[field] = ["schemaVersion": 1, "kind": "primary"]
            default: bad[field] = "forbidden"
            }
            let bytes = try JSONSerialization.data(withJSONObject: bad); try bytes.write(to: repository.fileURL)
            #expect(throws: (any Error).self) { try repository.load() }
            #expect(try Data(contentsOf: repository.fileURL) == bytes)
        }
        object["origin"] = "https://workspace.example/"
        try JSONSerialization.data(withJSONObject: object).write(to: repository.fileURL)
        #expect(throws: (any Error).self) { try repository.load() }
        let large = Data(repeating: 32, count: 8193); try large.write(to: repository.fileURL)
        #expect(throws: CloudLibraryBindingError.oversized) { try repository.load() }
        #expect(try Data(contentsOf: repository.fileURL) == large)
    }
    @Test func linksAndFailedReplacementPreserveOwnedFiles() throws {
        let (root, repository, binding) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        try repository.save(binding, replacing: nil)
        let bytes = try Data(contentsOf: repository.fileURL)
        let parent = repository.fileURL.deletingLastPathComponent()
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: parent.path)
        do { #expect(throws: (any Error).self) { try repository.save(binding, replacing: binding) } }
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: parent.path)
        #expect(try Data(contentsOf: repository.fileURL) == bytes)
        let outside = root.appending(path: "outside.json"); try bytes.write(to: outside)
        try FileManager.default.removeItem(at: repository.fileURL)
        try FileManager.default.createSymbolicLink(at: repository.fileURL, withDestinationURL: outside)
        #expect(throws: CloudLibraryBindingError.unsafeFile) { try repository.load() }
        #expect(throws: (any Error).self) { try repository.save(binding, replacing: binding) }
        #expect(try Data(contentsOf: outside) == bytes)
    }
    @Test func strictOriginAndProfile() throws {
        let locator = OwnedLibraryLocator.primary
        for origin in ["http://example.com", "https://u:p@example.com", "https://example.com/a", "https://example.com?x=1", "https://example.com/%2e"] {
            #expect(throws: CloudLibraryBindingError.invalidRecord) { try CloudLibraryBinding(locator: locator, origin: origin, profileID: "p", accountID: UUID(), remoteLibraryID: UUID()) }
        }
        #expect(try CloudLibraryBinding(locator: locator, origin: "https://EXAMPLE.com:443/", profileID: "p", accountID: UUID(), remoteLibraryID: UUID()).origin == "https://example.com")
    }
}

extension CloudLibraryBindingTests {
    @Test func decodedMetadataMustValidateAndCanonicalRecordsRejectDuplicates() throws {
        let (root, repository, binding) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        try repository.save(binding, replacing: nil)
        let valid = try Data(contentsOf: repository.fileURL)
        var object = try #require(JSONSerialization.jsonObject(with: valid) as? [String: Any])
        object["profileID"] = ""
        let invalid = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: (any Error).self) { try JSONDecoder().decode(CloudLibraryBinding.self, from: invalid) }
        let duplicate = Data(("{\"schemaVersion\":1," + String(decoding: valid, as: UTF8.self).dropFirst()).utf8)
        try duplicate.write(to: repository.fileURL)
        #expect(throws: CloudLibraryBindingError.invalidRecord) { try repository.load() }
        #expect(try Data(contentsOf: repository.fileURL) == duplicate)
    }
    @Test func ancestorLinkNonregularFileAndScopedRemove() throws {
        let (root, repository, binding) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        try repository.save(binding, replacing: nil)
        let sibling = repository.fileURL.deletingLastPathComponent().appending(path: "unrelated.txt")
        let content = Data("Keep".utf8); try content.write(to: sibling)
        try repository.remove(expected: binding)
        #expect(try Data(contentsOf: sibling) == content)
        try FileManager.default.createDirectory(at: repository.fileURL, withIntermediateDirectories: false)
        #expect(throws: CloudLibraryBindingError.unsafeFile) { try repository.load() }
        try FileManager.default.removeItem(at: repository.fileURL)
        let parent = repository.fileURL.deletingLastPathComponent(), moved = root.appending(path: "moved")
        try FileManager.default.moveItem(at: parent, to: moved)
        try FileManager.default.createSymbolicLink(at: parent, withDestinationURL: moved)
        #expect(throws: CloudLibraryBindingError.unsafeFile) { try repository.load() }
        #expect(throws: CloudLibraryBindingError.unsafeFile) { try repository.save(binding, replacing: nil) }
        #expect(try Data(contentsOf: moved.appending(path: "unrelated.txt")) == content)
    }
}
