# Independent final nested export TOC review

Verdict: **PASS for the final TOC/prose fix**. Fresh aggregate SDK tests and provider/runtime checks remain root gates.

Current predicate exactly matches SemanticParser.block: a Paragraph whose children are all Markdown.Text and whose plainText is `(toc)`. The projection excludes all descendants of those directive paragraphs; the structural signature records their exportTOC boolean. This protects removal and rejects creation without treating inline prose, headings or emphasis as directives. Source-backed Text eligibility, metadata masks and before/after byte/protection checks remain unchanged.

Independent compiled probes against exact current QualityCore linked to pinned official Markdown/cmark objects:

- Previous eleven metadata/URI/continuation cases still reject.
- Standalone, quote and list TOC identifier changes now all reject (including both previous blockers).
- Ordinary quote/list/nested-quote prose replaced with `(toc)` rejects in all three cases.
- Inline prose mention, emphasized literal and heading literal accept `toc` → `TOC`; inline code rejects.

Fixture/executable work/review-probe; compile/execution exit 0. New regression tests additionally cover escaped literals and nested quotes. The actual-exporter conformance test compares HTML nav presence with correction eligibility for nine representative cases using includeTOC=false, so it checks genuine directive behavior rather than merely copying a mask assertion. This test is included only when the export module is available, with export dependency confined to the root quality test target. No new production cross-module dependency or source changes made during review.

No remaining reproducible blocker in the inspected final source contract.
