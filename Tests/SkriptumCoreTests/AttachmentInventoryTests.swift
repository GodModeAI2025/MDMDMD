import Foundation
import Testing
@testable import SkriptumCore
struct AttachmentInventoryTests {
 @Test func actualReferencesAndRetentionAreDistinct() {
  let space = UUID(), id = UUID(), missing = UUID()
  let media = MediaAttachment(id:id,filename:"image.png",mediaType:"image/png",byteCount:123,sha256:String(repeating:"a",count:64))
  var page = Page(spaceID:space,title:"P",markdown:"![A](media/\(id))\n\n`![code](media/\(id))`\n\n![lost](media/\(missing))\n")
  page.attachments = [media]
  var trash = Page(spaceID:space,title:"Trash",markdown:"![T](media/\(id))"); trash.attachments = [media]; trash.trashedAt = Date()
  var historical = page; historical.revision = UUID()
  var snapshot = LibrarySnapshot(); snapshot.pages = [page,trash]; snapshot.revisions = [Revision(page:historical,author:"A",capturedAt:Date())]
  let inventory = AttachmentInventory(libraryID:UUID(),snapshot:snapshot)
  let row = inventory.entries.first { $0.id == id }!
  #expect(row.activeReferenceCount == 1 && row.trashedReferenceCount == 1 && row.historicalReferenceCount == 1)
  #expect(!row.isUnusedInCurrentPages && row.isRetainedByHistoryOrTrash)
  #expect(row.metadata == media && row.storageStatus == .notChecked)
  #expect(inventory.entries.first { $0.id == missing }?.storageStatus == .missingMetadata)
  #expect(inventory.references(on:page.id).count == 2)
  #expect(inventory.references(on:page.id).filter { !$0.hasPageMetadata }.map(\.attachmentID) == [missing])
 }
 @Test func unusedMetadataAndConflictsNeverAuthorizeDeletion() {
  let id = UUID(), space = UUID()
  let first = MediaAttachment(id:id,filename:"a.png",mediaType:"image/png",byteCount:10,sha256:String(repeating:"a",count:64))
  let conflicting = MediaAttachment(id:id,filename:"b.png",mediaType:"image/png",byteCount:20,sha256:String(repeating:"b",count:64))
  var a = Page(spaceID:space,title:"A"), b = Page(spaceID:space,title:"B"); a.attachments = [first]; b.attachments = [conflicting]
  var snapshot = LibrarySnapshot(); snapshot.pages = [a,b]
  var probes = 0
  let inventory = AttachmentInventory(libraryID:UUID(),snapshot:snapshot,probe: { _ in probes += 1; return .verified })
  #expect(inventory.entries[0].storageStatus == .conflictingMetadata)
  #expect(probes == 0)
  #expect(inventory.entries[0].isUnusedInCurrentPages)
 }
 @Test func destinationsAreStrictAndCatalogIsLibraryLocal() {
  let id = UUID(), space = UUID()
  var page = Page(spaceID:space,title:"P",markdown:"![ok](media/\(id))\n\n![bad](media/../\(id))\n\n![query](media/\(id)?x=1)\n\n![remote](https://x/media/\(id))")
  page.attachments = [MediaAttachment(id:id,filename:"x.png",mediaType:"image/png",byteCount:1,sha256:String(repeating:"a",count:64))]
  var snapshot = LibrarySnapshot(); snapshot.pages = [page]
  let inventory = AttachmentInventory(libraryID:UUID(),snapshot:snapshot,probe:{ _ in .missingFile })
  #expect(inventory.entries.count == 1 && inventory.entries[0].activeReferenceCount == 1)
  #expect(inventory.entries[0].storageStatus == .missingFile)
 }
 @Test func canonicallyEquivalentFilenameBytesConflict() {
  let id = UUID(), space = UUID()
  let a = MediaAttachment(id:id,filename:"é.png",mediaType:"image/png",byteCount:1,sha256:String(repeating:"a",count:64))
  let b = MediaAttachment(id:id,filename:"e\u{301}.png",mediaType:"image/png",byteCount:1,sha256:String(repeating:"a",count:64))
  var first = Page(spaceID:space,title:"A"), second = Page(spaceID:space,title:"B")
  first.attachments = [a]; second.attachments = [b]
  var snapshot = LibrarySnapshot(); snapshot.pages = [first,second]
  var reads = 0
  let inventory = AttachmentInventory(libraryID:UUID(),snapshot:snapshot,probe:{ _ in reads += 1; return .verified })
  #expect(inventory.entries[0].storageStatus == .conflictingMetadata)
  #expect(reads == 0)
 }

}
