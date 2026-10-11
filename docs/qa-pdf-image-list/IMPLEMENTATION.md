# Image-first list admission

Image-first list items now share label measurement with text lists. The row reserves the larger of image height and label metrics, then draws the label alongside the actual image top after any page promotion. Figure and following caption blocks remain under the same LBody. The image primitive separates its reserved row rectangle from its natural fitted image rectangle; annotations cover only actual image pixels, not marker spacing. Both structures and plain drawing remain supported.

Evidence:89export tests passed. Near-full-page filler forces a linked portrait and marker9to page2 together; marker and image link are absent from page1. Independent strict pypdf verifies Lbl/LBody/Figure, exact same page references and zero warnings. Both raster pages inspected: no orphan marker, upright natural-size image, clear spacing inside margins. A100pt minimum reservation with a60pt image verifies no stretching and exact natural link frame. Actual parsed Markdown image-first list retains a caption paragraph in the same LBody and its live image link. Existing raster/source-preservation tests remain green.

Direct unsigned Xcode simulator compilation passed for final production source, arm64/x86_64, terminal exit0/BUILD SUCCEEDED (work/pdf-image-list-xcode.log); the final Markdown integration test was test-only and all export tests were rerun afterward.

Open: code/quote/table-first label admission, mixed inline media flow, table header associations, link glyph ownership and assistive/PDF-UA/native app acceptance. Tagged output still defaults off; active app export stays WebKit. No new Release/archive/TestFlight claim. Existing capability/MCP approval gates are unchanged by this code work.
