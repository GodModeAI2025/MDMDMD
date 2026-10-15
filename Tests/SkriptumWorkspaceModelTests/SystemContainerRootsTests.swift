import Foundation
import Darwin
import Testing
import SkriptumCore
@testable import SkriptumWorkspaceModel

struct SystemContainerRootsTests {
    @Test func foundationSystemAliasMustBeCanonicalBeforeNoFollowOutboxCreation() throws {
        let name = "scriptum-system-root-" + UUID().uuidString
        let physical = URL(fileURLWithPath: "/private/tmp", isDirectory: true).appendingPathComponent(name, isDirectory: true)
        let systemAlias = URL(fileURLWithPath: "/tmp", isDirectory: true).appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: physical, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: physical) }
        let location = systemAlias.appendingPathComponent("Library/Application Support", isDirectory: true)
        let expected = physical.appendingPathComponent("Library/Application Support", isDirectory: true)
        let canonical = WorkspaceSystemContainerRoots.canonicalSystemDirectory(location)
        #expect(canonical.path == expected.path)
        let directory = canonical.appendingPathComponent("ICloudSync", isDirectory: true)
        let scope = try ICloudSyncScope(accountID: "synthetic-account", libraryID: UUID())
        let change = ICloudSyncChange(recordID: .init(kind: .page, id: UUID()), revisionID: UUID(), operation: .upsert, payload: Data("café e\u{301} 🦊\r\n".utf8))
        let journal = try ICloudSyncJournal(directory: directory, scope: scope)
        try journal.enqueue(change)
        let bytes = try Data(contentsOf: journal.fileURL)
        #expect(try ICloudSyncJournal(directory: directory, scope: scope).pendingBatch() == [change])
        #expect(try Data(contentsOf: journal.fileURL) == bytes)
        #expect(WorkspaceSystemContainerRoots.canonicalSystemDirectory(location).path == expected.path)
    }

    @Test func canonicalSystemRootDoesNotAuthorizeLinkedInteriorOutbox() throws {
        let name = "scriptum-root-link-" + UUID().uuidString
        let physical = URL(fileURLWithPath: "/private/tmp", isDirectory: true).appendingPathComponent(name, isDirectory: true)
        let systemAlias = URL(fileURLWithPath: "/tmp", isDirectory: true).appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: physical, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: physical) }
        let outside = physical.appendingPathComponent("untouched", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: false)
        let marker = outside.appendingPathComponent("original.txt")
        let original = Data("must remain exact\r\ne\u{301}".utf8)
        try original.write(to: marker)
        let canonical = WorkspaceSystemContainerRoots.canonicalSystemDirectory(systemAlias)
        let linked = canonical.appendingPathComponent("ICloudSync", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: linked, withDestinationURL: outside)
        let scope = try ICloudSyncScope(accountID: "synthetic-account", libraryID: UUID())
        #expect(throws: ICloudSyncJournalError.unsafeFile) { try ICloudSyncJournal(directory: linked, scope: scope) }
        #expect(try Data(contentsOf: marker) == original)
        #expect(try FileManager.default.contentsOfDirectory(atPath: outside.path) == ["original.txt"])
    }

    @Test func systemRootsPermitNoFollowTraversalAndKeepOwnedLocator() throws {
        for root in [WorkspaceSystemContainerRoots.documents, WorkspaceSystemContainerRoots.applicationSupport] {
            #expect(root.isFileURL)
            var descriptor = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
            guard descriptor >= 0 else { throw CocoaError(.fileReadUnknown) }
            defer { close(descriptor) }
            for component in root.pathComponents.dropFirst() {
                let next = openat(descriptor, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                #expect(next >= 0)
                guard next >= 0 else { return }
                close(descriptor); descriptor = next
            }
        }
        let library = try LibraryStoragePaths.libraryDirectory(locator: .primary, documentRoot: WorkspaceSystemContainerRoots.documents)
        #expect(try LibraryStoragePaths.locator(libraryDirectory: library, documentRoot: WorkspaceSystemContainerRoots.documents) == .primary)
    }
}
