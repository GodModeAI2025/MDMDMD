import CryptoKit
import Foundation

public struct ScheduledProposal: Codable, Equatable, Sendable, Identifiable {
  public let id: UUID, scope: SchedulingScope, runID: UUID, pageID: UUID, baseRevision: UUID,
    allowedBlockIDs: Set<UUID>, sourceDigest: String, replacementBlocks: [UUID: String]
  public let providerID: String?, modelID: String?
  public init(
    id: UUID = UUID(), scope: SchedulingScope, runID: UUID, pageID: UUID, baseRevision: UUID,
    allowedBlockIDs: Set<UUID>, source: String, replacementBlocks: [UUID: String],
    providerID: String? = nil, modelID: String? = nil
  ) throws {
    guard source.utf8.count <= 8 * 1024 * 1024 else { throw SchedulingError.invalidValue }
    self.id = id
    self.scope = scope
    self.runID = runID
    self.pageID = pageID
    self.baseRevision = baseRevision
    self.allowedBlockIDs = allowedBlockIDs
    self.sourceDigest = Self.digest(source)
    self.replacementBlocks = replacementBlocks
    self.providerID = providerID; self.modelID = modelID
    try validate()
  }
  public static func digest(_ source: String) -> String {
    SHA256.hash(data: Data(source.utf8)).map { String(format: "%02x", $0) }.joined()
  }
  public func validate() throws {
    guard !allowedBlockIDs.isEmpty, allowedBlockIDs.count <= 10000, !replacementBlocks.isEmpty,
      Set(replacementBlocks.keys).isSubset(of: allowedBlockIDs), sourceDigest.utf8.count == 64,
      sourceDigest.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) })
    else { throw SchedulingError.invalidValue }
    guard (providerID == nil) == (modelID == nil),
      [providerID, modelID].compactMap({ $0 }).allSatisfy({ !$0.isEmpty && $0.utf8.count <= 128 }) else { throw SchedulingError.invalidValue }
    var bytes = 0
    for value in replacementBlocks.values {
      guard value.utf8.count <= 1024 * 1024 else { throw SchedulingError.invalidValue }
      bytes += value.utf8.count
    }
    guard bytes <= 1024 * 1024 else { throw SchedulingError.invalidValue }
  }
  public func admit(
    scope: SchedulingScope, pageID: UUID, revision: UUID, source: String,
    readableBlockIDs: Set<UUID>
  ) throws -> Bool {
    try validate()
    guard self.scope == scope, self.pageID == pageID, baseRevision == revision,
      source.utf8.count <= 8 * 1024 * 1024, sourceDigest == Self.digest(source),
      allowedBlockIDs.isSubset(of: readableBlockIDs)
    else { throw SchedulingError.staleProposal }
    return true
  }
}
