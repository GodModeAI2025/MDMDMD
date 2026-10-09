import Foundation
import Testing
@testable import SkriptumCore
struct AttachmentAuditTests {
 private let png = Data(base64Encoded:"iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=")!
 @Test func readsOnlyCheckedOwnedMediaAndReportsDamage() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at:root) }
  try FileManager.default.createDirectory(at:root.appendingPathComponent("media"),withIntermediateDirectories:true)
  func descriptor(_ name: String) -> MediaAttachment { MediaAttachment(filename:name,mediaType:"image/png",byteCount:png.count,sha256:MediaValidation.digest(png)) }
  let good = descriptor("good.png"), missing = descriptor("missing.png"), bad = descriptor("bad.png"), symlink = descriptor("link.png")
  try png.write(to:root.appendingPathComponent(good.relativePath))
  try Data(repeating:0,count:png.count).write(to:root.appendingPathComponent(bad.relativePath))
  try FileManager.default.createSymbolicLink(at:root.appendingPathComponent(symlink.relativePath),withDestinationURL:root.appendingPathComponent(good.relativePath))
  var page = Page(spaceID:UUID(),title:"P"); page.attachments = [good,missing,bad,symlink]
  var snapshot = LibrarySnapshot(); snapshot.pages = [page]
  let library = UUID(), inventory = try await AttachmentAudit.inspect(libraryID:library,snapshot:snapshot,mediaRoot:root)
  #expect(inventory.libraryID == library)
  let statuses = Dictionary(uniqueKeysWithValues:inventory.entries.map { ($0.id,$0.storageStatus) })
  #expect(statuses[good.id] == .verified)
  #expect(statuses[missing.id] == .missingFile)
  #expect(statuses[bad.id] == .invalidFile)
  #expect(statuses[symlink.id] == .invalidFile)
  #expect(try Data(contentsOf:root.appendingPathComponent(good.relativePath)) == png)
 }
 @Test func cancelledAuditDoesNotPublish() async throws {
  let task = Task { try await AttachmentAudit.inspect(libraryID:UUID(),snapshot:LibrarySnapshot(),mediaRoot:FileManager.default.temporaryDirectory) }
  task.cancel()
  do { _ = try await task.value; Issue.record("Cancelled audit published") }
  catch is CancellationError { }
 }
 @Test func unsafeMediaDirectoryCannotBecomeVerified() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  let outside = root.appendingPathComponent("outside")
  defer { try? FileManager.default.removeItem(at:root) }
  try FileManager.default.createDirectory(at:outside,withIntermediateDirectories:true)
  let item = MediaAttachment(filename:"x.png",mediaType:"image/png",byteCount:png.count,sha256:MediaValidation.digest(png))
  try png.write(to:outside.appendingPathComponent(item.id.uuidString))
  try FileManager.default.createSymbolicLink(at:root.appendingPathComponent("media"),withDestinationURL:outside)
  var page = Page(spaceID:UUID(),title:"P"); page.attachments = [item]
  var snapshot = LibrarySnapshot(); snapshot.pages = [page]
  let result = try await AttachmentAudit.inspect(libraryID:UUID(),snapshot:snapshot,mediaRoot:root)
  #expect(result.entries[0].storageStatus == .invalidFile)
 }
}
