import Darwin
import Foundation
import Testing

@testable import SkriptumScheduling

struct FileDescriptorTests {
  @Test func ownedFileNeedsSearchButNotDirectoryListingAccessToAncestors() throws {
    let root = URL(fileURLWithPath: "/private/tmp/SchedulingSearchQA-" + UUID().uuidString,
                   isDirectory: true)
    let ancestor = root.appendingPathComponent("search-only", isDirectory: true)
    let owned = ancestor.appendingPathComponent("owned", isDirectory: true)
    try FileManager.default.createDirectory(at: owned, withIntermediateDirectories: true)
    defer {
      _ = chmod(ancestor.path, 0o700)
      try? FileManager.default.removeItem(at: root)
    }
    let file = owned.appendingPathComponent("state.json")
    let original = Data("original café 🦊\r\n".utf8)
    try original.write(to: file)
    guard chmod(ancestor.path, 0o111) == 0 else {
      throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
    let persistence = try FileSchedulingPersistence(url: file)
    #expect(try persistence.read() == original)
    let replacement = Data("replacement e\u{301}\r\n".utf8)
    try persistence.write(replacement)
    #expect(try persistence.read() == replacement)
  }

  @Test func ownedFIFOIsRejectedWithoutBlocking() throws {
    let supplied = ProcessInfo.processInfo.environment["SCHEDULING_FIFO_FIXTURE_ROOT"]
    let root = URL(
      fileURLWithPath: supplied ?? "/private/tmp/SchedulingFIFOQA-" + UUID().uuidString,
      isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("state.fifo")
    guard mkfifo(file.path, 0o600) == 0 else {
      throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
    #expect(throws: SchedulingError.unsafeFile) { try FileSchedulingPersistence(url: file).read() }
  }
}
