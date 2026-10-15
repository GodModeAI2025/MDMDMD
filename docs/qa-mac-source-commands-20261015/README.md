# Native Mac source commands — 15 October 2026

Three formatting defects were reproduced with real menu commands in the old Mac source editor, then corrected and checked in the running native app:

- `Al|pha` → Format / Überschrift originally produced `Al## pha`; the corrected editor produces `## Alpha`.
- Selecting `Alpha` and `Beta` across two lines originally added a list marker only to the first line; the corrected editor marks both lines.
- Link insertion originally left the caret after `[Alpha](https://)`. The corrected editor selects exactly `https://`, and direct typing creates `[Alpha](https://example.invalid)`.

The native Edit menu's Undo and Redo restored/reapplied the heading. A heading inside a fenced code block was rejected without changing the source. The first correction still scrolled a 200-line document to its end; after the explicit visibility fix, the same action keeps the caret and heading visible at scroll position 0.

## Byte preservation

The app's ordinary **Export / MD / Datei sichern** flow produced both Markdown witnesses in this directory. `source-codefence-crlf.md` equals the exact input after the rejected code-block command: 72 bytes, 8 CRLF sequences, two decomposed accents and two fox emoji. `source-long-heading-crlf.md` equals exactly `## ` plus the original long witness: 4,016 bytes, all 202 CRLF sequences, 200 decomposed accents and 200 fox emoji. The accompanying JSON checks contain SHA-256 and exact byte-comparison results.

## Revision and environment boundaries

`baseline-runtime-source.json`, `candidate-runtime-source.json` and `final-runtime-source.json` bind the actual source/binary for each UI phase. The final source remained unchanged through the completed 200-line retest (`final-source-after.json`). Native screenshots and actual AX output remain in the task transcript; JSON observations are a transcription, not screenshots.

The final command fix compiled through Xcode MCP for native Mac (8.533 seconds) and generic iOS (12.387 seconds), with zero errors. No new upload, Store action, physical-device test or iOS runtime test is claimed.

All interactions used a fresh synthetic library under `ScriptumSourceCommands-20261015` with UUID `8556B4CF-DFF3-42AF-BDC1-86B8BF170C5A`. iCloud was not activated, and no normal documents, accounts or AI were used. The source command QA process 92988 was regularly closed and its exit verified. The test library remains intact. Direct container reads were denied by macOS; byte evidence was obtained through the regular app export instead.

## Separately observed preview issue

The CRLF long witness's sidebar subtitle showed “Leeres Blatt” after a leading heading, despite intact source and export. A one-line fix in `MacLibraryNavigation.swift` now splits preview text on newline characters including CRLF. The subsequent native Mac SDK build passed (16.855 seconds, zero errors), and the actual library launch showed “Zeile 001 é 🦊 Zeile 002 …” instead of the empty placeholder. `preview-runtime-source.json` and `preview-source-after.json` bind this separate read-only recheck; all source hashes remained unchanged during it. The previously verified formatting files did not change. The final preview process 96728 was regularly closed and its exit verified.

Xcode is restored to **Skriptum / Any iOS Device (arm64)** and MCP control is released.
