# PDF layout review — 2026-10-14

Source: the existing 95,744-word mixed-manuscript export test. Original fixture and receipt remain in [the release QA report](../qa-release-20261014/README.md). No production source or PDF bytes were changed during this review.

| Export theme | Pages | Visually inspected pages |
| --- | ---: | --- |
| A4 Georgia | 376 | 1, 2, 3, 189, 376 |
| A4 Courier | 664 | 1, 2, 3, 333, 663, 664 |
| Letter Helvetica | 378 | 1, 2, 3, 190, 378 |

All 16 retained PNGs were visually reviewed. The sample showed legible multilingual text, emoji, code, table continuations, image orientations and endnotes. No overlap or clipping was observed in the sampled pages. The final Courier endnote occupies its own page; that is preserved as valid flow, not presented as optimal book pagination.

Poppler word bounding boxes were checked on all 1,418 pages: no extracted word lies outside its page, no word exceeds the configured right margin by more than one point, and extraction contains no U+FFFD replacement characters. PDF SHA-256 values and image hashes are recorded in `geometry-results.json`; unchanged original PDF paths are in `selections.json`.

Limits: bounding boxes and extraction do not prove the absence of every visual defect. Only 16 pages received visual inspection. This report does not claim that every page, theme, paper size or real manuscript was visually verified. It does not replace author review of an export.
