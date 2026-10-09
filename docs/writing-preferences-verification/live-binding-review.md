# Independent live block binding repair review

Verdict: **PASS for the identified immutable-row snapshot problem**, with original QA11 causation and iOS runtime coverage explicitly unresolved.

The production binding now computes projection from a currentSource callback on each getter invocation. Parent callback reads live @State blocks by the same stable UUID, rather than the row's immutable projection snapshot. Setter still travels through existing block proposal/domain acceptance; rejected commits reset editor and do not publish unaccepted canonical data. Style commands also obtain current source through the provider. No stale-update suppression, generation heuristic or ignored baseline update was added: legitimate external restore updates canonical blocks and is read normally.

Both native synchronize extractions retain the prior text/caret/marked-text/presentation/command sequence, making the actual coordinator method callable for testing without fabricated representable contexts. Actual AppKit regression test constructs the production binding and coordinator, publishes Unicode typing, invokes synchronization on the already-constructed row, verifies no text/caret rollback and unchanged UUID/CRLF bytes, then changes canonical bytes to the original baseline and verifies external restore and selection apply. Supplied green log confirms the test passes; prior RED establishes the old snapshot susceptibility under that ordering.

The change closes the demonstrated binding contract risk without conflating external Undo with stale text by equality. It does not prove that this ordering caused the original 'QA11 edit.'→'QA11it.' observation. UIKit has equivalent source logic but remains a separate native acceptance test, as do IME/autocorrection delivery and whole-baseline Undo/Redo. No new security/authorization/storage path introduced and no concrete blocking regression found in the diff.

Read-only review; no source/Xcode/device mutations performed.
