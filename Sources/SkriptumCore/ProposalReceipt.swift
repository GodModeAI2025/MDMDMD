import Foundation
import CryptoKit

/// Historical acceptance metadata. It confers no server or library authority.
public struct ProposalReceipt: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let proposalID: UUID
    public let pageID: UUID
    public let patchFingerprint: String
    public let appliedRevision: UUID
    public let author: String
    public let acceptedAt: Date

    init(proposalID: UUID, patch: PagePatch, fingerprint: String, appliedRevision: UUID, author: String) {
        schemaVersion = 1
        self.proposalID = proposalID
        pageID = patch.pageID
        patchFingerprint = fingerprint
        self.appliedRevision = appliedRevision
        self.author = author
        acceptedAt = Date()
    }

    static let maximumCount = 10_000
    static func validate(_ receipts: [Self]) throws {
        guard receipts.count <= maximumCount,
              Set(receipts.map(\.proposalID)).count == receipts.count else { throw LibraryError.invalidLibrary }
        for receipt in receipts {
            guard receipt.schemaVersion == 1,
                  !receipt.author.isEmpty, receipt.author.utf8.count <= 1_024,
                  receipt.acceptedAt.timeIntervalSinceReferenceDate.isFinite,
                  receipt.patchFingerprint.utf8.count == 64,
                  receipt.patchFingerprint.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { throw LibraryError.invalidLibrary }
        }
    }
}

extension PagePatch {
    /// Length-prefixed fields avoid delimiter collisions. Source bytes are never
    /// normalized. Set order is sorted; operation order remains significant.
    func receiptFingerprint() -> String {
        var bytes = Data()
        func field(_ value: String) {
            let payload = Data(value.utf8)
            bytes.append(contentsOf: String(payload.count).utf8)
            bytes.append(58)
            bytes.append(payload)
        }
        field("Scriptum.PagePatch.1")
        field(pageID.uuidString)
        field(baseRevision.uuidString)
        field(String(allowedBlockIDs.count))
        for id in allowedBlockIDs.sorted(by: { $0.uuidString < $1.uuidString }) { field(id.uuidString) }
        field(String(operations.count))
        for operation in operations {
            switch operation {
            case .replace(let id, let markdown): field("replace"); field(id.uuidString); field(markdown)
            case .delete(let id): field("delete"); field(id.uuidString)
            case .insert(let id, let block): field("insert"); field(id.uuidString); field(block.id.uuidString); field(block.markdown)
            }
        }
        return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }
}
