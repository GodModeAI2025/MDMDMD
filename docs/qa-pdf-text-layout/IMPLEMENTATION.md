# Semantic PDF text layout foundation

Baselinefb8852d. Adds internal PDFTextTypesetter to SkriptumExport and generated Xcode project. It snapshots attributed paragraph input, streams one CTLine at a time, records exact UTF16 source ranges/font metrics/line advance and flags an indivisible cluster wider than available space. Composed-character boundaries protect surrogate pairs, combining marks, ZWJ/family emoji and CRLF. Geometry is validated and cancellation checked at construction, each line and drawing. Drawing isolates and restores text matrix/position and graphics state.

Three meaningful tests: exact source-byte reconstruction at widths1/18/55/200 for Arabic/Japanese/combining/ZWJ/family/flag/CRLF content; mutable-source snapshot and invalid geometry; actual CoreText PDF across multiple pages with all64numbered fox paragraphs recovered by macOS PDFKit and caller text state unchanged. The last test uses normal Georgia font fallback, not separately forced emoji runs. These are macOS27 execution tests; iOS font fallback/extraction is not yet verified.

Final full suite exit0:483Swift Testing headline including3optional skips;58XCTest without failures. Xcode MCP final iOS simulator build succeeded with no errors, original Carina destination restored. No unsigned Release/signed archive/upload is claimed for this source change.

Integration remains deliberately incomplete: the active UI/export backend is not switched. This internal primitive has no user-facing route yet. Full semantic inline/style/link/note/image/table/TOC/manuscript adapters, page layout, tagged logical structure and iOS/native reader parity are required before replacement. It does not close the current WebKit PDF emoji/search/accessibility defect or R04/R13. Native UI was not changed in this step.
