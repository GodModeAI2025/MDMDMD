# Final standalone scheduling domain review

Verdict: **PASS currently implemented standalone domain subset**. No remaining confirmed blocker in the reviewed corrections. This does not accept the complete first wave, R09 or full product.

Frozen start/end SHA256: `d9e11ab69227c0b7dea509fd12f87b13f15412993076bceb8a6a895e19322494` (sorted module-relative *.swift path + NUL + bytes + NUL, excludes .build). Independent suite passed exit0: **20 tests in 3 suites**. Command: swift test --build-system native --disable-sandbox --disable-keychain --disable-netrc --scratch-path /private/tmp/ScriptumSchedulingReview. Authorized compiler-cache escalation followed the previously recorded sandbox manifest denial. Evidence: work/scheduling-independent-final.log. No network operation or source edit.

## Final fencing correction

Sources/SkriptumScheduling/ScheduleModels.swift persists ScheduledRun.usedFences. RunStateMachine.swift:13 rejects every previously used token and inserts a new token before incrementing attempts. SchedulingStore.swift:26 validates history count equals attempts, maximum3, and current lease belongs to history; nonzero attempts cannot omit a lease. Thus A→B→A is rejected after restart, without changing state/disk. Regression also rejects the original worker's authorize call and accepts a genuinely distinct third token. No new history invariant defect found. Prototype schema1 records lacking required history fail closed; no deployed scheduling data migration is claimed.

## Other reviewed corrections retained

- Dispatch/proposal/completion re-admit current exact task grants; dispatch checks quote expiry/version.
- Draft-only add prevents activation bypass. Reserved/running states require compatible held ledger records.
- Cancellation retry admits original cancelled generation with current CAS version.
- Independent enrolled account/currency ceiling plus task ceiling and checked integer sums bound reservation aggregation; uncertain holds cannot refund.
- Settled uncertain charges survive cancellation and restart unchanged.
- File read uses nonblocking descriptor open before regular-type rejection, bounded reads and no-follow paths; owned FIFO regression passes.
- Candidate transaction persists before publishing actor memory, with CAS/failure rollback; settlement and expired dispatch recovery are explicit transactions.

Persistence rename is successful commit; no thrown post-rename step is present. No assertion that a failed post-rename fsync leaves disk unchanged. Directory crash durability remains unproved. All-component no-follow requires genuinely owned canonical native roots and must not be bypassed by resolving untrusted aliases. Cross-process/database authority is excluded.

## Explicit open gates

Pause/revise, read-only summary representation, acceptance receipt, missed-occurrence audit, monthly recurrence/end/count remain open implemented-subset gaps. Server grant authentication/roles/revocation, backend durable queue/database, provider/vault eligibility, real costs, offline-device server execution, region/retention/delete-account, native scheduler UI and atomic document+receipt transaction remain unimplemented/unproved. Source/domain tests are not server or device proof. Full R09 and product requirements remain open.

Read-only ordinary code/data-integrity review; no broader SAST/SCA/compliance certification. No App/source edits, commits, network activity or unsafe external probes.
