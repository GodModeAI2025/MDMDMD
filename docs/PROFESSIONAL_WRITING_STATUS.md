# Professional writing — implementation and verification

Updated 2026-10-09. This extension supplements the full existing requirements; it does not close the application or release goal.

| Area | Implemented | Remaining evidence/work |
|---|---|---|
| Export formats | PDF, DOCX, HTML, source-preserving Markdown, EPUB, blog ZIP with HTML/CSS/media/metadata | Additional DOCX/blog native file inspection and large-manuscript checks |
| Export themes | Validated font, size, leading, paragraph spacing, margins, A4/Letter, heading color, title, TOC; library/Space preferences; real native PDF/live preview passed | iPad simultaneous controls/preview and wider device coverage |
| Preview | Real generated PDF in PDFKit; shared semantic HTML renderer for other formats | DOCX preview is semantic, not a claim of identical Word page breaks |
| Native quality | iOS27 spelling/grammar, local style suggestions, manual acceptance, revision/byte guards, explicit correction undo; native correction/recheck/undo restored exact UTF8 without a crash | Wider language/device coverage; native grammar language coverage is not inferred from spelling dictionaries |
| 20+ language rules | Real LanguageTool 6.6: 31 primary catalog languages; non-spelling rule examples executed for 29. Actual app HTTPS catalog/check/correction/recheck/undo passed in an isolated simulator | Physical device/production server deployment remains separate; no public endpoint configured and no HTTP fallback |
| AI writing | Proofread, rewrite, summarize open the chosen-provider workflow with a prepared prompt | Real authenticated provider/region/language/device checks; preparing a prompt is not proof of inference |
| Ulysses-inspired workflow | TOC, blog-ready output, per-Space export preferences, existing outline, goals, history and media | Backlinks/heading links, navigation history, templates, material exclusion, configurable writing controls, richer tables/attachment dashboard remain planned |

## Current review findings

Regression tests preserve the source/structure boundary of offered corrections. Correction eligibility defaults to protected; only source-backed AST prose text is permitted. Reference definitions omitted from CommonMark's content tree remain protected, and explicit footnote/URI/export-directive protections cover extension metadata. Actual exporter-conformity tests verify nested TOC roles. Native grammar completion has a 30-second timeout and once-only cancellation/completion handling. All 125 aggregate tests and the iOS27 simulator build pass.

The live PDF preview was observed repeatedly restarting. Its task signature now encodes sorted keys and a concrete container preserves its task across progress/error/rendered branches. Native PDFKit preview completion with embedded media is verified. Export sheets capture page/media/preferences together in one immutable presentation item.

Native PDF export measured **14.000 pt on Letter** and **16.003 pt on A4**, each with a **72 pt margin** and embedded media; native saving preserved file bytes. PDF-specific CSS normalizes WebKit's documented minimum print shrink factor and removes HTML insets; UIKit owns paper/margins. See [WebKit PrintContext](https://github.com/WebKit/WebKit/blob/main/Source/WebCore/page/PrintContext.h). Remeasure after SDK/runtime changes; this uses public CSS rather than private WebKit preferences.

The grammar callback is explicitly Sendable and constructed outside MainActor isolation. A native repeated check/accept/recheck/undo run now passes without the former XPC callback crash. Already committed updates do not create a phantom typing journal. Baseline source, code, URLs and Unicode are restored byte exactly; pre-fix failures remain sanitized regression evidence.

The actual HTTPS catalog exposed a valid long German language code rejected by the earlier client bound. A real 60-entry LanguageTool catalog is now a permanent test; 31 primary languages are counted separately from variants. The app loaded that catalog, selected English (US), received real grammar findings, accepted a correction, rechecked and restored baseline UTF8 exactly. Code, URI, footnote ID and quoted TOC assertions all passed. The separate test simulator/CA was removed, both owned test processes stopped, and temporary private keys deleted; existing devices and macOS trust were unchanged by the test.

## Release snapshot boundary

The processed internal-only TestFlight artifact is still **1.0.0 (1), commit 1139ce8**. It does not contain this professional-writing wave. Its export-compliance declaration and internal group availability are pending; none of the new features should be described as shipped in that artifact.
