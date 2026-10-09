# Build 3 release preflight

Candidate source: `dbe1750`, including simplified writing-action dialogs and pinned Apple Foundation Models Utilities. Intended version: 1.0.0 (3); CURRENT_PROJECT_VERSION=3 was passed to preflight commands without changing the currently committed project version.

The optimized Release build for the actual iphoneos SDK succeeded with CODE_SIGNING_ALLOWED=NO. This confirms release compilation, not code signing, archive export or upload.

Signed archive attempt with existing cached profiles failed. Xcode reported that the iOS Team Provisioning Profile for com.mobilebox.Skriptum lacks iCloud capability, iCloud.com.mobilebox.Skriptum and the iCloud container/services entitlements. No provisioning-update flag was used and no developer-portal capability was altered by this attempt.

Current Apple Developer App ID readback for Team SP73Z8JWXM confirms PCC enabled and iCloud disabled. The portal is prepared at the specific App ID configuration. Action-time approval is requested for iCloud/CloudKit activation, the Scriptum-only container and CloudKit push capability. This approval is required by the computer-use confirmation policy for security-sensitive access changes, despite the broader development authorization.

Pending: capability/container provisioning, suitable refreshed signing profiles, signed archive, export/upload, processing, compliance and internal TestFlight assignment. Production CloudKit schema and real synchronization/collaboration are not yet verified. No new TestFlight build has been uploaded.
