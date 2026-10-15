# Current PDF gap: image-first heading destinations

The current production `ExportPDFRoute` uses the semantic renderer with structural tagging. The 321-page report in `docs/qa-pdf-long-current/reader/REPORT.md` describes the historical WebKit path. The later `docs/qa-production-semantic-pdf-20261012/README.md` records production integration and Unicode extraction evidence. This task did not reimplement the old emoji finding.

## Reproduction and bounded correction

A valid Markdown image-only heading (`# [![ImageHeadingWitness](photo.jpg)](https://example.com/figure)`) with generated contents and an author's internal link aborted the public tagged PDF export with `.referencedMissingObject`. A mixed image/text/image heading did export, but its internal link targeted later text, 60.0078 points below the first image. Both independent public-API/PDFKit regressions failed against the original renderer; see `red-final.log` and `red-sources.json`. No baseline PDF was produced for the image-only heading because export threw.

The renderer now transfers a heading destination to its first visible image fragment and consumes it exactly once. The writer registers the destination at the actual image frame after page placement. Later text and images cannot replace that destination. The finalizer's missing-object rejection, drawing, tags, ActualText and layout policy remain unchanged. Changes are limited to two export source files and two public-API tests.

## Verification

Final focused run: 2 test definitions executed and passed, exit 0 (`green-final.log`, `green-final-result.json`). The first post-fix run is retained in `green.log`: all navigation checks passed, but an ancillary text assertion incorrectly demanded contiguous PDFKit whitespace around an emoji. It was changed to verify the body marker and exactly one fox independently. The final test file therefore differs from the RED test file only in that unrelated text-extraction assertion. One compiler-cache sandbox failure is retained separately; it was an infrastructure failure before tests, followed by the approved normal cache-access run.

Full Export suite: terminal exit 0, 126 reported definitions; 125 passed definitions / 146 executed parameterized cases, with the single opt-in long-manuscript test skipped. Pure test duration was 4.349 seconds. See `export-full.log`, `export-full-result.json` and `RESULTS.json`. `git diff --check` passed for the export source/test scope.

`image-heading-fixed.pdf` is the real artifact produced by the public renderer during the final focused test. Independent pypdf 6.10 strict parsing reports no warnings. All three internal annotation destinations resolve to valid page objects; two target the image top at y=678.3977 and one targets the later text heading at y=577.9055. The external image URL annotation and Figure Alt remain intact. A Document structure and the separate text heading's H1 are present. Poppler text retains all prose markers and exactly one fox. Reader and command receipts are retained.

Poppler rendered the actual one-page PDF at 110 dpi. Visual inspection of `image-heading-fixed.png` found readable contents links, the four-color test image, body text/fox and following text heading, without clipping or overlap in this fixture. This is a small synthetic fixture, not an all-profile, long-manuscript, accessibility or device acceptance claim.

## Remaining bounds

This fix addresses navigation and export completion only. The image-only heading still contributes Figure/Alt rather than an enclosing H1 semantic group. Existing cross-reader differences and broad acceptance limitations recorded in the 2026-10-12 report remain open. No claim of PDF/UA certification or complete VoiceOver behavior is made. No Xcode-MCP, app or simulator launch, commit, push, signed archive or upload occurred.
