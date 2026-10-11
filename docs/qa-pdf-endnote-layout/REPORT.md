# Semantic PDF endnote layout

2026-10-11. Source base: 2f00d96 plus this change; verification.json binds the final implementation and regression test hashes.

## Reproduced problem and change

The previous semantic renderer exported a text-first endnote number as its own paragraph. Both plain and tagged fixtures reproduced a 35.62-point first-line separation, with the reference destination pointing above the note body. Failure-before fixtures and four failing expectations are retained in before/ and test-before.log.

Text/code-first notes now place the number and body on the same baseline, with a measured hanging inset (at least 24 points, or label width plus eight). Subsequent paragraphs and nested blocks use the same inset. The reference destination identifies the first actual body line. Tagged output keeps one Note, a source-backed Span number and ordinary P/Code body elements, without inventing LI/LBody list containers. Text/image/text fragments and later quote/table blocks remain present. Image/container-first notes retain their original complete traversal and layout; their number placement is not changed by this patch.

An implementation-stage Swift exclusivity conflict was corrected by capturing the marker's horizontal position before the paragraph borrows the cursor. The final focused and full tests pass.

## Verification and limits

- Full suite: 611 Swift Testing headline tests, four opt-in skips, plus 58 XCTest; no failures. The run explicitly uses --no-parallel. A preceding parallel run stalled in PDFKit/AppKit initialization; its log and process sample are retained. Only the exact owned test processes were terminated before retry.
- The two long-note cases verify the first-line geometry, multi-page body, later paragraph, link annotation and reference destination with actual PDFKit readback.
- Three tagged rich-note cases preserve code, text/image/text, image-first traversal and nested quote/table content exactly once.
- Independent strict pypdf structure checks and standard-aware Poppler text extraction pass for all five after fixtures. Notes retain all 240 French/Greek repetitions and the fox; rich fixtures retain Figure alternatives and nested Code/BlockQuote/Table roles.
- All 13 after pages were rasterized. The five plain/tagged page pairs are pixel-identical. The eight distinct page layouts were visually reviewed via the contact sheet, with first/last long-note and mixed-image pages also inspected at larger size.
- Unsigned Debug Simulator and iOS Release compilation succeed. Build logs and SHA receipts are recorded in verification.json.

This fixes the internal semantic PDF path. App semantic activation remains Debug QA only; Release still uses WebKit. It does not prove native iOS reader/VoiceOver behavior, complete PDF/UA, page-bottom footnote placement, every theme/format, Files roundtrip, iCloud provisioning or current-source TestFlight delivery. No external permission, signing capability or provisioning was changed. The complete R01-R15 requirements remain open according to their actual acceptance evidence.
