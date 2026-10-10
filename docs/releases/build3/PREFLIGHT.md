# Build 3 release preflight

Candidate source: `dbe1750`, including simplified writing-action dialogs and pinned Apple Foundation Models Utilities. Intended version: 1.0.0 (3); CURRENT_PROJECT_VERSION=3 was passed to preflight commands without changing the currently committed project version.

The optimized Release build for the actual iphoneos SDK succeeded with CODE_SIGNING_ALLOWED=NO. This confirms release compilation, not code signing, archive export or upload.

Signed archive attempt with existing cached profiles failed. Xcode reported that the iOS Team Provisioning Profile for com.mobilebox.Skriptum lacks iCloud capability, iCloud.com.mobilebox.Skriptum and the iCloud container/services entitlements. No provisioning-update flag was used and no developer-portal capability was altered by this attempt.

Current Apple Developer App ID readback for Team SP73Z8JWXM confirms PCC enabled and iCloud disabled. The portal is prepared at the specific App ID configuration. Action-time approval is requested for iCloud/CloudKit activation, the Scriptum-only container and CloudKit push capability. This approval is required by the computer-use confirmation policy for security-sensitive access changes, despite the broader development authorization.

Pending: capability/container provisioning, suitable refreshed signing profiles, signed archive, export/upload, processing, compliance and internal TestFlight assignment. Production CloudKit schema and real synchronization/collaboration are not yet verified. No new TestFlight build has been uploaded.


## Current Build 3 candidate (2026-10-10)

Source base32d80c2 now includes refreshed icon, native Settings licenses, activation/proposal handling, foreground execution and explicit iOS background processing. Project build number is durably3 in project.yml/generated project, not merely a command-line override. Unsigned optimized iphoneos Release compilation passed; actual app Info.plist confirms1.0.0(3), com.mobilebox.Skriptum, iOS27, processing mode and one permitted processing ID. Settings.bundle is present. Binary SHA256 and scoped evidence are in CURRENT_PREFLIGHT.json. Checked DEBUG activation/foreground-fixture markers are absent from the Release binary; this is a marker check, not proof of every possible DEBUG path.

Full local suite:58 XCTest plus414 executed Swift Testing tests passed, with3 initially skipped opt-ins (runner headline417 includes those skips). The2 public price-feed opt-ins were then explicitly enabled and passed, giving474 executed successes,1 historical own-server fixture still skipped. Anonymous current OpenAI/Anthropic price HTTP/parser checks sent no API key, manuscript or inference. Controlled/unit tests do not prove live inference, CloudKit, OS-granted background execution or physical device QA.

Current signed archive preflight failed with the same concrete iCloud capability/container/services mismatch (exit65). No allowProvisioningUpdates flag was used. Embedded metadata of matching cached development and App Store profiles includes PCC, lacks iCloud/container/services and APS. CMS signature verification was not supplied by this metadata extraction; the profile mismatch is independently emitted by Xcode. Fresh read-only Developer portal for the exact Team/App ID confirms PCC1/iCloud0/Push0, Save disabled, no mutations. Screenshot icloud-capability-pending.png captures the unchecked iCloud row.

A precise action-time confirmation is pending for enabling iCloud/CloudKit, only iCloud.com.mobilebox.Skriptum, and CloudKit Push on this App ID. Computer/Browser Use Confirmation Policy requires confirmation for new security-sensitive access despite broad project authorization. No approval response or capability change was inferred from elapsed time. Existing production iCloud runtime gate remains disabled; capability/profile refresh alone will not prove production schema or real collaboration. No new signed archive, export, upload or internal assignment has succeeded. Existing distributed Build2 remains a separate older verified delivery. Full R01–R15 acceptance and actual current TestFlight delivery remain open.
