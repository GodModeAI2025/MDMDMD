# Production semantic PDF integration — 2026-10-12

Normal page/manuscript PDF export and PDF live preview now share the semantic renderer with structural tagging enabled. The Debug-only route switch is removed. HTML previews still use WebKit. Renderer errors/warnings and cancellation propagate through the existing export flow; no PDF fallback changes the output silently.

The old unused WebKit/UIPrintPageRenderer implementation is retained byte-for-byte in `Research/LegacyPDF`, excluded from the generated Xcode target. XcodeGen removes exactly its four project references. This cleanup occurred after native QA: the three active UI files match the exact tested hashes, while final Release compilation separately checks the cleaned project. The source archive's SHA is in `legacy-move.json`.

## Actual app evidence

Official Xcode MCP fresh-installs regular app source without QA arguments. The existing synthetic43-byte page is identified by its actual page/block IDs. Prior MD export preferences are observed; PDF/Standard is selected explicitly. Native PDF preview completes and the real system-share flow produces `native/export.pdf` (56,595 bytes). No recipient, Files, clipboard, provider or account action follows. The complete original page record,43 UTF-8 bytes and all456 Swift hashes remain unchanged during QA. EndSession stops, the prior Xcode destination is restored and the owned MCP bridge exits0.

Independent strict pypdf inspection finds one A4 page, language `de`, Marked=true and Document/H1/P/Span structure. Poppler text preserves `Café é 🦊 — Fett.` including the decomposed accent, with one fox. The structure's ActualText contains the original Unicode. The exported page is rendered and visually inspected: heading and bold text are readable, without clipping or overlap. A tagged structure is not a PDF/UA certification or a VoiceOver acceptance proof.

## Long manuscript and reader limits

All124 export test headlines pass with the long opt-in actually enabled. Fresh public tagged manuscript generation covers95,744 words, four chapters,1,600 ordered paragraph markers,16 tables,48 figures, four notes and1,796 fox characters, in Georgia/A4, Courier/A4 and Helvetica/Letter. Exact artifact hashes, page counts and original-source invariants are retained. Strict independent structure inspection and Poppler26.05 text checks pass all three fixtures; representative first/middle/last images were inspected.

Two reader differences remain explicit. pypdf6.10 extracts the Japanese day glyph as a different codepoint and composes accents; Poppler26.05 text and PDFKit preserve the original sequences. The initial reader check that assumed equal pypdf behavior is retained and excluded from acceptance. Bundled Poppler26.05 raster omits body text on the Helvetica last page despite correct extraction. Homebrew Poppler26.04 and Apple PDFKit render the exact same bytes completely. Both images and versions are retained; no cause or global producer/reader defect is established. This is an open compatibility investigation, not a passed all-reader matrix.

The Courier fixture's final note occupies its own last page. That page is intentional pagination, not a blank or lost-content claim. Visual sampling is not a review of every page. Native iOS long-manuscript/media/all-theme responsiveness, full accessible-reader acceptance, complete R01–R15 and signed current-source TestFlight delivery remain open.
