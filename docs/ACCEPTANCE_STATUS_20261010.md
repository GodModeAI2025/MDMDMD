# Scriptum full-scope acceptance audit

Audit source: 8dd7598, checked local worktree 2026-10-10. Evidence update after native grammar admission/completion/cancellation and export literal-protection fixes; no fresh external portal read in this update. Original REQUIREMENTS.md R01–R12 and PROFESSIONAL_WRITING_PLAN.md R13–R15 remain binding. This is not a reduced definition of done. No requirement is closed by a source file, picker, mock, green aggregate suite, or absence of an observed failure. Current full suite: 480 Swift Testing headline, three optional skips, 58 XCTest; latest current-source unsigned Release compilation passes. Neither proves the entire application or a distributed release.

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
