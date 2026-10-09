# Atomic proposal acceptance receipts

R09 Core contract only; server authentication, scheduling and native presentation remain separate gates.

`applyProposal(_:patch:author:)` validates and mutates through the same patch rules as ordinary `apply`. One atomic library.json commit publishes both changed page/history and receipt. Receipt contains schema 1, proposal/page IDs, SHA-256 of canonical length-prefixed exact UTF-8 patch fields (sorted allowed IDs, ordered operations), applied revision, author and finite timestamp. No prompt, credential or authority is stored.

Exact retries return the historical outcome before current revision/edit checks. A reused proposal ID with different patch, page, allowed scope or exact author bytes conflicts. No-op acceptance persists a receipt without adding history or changing revision. Receipt count is capped at 10,000 and author at 1,024 UTF-8 bytes; overflow fails closed rather than evicting idempotency records. Existing schema-1 libraries without receipts decode unchanged. Malformed, duplicate or unsupported receipt metadata is rejected.

Tests must use actual disk storage: restart/later-edit retry, Unicode/CRLF/scope/author conflicts, no-op, stale/forbidden/trashed/active-edit rejection and atomic-write failure. Import/export receipts are historical metadata, never remote authorization. Caller must independently establish server/library ownership; this API does not bypass typing or create another store.

## Verification

Test-first missing-API RED: `work/proposal-receipts-red.log` (the first unprivileged attempt could not access compiler caches; the escalated run reached the expected missing API diagnostics). This is a compile-time contract RED, not a pre-existing runtime failure claim.

Final focused verification: five actual-disk tests pass in `work/proposal-receipts-final-focused.log`. Full root native SwiftPM verification: 183 tests in 15 suites pass in `work/proposal-receipts-full.log`. Includes exact Unicode/CRLF mutation, normalized-author conflict, scope/page/order conflicts, durable no-op, restart and later edit retry, malformed/duplicate/oversized receipt rejection, permission-scope/edit/trash/revision rejection, actual atomic write collision and unrelated journal durability.

Core source is frozen. No App, root Package.swift, Xcode project, native UI or scheduling-module changes were made in this wave. Root Xcode regeneration/build and independent source review remain required before integration. R09 native server scope, proposal authenticity and scheduler UI gates remain open.
