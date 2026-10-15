# Scriptum iOS 1.0.1 (12) — iCloud local storage correction

Preparation after actual Build11 feedback at 08:51 CEST on 15 October 2026. The owner explicitly chose to keep the current iOS11 Store submission for now; it must not be withdrawn or replaced without a new instruction. The native Mac14 submission is also unchanged. The Release archive and App Store export have succeeded. All 25 distribution checks pass, including actual signing and Production CloudKit entitlements. Apple accepted the upload at 09:21 CEST. The processed iOS build is assigned to Mark – Intern and shows “Im Test” in the actual internal group. Export compliance is complete. No replacement Store submission is planned.

## Change

Foundation-provided app document/support locations use POSIX canonical paths, including first-launch missing suffixes, before the existing strict descriptor no-follow checks. The old Foundation-only normalization reproduces the exact Outbox.unsafeFile failure with a system-alias fixture. No iCloud credentials, container entitlements, endpoint, manuscript bytes, journal contents or security checks are bypassed or reset. [Feedback and red/green regression](../../qa-icloud-unsafe-file-20261015/REPORT.md).

## Verification

806 root tests actually executed and passed, four optional tests skipped. All 22 targeted system-root/session/outbox tests passed; the red test reproduced unsafeFile before correction. An own iOS27.0 simulator runtime probe reproduces the alias-plus-missing-suffix failure and a successful canonical-path outbox roundtrip; the actual production helper and both official Xcode MCP SDK builds pass. This is not physical-device or live CloudKit-transfer proof. No additional mandatory device gate is imposed.
