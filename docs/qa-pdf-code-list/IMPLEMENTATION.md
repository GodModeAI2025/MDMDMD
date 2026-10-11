# Code-first list items

Semantic list traversal now recognizes a leading fenced/indented code block and passes its immutable monospaced text to the shared label/body admission. The body retains Code role under LBody, with the separate Lbl under LI. Marker and first actual code baseline share page promotion. Remaining blocks stay in the same list body and hanging column. Original CTLineDraw remains unchanged.

Evidence:91export tests passed. A real valid CommonMark fenced-code list retains the fox, literal[^literal]and(toc), and the Code structure role. A near-full-page regression promotes marker9and all three code lines to page2 together. Independent strict pypdf verifies Lbl/LBody/Code, common page references and zero warnings. The one-page code fixture raster was inspected: clear marker, monospaced lines, preserved literal syntax and no observed clipping/overlap.

Initial fixture syntax9followed by a blank line and an indented fence parsed as an empty list plus a separate indented code block. The fixture was corrected to a fence on the marker line with proper continuation indentation; production CommonMark interpretation was not changed.

Direct unsigned Xcode simulator build passed for final production source, arm64/x86_64, terminal exit0/BUILD SUCCEEDED (work/pdf-code-list-xcode.log); the final promotion regression was test-only and all export tests were then rerun.

Open: quote/table-first marker admission, inline media flow, header associations, link glyph ownership, full assistive/native/PDF-UA acceptance. Tagged output still defaults off; active app route remains WebKit. No new Release/archive/TestFlight claim.
