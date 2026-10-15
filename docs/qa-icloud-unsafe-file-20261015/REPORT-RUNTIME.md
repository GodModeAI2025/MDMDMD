# iOS outbox path probe and compilation — 2026-10-15

The official RunCodeSnippet executed in Xcode's iOS 27.0 simulator preview host, bundle com.mobilebox.Skriptum, metadata build 11. Source was already the POSIX canonicalization fix; no pre-fix application binary was measured. Source hashes are in source-at-snippet-request.json.

An own Application Support alias with a missing suffix reproduces the contract failure: Foundation-only resolution leaves the alias unresolved and the actual ICloudSyncJournal throws unsafeFile. The actual production WorkspaceSystemContainerRoots.canonicalSystemDirectory resolves that fixture; Journal enqueue/reopen preserves one record, 41 payload bytes and its revision exactly. Evidence: runtime-probe-production-helper.json and runtime-probe-production-helper-receipt.json. Root has retained the safe JSON in repository QA documentation.

The simulator's actual container has neither /var nor /private/var prefix; its global no-follow ancestor traversal succeeds. Thus a physical iPhone sandbox denial and the reporter's exact device path were not reproduced. This proves the synthetic missing-suffix alias regression and fixed helper behavior, not physical-device CloudKit sync. No iCloud activation, provider request or primary library payload was used.

## Compilation

MCP updated Skriptum CURRENT_PROJECT_VERSION to 12 and read back evaluatedValue 12. Both compile sequences switched scheme and destination within one bridge connection:

- iOS: Skriptum / Any iOS Device (arm64), BuildProject successful, errors empty. Receipt: work/review-release-20261014/icloud-unsafe-ios12-build-2-BuildProject.json. Build log: BuildProject-Log-20261015-091021.txt.
- Mac: SkriptumMac / My Mac, BuildProject successful, errors empty. Receipt: work/review-release-20261014/icloud-unsafe-mac14-build-2-BuildProject.json. Build log: BuildProject-Log-20261015-091317.txt.
- Metadata receipts: icloud-unsafe-ios-version12-0-UpdateTargetBuildSetting.json and icloud-unsafe-ios-version12-1-GetTargetBuildSettings.json in the same receipt directory.

Final actual Info.plist readback in final-build-metadata.json confirms Debug-iphoneos/Skriptum.app = 1.0.1 (12), platform iphoneos; Debug/Scriptum.app = 1.0.1 (14), platform macosx. These are source compilation results, not archive/upload or release proof.

## Cleanup

Own debugger launch was stopped through StopProject; DeviceInteractionEndSession reported session no longer exists. Preview hosts were ended and own PIDs 95198, 98948, 99657 are absent at final check. No bridge or QA process remains owned by this check. No physical device, portal action, source edit, Git mutation or release operation was performed here; only the explicitly authorized Xcode target version serialization changed. Xcode/DeviceInteraction access is released to parent.
