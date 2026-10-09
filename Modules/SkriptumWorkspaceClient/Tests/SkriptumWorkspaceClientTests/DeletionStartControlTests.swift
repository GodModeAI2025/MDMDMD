import Foundation
import Testing
@testable import SkriptumWorkspaceClient
@Test func deletionStartControlIsOneWayClosedAndRedacted() throws {
    let cancelled = WorkspaceIdentityDeletionStartControl(); cancelled.cancel(); cancelled.cancel()
    #expect(cancelled.state == .cancelled)
    #expect(throws: CancellationError.self) { try cancelled.claimStart() }
    let started = WorkspaceIdentityDeletionStartControl(); try started.claimStart(); started.cancel()
    #expect(started.state == .started)
    #expect(throws: WorkspaceClientError.invalidRequest) { try started.claimStart() }
    #expect(String(reflecting: started) == "WorkspaceIdentityDeletionStartControl(<opaque>)")
}
