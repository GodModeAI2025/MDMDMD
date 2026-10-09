# Native account UI implementation

The reviewed UI plan is being implemented. This is not a completed account UI or a new TestFlight build.

Implemented in the current worktree:

- Stable app-owned account runtime, initialized once and injected into launch, library and external-document subtrees.
- Optional environment values with nil defaults; no implicit runtime allocation or fallback account.
- A noninteractive, inaccessible UIKit view reads only its own hosting window. A bounded weak anchor registry supplies that window to the real Apple authorization adapter. Reader identities prevent a departing view from clearing a replacement reader's anchor.
- Per-window account presentation and synchronous coordinator publication are under focused validation.
- Explicit bundle deployment validation and consent-gated metadata restoration are under focused validation.

The first actual iOS 27 SDK build failed because the initial runtime construction omitted handling the throwing connection-registry initializer. A second build exposed an incorrect argument label in metadata invalidation. Both were corrected. The subsequent foundation snapshot built successfully (exit 0, `workspace-account-ui-foundation-sdk-green.log`). This proves compilation of that snapshot, not the subsequently added inspector routing or native behavior.

Focused observation validation passed all 6 new observation tests and all 27 retained coordinator tests (33 tests, zero failures, `workspace-observation-green.log`). The tests exercise synchronous account-A invalidation before blocked remote work, account-B isolation, actual Observation callbacks, cancellation, controlled deletion outcomes, cleanup retry and subscription lifetime.

The first four focused runtime tests passed (`workspace-account-runtime-green.log`): strict deployment inputs, no side effects without configuration, exact operator acknowledgement before metadata restoration, and linked-interior rejection. Independent observation-only review and audit both passed; exact source hashes and limitations are recorded in `WORKSPACE_ACCOUNT_OBSERVATION_REVIEW.md`.

Root UI wiring review initially blocked on same-locator facade replacement and stale positive anchor updates. The lifecycle task now includes the ephemeral facade ID, while the owned locator remains the credential selector. Sheet identity captures both; the runtime action layer is being extended to reject stale facade requests. Anchors now require an explicit weak reader claim before either positive or negative window updates, and release only the matching claim. These source corrections require re-review and complete SDK/native validation; the earlier successful foundation build does not validate them.

The inspector is now implemented with the paper surface, operator disclosure, the official Apple sign-in control, checking an existing session, logout confirmation, same-account deletion confirmation, controlled server uncertainty, and local-only cleanup retry. Actions carry the owned locator and ephemeral facade ID; no arbitrary remote library identifier entry is offered. The full inspector snapshot built successfully (exit 0, `workspace-account-inspector-sdk-fixed.log`) after correcting actor isolation of the immutable sheet identity.

The first seven guarded runtime tests passed (`workspace-account-runtime-final-green.log`), including same-locator facade replacement and exact origin/profile consent changes. Initial whole-wave review blocked on three meaningful failure paths: cleanup retry lost authority when presentation state was unavailable, post-DELETE local removal failure did not expose retry, and cancellation during an in-flight DELETE falsely reported cancellation before start. The seven-test result did not prove those failure paths. The initial blocking review and its inspected hashes are retained separately below.

Those three source findings have now been corrected. Three new coordinator regressions produced actual failures before the fix and pass afterward (36 coordinator/observation tests). A runtime boundary regression likewise failed before the retry fix and then passed with all 8 runtime tests. Cleanup authority comes from the coordinator's actual attached pending record, and the presentation publishes only retry availability. Cancellation does not publish a pre-start conclusion before the actual deletion result.

Final aggregate validation passed: 45 XCTest tests and 210 Swift Testing tests (255 total), exit 0, `workspace-account-ui-final-root.log`. The regenerated iOS 27 app built successfully, exit 0, `workspace-account-ui-final-sdk.log`. A non-blocking weak-reference mutability warning remains in one observation test, plus the SwiftPM native-build-system deprecation warning. The initial blocking review is preserved in `WORKSPACE_ACCOUNT_UI_INITIAL_REVIEW.md`; fresh independent review and audit both passed, with exact inspected hashes in `WORKSPACE_ACCOUNT_UI_REVIEW.md`.

Still required: native UI/lifecycle checks, real operator/service configuration, Apple provisioning and end-to-end device/service validation. The existing internal TestFlight build 1.0.0 (2) predates these changes.
