# PDF contents and thematic rules

The semantic backend now renders explicit (toc) markers and theme-requested automatic contents. A theme does not insert a second automatic contents list when an explicit marker exists. Entries retain nested heading levels and link to existing heading-N named destinations. Thematic rules reserve 24 points on the shared cursor and draw a 0.75-point gray vector line across the available content width, promoting pages when needed.

Validation: 65 export tests passed. Real multi-page PDFKit tests cover automatic and explicit contents, exactly one contents copy, two live destinations including a quoted heading on a later page, and retained 120 foxes. A bitmap rendering test verifies visible rule pixels across the content area and clear margins.

The bitmap test initially counted transparent pixels in the ceil-rounded final bitmap column as black. The fixture now paints the whole integer-sized bitmap white; one pixel around the fractional content edge allows antialiasing. No production drawing change was needed for that fixture failure.

Direct unsigned Xcode simulator build passed (arm64 and x86_64), terminal exit 0 and BUILD SUCCEEDED; log work/pdf-contents-xcode.log. The previous MCP bridge is unavailable; no MCP build claim is made.

Active app PDF export remains WebKit. Tables, linked images, heading keep-with-next, inline image flow, list geometry, note presentation and tagged accessibility remain open before activation. Native app export and TestFlight delivery are not claimed.
