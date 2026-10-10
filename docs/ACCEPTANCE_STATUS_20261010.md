# Scriptum full-scope acceptance audit

Audit source: 7ae7575, checked local worktree 2026-10-10. Original REQUIREMENTS.md R01–R12 and PROFESSIONAL_WRITING_PLAN.md R13–R15 remain binding. This is not a reduced definition of done. No requirement is closed by a source file, picker, mock, green aggregate suite, or absence of an observed failure. Current full suite: 471 Swift Testing headline, three optional skips, 58 XCTest; latest current-source unsigned Release compilation passes. Neither proves the entire application or a distributed release.

| Requirement | Current evidence and its scope | Still required to close |
|---|---|---|
| R01 offline library | Core/store tests, WritingLibrary and native temporary-library flows exercise individual operations | End-to-end persistent Spaces/subpages/tags/search/favorites/trash/recovery acceptance across restart and real file access |
| R02 writing | qa-composite-writing-ipad and prior phone evidence; source-preserving editor and metadata controls | Complete keyboard, IME, outline navigation, VoiceOver, Dynamic Type and large-document acceptance; composite media fidelity |
| R03 storage and revision | Core atomic storage/revision tests; native writing/reopen evidence; scoped conflict/draft recovery | Process termination/real Files coordination and concurrent writer failure matrix, complete undo/redo invariants |
| R04 import/export | Real Markdown ZIP readback, independently extracted DOCX/EPUB XML; two actual macOS Word image reader fixtures | Actual PDF/HTML/EPUB reader fidelity, large assembled manuscript, Files roundtrip and all selected profile/theme combinations |
| R05 AI interaction | Typed proposals, revision admission, cancellation/context tests and scoped native dialogs | Actual authorized provider streaming/failure/cancel/selection/Space context and all patch targets on device |
| R06 provider access | Provider/auth code and contract tests; source has no silent fallback | Commercial ChatGPT grant and live inference, physical PCC availability/region/language, actual API-key inference; mocks cannot prove grants |
| R07 blocks | Native synthetic image preview and exact source bytes; tools and block adapters exist | Composite image/table rich rendering, full slash/actions/reference/prompt/visualization behavior with accessibility and preservation |
| R08 collaboration | Owner/shared outbox, merge, account scope, foreground/push routing tests; unprovisioned views tested | Named CloudKit container/profile/schema/APNs, real two-device sharing/roles/comments/replies/resolve/reopen/concurrency/backpressure |
| R09 scheduled work | Durable dispatch/budget/authority tests and scoped native foreground controls | Real OS background launch/expiry/settlement/timing/retention/migration; no guaranteed exact-time execution |
| R10 adaptive access | Scoped phone/iPad/native window evidence and window registry | Resize/multiwindow/keyboard/drag/VoiceOver/Dynamic Type matrix on real devices |
| R11 professional QA | Scoped long Unicode writing evidence and tests, receipt hashes | Full integrity/offline/parallel/provider/physical-device acceptance; scope cannot be inferred from total test count |
| R12 internal TestFlight | Historical Oct10 portal receipt: only build2 installed; current unsigned compile | Current-source signed archive/export/upload/processing/compliance/group assignment and installation, separately proven |
| R13 export themes | Shared theme model, independent ZIP/XML checks, native preview; recent raw-package/heading/image fixes | Complete live-preview/output theme equivalence and external reader/pagination coverage, actual PDF geometry |
| R14 writing quality | Native corpus: 29 attempts, 18 reviews, only two grammar witnesses; separate own-server rule evidence | 20 distinct real integrated grammar/style languages and actual regional AI correction; spell dictionaries are not grammar proof |
| R15 writing/research tools | Template/attachment tools and source-preserving page workflow exist | Full backlinks/history/material exclusion/templates/tables/preferences/device behavior and accessibility acceptance |

## Release state boundary

Current checked project.yml omits ScriptumICloudProvisioned; owner/shared sessions derive the gate from Bundle and default to notConfigured. Skriptum.entitlements declares CloudKit iCloud.com.mobilebox.Skriptum and PCC, but no aps-environment. The source therefore does not claim live provisioned sync. CURRENT_RELEASE_CHECK_20261010.json is an earlier same-day external receipt, not a fresh portal read in this audit: iCloud/Push were unchecked, PCC checked, existing profile archive failed exit65, only build2 Im Test. Nothing in this turn refreshed portal state or uploaded current code. The existing specific action-time access-expansion confirmation remains pending; do not duplicate it or use automatic provisioning as a workaround.

## Next implementation decision

Prioritize R14 rather than further small export tweaks. Fresh source inspection finds NativeWritingReviewer.check rejects unsupported spellingLanguage before requestGrammarChecking. WritingQualitySheet also disables Text prüfen when language is empty. Grammar request itself has no spelling-language argument. Thus the measured eleven skipped native reviews establish only a dictionary gate, not lack of system grammar support.

Next: separate native spelling selection/admission from native grammar/system-availability checking. Offer an explicit, clearly described grammar/style-only native route when no spelling dictionary is selected; never substitute an unrelated dictionary or provider. Preserve Markdown-safe UTF-16/revision correction protections, cancellation gates and actual source-byte invariants. Re-measure the missing-dictionary corpus through the real route and record grammar witnesses separately from spelling/style. A zero-result review remains inconclusive; this does not predeclare twenty supported languages. Follow with native UI verification of clear labels and actual completion/cancel behavior. Real external LanguageTool remains optional explicit own-server use and does not become an operated public cloud prerequisite.
