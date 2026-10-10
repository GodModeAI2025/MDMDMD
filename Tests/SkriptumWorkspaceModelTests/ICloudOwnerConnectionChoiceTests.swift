import Foundation
import Testing
import SkriptumCore
@testable import SkriptumWorkspaceModel

@MainActor struct ICloudOwnerConnectionChoiceTests {
    @Test func optInPersistsAndDisconnectFencesOldActivationWithoutRemovingData() throws {
        let directory = URL(fileURLWithPath: "/private/tmp/OwnerChoice-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let id = UUID(), choice = ICloudOwnerConnectionChoice(directory: directory, libraryID: UUID())
        #expect(try choice.load() == nil)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
        let own = ICloudOwnerConnectionChoice(directory: directory, libraryID: id)
        let scope = try ICloudSyncScope(accountID: "account-e\u{301}", libraryID: id)
        let first = try own.enable(scope: scope, replacing: nil, intent: own.runtimeRevision)
        let reopened = ICloudOwnerConnectionChoice(directory: directory, libraryID: id)
        #expect(try reopened.load() == first)
        #expect(try reopened.admit(accountID: scope.accountID, selection: first) == scope)
        #expect(throws: ICloudOwnerConnectionChoiceError.accountChanged) {
            try reopened.admit(accountID: "account-é", selection: first)
        }
        let sentinel = directory.appendingPathComponent("durable-outbox-sentinel")
        try Data("preserve".utf8).write(to: sentinel)
        try reopened.disable()
        let disabled = try #require(try own.load())
        #expect(!disabled.enabled && disabled.scope == scope && disabled.revision != first.revision)
        #expect(throws: ICloudOwnerConnectionChoiceError.superseded) { try own.enable(scope: scope, replacing: first, intent: own.runtimeRevision) }
        #expect(throws: ICloudOwnerConnectionChoiceError.superseded) { try own.enable(scope: scope, replacing: nil, intent: own.runtimeRevision) }
        #expect(try Data(contentsOf: sentinel) == Data("preserve".utf8))
        #expect(throws: ICloudOwnerConnectionChoiceError.accountChanged) { try own.admit(accountID: "new-account", selection: disabled) }
        let changed = try own.admit(accountID: "new-account", selection: disabled, allowAccountChange: true)
        let next = try own.enable(scope: changed, replacing: disabled, intent: own.runtimeRevision)
        #expect(try own.load() == next)
    }
    @Test func foreignMalformedOversizedAndSymlinkMetadataNeverGrantsResume() throws {
        let directory = URL(fileURLWithPath: "/private/tmp/OwnerChoice-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let id = UUID(), choice = ICloudOwnerConnectionChoice(directory: directory, libraryID: UUID())
        let own = ICloudOwnerConnectionChoice(directory: directory, libraryID: id)
        _ = try own.enable(scope: ICloudSyncScope(accountID: "owned", libraryID: id), replacing: nil, intent: own.runtimeRevision)
        #expect(try choice.load() == nil)
        let valid = try Data(contentsOf: own.fileURL)
        var object = try #require(JSONSerialization.jsonObject(with: valid) as? [String: Any])
        object["containerIdentifier"] = "iCloud.someone.else"
        try JSONSerialization.data(withJSONObject: object).write(to: own.fileURL)
        #expect(throws: (any Error).self) { try own.load() }
        object["containerIdentifier"] = ICloudOwnerConnectionChoice.containerIdentifier
        object["libraryID"] = UUID().uuidString
        try JSONSerialization.data(withJSONObject: object).write(to: own.fileURL)
        #expect(throws: (any Error).self) { try own.load() }
        try own.disable()
        #expect(try own.load()?.enabled == false)
        try Data(repeating: 65, count: 4097).write(to: own.fileURL)
        #expect(throws: (any Error).self) { try own.load() }
        try own.disable()
        let target = directory.appendingPathComponent("outside-descriptor")
        try valid.write(to: target)
        try FileManager.default.removeItem(at: own.fileURL)
        try FileManager.default.createSymbolicLink(at: own.fileURL, withDestinationURL: target)
        #expect(throws: (any Error).self) { try own.load() }
        try own.disable()
        #expect(try Data(contentsOf: target) == valid)
        #expect(try own.load()?.enabled == false)
    }
    @Test func resumeRejectsChangedAccountAndConcurrentDisconnectBeforeCreatingTransport() async throws {
        let root = URL(fileURLWithPath: "/private/tmp/OwnerResume-" + UUID().uuidString)
        let suite = "test.ownerresume." + UUID().uuidString
        defer { try? FileManager.default.removeItem(at: root); UserDefaults.standard.removePersistentDomain(forName: suite) }
        let documents = root.appendingPathComponent("Documents")
        let store = try LibraryStore(directory: documents.appendingPathComponent("Skriptum"))
        let space = try store.createSpace(title: "Offline")
        _ = try store.createPage(spaceID: space.id, title: "Page", markdown: "e\u{301}\r\n🦊")
        let library = try WritingLibrary(store: store, documentRoot: documents, supportRoot: root.appendingPathComponent("Support"), preferences: #require(UserDefaults(suiteName: suite)))
        let bytes = try Data(contentsOf: store.directory.appendingPathComponent("library.json"))
        let choice = try library.iCloudConnectionChoice()
        var lookups = 0
        let noSelection = ICloudLibrarySession(library: library, provisioned: true, accountLookup: { lookups += 1; return "new-account" })
        await noSelection.resumeSavedConnection()
        #expect(lookups == 0 && noSelection.status == .inactive)
        let scope = try ICloudSyncScope(accountID: "old-account", libraryID: library.ownedICloudLibraryID())
        let selected = try choice.enable(scope: scope, replacing: nil, intent: choice.runtimeRevision)
        await noSelection.resumeSavedConnection()
        #expect(lookups == 1 && noSelection.status == .accountChanged)
        #expect(try choice.load() == selected)
        let raced = ICloudLibrarySession(library: library, provisioned: true, accountLookup: {
            try choice.disable()
            return "old-account"
        })
        await raced.resumeSavedConnection()
        #expect(raced.status == .failed)
        #expect(try choice.load()?.enabled == false)
        let files = try FileManager.default.contentsOfDirectory(atPath: library.iCloudStorageDirectory().path)
        #expect(files == [choice.fileURL.lastPathComponent])
        #expect(try Data(contentsOf: store.directory.appendingPathComponent("library.json")) == bytes)
        let unprovisioned = ICloudLibrarySession(library: library, provisioned: false, accountLookup: { Issue.record("Unprovisioned account lookup"); return "old-account" })
        await unprovisioned.resumeSavedConnection(); await unprovisioned.activate(); await unprovisioned.stop()
        #expect(unprovisioned.status == .notConfigured)
        #expect(try choice.load()?.enabled == false)
    }
    @Test func failedDisconnectWriteBlocksNewSessionsAndStaleActivationUntilExplicitDurableEnable() async throws {
        let root = URL(fileURLWithPath: "/private/tmp/OwnerDisconnectFailure-" + UUID().uuidString)
        let suite = "test.ownerdisconnectfailure." + UUID().uuidString
        defer { try? FileManager.default.removeItem(at: root); UserDefaults.standard.removePersistentDomain(forName: suite) }
        let documents = root.appendingPathComponent("Documents")
        let store = try LibraryStore(directory: documents.appendingPathComponent("Skriptum"))
        let space = try store.createSpace(title: "Offline")
        _ = try store.createPage(spaceID: space.id, title: "Page", markdown: "e\u{301}\r\n🦊")
        let library = try WritingLibrary(store: store, documentRoot: documents, supportRoot: root.appendingPathComponent("Support"), preferences: #require(UserDefaults(suiteName: suite)))
        let choice = try library.iCloudConnectionChoice()
        let scope = try ICloudSyncScope(accountID: "old-account", libraryID: library.ownedICloudLibraryID())
        let selection = try choice.enable(scope: scope, replacing: nil, intent: choice.runtimeRevision)
        let metadata = try Data(contentsOf: choice.fileURL)
        let manuscript = try Data(contentsOf: store.directory.appendingPathComponent("library.json"))
        let stale = choice.runtimeRevision
        let failing = ICloudOwnerConnectionChoice(directory: library.iCloudStorageDirectory(), libraryID: scope.libraryID,
            beforeWrite: { throw CocoaError(.fileWriteOutOfSpace) })
        #expect(throws: CocoaError.self) { try failing.disable() }
        #expect(try Data(contentsOf: choice.fileURL) == metadata)
        let stillSelected = try choice.load()
        #expect(stillSelected == selection && choice.isRuntimeDisconnected)
        let independent = ICloudOwnerConnectionChoice(directory: root.appendingPathComponent("OtherSupport"), libraryID: scope.libraryID)
        #expect(!independent.isRuntimeDisconnected)
        let otherLibrary = ICloudOwnerConnectionChoice(directory: library.iCloudStorageDirectory(), libraryID: UUID())
        #expect(!otherLibrary.isRuntimeDisconnected)
        #expect(throws: ICloudOwnerConnectionChoiceError.superseded) { try choice.confirm(selection, intent: stale) }
        #expect(throws: ICloudOwnerConnectionChoiceError.superseded) { try choice.enable(scope: scope, replacing: selection, intent: stale) }
        var lookups = 0
        let replacement = ICloudLibrarySession(library: library, provisioned: true, accountLookup: {
            lookups += 1; throw CocoaError(.userCancelled)
        })
        await replacement.resumeSavedConnection()
        #expect(lookups == 0 && replacement.status == .inactive)
        #expect(throws: CocoaError.self) { try failing.enable(scope: scope, replacing: selection, intent: failing.runtimeRevision) }
        #expect(choice.isRuntimeDisconnected)
        // A new explicit enable clears the process fence only after its actual
        // owned atomic write succeeds; no CloudKit transport is supplied here.
        let renewed = try choice.enable(scope: scope, replacing: selection, intent: choice.runtimeRevision)
        #expect(!choice.isRuntimeDisconnected && renewed.revision != selection.revision)
        #expect(try Data(contentsOf: store.directory.appendingPathComponent("library.json")) == manuscript)
    }

}
