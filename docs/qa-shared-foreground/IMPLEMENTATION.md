# Shared-document foreground refresh — 2026-10-10

Changes made through the shared session (Markdown, anchored comments, replies, resolve/reopen) first commit to the existing durable local shared store. A per-scene refresh coordinator requests synchronization after a quiet interval. New edits during debounce restart the interval; new edits during a running operation request one coalesced successor rather than canceling a write. The minimum quiet interval is 600 ms, not an exact network deadline.

The real shared view supplies its own scenePhase on appearance and changes. Inactivation first flushes the draft, then cancels automatic work. Disappearance pauses it as well. A returning active scene requests a refresh, including when there are no local changes, because silent CloudKit notifications are not guaranteed. Session stop/account change pauses the coordinator; ready-state presentation resumes according to the actual scene. The unprovisioned gate cannot start a worker, account lookup, CloudKit state creation, or provider call.

A canceled refresh may take time to finish. Its worker remains the serialization owner until it actually exits. A rapidly returning scene queues replacement work instead of overlapping that operation. Worker UUID and session generation checks prevent a stale completion from retiring a replacement or publishing into a stopped session. Failed network/grant checks keep the existing explicit retry path; this is not an unlimited automatic retry loop. No AI task, new cloud service, provider fallback, provisioning capability, or subscription credential was introduced.

Pending local work remaining after a successful shared synchronization requests a successor while the scene is active. The existing fresh participant-grant/account checks and revision-guarded durable send/receive paths are unchanged. Autosync does not provide CRDT convergence or eliminate author conflict review. Two scenes/windows do not share this coordinator; cross-session concurrent writes retain the existing CloudKit conflict checks and remain part of the two-device acceptance gate.

## Native finding and correction

The first private DEBUG launch of the real unprovisioned shared view on iPhone showed a blank sidebar: the unavailable notice and toolbar were attached only to the hidden detail column. Home/return preserved that bug in the same process. This was a real UI defect, retained in native/REPORT.md rather than counted as success. The unavailable notice now appears in an empty sidebar and the same toolbar content is explicitly attached to each split column. Attaching it to the outer split container failed to expose actions on the compact iPhone column; that intermediate failure is retained in native-fixed/REPORT.md. The unavailable title uses a multiline label with full row width. Page/draft selection also requests the detail column on compact devices; that populated, provisioned navigation path is not proven by the unprovisioned fixture.

The DEBUG flag --scriptum-shared-foreground-ui-qa presents an unprovisioned session with a unique temporary-directory locator. It creates no fabricated CloudKit grant or page and does not change the production provisioned gate. The host is excluded from Release.

## Checks and limits

Controlled asynchronous tests verify burst coalescing, no idle/background dispatch, serial successor work, cancellation/replacement ownership, and rapid return while an operation ignores cancellation. The unprovisioned shared-session test exercises activation/deactivation and still verifies no cloud files or edits. The full model suite and Xcode MCP build passed after the correction; receipts are alongside this record. A separate native-final report records the final runtime proof, with its precise source-hash and EndSession timing.

Unsigned optimized Release compilation is a build check only. Actual account activation, autosync send/receive, revoked grants, foreground/background cancellation during a real CloudKit request, physical device behavior, and multi-device collaboration remain unverified while capability/schema/profile prerequisites are unavailable. This change is not a new TestFlight distribution.
