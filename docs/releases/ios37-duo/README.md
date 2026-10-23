# Scriptum iOS 1.0.3 (37) — native Duo launch layout

Source commit: `16767288bc2ab210ed6964fcc228004bbd8f5a8a`. The recorded build-input hashes match the signed archive. Xcode27.2 (27B48), iOS27.2 SDK. Mac1.0.2(36) is unchanged and its existing review was not cancelled.

The previous full-window-positioned wordmark overlapped the system document browser. The launch scene now uses Apple's native title layout. The paper background and actual library-button binding remain. No document/storage/Cloud/AI implementation changed.

## Verification

Official Xcode MCP built and ran the actual app on iPhone Duo. The outer-display title and button are readable; tapping opens the library. Synthetic text remains after device rotation. The app surface stayed466×678, so no inner-display/folding claim is made. A separate iPad regular-width run at834×1210 and1210×834 verified readable launch content and a real tap into the three-column library. See `qa/DUO_UI_RESULT.md` and screenshots.

Two document-registration checks passed after project generation. Release archive/export succeeded. All25 signed-export gates passed, including Production CloudKit/PCC; actual package version37 and SDK27.2 verified. Some pre-existing third-party package warnings were emitted by the newer SDK; no App build errors. Full unchanged functional/language/cloud/AI suites and physical-device testing were not repeated.

## Delivery

Apple accepted and processed the upload. Build37 is **Im Test** in existing internal group **Mark – Intern**, one tester, with German test notes saved. Store version1.0.3 (37) was submitted on23 October2026 at21:41 Europe/Berlin and is **Warten auf Prüfung**. Submission `8ef1b9c8-5a14-4d8f-a57f-d5a7d4672085`; automatic publication after approval selected. See STATE.json, testflight-37.png and store-waiting-37.png. This is not Apple approval or public publication.

Archives, dSYMs, exported IPA and expanded app remain in `work/release-ios37-duo` in the task workspace. Only owned temporary DerivedData was removed after successful terminal upload completion, preserving the IPA hash.
