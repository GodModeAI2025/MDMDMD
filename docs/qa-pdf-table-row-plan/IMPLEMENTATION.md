# Tall table-row fragment planning

New internal PDFTableRowPlanner divides per-cell scalar line metrics into contiguous page fragments. It excludes caller-reserved header height from available row space, aligns fragment first baselines using maximum ascent, accounts for per-cell vertical offsets and padding, and keeps exhausted cells empty in later fragments. Cancellation is checked during validation and line consumption. Impossible line/alignment geometry and page-budget exhaustion throw before returning a partial plan.

Evidence: 73 export tests passed. Variable-height 100-line and 50-line cells, short/empty neighbors, partial first page and more than twenty fragments preserve every per-cell line index exactly once; independently recomputed fragment heights fit. Impossible aligned first lines, bounded page exhaustion and empty rows after promotion are covered. The empty-row test caught repeat/continue termination before emitting a promoted empty fragment; changed to explicit completion after emission and reran successfully.

Direct unsigned Xcode simulator compilation passed (arm64/x86_64), terminal exit 0/BUILD SUCCEEDED, work/pdf-table-row-plan-xcode.log.

This is planning only, not integrated tall-row drawing. The existing table writer still rejects oversized rows. Next work must feed measured CoreText ascents into this planner, stream each cell's shaped lines across fragments with repeated headers, preserve annotations and verify a real multi-page oversized-row PDF visually and in independent readers. Active app export remains WebKit. Tagged accessibility and full app/TestFlight acceptance remain open.
