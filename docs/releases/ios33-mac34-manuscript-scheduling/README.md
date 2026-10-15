# Scriptum 1.0.1 — iOS33 / native Mac34

**Both builds are Im Test in Mark – Intern and Warten auf Prüfung in App Store Connect.** iOS33 was submitted on 15 October 2026 at 20:06 CEST; Mac34 at 20:11 CEST. Previous iOS31/Mac32 submissions show Entfernt. Automatic publication after Apple approval remains selected; approval and public availability are pending.

| Platform | Build | TestFlight ID | Review submission |
| --- | --- | --- | --- |
| iOS/iPadOS | 1.0.1 (33) | f4781a81-6dcb-4109-8ab7-fd855e9f8df2 | 124a8656-c99b-4774-9dad-21a55520a43d |
| Native macOS | 1.0.1 (34) | c243dd95-a97e-4b15-83c6-d5f2e6da7dab | 9e62c508-c127-4b33-9536-36d48909ba4b |

[TestFlight group receipt](testflight-group-final.txt), [iOS review receipt](ios-review-final.txt), [Mac review receipt](mac-review-final.txt), and [both waiting](both-waiting-review.png) record actual final states. The group retains one existing tester. Export compliance, processing and German test notes are complete. German iOS What's New and both review notes describe the selected builds. No privacy-site or Jimdo change occurred.

## Changes and bounded verification

Archive source: `7a254789a352ffd901be9b385b903e1c8c048df9`. [Focused regression evidence](../../qa-manuscript-scheduling-20261015/README.md) covers actual DOCX image sizing within tables/quotes/lists and final scheduled-send admission after asynchronous provider checking. Two A4/Letter export cases and eight scheduling parameter cases pass; the latter focused run also passes two existing reservation persistence failure tests. Corrected DOCX output was rendered through LibreOffice and visually inspected. Apple-only grammar remains unchanged.

Per the owner's latest instruction, previously confirmed unchanged features were not retested. The earlier coupled scheduling run is retained as evidence, but no new whole-project audit, physical-device run, simulator run or live provider request was added. Official Xcode MCP compiles final iOS and native Mac sources successfully; both Release archives succeed. Final exported apps pass all 25 iOS / 28 Mac distribution-package checks. Uploads were accepted at 19:58:21 / 19:58:31 CEST. ARTIFACTS.json binds both exported packages, and EVIDENCE_BINDINGS.json binds changed sources and configuration. Source changes introduce no dependency.

## Preservation and limits

Archives, packages, expanded exports and logs remain in `work/release-ios33-mac34-manuscript-scheduling`. Only the two owned DerivedData directories were deleted after all archive/export/upload processes completed: 665,620,378 regular-file bytes. All 105 retained artifact-file hashes remained unchanged. See CLEANUP.json and LOCAL_ARTIFACT_MANIFEST.json. No GitHub workflows were added.

Microsoft Word itself was not run; actual rendering used LibreOffice. Live cross-account iCloud collaboration and measured grammar quality in 20+ languages retain their prior evidence limits. This release report does not claim Apple approval or publication.
