# Tall-row independent reader and visual acceptance

Production source a73afe5. The existing oversized-row test now optionally saves its real generated PDF using SCRIPTUM_PDF_TALL_ROW_QA_OUTPUT. Normal assertions are unchanged. Focused test passed, terminal exit0.

All five pages independently rendered with Poppler at1100px and visually inspected: rows0–19/20–39/40–59/60–79/80–99 continue inside a single logical split row, table header repeats on every page, paired initial baselines align, cell borders stay continuous, no observed clipping/overlap or missing visible emoji. The short neighboring cell appears on the first fragment and remains empty after completion, as intended. Scope is this synthetic100-line fixture, not all mixed tables or themes.

Independent pypdf recovers all100emoji, exact ordered indices0–99 once each, both headers on all five pages, Other once, and200link rectangles to the exact target URL. PDFKit's existing regression independently checks links and content bounds. Reader JSON retains SHA and the warning about unused wrong-pointing object9at offset0; this is not a strict PDF-conformance pass. The initial reader script compared an indirect URI object directly with a string, causing its check to fail; dereferenced/string URI readback was verified and recorded. The generated PDF needed no correction in this turn.

No production source change, new app UI test, Release compile or TestFlight upload. Active app route remains WebKit; structural tagging, image-alt/table semantics, full mixed-document/profile matrix and native/physical export acceptance remain open. The previous ordinary-row seven-page review does not replace this tall-row review, and this tall-row review does not close all PDF acceptance.
