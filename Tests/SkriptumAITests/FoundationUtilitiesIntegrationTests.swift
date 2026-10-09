import Foundation
import Testing
@testable import SkriptumAI

@Test func cumulativeStreamingPreservesCombiningCharactersAndEmojiExactly() throws {
    let snapshots = ["e", "e\u{301}", "e\u{301}\r\n", "e\u{301}\r\n🦊"]
    var previous = "", reconstructed = ""
    for snapshot in snapshots {
        reconstructed += try AIStreamingSnapshot.delta(from: previous, to: snapshot)
        previous = snapshot
    }
    #expect(reconstructed.utf8.elementsEqual(snapshots.last!.utf8))
    #expect(throws: (any Error).self) { try AIStreamingSnapshot.delta(from: "e\u{301}", to: "é") }
}

#if canImport(FoundationModels) && canImport(FoundationModelsUtilities)
@Test func appleWritingGuidesNeverShareActivationStateAcrossRequests() {
    let first = AppleWritingProfile(instructions: "First document: only edit the allowed target")
    let second = AppleWritingProfile(instructions: "Second document")
    first.activations.activate("proofreading")
    #expect(first.activations.activeSkillNames == ["proofreading"])
    #expect(second.activations.activeSkillNames.isEmpty)
    #expect(first.instructions == "First document: only edit the allowed target")
    #expect(second.instructions == "Second document")
}
#endif
