# Native coordinator implementation findings

The coordinator candidate is incomplete and has not been published or exposed as a working account feature. The independently reviewed plan remains the intended contract.

## Reproduced stale logout completion

A permanent regression signs out an existing account, admits a fresh session for the same account while the old revocation is suspended, then releases the old response. The unchanged candidate incorrectly replaces `active` with `localDenied`.

Actual failing execution: `work/workspace-coordinator-old-logout-red-isolated.log`, exit 1, one executed test and one assertion failure. The harness uses the exact candidate source and frozen regression with the valid client from archived commit `3c57a6e`; this avoids the concurrent unfinished admission module. No test expectation was weakened. Candidate source SHA256: `bb74eb000e627da35a2fadc9ab57e7d9eec2c5ca1b35c506c1f3ac0917a27cf7`.

Required correction: fresh admission rotates the account slot generation before suspension, and every old success/error callback checks its captured generation before publishing. Add a distinct late-GET regression as well.

## Additional source review findings awaiting regression/fix

- Cancellation after a successful credential save must retain the returned exact ticket and perform local denial/removal as well as remote cleanup. Unknown remote revocation cannot justify leaving a cancelled credential available for cold restoration. A stale cleanup must preserve a newer session.
- Retired, unattached signed-out slots must release bounded capacity. Recreated slots need a new incarnation, so retiring a slot cannot revive old callbacks.
- Failed durable-denial persistence must retain the initiating driver and controlled retry information for cleanup. The UI must remain honest about unavailable persistence; an in-memory fence alone cannot prove safe restoration after restart.

These are implementation blockers, not claims against a released login UI. Production adapters, native account controls, real Security admission, Foundation-container path evidence, production Apple login and deployed service/vault remain open.
