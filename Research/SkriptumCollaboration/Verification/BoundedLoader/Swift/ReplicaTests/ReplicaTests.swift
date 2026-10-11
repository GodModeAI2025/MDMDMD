import Foundation
import Testing
import Automerge
@testable import SkriptumCollaboration

func identity() -> ReplicaIdentity { ReplicaIdentity(libraryID: UUID(), spaceID: UUID(), pageID: UUID()) }

@Test func r08_twoPeersExchangeRealChangesAndConverge() async throws {
    let id = identity(), block = ReplicaSeedBlock(id: UUID(), markdown: "abc")
    let original = try PageReplica(identity: id, blocks: [block])
    let baseline = try await original.snapshot().version
    let left = await original.fork(), right = await original.fork()
    try await left.edit(blockID: block.id, range: UTF16Range(location: 0, length: 0), replacement: "A")
    try await right.edit(blockID: block.id, range: UTF16Range(location: 3, length: 0), replacement: "B")
    let leftChanges = try await left.changes(since: baseline), rightChanges = try await right.changes(since: baseline)
    try await left.receive(rightChanges); try await right.receive(leftChanges)
    let a = try await left.snapshot(), b = try await right.snapshot()
    #expect(a == b)
    #expect(a.markdown == "AabcB")
    #expect(a.blocks.map(\.id) == [block.id])
    #expect(a.conflicts.isEmpty)
}

@Test func r08_unicodeCRLFAndReloadPreserveExactBytes() async throws {
    let source = "é e\u{301}\r\n👨‍👩‍👧‍👦 🦊\r\nEnde\n"
    let id = identity(), seed = ReplicaSeedBlock(id: UUID(), markdown: source)
    let original = try PageReplica(identity: id, blocks: [seed])
    let before = try await original.snapshot()
    #expect(Data(before.markdown.utf8) == Data(source.utf8))
    let saved = try await original.save()
    let reloaded = try PageReplica(identity: id, saved: saved)
    #expect(Data(try await reloaded.snapshot().markdown.utf8) == Data(source.utf8))
    // A UTF-16 offset inside the fox's surrogate pair must be rejected.
    let fox = try #require((source as NSString).range(of: "🦊").location < source.utf16.count ? (source as NSString).range(of: "🦊").location : nil)
    await #expect(throws: ReplicaError.invalidUTF16Range) { try await reloaded.edit(blockID: seed.id, range: UTF16Range(location: fox + 1, length: 0), replacement: "X") }
    try await reloaded.edit(blockID: seed.id, range: UTF16Range(location: source.utf16.count, length: 0), replacement: "é e\u{301}")
    #expect(Data(try await reloaded.snapshot().markdown.utf8) == Data((source + "é e\u{301}").utf8))
}

@Test func r08_wrongIdentityAndInvalidCandidatesRollBack() async throws {
    let id = identity(), seed = ReplicaSeedBlock(id: UUID(), markdown: "Accepted")
    let replica = try PageReplica(identity: id, blocks: [seed])
    let accepted = try await replica.snapshot()
    let malicious = Document(textEncoding: .utf16)
    try malicious.applyEncodedChanges(encoded: await replica.save())
    try malicious.put(obj: .ROOT, key: "pageID", value: .String(UUID().uuidString))
    await #expect(throws: ReplicaError.identityMismatch) { try await replica.receive(malicious.save()) }
    #expect(try await replica.snapshot() == accepted)
    await #expect(throws: (any Error).self) { try await replica.receive(Data([0,1,2,3])) }
    #expect(try await replica.snapshot() == accepted)
    let wrongScope = ReplicaIdentity(libraryID: UUID(), spaceID: id.spaceID, pageID: id.pageID)
    #expect(throws: ReplicaError.identityMismatch) { try PageReplica(identity: wrongScope, saved: malicious.save()) }
}

@Test func r08_concurrentDeleteEditRetainsRecoveryAndConverges() async throws {
    let seed = ReplicaSeedBlock(id: UUID(), markdown: "Old")
    let original = try PageReplica(identity: identity(), blocks: [seed])
    let deleted = await original.fork(), edited = await original.fork()
    try await deleted.delete(blockID: seed.id)
    try await edited.edit(blockID: seed.id, range: UTF16Range(location: 0, length: 3), replacement: "New 🦊")
    let deleteData = try await deleted.save(), editData = try await edited.save()
    try await deleted.receive(editData); try await edited.receive(deleteData)
    let a = try await deleted.snapshot(), b = try await edited.snapshot()
    #expect(a == b)
    #expect(a.blocks[0].isDeleted)
    #expect(a.blocks[0].markdown == "New 🦊")
    #expect(a.conflicts.contains(.deletionEdit(blockID: seed.id, recoverableMarkdown: "New 🦊")))
    try await deleted.restore(blockID: seed.id)
    #expect(try await deleted.snapshot().markdown == "New 🦊")
}

@Test func r08_reorderConflictsAreObservableAndIDsStable() async throws {
    let a = ReplicaSeedBlock(id: UUID(), markdown: "A\n\n"), b = ReplicaSeedBlock(id: UUID(), markdown: "B\n\n"), c = ReplicaSeedBlock(id: UUID(), markdown: "C")
    let original = try PageReplica(identity: identity(), blocks: [a,b,c])
    let left = await original.fork(), right = await original.fork()
    try await left.move(blockID: c.id, after: a.id)
    #expect(try await left.snapshot().blocks.map(\.id) == [a.id,c.id,b.id])
    try await right.move(blockID: c.id, after: nil)
    #expect(try await right.snapshot().blocks.map(\.id) == [c.id,a.id,b.id])
    let l = try await left.save(), r = try await right.save()
    try await left.receive(r); try await right.receive(l)
    let x = try await left.snapshot(), y = try await right.snapshot()
    #expect(x == y)
    #expect(Set(x.blocks.map(\.id)) == Set([a.id,b.id,c.id]))
    #expect(!x.conflicts.isEmpty)
}

@Test func r08_sizeRejectedBeforePublishingAndOriginalSurvives() async throws {
    let seed = ReplicaSeedBlock(id: UUID(), markdown: "Small")
    let original = try PageReplica(identity: identity(), blocks: [seed], limits: ReplicaLimits(maximumTextBytes: 16))
    let before = try await original.snapshot()
    await #expect(throws: ReplicaError.limitExceeded) { try await original.edit(blockID: seed.id, range: UTF16Range(location: 0, length: 0), replacement: String(repeating: "Z", count: 20)) }
    #expect(try await original.snapshot() == before)
}

@Test func r08_upstreamMergeKeepsConfiguredUTF16ForReload() throws {
    let source = Document(textEncoding: .utf16)
    let text = try source.putObject(obj: .ROOT, key: "text", ty: .Text)
    try source.spliceText(obj: text, start: 0, delete: 0, value: "🦊")
    let raw = try Document(source.save())
    let receiver = Document(textEncoding: .utf16)
    try receiver.merge(other: raw)
    #expect(receiver.length(obj: text) == 2)
    guard case .utf16 = receiver.textEncoding else { Issue.record("Upstream merge lost UTF-16 configuration"); return }
    #expect(try receiver.text(obj: text) == "🦊")
}

@Test func r08_replacedContainerAndMalformedSuffixRejectAtomically() async throws {
    let id = identity(), seed = ReplicaSeedBlock(id: UUID(), markdown: "é\r\n")
    let replica = try PageReplica(identity: id, blocks: [seed])
    let accepted = try await replica.snapshot(), saved = try await replica.save()
    let attacker = try Document(saved)
    _ = try attacker.putObject(obj: .ROOT, key: "blocks", ty: .Map)
    await #expect(throws: ReplicaError.invalidSchema) { try await replica.receive(attacker.save()) }
    #expect(try await replica.snapshot() == accepted)
    let peer = await replica.fork()
    try await peer.edit(blockID: seed.id, range: UTF16Range(location: 0, length: 1), replacement: "e\u{301}")
    var payload = try await peer.changes(since: accepted.version)
    payload.append(contentsOf: [0, 1, 2, 3])
    await #expect(throws: (any Error).self) { try await replica.receive(payload) }
    #expect(try await replica.snapshot() == accepted)
    let wrongLibrary = ReplicaIdentity(libraryID: UUID(), spaceID: id.spaceID, pageID: id.pageID)
    #expect(throws: ReplicaError.identityMismatch) { try PageReplica(identity: wrongLibrary, saved: saved) }
    try await replica.receive(peer.save())
    #expect(Data(try await replica.snapshot().markdown.utf8) == Data("e\u{301}\r\n".utf8))
    let merged = try await replica.snapshot()
    try await replica.receive(peer.save())
    #expect(try await replica.snapshot() == merged)
}

@Test func r08_concurrentInsertsAndCyclesRetainEveryBlock() async throws {
    let a = ReplicaSeedBlock(id: UUID(), markdown: "A"), b = ReplicaSeedBlock(id: UUID(), markdown: "B"), c = ReplicaSeedBlock(id: UUID(), markdown: "C")
    let original = try PageReplica(identity: identity(), blocks: [a,b,c])
    let left = await original.fork(), right = await original.fork()
    let x = ReplicaSeedBlock(id: UUID(), markdown: "X"), y = ReplicaSeedBlock(id: UUID(), markdown: "Y")
    try await left.insert(x, after: a.id); try await right.insert(y, after: a.id)
    let l = try await left.save(), r = try await right.save()
    try await left.receive(r); try await right.receive(l)
    let inserted = try await left.snapshot()
    let insertedRight = try await right.snapshot()
    #expect(inserted == insertedRight)
    #expect(Set(inserted.blocks.map(\.id)) == Set([a.id,b.id,c.id,x.id,y.id]))
    #expect(inserted.conflicts.contains { if case .concurrentPlacement = $0 { true } else { false } })
    // Concurrent valid predecessor assignments may form a cycle after merge.
    let cycleLeft = await original.fork(), cycleRight = await original.fork()
    try await cycleLeft.move(blockID: a.id, after: c.id)
    try await cycleRight.move(blockID: c.id, after: a.id)
    let cl = try await cycleLeft.save(), cr = try await cycleRight.save()
    try await cycleLeft.receive(cr); try await cycleRight.receive(cl)
    let cycle = try await cycleLeft.snapshot()
    let cycleOther = try await cycleRight.snapshot()
    #expect(cycle == cycleOther)
    #expect(Set(cycle.blocks.map(\.id)) == Set([a.id,b.id,c.id]))
    #expect(cycle.conflicts.contains { if case .orderingCycle = $0 { true } else { false } })
}
