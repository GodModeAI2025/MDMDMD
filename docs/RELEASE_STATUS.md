# Scriptum release status

Updated 2026-10-15, 13:01 CEST. The complete [R01–R15 requirements](REQUIREMENTS.md) remain binding. Earlier checkpoints below retain their original evidence boundaries.

## Latest local integration after iOS 16 / Mac 17

The [authoring integration checkpoint](qa-authoring-integration-20261015/README.md) combines CommonMark outline navigation in both inspectors, one semantic PDF heading for mixed image/text fragments, and native parent assignment for new owner comments/replies/revisions on already shared pages. Both official Xcode-MCP SDK builds pass. The final Core/WorkspaceModel run passes 466 executed cases with three optional skips; the separate Export run passes 156 cases with one optional skip. Xcode accepted the renewed project connection without another permission dialog.

These new source corrections are **not yet in the delivered iOS 16 / Mac 17 builds**. No new upload, app/simulator launch, live participant sync or Store change is claimed. Previously private metadata is not retroactively shared, and dynamic page/image expansion of an existing share remains open. Existing Store submissions iOS 11 / Mac 14 are retained.

## Current internal release — iOS 16 / native Mac 17

**iOS 1.0.1 (16) and native Mac 1.0.1 (17) are available in Mark – Intern with actual Im Test status.** Both uploads, processing, export compliance and saved German test notes are complete. The clean archive source is `9358bde9749d5a18d79d39743467a89d49ffa65f`; actual exported apps pass all 25 iOS / 28 Mac distribution checks. The renewed Xcode-MCP project connection and both SDK builds succeeded. [Release receipts and portal evidence](releases/ios16-mac17-quality/README.md).

The iOS launch-button correction is now included, alongside complete-response validation, proofreading of visible link/image text and PDF destinations for image-first headings. These builds retain the iCloud correction delivered in iOS 14 / Mac 16. Launch navigation and successful live sync on the affected iPhone remain unverified; the optional simulator exception is still unanswered and was not treated as a mandatory release gate. Native grammar remains excluded. Existing Store submissions iOS 11 / Mac 14 were not withdrawn or replaced.

## Latest native source research

The [Irish source comparison](qa-native-irish-source-20261015/REPORT.md) reproduces all 2,081,826 morphology entries, all 3,559 tags and the Gaelspell 4.8 text resources; 17 focused tests pass. The newer [full Ukrainian resource comparison](qa-native-ukrainian-generated-20261015/REPORT.md) matches all 6,699,678 synthesis rows, all 7,474 synthesis tags and all 3,472,529 spelling words. The remaining 9,195 POS rows and 404 general tags are entirely in the missing `:obsc` segment; original spelling-frequency inputs also remain absent. The [earlier Ukrainian investigation](qa-native-ukrainian-source-20261015/REPORT.md) retains its narrower 11/17 resource and 47-lemma evidence. Full preferred-source reconstruction, original release-tool identity and distribution remain open; this research does not activate the native engine.

## New owner feedback from iOS12 — local Connection.superseded correction

The [Apple-MCP investigation and regression](qa-icloud-connection-superseded-20261015/REPORT.md) reproduce a first-journal-creation identity change: Foundation standardization removes /private only after the directory exists, invalidating Scriptum's own connection revision. The runtime key now has stable physical identity, while actual file paths and all no-follow/account/disconnect checks remain unchanged. Three permanent regressions, both SDK builds and 814 executed tests across two successful scoped runs pass (four optional skips); the initial full run stalled in Apple FontRegistry during unchanged PDF tests and remains explicitly recorded. Live sync on the affected iPhone is still unproven.

The preceding iOS13/Mac15 archives were uploaded successfully but retain the old code and were withheld from internal distribution after this feedback. [Their receipts](releases/ios13-mac15/README.md). The corrected release **iOS1.0.1(14) / native Mac1.0.1(16)** is now processed, export-compliant and available in **Mark – Intern** with actual **Im Test** status for both platforms (verified 15 October 2026 at 11:16 CEST). German build notes are saved. [Release evidence](releases/ios14-mac16-icloud/README.md). The existing iOS11/Mac14 Store submissions remain unchanged. This is internal distribution, not App Review approval or publication.

## iOS 1.0.1 (12) — iCloud correction in internal TestFlight, 15 October 2026

The local `Outbox.unsafeFile` alias regression is corrected and covered by 806 passing executed tests, four optional skips. Both official Xcode MCP SDK builds pass. The actual exported iOS12 app passes all 25 distribution checks; Apple accepted the upload at 09:21 CEST. Processing and export compliance are complete; iOS12 is available in Mark – Intern with actual status “Im Test”. The owner explicitly chose to keep Store submission iOS11; neither that submission nor Mac14 is withdrawn or replaced. [Release evidence](releases/ios12-icloud/README.md).

## Local R10 source correction after iOS12

The [window-ownership checkpoint](qa-window-ownership-20261015/REPORT.md) moves launch presentation from one App-wide state to each launch view, retains closing through host lifetime with a weak controller back-reference, consumes duplicate requests in the local window, and passes real scene window actions explicitly into the UIKit-hosted library. Three actual action bars use safeAreaBar. Both official Xcode MCP SDK builds and 811 executed root tests pass (four optional skips). The simulator run was expressly denied by automatic approval review and was not retried or replaced; current launch/rotation/multiwindow runtime behavior remains unverified. This is a source/lifetime correction, not proof that the historical rotation bug is fixed. No native grammar activation, upload or Store change in this checkpoint.

## Local development after the iOS12 upload — task progress

Source c9128ef corrects the exhausted-task status from the real PCC checkpoint. The native task list now derives progress from the eligible next occurrence and current scoped runs, distinguishes queued/running/finished planning, shows the last run result, and suppresses impossible dates and inactive actions. No task, history or budget migration is performed. All 811 actually executed root tests pass (four optional skips), and both official Xcode MCP SDK builds pass. An isolated iPhone17e simulator check confirms both finished rows and opening/closing the preserved proposal comparison. This correction is not part of the already delivered iOS12 or Mac14 builds and changes no Store submission. [Verification](qa-schedule-progress-20261015/REPORT.md).

## Native grammar synthesis-source checkpoint

The [full Portuguese synthesis comparison](qa-native-synthesis-source-20261015/README.md) binds all 16,679,668 release form/lemma/POS records and all 1,386 tag members to the previously verified editable sources. Nine Python tests and eleven Java adapter controls pass. Spelling, byte-identical serialization, other artifacts and final distribution/relinking remain open. No production dependency, upload or Store submission changes.

## Native grammar source work after the upload

The [Portuguese tagger checkpoint](qa-native-portuguese-source-20261015/README.md) now binds the official v1.2.0 source and reproduces all 16,679,668 actual Release dictionary form/lemma/POS rows from 204 verified editable inputs. Six verifier regressions and the local source-material package readback pass. Checked-in older dictionary snapshots remain recorded as different. This advances R14 source preparation; synthesis/spelling, other artifact and native-distribution work remain open. No new native grammar dependency or build is shipped by this research step.

## New Build11 feedback · local outbox path failure

The actual new TestFlight screenshot submitted at 08:51 CEST confirms **Outbox.unsafeFile** on iPhone17ProMax/iOS27.2, Build11. The owner-supplied diagnosis confirms the same code. This is local outbox admission after successful account lookup, not the earlier account-availability message. A permanent red regression reproduces Foundation system-alias normalization plus an initially missing Application Support suffix being rejected by the existing no-follow traversal. The narrowed system-root POSIX canonicalization fixes that regression while preserving all interior no-follow, ownership and file checks. All 806 actually executed root tests pass (four optional tests skipped), including 22 targeted cases. [Actual feedback and scope](qa-icloud-unsafe-file-20261015/REPORT.md).

iOS12 is available in internal TestFlight as recorded above. The owner explicitly chose to keep the iOS11 Store submission for now after the exact withdrawal was denied by automatic approval review. That submission and Mac14 therefore remain unchanged. No withdrawal or replacement is authorized by the current feedback instruction alone.

## New release delivery · iOS 1.0.1 (11), native Mac 1.0.1 (14)

Both Release archives were built from clean source `4b9b222`, exported and verified (25 iOS / 28 native Mac distribution checks). All 804 actually executed root tests pass, with four optional cases skipped; the 13 distribution-verifier tests also pass. Apple accepted both uploads at 08:27 CEST. Processing and export compliance are complete, and both show **Im Test** in **Mark – Intern**. [Source, signatures, tests, images and receipts](releases/ios11-mac14/README.md).

iOS 11 replaces the withdrawn iOS10 submission and is **Warten auf Prüfung**, submitted at 08:38 CEST with automatic release after approval (`4625ac11-3d3e-455a-9db9-395d8766bc2d`). Mac13 was withdrawn for Mac14, whose exact native light/dark Store images are submitted as unchanged raw JPEGs after initial PNG processing stalled. Mac14 is **Warten auf Prüfung**, submitted at 08:49 CEST (`64c9f5f0-8444-491d-96b6-0e88590a1e10`) with automatic release after approval. No approval or publication of these new builds is claimed. The affected iPhone account condition remains unresolved; no further device action is required from the owner in this release workflow.

## Further native Mac design and account-diagnostic work · 15 October

The owner's new [Mac screenshot and design review](qa-mac-design-20261015/REPORT.md) prompted a compact native title bar, named view/AI controls, consistent sidebar symbols and continuous subtle paper without a card frame. This work is included in the new iOS11/Mac14 delivery described above. The owner says the latest iOS build is installed but currently has no device available to copy a diagnosis. Account-access and authentication messages are now distinct; the bounded error code is visible next to an iCloud failure and retained when opening sharing. Two focused tests pass for fresh retry diagnosis, sharing-code preservation, unchanged local bytes and no sync-file creation on denied account access. These are diagnostic corrections, not proof of resolving the owner's iPhone account condition.

A [real, once-only scheduled PCC inference](qa-pcc-task-completion-20261015/REPORT.md) now completes in the native Mac app and stores the actual summary. The original 151 UTF-8 bytes remain exact, and the task was cancelled after the single run with no future occurrence. This closes that specific unverified runtime path; iOS background execution, other providers and the full R09 scope are not thereby proven. Minor result formatting remains open. The later read-only exhausted-task status correction is recorded in qa-schedule-progress-20261015; it is source work after the iOS12 upload, not included in that delivered build. The separate design check found that merely opening Lektorat automatically sent its own synthetic text to PCC; no proposal was accepted. This implicit request is removed in the candidate, leaving the visible Starten button as the trigger. The follow-up uses the existing local debug provider. iCloud stays off throughout these design checks.

## Previous uploads · iOS 1.0.1 (10), native Mac 1.0.1 (13)

The user's clarification exposed a real iPhone navigation defect: opening Spaces selected the first page automatically, hiding the library toolbar. The [accepted simulator check](qa-icloud-entry-20261015/REPORT.md) now verifies a visible single launch action, initial page list, and direct iCloud access from the library toolbar and page menu. Rejected two-action launch layouts are preserved as failed evidence and are not shipped.

The [manuscript checkpoint](qa-icloud-manuscript-20261015/REPORT.md) fixes base64 capacity overflow in durable transport files and batches journal commits/exact-revision acknowledgements. Both failures were reproduced before correction. 128 affected tests and 803 actually executed full-suite tests pass; four optional full-suite tests were skipped. A real native Mac Production run with 90 historical revisions finishes ready with no pending changes or error. This is not proof of the affected iPhone's actual sync. These uploads also include the earlier Mac/editor/diagnostic/PCC-policy changes recorded below. Live scheduled PCC inference had not yet been verified at upload time; the later real native Mac completion is recorded above.

Both were archived from clean source `4f1b4c5`, exported and checked: all 25 iOS and 28 native Mac distribution checks pass, as do 13 verifier tests. Apple confirmed upload success and processing started at 07:07 CEST on 15 October. [Source, signatures, hashes and upload receipts](releases/ios10-mac13/README.md). Owner sign-in is now complete. Both builds finished processing, export compliance is completed, and **Mark – Intern shows both Im Test**. They are submitted to Apple: iOS build 10 at 07:28 CEST (`40c06973-1467-41fe-b6ff-f4c45f59f552`), native Mac build 13 at 07:33 (`794a5772-a49c-450e-ac2e-f36b25e8efbf`); both show **Warten auf Prüfung**, with automatic release after approval. The previous iOS9/Mac10 submissions were withdrawn for these replacements. No approval/publication is claimed. The [new build-9 feedback and separate direct account-error screenshot](qa-icloud-account-20261015/REPORT.md) have now been read and remain distinguished; the device-specific account cause is unresolved. Two UIKit closure-conversion warnings and App Intents metadata warnings remain recorded; this is not a zero-warning claim.

## Native Mac task planning included in Build 13 · 15 October

The [Mac task checkpoint](qa-mac-tasks-20261015/REPORT.md) exposes the common persistent tasks, activation review, owner budgets and results from the Mac library menu, with foreground scheduling and native scrollable sheets. Actual sandbox QA found and fixed unnecessary ancestor-directory read access using search-only descriptors with all no-follow guards retained. Draft/budget restart persistence, individually accessible actions, cancellation and exact original-source preservation pass. Both MCP targets and native Mac Release pass; 99 tests are reported, with two optional price-network/document tests skipped (97 executed). That initial checkpoint kept scheduled PCC/ChatGPT price policies unavailable; the later [bounded PCC scheduling policy](qa-pcc-scheduling-20261015/REPORT.md) adds PCC eligibility, while ChatGPT scheduling remains unavailable. That initial checkpoint did not verify successful live scheduled inference; the later real Mac completion is recorded above. This work was absent from Build 12 and is included in uploaded Build 13.

## Editor concurrency refinement included in Build 13 · 15 October

The [actor-bound editor checkpoint](qa-editor-actor-20261015/README.md) resolves the two app-source Sendable warnings with explicit main-actor callbacks. Both Xcode MCP targets and a strict native Mac Release build pass, as do ten existing input/preference tests. Dependency migration and App Intents metadata warnings remain recorded. Uploaded Build 12 is unchanged.

## Previous upload: native Mac 1.0.1 (12) · 15 October

The [Mac workflow checkpoint](qa-mac-workflows-20261015/REPORT.md) integrates templates, heading links/backlinks, window-local Back/Forward, the attachment dashboard and revision-bound structured table editing. Fifty selected domain regressions and final native Mac/iOS-arm64 Xcode MCP builds pass. Actual isolated Mac interactions verify full template/source preservation, copied image metadata, table apply/Undo/Redo, dirty-cell protection, navigation with pending input, cold-start source equality and opening pages from attachment usage. Build 12 from `64cbfbf` passes all 28 exported-distribution checks and 13 verifier tests. Apple confirmed upload success at 05:26 CEST and reported processing started. [Build 12 receipts and limits](releases/build12/README.md). Processing completion, export compliance and internal TestFlight availability are not yet observed; owner browser authentication remains pending. No existing review submission was withdrawn or replaced. Native grammar-engine production integration and the full R01–R15 scope remain open.

## Mac paper-canvas and focus refinement included in Build 12 · 15 October

The [further Mac UI checkpoint](qa-mac-paper-20261015/REPORT.md) separates the manuscript sheet from the workspace. The subsequent [editorial Mac refinement](qa-mac-editorial-20261015/REPORT.md), source `7b78afb`, further reduces navigation texture, adds a centered bounded sheet and a working ⌥⌘F focus mode, clarifies the inspector and removes a constraint-loop transition found during actual QA. Native Xcode MCP builds and isolated light/dark, resizing, source/view and full Unicode readback checks pass. These refinements are included in uploaded Build 12 above; Build 11 below is the previous uploaded interface checkpoint.

## Previous upload: native Mac 1.0.1 (11)

The refined Mac interface is archived and exported from `b537530`. The actual exported app passes all 28 distribution checks, and Xcode MCP builds the current version. Apple confirmed upload success on 15 October at 02:48 CEST. [Build 11 receipts and limits](releases/build11/README.md). Processing completion, export compliance and internal TestFlight assignment are not yet observed: the browser is logged out and the owner has been asked to sign in. No existing review submission was withdrawn or replaced. The unshipped native grammar engine is excluded; iOS was not uploaded in this checkpoint.

## Previous verified internal delivery: Mac 1.0.1 (10), iOS/iPadOS 1.0.1 (9)

Mac source `429cb112adfd81a2669c6938d57a92b373862503` refines the native Mac library, page list, writing toolbar, typography, appearance settings and Info/Comments/History inspector. [Visual audit and native interaction evidence](qa-mac-ui-20261014/REPORT.md). The new-page preview cell-height defect found during this work was corrected and verified in the actual app. Native formatting/Undo, Unicode and Markdown preservation, comments/replies, search, view switching and separate windows were checked. Both Mac Debug and iOS Xcode MCP compatibility builds succeed; the two focused preference-storage tests pass.

Mac build 10 passed all 28 distribution checks, uploaded successfully, completed Apple processing/compliance and is **Im Test** in **Mark – Intern**. It was submitted on 15 October at 00:01 CEST and shows **Waiting for Review**, with automatic release after approval. Three real Mac screenshots and review notes were updated. [Build 10 state and receipts](releases/build10/STATE.json). The previous Mac build 9 review was withdrawn for this replacement. iOS build 9 remains **Waiting for Review** in submission `c7b03f6f-f8cc-4b14-8a14-e78300c5aeab`. Neither new platform version is approved or published.

Mandatory additional device tests remain removed. Jimdo stays separate. Signing checks do not establish live iCloud/PCC behavior. Existing Release warnings in BlockEditorBinding and WritingPreferencesSheet remain recorded in the archive log; no zero-warning claim is made.

## Mac visual refinement uploaded in Build 11 · 15 October

The [Mac interface checkpoint](qa-mac-ui-20261015/REPORT.md) adds quieter paper-backed navigation, page counts, a direct Lektorat button, a cleaner writing canvas and an editable title in the compact inspector. At narrow widths the native library sidebar hides when the inspector opens, keeping the text readable; both opening and resizing paths were checked. The actual Mac Xcode MCP build and focused native interactions pass in an isolated library, including an exact 528-character source witness after relaunch, light/dark appearances, shorter-window layout, search and inspector/view switching. An experimental focus layout was removed after a constraint-loop crash; the final code retains the established native three-column structure. It is now included in uploaded Mac Build 11; internal TestFlight availability remains unverified as described above.

## Unshipped R14 app-runtime integration · 15 October

The further [data/source-package checkpoint](qa-native-data-release-20261015/README.md) verifies complete Catalan/Valencia tagger-row correspondence, adds a 12-artifact source-review matrix and preserves distinct Irish/Ukrainian notices and gaps. Eighteen packaging/provenance-tool regressions pass. The local source-material mirror has full hash readback but is not approved for customer redistribution; applicable terms and final relinking/source completion remain open. No app dependency, Settings.bundle, release build or upload changes in this checkpoint.

The further [upstream linguistic checkpoint](qa-native-linguistic-20261015/README.md) retains 276 preselected positive/negative cases with complete native/JVM match-object parity, 122 safe source/revision-bound corrections, 15 findings without replacements and one explicitly manual-only Swedish suggestion. Two overlapping Irish XML IDs and the original strict failures remain documented. All 62 quality tests, nine evidence-tool regressions and the iOS Xcode MCP build pass. This selection proves grammar/style classifications in 15/four languages respectively, not comprehensive quality in 20+. [Further data-source checks](qa-native-data-review-20261015/README.md) bind complete Dutch/Asturian resources and rebuild all 259,353 English tagger rows from editable source. Production integration and full distribution/quality completion remain open; no new build was uploaded.

The [application-runtime checkpoint](qa-native-app-runtime-20261015/README.md) connects a verified on-device driver to the shared Textprüfung flow, with explicit text language and matching Apple spelling. All 59 quality tests, 29 native host examples and final regular iOS/Mac Xcode MCP builds pass. Actual local Mac/iOS-arm64 apps compile/link with the framework and all 1,888 byte-verified resources; both development signatures pass. A resource-read autorelease repair reduces the measured same-corpus host peak from 759 MB to 418 MB. Xcode approval now succeeded; the [actual native Mac dialog](qa-native-dialog-20261015/README.md) passes German/English correction, source-protection and Undo within and after the sheet. These are exact AX-editor-value checks, not independent disk/cold-start proof; iOS execution is still unverified. The regular project still excludes the native binary/data dependency. Source/relinking/distribution completion and broader quality acceptance remain open; delivered builds are unchanged.

## Unshipped R14 source bindings · 15 October

The [source-binding checkpoint](qa-native-source-bindings-20261015/README.md) retains pinned Graal, Java-base and iOS static-SDK sources, the actual bundled Java sources, corrected root/license notices and a source-material mirror. Complete French and Spanish tagger-source comparisons pass for 666,726 and 3,689,171 records respectively, with frequency/serialization scope explicitly excluded. Thirteen provenance/packaging tests pass. Ten other linguistic-data source reviews, native binary correspondence, final distribution/relinking obligations and production integration remain open. No engine app route or new TestFlight upload is enabled by this checkpoint.

## Unshipped R14 framework/distribution checkpoint · 15 October

The [distribution checkpoint](qa-native-distribution-20261015/README.md) packages separate iOS/Mac arm64 frameworks and the verified raw resource bundle. It fixes the missing iOS runtime SDK pin, proves complete native linking and passes all native groups plus the real Swift correction pipeline through direct framework imports. Swift consumers link for both target platforms; host execution and strict ad-hoc signature checks pass. The actual Mac app builds through Xcode MCP with explicit arm64 for macOS 27's supported hardware. Published source archives for 132 artifacts and corrected license/documentation materials are retained; SDK/data-source and final distribution/relinking obligations, broader acceptance and app availability remain open. This checkpoint does not enable the native route or upload a new TestFlight build. R14 remains incomplete.

## Unshipped R14 application-module integration · 15 October

The [native worker milestone](qa-native-worker-20261015/README.md) passes the real host engine through the actual Swift quality module, Markdown protection and revision-bound correction admission for all 29 synthetic witnesses. Prompt cancellation and process-wide serialized cleanup have regression coverage. The integration test found and fixed a missing Chinese HanLP resource path, now covered by a permanent native regression and pinned metadata. All five native groups, 53 Swift quality tests, both Xcode MCP app builds and corrected iOS static compilation pass. The native iOS archive is about 149 MB. Production native UI activation, final framework/resource/source/license packaging, iOS execution and broader linguistic acceptance remain open. No new build was uploaded; R14 remains incomplete.

## Unshipped R14 external-resource progress · 15 October

The [external-resource milestone](qa-native-resource-pack-20261015/README.md) builds the native iOS archive at 138 MB plus a separate byte-exact 155-MB transfer package for 1,888 rule/morphology files. The unchanged multilingual/correction/long-text groups and expanded ABI/broker/packaging checks pass. License metadata for all 146 classpath artifacts and original notices is retained. This enables a separable data layer; actual App Store download size, production packaging, corresponding-source/distribution obligations and app integration remain open. Delivered builds are unchanged.

## Unshipped R14 native-engine progress · 15 October

The [native C-ABI milestone](qa-native-rule-engine-20261015/README.md) passes 29 exact language/range witnesses, 29 correction controls, five long chunks, sixteen ABI checks and explicit no-partial-output heap-exhaustion handling without network. The updated iOS-arm64 library compiles. Isolate teardown and a 256-MiB heap budget reduce the measured process peak to about 425 MB; the 476-MB static archive, actual distribution/license obligations, off-main-thread application integration and broader linguistic acceptance remain open. This research is excluded from the app, does not change the delivered builds, and does not close R14.

## Previous delivery: 1.0.1 (9), iOS/iPadOS and native macOS

Source commit `51f9b66a581fb1da5d508272c6ac82f086524cad` includes the new TestFlight-feedback corrections, earlier proofreading improvements, refined light/dark icon, and genuine SwiftUI/AppKit Mac target. iOS and Mac archives and exports succeeded. Actual exported apps pass 26 iOS and 28 Mac distribution checks, including PCC, CloudKit, Production push, and Mac sandbox. Both uploads succeeded and Apple processing/compliance are confirmed. Both iOS and native macOS show **Im Test** in **Mark – Intern** (one tester). Both platform versions were submitted to Apple and show **Waiting for Review**, with automatic release after approval. Neither is approved or published. [Build 9 state and proof](releases/build9/STATE.json).

The feedback [plan](qa-testflight-feedback-20261014/PLAN.md) and [results](qa-testflight-feedback-20261014/RESULTS.md) distinguish the reproduced filesystem bug from unproven live iPhone sync. Native Mac acceptance covers actual writing/undo/Unicode, formatting, comments/replies across restart, PDF preview/save and full license texts. Mac scheduling/template/image-generation UI parity is not claimed. The full package run reports 723 Swift Testing checks and 58 XCTest checks without failures; four optional checks are skipped. Thirteen distribution-verifier tests pass; Xcode MCP builds the final iOS source successfully.

Build 8 was withdrawn from App Review to replace the known feedback defects. Its old Waiting for Review receipt below is historical, not the current submission. All subsequent dated receipts are preserved for audit. Mandatory additional device tests remain removed; Jimdo remains separate. No current multi-device CloudKit or live PCC proof is inferred from compile/signing checks.

## Historical delivered release: 1.0.1 (8)

[Current verification report](qa-release-20261014/README.md) records the writing, AI, undo, keyboard and file-creation repairs, complete local regressions and the separate 95,744-word mixed-manuscript PDF test. Mandatory device and multiple-device gates were removed by the owner. Existing device evidence remains historical.

The final signed export passes all 25 distribution checks. Upload succeeded after the owner renewed Xcode access. Apple processing and export compliance are confirmed. **Mark – Intern shows 1.0.1 (8), Testing.** It was submitted for production with automatic release after approval, then withdrawn by the developer for replacement by Build 9. See [withdrawal proof](releases/build8/SUPERSEDED.json). [Build 8 receipts](releases/build8/README.md).

iCloud is directly under **Dateien → iCloud**. The deployed production schema contains `ScriptumItemV1` and `ScriptumSharedImageV1`; both runtime gates and actual distribution entitlements pass. The Console needs no additional configuration now. Live participant sync and actual provider/region behavior are not inferred from those receipts.

**Separate work by owner instruction:** Jimdo publication of the prepared DE/EN privacy section. The last fresh public-page readback did not contain Scriptum. No Jimdo login or publication performed.

## Source improvements after Build 8, included in Build 9

The proofreading correction dialog now highlights the exact occurrence in a bounded literal source excerpt. Emoji, combining accents and Markdown characters remain intact; correction admission still verifies the full source bytes and revision. All 46 writing-quality tests and a generic iOS Debug build pass. This change was absent from Build 8 and is included in uploaded Build 9. [Verification](qa-quality-context-20261014/README.md).

The existing long-manuscript exports also have preserved [visual and geometry evidence](qa-pdf-visual-20261014/README.md): 16 visually inspected pages, with word bounding boxes checked on all 1,418 pages. Integrated grammar/style coverage in 20+ languages remains unproven and is not marked complete.

The own-server review now accepts valid whitespace and future bounded rule types as **Sonstiges** instead of failing the whole response. Typography and uncategorized findings no longer inflate grammar counts; known agreement categories retain their grammatical classification. [Fresh real-engine response verification](qa-rule-categories-20261014/README.md) covers 29 synthetic language responses, the root quality target, and the final generic iOS build. This is included in uploaded Build 9; it does not close R14's integrated 20-language coverage requirement.

[Isolated native-rule-engine research](qa-native-rule-engine-20261014/README.md) runs full LanguageTool 6.6 directly without a server, with network denied, retaining expected rules across 29 existing synthetic language examples on both tested JVM toolchains. The [isolated native compilation milestone](qa-native-rule-engine-20261014/native-milestone/STATE.json) subsequently compiled the iOS grammar/style static library, but a separate native corpus still fails its old spelling fixture. No native library is linked into the app; no integrated 20-language completion or iOS runtime-performance claim is made.

The pre-existing 1.0.0 (7) is separately shown as Ready for Distribution.

## Historical candidate notes (October 12)

- Production code is separated from unshipped prototypes in `Research/`; 455 relocated tracked files retain their exact source bytes. QA evidence and licenses remain versioned. GitHub is the code repository, with no workflows.
- The ordinary editor now applies native keystrokes against the displayed syntax frame. The 43-byte Unicode witness survives editing, durable checkpoint and reopening exactly; rejected drafts are preserved separately. [Evidence](qa-input-frame-20261011/REPORT.md).
- Full local verification for the editor change: 655 Swift Testing headlines (four optional skips) and 58 XCTest, plus unsigned Release compilation. Ten signed-archive-verifier regression tests pass.
- The initial white HTML preview capture was taken before load completion; the stable preview renders correctly. The candidate adds loading/error feedback for page and HTML export previews. Official Xcode MCP verifies the loading indicator followed by actual content on first opening and after closing/reopening the regular page preview; the HTML export caller compiles in Release. [Evidence](qa-preview-loading-20261011/README.md).

## Additional export fix awaiting integration

A separate `fix/epub-author-metadata` branch omits invalid empty EPUB creator metadata. All 124 export-test headlines (one optional skip), unsigned Release compilation and six current-renderer EPUBCheck validations pass. Three 24-chapter profiles preserve paragraph/Unicode/table/footnote/TOC counts independently. [Evidence](qa-epub-conformance-20261012/README.md). Actual Apple Books import requires a concrete confirmation after automatic approval rejected its potential library/synchronization side effect. PR #2 remains at the previously presented `2c2fcf5` commit.

## Selection correction awaiting integration

A separate `fix/structural-selection-retention` branch preserves selected text when an unchanged block is duplicated or moved, including when a native text field is recreated with a new Markdown projection. Two intermediate corrections failed native QA. The final correction also handles actual last-block duplication, which appends separators, and remaps selection when the existing native frame rebases. Final local verification passes 662 Swift Testing headlines (four optional skips), 58 XCTest and unsigned iPhoneOS Release. Fresh official Xcode MCP native verification preserves the full “Foo” highlight after the actual last-block duplication, with unchanged source hashes and no provider request. [Evidence](qa-selection-relocation-20261012/README.md).

The regular Markdown export produces the exact 43-byte Unicode witness. The system Files save dialog did not expose actionable hierarchy controls, so save/import/reopen acceptance remains incomplete. [Partial evidence](qa-markdown-files-20261012/README.md).

## Production PDF integration awaiting integration

A separate `fix/production-semantic-pdf` branch makes the semantic tagged renderer the regular shared route for PDF preview and page/manuscript export. Native regular-launch preview and actual system-share PDF pass with unchanged original source. All 124 export tests pass with the 95,744-word/three-profile opt-in enabled. The unused WebKit PDF class is preserved in Research and removed from the native target. Reader compatibility limits and final Release evidence are recorded in [production PDF QA](qa-production-semantic-pdf-20261012/README.md); tagged output does not certify PDF/UA. Native long/media/theme, accessible-reader and full R13 acceptance remain open.

## Resizability investigation

Regular native phone verification found that rotating the focused editor loses the writing surface to the file-browser root. A foreground-presentation experiment failed and was reverted. A fresh iPad pass reproduced the same failure with the scene-configuration hypothesis, so that change was reverted. The independent writing-bar API modernization remains; it does not fix rotation. [Investigation and retained failures](qa-resizability-20261012/README.md). R10 remains open.

## Library presentation lifetime candidate

A separate `fix/library-presentation-lifetime` candidate retains the library hosting controller independently of the decorative document-browser background, using only the anchor view’s own window. Final unsigned Release compilation passes. Fresh ordinary iPad verification preserves the focused editor through portrait/landscape/portrait, supports close/reopen and opens a second library window with the same scope. Exact complete library bytes remain unchanged. Phone verification also retains the correct editor through rotation and background/foreground, with exact original Unicode source and complete library bytes. Phone rotation still dismisses the keyboard and input focus, and landscape body content is partly clipped. The second-window Markdown creation action did not open a creation UI; pending-typing lifecycle acceptance remains separate. [Evidence and limits](qa-library-lifetime-20261012/README.md). Full R10 and R04 remain open.

## Build 1.0.0 (3), 12 October 2026

Quelle `c9f29e1` auf `fix/compact-writing-viewport`: Fokus-Wiederherstellung nach Drehen (`FocusRestoringTextView`), kompaktes Querformat-Layout und „Neue Markdown-Datei“ aus der Bibliothek. 668 Swift-Testing-Tests (vier optionale übersprungen), 58 XCTest, unsignierter Release-Build. Native Prüfung auf Phone und iPad über Xcode MCP: [Evidenz](qa-merged-ui-20261012/README.md). Fokus, Cursor und Tippen bleiben über Drehungen erhalten, der Editor ist im Querformat nicht mehr abgeschnitten, Dateierstellung funktioniert im Hauptfenster und im zweiten Bibliotheksfenster. Grenzen: Auf den Simulatoren erschien keine Software-Tastatur, daher sind der Fall mit eingeblendeter Tastatur im Querformat und das bewusste Schließen der Tastatur ungeprüft. Der Start-Button „Neue Markdown-Datei“ legte `Untitled.txt` an und wurde entfernt. Die Seitenlisten zweier Bibliotheksfenster laufen bis zur nächsten Aktion auseinander.

Signierung: Nach der Anmeldung im Xcode-Konto setzte `-allowProvisioningUpdates` iCloud/CloudKit, den Container `iCloud.com.mobilebox.Skriptum` und Push an der App-ID und erneuerte die Profile. Der App-Store-Export trägt aps-environment production, CloudKit und PCC ([Nachweis](releases/build3/signed-20261012/distribution-proof-c9f29e1.json)). Der Verifier meldet nur `iCloudRuntimeGate` als offen: Der iCloud-Sync bleibt zur Laufzeit abgeschaltet, bis Produktionsschema und echte Teilnehmer-Zusammenarbeit nachgewiesen sind. Der Upload meldete „Upload succeeded“. Danach verarbeitet, Exportcompliance „None of the algorithms mentioned above“ (wie Build 2) auf ausdrückliche Bestätigung des Nutzers gespeichert, Status Ready to Test, und der Build der internen Gruppe Mark–Intern zugewiesen: Die Gruppe zeigt 1.0.0 (3) und 1.0.0 (2) mit Status Testing ([Nachweis](releases/build3/signed-20261012/testflight-build3-internal.jpg)). Installation und Test von Build 3 auf einem Gerät stehen aus.

## Build 1.0.0 (4), 13. Oktober 2026

Quelle `9959ac2` auf `fix/compact-writing-viewport`: Ulysses-Welle als Antwort auf das TestFlight-Feedback zu Build 3 ([Feedback](qa-testflight-feedback-20261012/README.md), Produktfokus in [REQUIREMENTS.md](REQUIREMENTS.md)). Schreibfläche zuerst: leere Einfügevorlagen, Blockwerkzeuge nur auf Abruf (Kontextmenü, langes Drücken, natives Umsortieren), Tastatur-Zubehörleiste (Fett, Kursiv, Überschrift, Liste, Link, Rückgängig, Wiederholen, KI-Menü), Cursor bleibt sichtbar, Markdown-Zeichen abgedimmt ohne Änderung der Bytes, KI-Aktionen auf Auswahl, aktiven Block oder Seite mit Annehmen/Verwerfen, Assistent beantwortet die Aufgabe statt die Seite zu wiederholen, Seitenleisten bei sichtbarer Tastatur ausgeblendet. Native Prüfung mit Software-Tastatur: [Welle](qa-ulysses-wave-20261012/), [Korrekturen](qa-ulysses-fix-20261013/). Ungeprüft: iPad, echtes Gerät, Tippen mit sichtbarer Tastatur. Lange Rohquellen-Blöcke scrollen bei sichtbarer Tastatur intern (kosmetisch).

Signierung wie Build 3, Verifier meldet nur `iCloudRuntimeGate` ([Nachweis](releases/build4/)). Der Upload lief nach erneuter Xcode-Anmeldung durch. Danach verarbeitet, Exportcompliance „None of the algorithms mentioned above“ auf ausdrückliche Wahl des Nutzers gespeichert (Ready to Test) und der Build der Gruppe Mark–Intern zugewiesen: Die Gruppe zeigt 1.0.0 (4), (3) und (2) mit Status Testing ([Nachweis](releases/build4/testflight-build4-internal.jpg)). Installation auf einem Gerät steht aus.

## Build 1.0.0 (5), 13. Oktober 2026

Quelle `4749463` auf `fix/compact-writing-viewport`, Antwort auf das Feedback zu Build 4 ([Feedback](qa-testflight-feedback-20261012/build4-feedback.md)). Der Freigabedialog „KI-Anfrage freigeben“ entfällt, der Empfänger steht dauerhaft in der Kontextkarte. Ein Chat-Auftrag mit Änderungswunsch ersetzt Auswahl, aktiven Block oder Seite sofort; „Rückgängig“ stellt das Original wieder her. Kontextkarte und Auftragsfeld sind getrennt und hervorgehoben, im Querformat mit Tastatur bleiben Feld und Senden-Pfeil sichtbar. Native Prüfung im Simulator: [Evidenz](qa-assistant-build4-20261013/README.md). Ungeprüft: Ersetzen mit echter KI-Antwort (im Simulator ist kein Anbieter verfügbar), iPad, echtes Gerät. Bekannt: Das Lektorat startet beim Öffnen automatisch und schreibt den Auftragstext in den Chatverlauf der Seite.

Signierung wie Build 3 und 4, Verifier meldet nur `iCloudRuntimeGate` ([Nachweis](releases/build5/)). Upload erfolgreich, Exportcompliance „None of the algorithms mentioned above“ auf ausdrückliche Bestätigung des Nutzers gespeichert, Build der Gruppe Mark–Intern zugewiesen, Status Testing ([Nachweis](releases/build5/testflight-build5-internal.jpg)).

## Build 1.0.0 (6), 13. Oktober 2026

Quelle `2e8ec92` auf `fix/compact-writing-viewport`. Der Chat entscheidet selbst: Fragen beantwortet er, Änderungswünsche setzt er sofort im Bereich (Auswahl, aktiver Block, Seite) um. Der Umschalter Chat/Änderung entfällt. Die Antwort trägt den neuen Text zwischen Markern, die Erkennung hängt nicht mehr an einer Liste von Befehlswörtern. Native Prüfung mit lokalem Test-Anbieter (nur Debug-Builds, im Release-Binary nicht enthalten): [Evidenz](qa-chat-replace-20261013/README.md), alle sieben Punkte bestanden. Ungeprüft: echte KI-Antwort, iPad, echtes Gerät. Offen: Das Rückgängig im Panel verschwindet nach dem Schließen; das Editor-Menü „Textänderung rückgängig“ wurde danach nicht gezielt geprüft.

Signierung wie zuvor, Verifier meldet nur `iCloudRuntimeGate` ([Nachweis](releases/build6/)). Upload erfolgreich, Exportcompliance „None of the algorithms mentioned above“ auf ausdrückliche Bestätigung des Nutzers gespeichert, Build der Gruppe Mark–Intern zugewiesen, Status Testing ([Nachweis](releases/build6/testflight-build6-internal.jpg)).

## App-Store-Einreichung, 13. Oktober 2026

Version 1.0.0, Build 7 (Quelle `5c31a2b`, wie Build 6, aber ohne „nur internes TestFlight“; TestFlight-Builds 1 bis 6 waren dafür nicht wählbar). Auf Wunsch des Nutzers eingereicht: manuelle Veröffentlichung nach Freigabe, weltweit (175 Länder), Preis 0,99 € (Basisland Deutschland), Kategorie Produktivität, Altersfreigabe 4+ (alle Fragen mit Nein bzw. Keine), Content Rights „keine Inhalte Dritter“, Exportcompliance „None of the algorithms mentioned above“. Datenschutz-URL und Support-URL sind die Seiten von mobilebox-consulting.de; die Datenschutzseite füllt der Nutzer separat. App-Privacy-Angaben: „Sonstige Nutzerinhalte“ (an den vom Nutzer gewählten KI-Anbieter), Zweck App-Funktion, mit dem Nutzer verknüpft, kein Tracking. Das ist eine vorsichtige Einschätzung und mit der Datenschutzerklärung abzugleichen. Screenshots: sechs je iPhone (1206 x 2622) und iPad 13 Zoll (2064 x 2752), siehe [docs/app-store/screenshots](app-store/screenshots/README.md). Status in App Store Connect: Waiting for Review ([Beleg](releases/build7/app-store-submitted.jpg)).

## Remaining external status

Mac build 10 and iOS build 9 are waiting for Apple review. Automatic public release is configured for approval; approval/publication are not claimed yet. The owner confirmed the Xcode login renewal and Paid Applications Schedule handling, and the subsequent upload succeeded. No new agreement was accepted by the agent.

Jimdo remains a separate explicitly deferred task. The full professional scope retains its documented capability limits; see the current verification report and original requirements.

## Evidence map

- [Requirements](REQUIREMENTS.md), [professional writing scope](PROFESSIONAL_WRITING_PLAN.md)
- [Acceptance history](ACCEPTANCE_STATUS_20261010.md), [release preflight](releases/build3/PREFLIGHT.md)
- [WWDC improvements](WWDC_WRITING_IMPROVEMENTS_20261011.md), [project layout](PROJECT_LAYOUT.md)
- [German/English privacy text](legal/README.md), [licenses](licenses/README.md), [Apple submission material](app-store/README.md)
