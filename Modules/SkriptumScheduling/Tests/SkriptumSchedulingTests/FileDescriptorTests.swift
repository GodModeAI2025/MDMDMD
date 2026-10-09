import Darwin
import Foundation
import Testing

@testable import SkriptumScheduling

struct FileDescriptorTests {
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
