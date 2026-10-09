# Shared document account changes

An open shared-document session observes `CKAccountChanged`. Its notification callback invalidates a lock-protected admission fence immediately on the posting queue; main-actor cleanup then discards the visible context, grant, transport, checkpoint handles, account/share identity and recovery list. Existing account/share-scoped files remain unchanged. An already dispatched remote write cannot be recalled; later admissions and local completion callbacks are fenced.

Invitation acceptance, descriptor restoration, receive/send completion and local page/comment mutations check both session generation and account generation. Old account lookup results cannot recreate a session. Reopening requires a fresh account lookup and CloudKit participant grant; an identity belonging to another account is rejected. The shared editor dismisses its comments sheet and explains the account change. Unsaved text in the current window remains available for explicit local export.

The observer does not retain the session and removes its token when the session is released. Default production construction continues to use the bundle's provisioning gate, default notification center and native CloudKit account lookup. Tests inject a private notification center and suspend only account lookup; they do not request Apple access or change app provisioning.

Evidence: three focused tests passed for the old-account completion race, exact Unicode draft preservation, fresh-account mismatch rejection, observer lifetime and the existing unprovisioned gate. The broader iCloud/shared/draft selection passed **83 tests**. Xcode MCP `BuildProject` succeeded in 4.05 seconds, with no errors (receipt 71). Workspace logs: `work/shared-account-fence-tests.log`, `work/shared-account-fence-regression.log`, `work/shared-catalog-qa/shared-account-build.json`.

The standard Swift test invocation first failed because its compiler cache was sandbox-denied. Redirecting caches then exposed missing default-build dependency resolution/network access. The successful run used the already cached native SwiftPM scratch at `/private/tmp/SkriptumAppleBroker`, with no new dependency fetch.

This proves local lifecycle behavior and compilation. An actual Apple account switch, live shared participant collaboration and a new signed TestFlight delivery remain unverified. The iCloud provisioning gate remains disabled pending capability/profile completion.
