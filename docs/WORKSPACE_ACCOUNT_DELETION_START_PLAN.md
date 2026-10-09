# Reviewed deletion fixes: API/linearization proposal

No module edits by coordinator owner. Coordinate public module API with module owner/root before implementation.

## Actual actor-hop cancellation boundary

Add public `WorkspaceIdentityDeletionStartControl: @unchecked Sendable` containing one NSLock-protected state: pending/cancelled/started. `cancel()` is synchronous and one-way; it changes pending->cancelled only, and cannot pretend to undo started deletion. Internal `claimStart()` atomically consumes pending->started; cancelled throws CancellationError; a second start throws controlled invalid-request/consumed error. Redacted descriptions/mirror; no token, scope or receipt inside control.

Add `WorkspaceIdentityClient.deleteAccount(using: WorkspaceReauthenticationReceipt, startControl: WorkspaceIdentityDeletionStartControl) async throws -> WorkspaceAccountDeletionOutcome`. Existing public overload keeps compatibility by supplying a fresh control; no caller scope override. INSIDE identity actor, validate active admission and Task cancellation, then claimStart before receipt.claim, local admission invalidation and request initiation. There is no await/actor hop between control claim and receipt claim/invalidation. Claim is the linearization point for destructive authorization, not proof that TCP transmission or server tombstoning completed. Cancellation winning before actor admission sends no DELETE and consumes no receipt. Cancellation after claim cannot promise undo; result remains confirmed/unknown according to actual request. Receipt validation failure after claim still triggers coordinator targeted fresh-session cleanup; no DELETE sent, no false tombstone.

Production coordinator driver owns a fresh control for each independent deletion driver. Its synchronous cancelProof invokes control.cancel alongside existing proof gate/broker cancel. Driver passes the SAME control through actual client actor hop; a MainActor check alone is insufficient. Native per-account reservation remains active through request/cleanup so a newer same-account session cannot be admitted ahead of an old authorized DELETE.

Permanent module RED: hold identity actor admission with an owned deterministic barrier (or narrowly extracted actual start-control admission used by actor), queue delete, synchronously cancel from another executor, release barrier, assert receipt remains unconsumed and owned server DELETE count0. Distinct case claim wins then cancel cannot reverse started; duplicate claim rejected. Root coordinator tests retain all23 assertions and add actual shared-control scheduled-hop boundary proof. No Task.cancel-only substitute.

## Retry cleanup ownership

Each DeletionCleanup gets fresh immutable cleanup UUID plus reservation UUID, captured slot generation and driver references. Every retry captures those identities. After EACH await (local remove, fresh discard, original invalidate), recheck cleanup UUID, reservation UUID and generation before changing metadata/state/cleanup or releasing reservation. Stale retry may target-discard only its own issued session; after that await it must again compare identities before clearing anything. A replacement deletion cleanup/reservation in the same slot is never cleared by an older continuation. Update helpers centralize CAS rather than unconditional assignments.

Permanent coordinator RED: old retry reaches owned discard barrier; slot generation/reservation replaced by newer explicit deletion; release old discard and assert new deleting/cleanup reservation remains. Also delayed remove and original-invalidate completions cannot replace a newer outcome. No deletion is resent by cleanup retry.

## Pre-fence cleanup outcomes

Use a bounded per-operation/window cleanup report keyed by deletion attempt UUID (or exact target slot generation and own attemptID where publication still valid). ALL issued-session cleanup outcomes from wrong account, cancel/superseded and enrollment error paths are reported as targeted-session confirmed/unknown, separately from deletion result and A/B authorization state. Older callbacks must not overwrite a newer report. A wrong-B newly issued credential is the ONLY cleanup target; no A denial/remove and no B-existing token mutation. Outcome report contains no receipt, token or proof and is not persisted as authorization.

Permanent coordinator RED: wrongB cleanupUnknown; pre-fence cancel cleanupUnknown; post-enrollment failure cleanupUnknown. Assert separate outcome is unknown while original A state/credentials remain unchanged; newer same-window report survives late old cleanup.
