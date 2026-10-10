import Foundation

/// Read-only output. No conversion to PagePatch or replacement proposal exists.
public struct ScheduledSummary: Codable, Equatable, Sendable, Identifiable {
  public let id: UUID, scope: SchedulingScope, runID: UUID, pageID: UUID, baseRevision: UUID
  public let sourceDigest: String, text: String, providerID: String, modelID: String,
    createdAt: Date
  public init(
    id: UUID = UUID(), scope: SchedulingScope, runID: UUID, pageID: UUID, baseRevision: UUID,
    source: String, text: String, providerID: String, modelID: String, createdAt: Date
  ) throws {
    guard source.utf8.count <= 8 * 1024 * 1024 else { throw SchedulingError.invalidValue }
    self.id = id
    self.scope = scope
    self.runID = runID
    self.pageID = pageID
    self.baseRevision = baseRevision
    sourceDigest = ScheduledProposal.digest(source)
    self.text = text
    self.providerID = providerID
    self.modelID = modelID
    self.createdAt = createdAt
    try validate()
  }
  public func validate() throws {
    guard !text.isEmpty, text.utf8.count <= 1024 * 1024, !providerID.isEmpty,
      providerID.utf8.count <= 128, !modelID.isEmpty, modelID.utf8.count <= 128,
      createdAt.timeIntervalSince1970.isFinite, sourceDigest.utf8.count == 64,
      sourceDigest.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) })
    else { throw SchedulingError.invalidValue }
  }
  public func admit(scope: SchedulingScope, pageID: UUID, revision: UUID, source: String) throws
    -> Bool
  {
    try validate()
    guard self.scope == scope, self.pageID == pageID, baseRevision == revision,
      source.utf8.count <= 8 * 1024 * 1024, sourceDigest == ScheduledProposal.digest(source)
    else { throw SchedulingError.staleProposal }
    return true
  }
}
