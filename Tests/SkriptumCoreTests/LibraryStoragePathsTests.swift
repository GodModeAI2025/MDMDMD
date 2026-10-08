import Foundation
import Testing
@testable import SkriptumCore

@Test func primaryLibraryKeepsLegacyPrivateStoragePaths() throws {
    let documents = URL(fileURLWithPath: "/container/Documents", isDirectory: true)
    let support = URL(fileURLWithPath: "/container/Library/Application Support", isDirectory: true)
    let primary = documents.appendingPathComponent("Skriptum", isDirectory: true)
    #expect(try LibraryStoragePaths.assistantHistoryDirectory(libraryDirectory: primary, documentRoot: documents, applicationSupportRoot: support).path == support.appendingPathComponent("Skriptum/Chats").path)
    #expect(try LibraryStoragePaths.recoveriesDirectory(libraryDirectory: primary, documentRoot: documents).path == primary.appendingPathComponent("Recoveries").path)
}

@Test func independentImportsHaveSeparateRelocatableNamespaces() throws {
    let firstID = UUID(), secondID = UUID()
    let documents = URL(fileURLWithPath: "/old-container/Documents", isDirectory: true)
    let support = URL(fileURLWithPath: "/old-container/Library/Application Support", isDirectory: true)
    let first = documents.appendingPathComponent("ScriptumLibraries/" + firstID.uuidString)
    let second = documents.appendingPathComponent("ScriptumLibraries/" + secondID.uuidString)
    let firstHistory = try LibraryStoragePaths.assistantHistoryDirectory(libraryDirectory: first, documentRoot: documents, applicationSupportRoot: support)
    let secondHistory = try LibraryStoragePaths.assistantHistoryDirectory(libraryDirectory: second, documentRoot: documents, applicationSupportRoot: support)
    let sharedPageID = UUID()
    #expect(firstHistory.appendingPathComponent(sharedPageID.uuidString + ".json") != secondHistory.appendingPathComponent(sharedPageID.uuidString + ".json"))
    #expect(firstHistory.lastPathComponent.utf8.count == 64)
    #expect(firstHistory.lastPathComponent.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) })
    let relocatedDocuments = URL(fileURLWithPath: "/new-container/Documents", isDirectory: true)
    let relocatedSupport = URL(fileURLWithPath: "/new-container/Library/Application Support", isDirectory: true)
    let relocatedLibrary = relocatedDocuments.appendingPathComponent("ScriptumLibraries/" + firstID.uuidString)
    let relocatedHistory = try LibraryStoragePaths.assistantHistoryDirectory(libraryDirectory: relocatedLibrary, documentRoot: relocatedDocuments, applicationSupportRoot: relocatedSupport)
    #expect(firstHistory.lastPathComponent == relocatedHistory.lastPathComponent)
    #expect(try LibraryStoragePaths.recoveriesDirectory(libraryDirectory: relocatedLibrary, documentRoot: relocatedDocuments).path == relocatedLibrary.appendingPathComponent("Recoveries").path)
    let encodedFirstCharacter = String(format: "%%%02X", firstID.uuidString.utf8.first!)
    let encodedUUID = encodedFirstCharacter + firstID.uuidString.dropFirst()
    let encodedAlias = URL(string: documents.absoluteString + "ScriptumLibraries/" + encodedUUID)!
    #expect(try LibraryStoragePaths.assistantHistoryDirectory(libraryDirectory: encodedAlias, documentRoot: documents, applicationSupportRoot: support) == firstHistory)
    let lowerCaseAlias = documents.appendingPathComponent("ScriptumLibraries/" + firstID.uuidString.lowercased())
    #expect(try LibraryStoragePaths.assistantHistoryDirectory(libraryDirectory: lowerCaseAlias, documentRoot: documents, applicationSupportRoot: support) == firstHistory)
}

@Test func unownedLibraryScopesFailClosedWithoutCreatingDirectories() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let documents = root.appendingPathComponent("Documents")
    let support = root.appendingPathComponent("ApplicationSupport")
    let uuid = UUID().uuidString
    let invalid = [
        URL(string: "https://example.com/Documents/Skriptum")!,
        URL(string: "file://foreign-host/container/Documents/Skriptum")!,
        root.appendingPathComponent("Documents-other/Skriptum"),
        root.appendingPathComponent("Foreign/Skriptum"),
        documents,
        documents.appendingPathComponent("Other"),
        documents.appendingPathComponent("ScriptumLibraries/not-a-uuid"),
        documents.appendingPathComponent("ScriptumLibraries/" + uuid + "/nested"),
        URL(string: documents.absoluteString + "/ScriptumLibraries/../Skriptum")!,
        URL(string: documents.absoluteString + "/ScriptumLibraries/%2e%2e/Skriptum")!
    ]
    for library in invalid {
        #expect(throws: (any Error).self) { try LibraryStoragePaths.assistantHistoryDirectory(libraryDirectory: library, documentRoot: documents, applicationSupportRoot: support) }
        #expect(throws: (any Error).self) { try LibraryStoragePaths.recoveriesDirectory(libraryDirectory: library, documentRoot: documents) }
    }
    #expect(throws: (any Error).self) { try LibraryStoragePaths.assistantHistoryDirectory(libraryDirectory: documents.appendingPathComponent("Skriptum"), documentRoot: documents, applicationSupportRoot: URL(string: "https://example.com")!) }
    #expect(!FileManager.default.fileExists(atPath: root.path))
}
