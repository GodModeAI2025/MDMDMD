# One semantic heading for image/text content

The public tagged PDF exporter previously emitted image-only headings as sibling Figures without a heading role. Text/image/text headings emitted separate heading elements for their text fragments, leaving the Figures outside the heading. This breaks the document's logical heading structure even though the preceding destination correction makes its links work.

The semantic traversal now opens one H1–H6 structure group for each image-containing heading. Text fragments are Spans and images retain their original Figure/Alt elements inside that group, in source order. The group closes before the next block. Drawing, typography, image sizing and destination placement are unchanged. The existing plain-text heading chain and its keep-with-following behavior remain unchanged.

## Verification

The final regression file is byte-identical in the recorded RED and GREEN runs. Three new definitions, covering ten cases, failed against source `31507fd` with 180 assertions. They cover all six heading levels, three mixed-fragment arrangements and one heading spanning pages. The corrected run passes these cases and the two existing image-heading destination regressions: five definitions, twelve cases. The complete export suite passes 128 executed definitions / 156 cases; one opt-in long-manuscript test remains skipped (129 reported definitions).

An earlier test compilation error from nested `#require` macros is retained in `red.log`; it is not counted as the behavioral RED. The initial post-fix run passed structural assertions but exposed an overly strict extraction comparison: PDFKit represents each Figure inside a heading with a U+FFFC object-replacement character. The final test explicitly checks exactly one such object per figure and unchanged prose tokens, rather than claiming byte-identical tagged/untagged extraction. The final test was rerun against the unchanged baseline before the successful correction run.

`heading-structure.pdf` is produced through the real public exporter, not assembled by the inspection script. Independent pypdf strict parsing confirms one H3 containing Span/Figure/Span/Figure/Span, both original alternative texts, correct parent references, valid page references, two internal destinations and two external annotations, each structurally owned once. It reports no warnings. Body text and exactly one fox remain present.

Poppler rendered the actual first page at 110 dpi. The inspected PNG has readable contents/jump links, three heading text fragments, two colored image witnesses and following body text, without clipping or overlap. This fixture preserves the existing vertical rendering of image fragments; it does not introduce inline image layout.

Apple Xcode-MCP documentation-search receipts are retained. Their returned symbol descriptions corroborate attribute APIs but do not establish PDF/UA conformance. The emitted PDF objects, independent reader and regression outputs provide the concrete structural evidence.

## Bounds

This closes the specific missing/fragmented image-heading structure gap. It is not PDF/UA certification, a complete VoiceOver/cross-reader acceptance test or a new device run. No claim of byte-identical text extraction across PDF readers is made. The delivered iOS 16 / Mac 17 builds precede this source correction; subsequent build or release evidence must be recorded separately.
