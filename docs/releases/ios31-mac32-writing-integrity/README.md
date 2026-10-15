# Scriptum 1.0.1 — iOS31 / native Mac32

**Both builds are available in TestFlight (Im Test) and submitted to App Store review (Warten auf Prüfung).** The owner explicitly authorized replacing the old iOS11/Mac14 submissions: “Ja, beide ersetzen und neu einreichen.” Those two submissions now show Entfernt. The new iOS31 submission was received on 15 October 2026 at 19:32 CEST; native Mac32 at 19:34 CEST. Existing automatic publication after Apple approval remains selected. Approval and public availability are pending.

| Platform | Build | TestFlight ID | Review submission |
| --- | --- | --- | --- |
| iOS/iPadOS | 1.0.1 (31) | 4338ae48-38bf-4843-8043-e604a74584b3 | 6b2140b2-3603-4ff0-84ff-a93e1f892d9e |
| Native macOS | 1.0.1 (32) | ad4d0a4f-b014-4eb7-b5b6-ac56d69e9f7c | 41edfce1-69ac-4420-a95d-6887c4bcba26 |

[Final TestFlight readback](testflight-group-final.txt) and [image](testflight-im-test.png) show both builds in Mark – Intern, with the one existing tester. Processing, export compliance and saved German test notes are complete. [iOS review receipt](ios-review-final.txt), [Mac review receipt](mac-review-final.txt), [review list](review-list-final.txt) and [both waiting](both-waiting-review.png) record actual final portal states. German is the existing iOS Store locale; its What's New and both platform review notes were updated. The first Mac version exposes no What's New field, so no such Mac field was changed. No privacy website or Jimdo publication occurred.

## Delivered changes and verification

Clean archive source: `bf6dc7e43e735d82cc86f7911d0c5e5ed95aad33`. [Reproduced failures, corrected source, tests and visual export evidence](../../qa-writing-integrity-20261015/README.md):

- Apple grammar retains sentence context at long-manuscript boundaries with single ownership of each finding. All 83 quality tests pass, including the opt-in real macOS Apple service witness; this count also includes retained historical adapter tests.
- PDF, DOCX, HTML and EPUB share heading/title sizing. All 134 export tests pass; an actual sample PDF was rendered and visually inspected.
- Read-only AI context removes Markdown image references using the existing parser. Editable targets retain exact source bytes; all 37 AI tests pass using a captured in-process provider request.

Both official Xcode MCP SDK builds pass. EVIDENCE_BINDINGS.json binds all nine tested source files to the archives. Actual production compilation lists include the corrections and exclude the four obsolete LanguageTool adapters. Apple-only grammar remains the production route; no bundled third-party grammar runtime or checking-server local-network declaration is present.

Both exact exported apps pass all 25 iOS / 28 Mac distribution checks, including signatures and Production CloudKit configuration. Both uploads were accepted at 19:21:53 CEST. The native Mac installer has its trusted Apple-issued team certificate. ARTIFACTS.json records package hashes; PAYLOAD_CHECKS.json records exact versions and source-identical privacy manifests. An independent read-only audit verified both package hashes, all nine source bindings and all 129 retained artifact files.

No app, device or simulator UI was launched during this delivery. Real collaboration between two iCloud accounts, measured 20-language grammar coverage and the remaining R01–R15 requirements keep their separate evidence limits. Actual Apple approval is not implied by upload, TestFlight access or review submission.

## Retained evidence and cleanup

Archives, packages and expanded exported apps remain in `work/release-ios31-mac32-writing-integrity` under the task working directory. Only the two owned DerivedData directories were removed after all archive/export/upload jobs exited: 665,256,529 regular-file bytes. All 129 retained artifact files remained hash-identical (CLEANUP.json and LOCAL_ARTIFACT_MANIFEST.json). No GitHub workflows were introduced.
