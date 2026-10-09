import Foundation
import Darwin
import Testing
import SkriptumCore
@testable import SkriptumWorkspaceModel

struct SystemContainerRootsTests {
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
