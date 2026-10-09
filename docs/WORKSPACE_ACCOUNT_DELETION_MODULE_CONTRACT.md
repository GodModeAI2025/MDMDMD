# Module deletion start control — exact boundary proposal

Plan only; no module production edits. Coordinator owner API proposal read and aligned. Existing UI plan remains saved separately. Root/reviewer approval required before implementation.

Public additive API:

```swift
public final class WorkspaceIdentityDeletionStartControl: @unchecked Sendable {
    public enum State: Sendable { case pending, cancelled, started }
    public init()
    public var state: State { get }
    public func cancel() // sync, pending->cancelled only; started never rolls back
    // Internal one-use claimStart: pending->started under same NSLock.
}
public func deleteAccount(using receipt: WorkspaceReauthenticationReceipt,
    startControl: WorkspaceIdentityDeletionStartControl) async throws -> WorkspaceAccountDeletionOutcome
```

Existing deleteAccount(using:) remains an overload delegating with a fresh control. Control carries no scope/token/proof/receipt, is non-Codable and redacted. No new authorization privilege or account selector. Coordinator driver owns one control per independent deletion attempt; cancelProof synchronously cancels that exact control, then broker/proof gate. Passing a different/fresh control at actor entry would reintroduce the bug and is prohibited.

Inside actual identity actor: validate available/current unexpired admission; if the Task is already cancelled, cancel the control and throw before consuming receipt. Atomic claimStart then occurs before receipt.claim, local invalidation and request initiation. There is NO await/actor hop between claim and those local operations. Cancellation winning before claim throws a controlled cancellation and consumes no receipt or DELETE. Claim winning is the linearization of accepted deletion, not TCP transmission or confirmed server tombstone. A duplicate claim is controlled invalidRequest. After start, cancellation cannot promise rollback: actual confirmed/unknown result and cleanup/reservation rules remain authoritative.

Receipt scope/expiry/one-use validation remains exactly existing logic. If it fails after start, no request is sent and error propagates for targeted issued-session cleanup; state.started still means the start gate cannot be reused, never confirmed deletion. Coordinator retains per-account reservation through request/cleanup and publishes unknown honestly.

Test-first meaningful actual actor boundary: a DEBUG+SWIFT_PACKAGE internal immutable pre-start scheduling checkpoint (public init alwaysnil; production/Xcode/swiftc hasnohook), placed BEFORE claim, lets the real actor be queued/resumed deterministically. Enroll through existing controlled own HTTP fixture to get actual SDK receipt; queue DELETE at checkpoint, sync control.cancel from outsideactor, release, assert controlledcancel, exact receipt stillclaimable, localadmission intact, server DELETE count0. Start-win case drives actual request first, observes fixture DELETE barrier then cancels; outcome remains confirmed/unknown according to wire, never cancelledBeforeStart. Duplicate/sharedcontrol claims rejected. Pure control race test supplements but cannot replace actual actor HTTP proof.

Preserve existing module29tests and actual signed-server20proof. Tests add assertions, do not weaken old cases. New source hashes +SDK compile +realfixtures before root final review. No App/Coordinator/server edits, no commits by module owner.
