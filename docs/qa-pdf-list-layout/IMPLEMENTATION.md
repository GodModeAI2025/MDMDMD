# Hanging text lists and separate labels

Text-first list items now create LI children Lbl and LBody. The marker draws once at the first actual body baseline after any page promotion; body lines use a dedicated hanging column (minimum24pt or measured label width+8pt). Following blocks in the item share that body indent/group. Nested work-stack begin/end scopes stay balanced. Typed parent-role checks reject creating a marked label outside LI.

Paragraph measurement/page placement now accept minimum first ascent and descent, reserving both marker and body metrics before drawing. This prevents a large marker from crossing page margins when body text uses a smaller/different font. Existing CTLineDraw remains; the rejected run-drawing experiment is not used.

Evidence:86export tests passed. A parsed ordered list beginning at3 spans four actual pages, retains200foxes and ends with item4. CoreGraphics and independent strict pypdf verify each LI contains Lbl/LBody, with zero warnings. All four Poppler raster pages were visually inspected: marker once per item, common baseline and consistent continuation indent, no observed clipping/overlap. A small-body/large-minimum-metrics boundary test confirms page promotion and40pt reservation; paragraph measurement matches that admission. The initial new test's mutating nextLine inside require macro was split before passing.

Direct unsigned Xcode simulator build passed for final production source (arm64/x86_64), terminal exit0/BUILD SUCCEEDED (work/pdf-list-verified-xcode.log); the final macro correction was test-only.

Limits: image/code/quote-first items use a separate label paragraph; same-page marker/body admission for those cases remains open. Inline image flow and full assistive navigation remain open. Tagged output stays internal/default off; active app export stays WebKit. Link glyph ownership and table-header associations are still required. No new Release archive or TestFlight delivery claim.
