import Foundation
import Testing
@testable import SkriptumCore

struct OwnedLibraryLocatorTests {
    @Test func locatorsRoundTripAndDeriveOnlyOwnedRelativeScopes() throws {
        let root = URL(fileURLWithPath: "/owned/Documents", isDirectory: true), id = UUID()
        for locator in [OwnedLibraryLocator.primary, .imported(id)] {
            let data = try JSONEncoder().encode(locator)
            #expect(try JSONDecoder().decode(OwnedLibraryLocator.self, from: data) == locator)
            let path = try LibraryStoragePaths.libraryDirectory(locator: locator, documentRoot: root)
            #expect(try LibraryStoragePaths.locator(libraryDirectory: path, documentRoot: root) == locator)
        }
        #expect(throws: LibraryStoragePathError.outsideDocumentRoot) {
            try LibraryStoragePaths.locator(libraryDirectory: URL(fileURLWithPath: "/other/Skriptum"), documentRoot: root)
        }
        #expect(throws: LibraryStoragePathError.invalidOwnedLibrary) {
            try LibraryStoragePaths.locator(libraryDirectory: root.appending(path: "ScriptumLibraries/not-a-UUID"), documentRoot: root)
        }
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(OwnedLibraryLocator.self, from: Data(#"{"schemaVersion":99,"kind":"primary"}"#.utf8))
        }
    }
}
