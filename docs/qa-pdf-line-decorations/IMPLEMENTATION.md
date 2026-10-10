# Semantic PDF line decorations and links

Baselineeb46890. PDFTextTypesetter.Line now draws strike decorations and exposes glyph-run link rectangles plus actual PDF annotation emission. PDFLineDecorations uses per-glyph positions/advances and run metrics, retains global UTF16 ranges, handles positive/negative advances, and includes raised note positioning. Strike lines span spaces at font x-height and retain run color. URL targets are checked with the existing safeLink policy; named destinations preserve heading/note identifiers for the final writer to declare. No network fetching occurs.

Three meaningful macOS27 tests: wrapped Latin/Arabic/emoji links produce positive bounded rectangles within line ranges and actual PDFKit URL annotations, retaining ten foxes; a bitmap ink comparison in a space column proves an actual continuous strike; raised numbered note reference has a bounded raised link region and a real named destination resolves to another PDF page. These tests do not establish native iOS tap/VoiceOver behavior, all bidi/vertical layout or complete document anchor mapping.

Full suite exit0:500Swift Testing headline including3optional skips;58XCTest without failures. Xcode MCP iOS simulator build succeeded without errors; original Carina destination restored after fresh selection check. No new unsigned Release, archive/upload or TestFlight delivery.

Active app export backend remains unchanged. Full semantic block/table/list/quote/footnote/TOC/manuscript writer, image link areas, destination declarations, tagged logical reading structure and native reader fidelity must be integrated before replacing WebKit. Current Unicode/search/accessibility defect is not declared solved by this foundation step.
