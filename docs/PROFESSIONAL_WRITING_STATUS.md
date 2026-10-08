# Professional writing — implementation and verification

Updated 2026-10-09. This extension supplements the full existing requirements; it does not close the application or release goal.

| Area | Implemented | Remaining evidence/work |
|---|---|---|
| Export formats | PDF, DOCX, HTML, source-preserving Markdown, EPUB, blog ZIP with HTML/CSS/media/metadata | Current-wave native file/output inspection, especially PDF geometry and large manuscripts |
| Export themes | Validated font, size, leading, paragraph spacing, margins, A4/Letter, heading color, title, TOC; library/Space preferences | Native live preview completion after deterministic-signature fix; iPad simultaneous controls/preview |
| Preview | Real generated PDF in PDFKit; shared semantic HTML renderer for other formats | DOCX preview is semantic, not a claim of identical Word page breaks |
| Native quality | iOS27 spelling/grammar, local style suggestions, manual acceptance, revision/byte guards, explicit correction undo | Final parser-backed nested-code protection review and native accept/undo/stale checks; native grammar language coverage is not inferred from spelling dictionaries |
| 20+ language rules | Real local LanguageTool 6.6: 31 primary catalog languages; non-spelling rule examples executed for 29 | An explicitly configured, trusted HTTPS route and actual app request; no public endpoint configured and no HTTP fallback |
| AI writing | Proofread, rewrite, summarize open the chosen-provider workflow with a prepared prompt | Real authenticated provider/region/language/device checks; preparing a prompt is not proof of inference |
| Ulysses-inspired workflow | TOC, blog-ready output, per-Space export preferences, existing outline, goals, history and media | Backlinks/heading links, navigation history, templates, material exclusion, configurable writing controls, richer tables/attachment dashboard remain planned |

## Current review findings

Regression tests preserve the source/structure boundary of offered corrections. Quote/list container and indented-code gaps led to replacing ad hoc code detection with the existing pinned Markdown parser. Native grammar completion now has a 30-second timeout and once-only cancellation/completion handling.

The live PDF preview was observed repeatedly restarting. A local Foundation reproducer showed different JSON key orders for an identical theme. Its task signature now encodes sorted keys; the simulator must prove completion on that revised snapshot.

Native export produced a real seven-page Letter PDF with the embedded image and chosen Helvetica. Measurement also exposed a 14-point theme rendered at 18.67 PDF points and an excess left inset. PDF-specific CSS now uses the formatter's pixel-to-PDF-point mapping and removes HTML layout insets; UIKit owns the selected paper/margins. New native measurements are required before closing this issue.

Native spelling produced findings and a manually accepted correction persisted with all unrelated bytes intact. Automatic rechecking then crashed because an Apple text-composer callback ran on its XPC queue while the closure inherited MainActor isolation. That callback fix and a repeated check/accept/undo run are required; the pre-fix crash is retained as sanitized QA evidence.

## Release snapshot boundary

The processed internal-only TestFlight artifact is still **1.0.0 (1), commit 1139ce8**. It does not contain this professional-writing wave. Its export-compliance declaration and internal group availability are pending; none of the new features should be described as shipped in that artifact.
