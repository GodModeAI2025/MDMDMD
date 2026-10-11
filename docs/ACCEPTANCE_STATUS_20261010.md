# Scriptum full-scope acceptance audit

Latest local full-suite check: 2026-10-11, long mixed manuscript whitespace/Unicode update. Full suite609 headline/four optional skips plus58XCTest, with the expensive 95,744-word long export separately verified in three themes; unsigned Simulator/iOS Release builds pass. See qa-pdf-long-mixed for reader and scope limits. No current-source signed archive or TestFlight delivery is established.

Audit source: 8dd7598, checked local worktree 2026-10-10. Evidence update after native grammar admission/completion/cancellation and export literal-protection fixes; no fresh external portal read in this update. Original REQUIREMENTS.md R01–R12 and PROFESSIONAL_WRITING_PLAN.md R13–R15 remain binding. This is not a reduced definition of done. No requirement is closed by a source file, picker, mock, green aggregate suite, or absence of an observed failure. Latest full-suite update (2026-10-11): 604 Swift Testing headline, three optional skips, 58 XCTest; current-source unsigned Simulator and iOS Release compilation pass. The original 480-test count and prior 549/556/561/567/569/574/580/586/592/597-test updates are historical. Neither proves the entire application or a distributed release.

| Requirement | Current evidence and its scope | Still required to close |
|---|---|---|
| R01 offline library | Core/store tests, WritingLibrary and native temporary-library flows exercise individual operations | End-to-end persistent Spaces/subpages/tags/search/favorites/trash/recovery acceptance across restart and real file access |
| R02 writing | qa-composite-writing-ipad and prior phone evidence; source-preserving editor and metadata controls | Complete keyboard, IME, outline navigation, VoiceOver, Dynamic Type and large-document acceptance; composite media fidelity |
| R03 storage and revision | Core atomic storage/revision tests; native writing/reopen evidence; scoped conflict/draft recovery | Process termination/real Files coordination and concurrent writer failure matrix, complete undo/redo invariants |
| R04 import/export | Real Markdown ZIP readback, independently extracted DOCX/EPUB XML; actual macOS Word image reader fixtures including natural-size recheck; literal footnote/TOC protection regressions for container code and raw HTML | Mixed/assembled long-manuscript and HTML/EPUB reader fidelity, Unicode PDF extraction, Files roundtrip and all selected profile/theme combinations |
| R05 AI interaction | Typed proposals, revision admission, cancellation/context tests and scoped native dialogs | Actual authorized provider streaming/failure/cancel/selection/Space context and all patch targets on device |
| R06 provider access | Provider/auth code and contract tests; source has no silent fallback | Commercial ChatGPT grant and live inference, physical PCC availability/region/language, actual API-key inference; mocks cannot prove grants |
| R07 blocks | Native synthetic image preview and exact source bytes; tools and block adapters exist | Composite image/table rich rendering, full slash/actions/reference/prompt/visualization behavior with accessibility and preservation |
| R08 collaboration | Owner/shared outbox, merge, account scope, foreground/push routing tests; unprovisioned views tested | Named CloudKit container/profile/schema/APNs, real two-device sharing/roles/comments/replies/resolve/reopen/concurrency/backpressure |
| R09 scheduled work | Durable dispatch/budget/authority tests and scoped native foreground controls | Real OS background launch/expiry/settlement/timing/retention/migration; no guaranteed exact-time execution |
| R10 adaptive access | Scoped phone/iPad/native window evidence and window registry | Resize/multiwindow/keyboard/drag/VoiceOver/Dynamic Type matrix on real devices |
| R11 professional QA | Scoped long Unicode writing evidence and tests, receipt hashes | Full integrity/offline/parallel/provider/physical-device acceptance; scope cannot be inferred from total test count |
| R12 internal TestFlight | Historical Oct10 portal receipt: only build2 installed; current unsigned compile | Current-source signed archive/export/upload/processing/compliance/group assignment and installation, separately proven |
| R13 export themes | Shared theme model, independent ZIP/XML checks, native preview; recent raw-package/heading/image fixes | Complete theme parity and mixed manuscript pagination, semantic/accessible PDF with Unicode extraction; Standard/A4 synthetic321-page sample alone does not close this |
| R14 writing quality | Native corpus: 29 attempts and 29 completed reviews, including 11 without a spelling dictionary; only two grammar witnesses. Native zero-result completion and actual inflight stop/settlement verified separately; own-server rule evidence remains separate | 20 distinct real integrated grammar/style languages and actual regional AI correction; spell dictionaries are not grammar proof |
| R15 writing/research tools | Template/attachment tools and source-preserving page workflow exist | Full backlinks/history/material exclusion/templates/tables/preferences/device behavior and accessibility acceptance |

## Release state boundary

Current checked project.yml omits ScriptumICloudProvisioned; owner/shared sessions derive the gate from Bundle and default to notConfigured. Skriptum.entitlements declares CloudKit iCloud.com.mobilebox.Skriptum and PCC, but no aps-environment. The source therefore does not claim live provisioned sync. CURRENT_RELEASE_CHECK_20261010.json is an earlier same-day external receipt, not a fresh portal read in this audit: iCloud/Push were unchecked, PCC checked, existing profile archive failed exit65, only build2 Im Test. Nothing in this turn refreshed portal state or uploaded current code. The existing specific action-time access-expansion confirmation remains pending; do not duplicate it or use automatic provisioning as a workaround.

## Evidence added since the initial audit

The former dictionary gate was removed in 71df93a: an explicit native route without a spelling dictionary still requests system grammar checking and local style checks. The real native corpus completed all 29 reviews, including the eleven previously skipped entries. Only German and Chinese produced actual Apple grammar witnesses; these results do not establish twenty integrated grammar/style languages. See qa-grammar-without-dictionary/native/corpus-result.json and the separate native-completion evidence. The original ambiguous zero-result UI report is retained rather than overwritten.

Preparation now runs off the main actor with an 8 MiB admission bound (28ef8b8). The real native 445000-byte, 5000-block fixture demonstrated busy, stopping, canceled settlement and stable canceled UI with unchanged document bytes (e24f767; qa-quality-stop/native/REPORT.md). This is scoped simulator evidence, not a hard cancellation latency or cross-window concurrency guarantee.

Export fixes f0011df, 2f34cfb and 469b0d8 preserve literal footnote and TOC examples inside container code and raw HTML. Failure-before/fix-after evidence is retained in qa-footnote-code, qa-toc-code and qa-html-literal. The latest full test receipt is qa-html-literal/TEST_SUMMARY.txt; unsigned iOS27 Release compilation at source469b0d8 succeeded, recorded in qa-html-literal/RELEASE_BUILD.json. These checks do not close external reader, pagination or Files roundtrip acceptance.

The latest saved external release audit is releases/build3/current-1430/REPORT.md at sourcee24f767: exact App ID still had iCloud and Push unchecked; signed archive failed with the existing profile; the internal group exposed build2. This update does not refresh those external facts or claim a signed current-source build.

## Next acceptance work

R14 still needs twenty distinct actual integrated grammar/style language witnesses and regional AI correction evidence. Do not count dictionaries, completed zero-result checks or an independent server corpus as this proof. R04/R13 still need actual PDF/HTML/EPUB reader and long-manuscript fidelity, profile/theme parity and Files roundtrip evidence. R08/R12 remain dependent on the pending specific capability-access confirmation and subsequent provisioning, real collaboration and current-source TestFlight gates. The full R01–R15 matrix remains binding; none is closed by this evidence update.

## Long PDF evidence update (source8f07ba3)

qa-pdf-long-current retains the real native preview/export and exact source preservation evidence for the656187-byte/88025-word synthetic fixture. Actual PDF has321A4pages; independent pypdf and macOS PDFKit both find all8000repeated prose paragraphs. Poppler renders of pages1,161,321 were visually inspected. No source-code change or fresh release/provisioning action occurred in this update.

Confirmed open defect: visible fox emoji are absent from extracted Unicode text in both independent readers (0 vs8001expected). PDF still lacks structural tags. Visual success cannot close copy/search/accessibility semantics. These defects, mixed-content pagination, theme matrix and Files roundtrip remain required; originalR01–R15scope is preserved.

## Current-source integration update (2026-10-11, source61a1073)

The internal semantic PDF foundations now include immutable streaming text, inline typography and annotations, bounded upright images, paragraph widow/orphan planning, heading keep for adjacent same-indent text, contents, endnotes, thematic rules and equal-width multiline tables with repeated headers. All seven pages of the synthetic 90-row table were independently rasterized and visually reviewed; first-baseline mismatch was corrected. PDFKit and pypdf recover all 90 foxes and links. pypdf still reports an unused wrong-pointing object; the PDF is untagged, so strict conformance/accessibility is not established.

Fresh full suite at source61a1073: 514 Swift Testing headline with three optional skips, plus 58 XCTest passing. These are integration tests, not full product acceptance. Actual app preview and export still call PaginatedPDF from ExportLivePreview.swift and ExportOptionsSheet.swift. The semantic renderer is not wired to either route. Therefore the current app Unicode extraction defect and lack of tagged PDF remain open. No fresh portal/provisioning/upload action is evidenced here.

Before activation: split oversized table rows, cell-image support/column sizing, heading chains and non-text followers, true inline image/paragraph spacing, list hanging indentation, note policy, accessible structure, long mixed-manuscript/theme matrix, cancellation/resource bounds and real native app export/reader acceptance. The full R01–R15 scope above remains unchanged.

## Fresh external release audit, 2026-10-11

releases/build3/current-20261011 records exact Developer/ASC reads: PCC enabled, iCloud/Push unchecked; only build1.0.0(2)in Mark–Intern, one tester/eight sessions. Both local profiles lack CloudKit and Push. Current-source signed archive at a3b6c75 failed exit65 for missing iCloud/container/service rights; no provisioning update or upload occurred. The specific capability expansion confirmation remains pending. The Xcode MCP transport was restarted but Xcode requires fresh agent/project-folder approval, requested through the user input panel. These external gates do not close or reduce the full product acceptance matrix.

## Native PDF acceptance route, 2026-10-11

Debug-only `--scriptum-semantic-pdf-ui-qa` now wires actual preview/share UI to the public semantic renderer for single documents and assembled manuscripts. Release defaults remain WebKit; tags remain default false. 97 export tests and unsigned simulator compilation pass. Fresh MCP project-open succeeded and agent/folder approvals are confirmed, superseding the earlier pending Xcode approval statement. Destination discovery and device-session start then timed out. No native session, installation, UI proof or app-generated PDF was obtained; all3307source hashes stayed identical during attempted QA. See qa-pdf-native-route. CloudKit/Push capability confirmation/provisioning and current-source TestFlight remain separate open gates. R01-R15 are unchanged.

## PDF heading-chain pagination, 2026-10-11

Semantic renderer now reserves adjacent text-only heading chains and the first three lines of following text/code. Reproduced orphaning was corrected; final three-heading paragraph/code fixtures each retain headings/body on page2and all10foxes, independently read by strict pypdf without warnings and visually checked on both pages. 98export tests and unsigned simulator app build pass. See qa-pdf-heading-chains. Non-text/mixed/oversized heading groups, actual native app export, accessibility and release gates remain open; R01-R15are not closed.

## Code-first endnotes and fresh Release compilation, 2026-10-11

Code-first semantic PDF endnotes now reserve their number and first three body lines at the actual code font/18pt indent. A reproduced broken destination was corrected; independent strict reader and both-page raster review confirm number/code/annotation destination together,10foxes and10literal markers retained. 99export tests and unsigned Debug Simulator plus iOS27Release builds pass. Final Release executable receipt is in qa-pdf-code-endnotes. Xcode-MCP BuildProject returned timeout; no native UI/device proof or release delivery was obtained. Non-text note admission, complete export fidelity/accessibility, provider and iCloud/collaboration/signing/TestFlight requirements remain open. R01-R15are unchanged.

## Xcode transport diagnosis and Settings bundle packaging, 2026-10-11

An owned-proxy text-buffer/select defect was reproduced and repaired with tested raw framing. Only the owned proxy/bridge were renewed after diagnosis; Xcode stayed open. Actual workspace RPC still timed out. Native CUA inspection found an old-proxy access dialog; automatic approval review rejected its dismissal due potential access revocation, and a specific user confirmation remains pending. No device/native acceptance claim. Current unsigned Release Settings.bundle independently matches all source panes/localizations and preserves pinned MIT/BSD license paragraphs plus Apache licenses/NOTICE verbatim; actual Settings UI remains unverified. See qa-xcode-transport-and-license-bundle. R01-R15 and TestFlight remain open.

## Page-spanning heading chains, 2026-10-11

Semantic PDF no longer rejects a complete text-heading chain merely because the chain spans pages. Forward groups reserve complete headings, with the final group retaining the first body fragment. Thirty-heading text/code fixtures now render three pages, retain all headings in order and all ten foxes, and keep heading 30 with the body start on page 3. Strict independent reader and all six page rasters confirm the scoped result; 100 export tests and unsigned simulator app compilation pass. See qa-pdf-long-heading-chains. Individually oversized/mixed headings, non-text followers, complete native/reader/accessibility acceptance, provisioning and current-source TestFlight remain open. No pending confirmation was treated as answered. R01-R15 are unchanged.

## PDF image tables, 2026-10-11

Semantic PDF table images are now retained as proportionally fitted, indivisible cell fragments alongside streamed text. Eighteen-row parsed Markdown and ten-page mixed-cell fixtures preserve every text/image/link; independent strict reader verifies source-photo counts/orientation/natural size, Unicode, annotation bounds and Figure Alt under TD. Four tagged/plain raster pairs are identical; plain pages and the tall-row contact sheet/last pages were inspected. 102 export tests and unsigned simulator app compilation pass. See qa-pdf-table-images. Inline-image parity, column sizing, extreme/header/theme/resource/accessibility and actual native/Files acceptance remain open. No pending confirmation was treated as answered and no TestFlight build was uploaded. R01-R15are unchanged.


## Library writer integrity and process-abort recovery, 2026-10-11

A reproduced lost-update defect between LibraryStore instances is corrected with a persistent cooperative kernel lock and observed library-file version checks around loading/recovery, commits and journal mutations. Old writers cannot overwrite committed state or write after another instance recovers their journal; rejected operations preserve snapshots and suppress durable notifications. Permanent regressions and all module consumers pass: 549 Swift Testing headline (three optional skips), 58 XCTest. Twenty real two-process writer trials preserve all earlier state and produce one commit/one conflict each. SIGKILL of the exact journalized helper process followed by a fresh process restores a 368022-byte Unicode/CRLF draft byte-for-byte and keeps its baseline revision/all 21 Spaces. Unsigned Simulator and current iOS Release builds pass; receipt/helper/harness in qa-library-writer. These are macOS Core/compile proofs, not physical iOS/Files/CloudKit, power-loss or complete UI recovery acceptance. R03/R08 and the full R01-R15 matrix remain open at their actual scope; pending confirmations/signing/current-source TestFlight are unchanged.


## Disk-conflict draft recovery and rescue export, 2026-10-11

Already-loaded stores now respect foreign active journals when opening an editor or committing changed page state; journal recovery explicitly admits its own locked journal set. Expired unchanged journals cannot block a valid external revision. WritingLibrary captures physical-conflict text/block/metadata drafts even when its obsolete in-memory snapshot matches; finalization captures block identities. A new menu action writes the current page binding as raw Markdown without requiring failed journal finalization. Full suite: 556 Swift Testing headline (three optional skips) and 58 XCTest pass; unsigned Simulator and iOS Release compile. Twenty process pairs plus an already-loaded peer attempting to overwrite a foreign journal and subsequent SIGKILL recovery preserve the scoped source invariants. See qa-disk-conflict-recovery. Fresh native-agent read finds old Xcode access dialog still open and MCP permission disabled/server not running; no permission change, device session or native rescue-action proof. Full UI/reopen/Files/CloudKit/release acceptance remains open; R01-R15 are unchanged.


## Atomic editor page/configuration saves, 2026-10-11

A reproduced partial-write defect in WritingLibrary.update and page/Space assistant configuration is corrected: complete validation and all requested fields publish through one library commit. A failed combined purpose/trash change or invalid prompt list no longer leaves earlier fields persisted. Valid multi-field page saves publish once and capture one baseline per changed page; trash descendants remain in the same transaction. Identical configuration retries are no-ops. Full suite: 561 Swift Testing headline (three optional skips), 58 XCTest; unsigned Simulator and iOS Release compile. See qa-atomic-page-save. This is model/Core evidence; full native editing/undo/reopen/Files/CloudKit and TestFlight remain open, with the pending Xcode/capability decisions unchanged. R01-R15 are preserved.


## Partial recovery source preservation, 2026-10-11

A reproduced missing-image failure no longer prevents durable recovery of the text. WritingLibrary first atomically writes and reads back a source-only record, then independently archives each image; valid images survive a failed neighbor. Repaired media completes the same record. Recovery scanning retains healthy entries alongside corrupt untouched files, and value-checked removal rejects changed records. Recovery UI exposes incomplete status, raw Markdown sharing and local action errors/unreadable-file count. Full suite: 567 Swift Testing headline (three optional skips) and 58 XCTest; unsigned Simulator/iOS Release compile. An exact owned child SIGKILL followed by a fresh macOS process retains all 216011 Unicode/CRLF bytes and the same source-only record identity. See qa-partial-recovery. This is scoped Core/model/process evidence, not power-loss, iOS native share/restore, full recovery/Files/CloudKit or TestFlight acceptance. Fresh native agent finds Xcode MCP disabled/server not running and the old dialog unchanged; no permissions or UI/device actions occurred. Pending Xcode/capability confirmations and R01-R15 remain unchanged.


## Editable incomplete-recovery text copies, 2026-10-11

The recovery sheet now offers an explicitly identified text copy for source-only records. It creates and verifies exact Markdown/block IDs/writing metadata as a new editable page without claiming image attachment restoration; original records/blobs and Markdown image references remain for later full recovery. Tests verify durable reopen, later repaired full recovery and stale-writer rejection without consuming the source. Full suite: 569 Swift Testing headline (three optional skips), 58 XCTest. See qa-recovery-text-copy for final compile receipts and native limits. Fresh native agent confirms old Xcode approval dialog/MCP disabled/server stopped, with no permission/device action; actual button/navigation/accessibility remain unverified. No provisioning or TestFlight action, no pending approval treated as answered, no R01-R15 requirement closed by these scoped checks.


## Historical version restore integrity, 2026-10-11

Nine failing expectations reproduced unchecked missing/corrupt historic image restoration, duplicate history on identical restore retries and silent parent untrashing. Core now validates historical media before publishing, preserves current identity/location/trash lifecycle and leaves unchanged writing-content retries as no-ops. Real restores retain the current baseline; independent disk readback/reopen and exact Unicode/block/media return are verified. Full suite: 574 Swift Testing headline (three optional skips), 58 XCTest. Final unsigned Simulator/iOS Release receipts and failure-before evidence are in qa-revision-restore-integrity. This is Core/disk evidence, not native history/undo/physical Files/CloudKit or release delivery; no permissions/provisioning/upload action. R01-R15 and pending confirmations remain unchanged.


## Exact multi-step quality-correction undo/redo, 2026-10-11

A reproduced source-only undo defect changed block IDs after a structural correction despite identical restored text. WritingQualitySheet now captures actual before/after Core blocks and offers bounded multi-step undo/redo. Revisions and exact IDs/UTF8 bind every inverse; stacks advance only after durable write success. Tests cover original comment anchors, three-step source/block/disk restoration, branches, intervening revisions/disk writers, failed journal admission/retry and retention bounds without deleting durable versions. Full suite: 580 Swift Testing headline (three optional skips), 58 XCTest. Final unsigned Simulator/Release receipts and failure-before proof are in qa-correction-history. Fresh native QA found the old Xcode dialog/MCP disabled/server stopped, with no permission/device action; actual UI remains unverified. This covers quality-correction history, not whole-editor/AI/tool undo/redo, physical Files/CloudKit or current-source TestFlight. Pending confirmations and the full R01-R15 matrix remain unchanged.


## Immutable assistant acceptance and shared tool source undo, 2026-10-11

Assistant requests now capture original page/source/revision/validated UTF16 selection. Context, comparison and replacement use that immutable target; invalid nonempty selections cannot widen to the page. An implementation-stage half-surrogate failure demonstrated that Swift Range conversion was insufficient; explicit endpoint checks now pass. Acceptance commits source before returning Bool success and closes only on success; rejected results remain in the dialog. Pre-assistant navigation persists the full draft. Actual admitted source tools now share bounded exact-block undo/redo; their own metadata-only writes can advance expected revision without losing source history. Full suite: 586 Swift Testing headline (three optional skips), 58 XCTest; final unsigned compile receipts in qa-assistant-domain-undo. Core tests cover selected/durable/undo/redo/conflict/trash/normalization/range behavior and actual PNG/table/history transactions. Native agent again finds old Xcode approval dialog/MCP disabled/server stopped and performs no action. Native interactions, live inference, complete typing/metadata/media/cross-mode/cross-window undo, physical Files/CloudKit and current-source TestFlight remain open. Pending confirmations and R01-R15 are unchanged.


## Read-only foreground rescue for failed journal recovery, 2026-10-11

A corrupt neighbor previously prevented opening a valid durable library. Foreground opening now explicitly requests a protected store on journal recovery failure; strict/background opening remains unchanged. All journals must decode/validate before publication/deletion, while valid pending sources remain extractable independently. A protected store rejects content/journal/media writes and marks unresolved editing so sync/schedule consumers refuse stale work; invalid library.json never becomes an empty writable library. UI exposes read-only source, disabled writing controls, pending-draft Markdown export and a recovery notice. Five Core tests plus actual cold foreground/facade resolution/export/background tests prove scoped file/source preservation and fresh-open recovery after test-owned repair. Full suite: 592 Swift Testing headline (three optional skips), 58 XCTest; final unsigned Simulator/Release receipts in qa-recovery-readonly. Native agent found old Xcode dialog/MCP disabled/server stopped; no permission/device action or native UI proof. Undecodable bytes, complete repair/fault/process/Files/resource/accessibility/CloudKit/release acceptance and the full R01-R15 matrix remain open. Pending approvals unchanged; no provisioning or TestFlight upload.


## Opaque original-file rescue ZIP, 2026-10-11

Read-only recovery can now stream an original-file ZIP without parsing, repairing or deleting library/journal/media/recovery content. Complete source/version checks, SHA manifest, synchronized output readback and atomic non-replacing publication precede sharing; unsupported/oversized content fails the complete export. Four Core cases and a facade case cover opaque data, destination/symlink/recursive/cancel/bounds safeguards and protected-store export. Full suite: 597 Swift Testing headline (three optional skips), 58 XCTest; final unsigned Simulator/Release receipts in qa-recovery-evidence. The actual current helper produces an 8MiB binary/Unicode/corrupt-journal/empty-directory fixture independently verified by Python ZIP CRC/SHA and macOS unzip, preserving every original byte. A second live 64MiB capture preserves a target created after staging begins and returns destinationExists, with staging removed. This is scoped macOS Core/process proof, not hostile filesystem races, power-loss, ZIP64/large-volume/resource/native stop/share/Files/CloudKit or TestFlight acceptance. Fresh native agent finds old Xcode dialog/MCP disabled/server stopped and performs no action. Pending confirmations and the full R01-R15 matrix remain unchanged; no provisioning/upload.


## Semantic PDF catalog/structure language, 2026-10-11

A missing catalog language and SDK27 region loss (fr-FR to fr) were reproduced. Semantic PDF now declares its default language in the Catalog through an incremental update with a complete zero-indexed xref and retained original bytes; structure languages use the public C setter for exact BCP47 identifiers. Syntax/duplicates/invalid inputs and default-versus-French override tests pass. Full suite: 602 Swift Testing headline (three optional skips), 58 XCTest; final unsigned Simulator/Release compile. Strict independent pypdf checks de-DE/en-GB/zh-Hant-TW catalog and paragraph language, unchanged text/content streams/geometry, one fox and zero warnings. All six two-page before/after raster pairs are pixel-identical; both unique page images inspected. See qa-pdf-catalog-language. Actual native reader/VoiceOver and complete PDF/UA remain unverified; app semantic activation is Debug-only and Release remains WebKit. Fresh native agent found old Xcode dialog/MCP disabled/server stopped, no action. R01-R15, pending confirmations and current-source provisioning/TestFlight remain open.

### PDF column-header scope — 2026-10-11

The own semantic PDF path now adds Column scope to simple table TH cells and batches it with catalog language/version in one incremental update. Two independently read eight-page fixtures preserve all original streams/text and 100 Unicode fox characters; all eight de-DE rendered page pairs are pixel identical. Latest full suite: 604 Swift Testing headline tests (three optional skips), 58 XCTest, unsigned Debug simulator and iOS Release builds successful. See qa-pdf-table-header-scope. Semantic Release activation, PDF/UA, VoiceOver, native top-layout verification and current-source TestFlight remain open.

### Shared catalog and bottom paper surface — 2026-10-11

Catalog source now matches the existing shared-writing inline paper header and wraps the unavailable label. Sidebar/detail decorative backgrounds extend through the bottom container safe area. Independent source review passes; native verification remains blocked by the old Xcode access dialog and disabled MCP server. No current screenshot, keyboard/resize/accessibility or TestFlight acceptance is claimed; see qa-shared-catalog-paper.

### Fresh iCloud release gate — 2026-10-11

A fresh read-only portal/profile audit still finds PCC only, missing iCloud/CloudKit/Push and only Build2 in Mark – Intern. The signing verifier previously accepted the real old archive without the required iCloud capability; it now rejects both old signed archive and App Store export for those unmet requirements. Ten Python regressions pass. See releases/build3/icloud-verifier-20261011. This change does not create provisioning, enable the runtime gate, complete product acceptance or upload current source.

### Heading/media pagination — 2026-10-11

Text-only heading chains now reserve following standalone/image-first paragraphs and table header/first-row fragments; large rasters scale proportionally and tall first rows retain their logical structure. Six independent before/after pairs preserve text/Unicode and required page association. Full suite606 headline/three optional skips plus58XCTest passes. Fresh hash-bound reader checks in qa-pdf-reader-current show the table heading in PDFKit and all tested Poppler variants. The earlier omission claim is not reproducible on final committed input and is superseded. Semantic Release activation remains gated by broader export/accessibility/device acceptance. See qa-heading-media.

### Hash-bound reader revalidation — 2026-10-11

Six committed heading/media fixtures pass 18 default Poppler render checks and two macOS PDFKit table renders with the heading visible. Independent text/Unicode/structure checks pass. The earlier omission claim is corrected as non-reproducible on exact current bytes. Input/output hashes are retained in qa-pdf-reader-current. This is fixture-level evidence and does not close R04/R13, native iOS UI or TestFlight delivery.

### Long mixed manuscript whitespace/Unicode — 2026-10-11

The actual public tagged manuscript API now succeeds for95,744 words/four chapters in Georgia/A4 (377pages), Courier/A4 (664pages) and Helvetica/Letter (378pages). It exposed and fixed invisible trailing-whitespace rejection and ambiguous Unicode glyph mapping through line-owned ActualText. Independent standard-aware extraction and structure checks preserve1,600 paragraph markers,1,796 foxes,48 figures,16 tables and four local notes. Raw pypdf extraction ignores ActualText; default untagged alias handling remains open. Full609 headline/four skips+58XCTest and unsigned builds pass. Nine sample page pairs are pixel identical; broader/native/accessible/format/Files/TestFlight acceptance remains open. See qa-pdf-long-mixed.
