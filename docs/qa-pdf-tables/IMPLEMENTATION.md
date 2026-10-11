# Initial semantic PDF table renderer

Equal-width columns, six-point cell padding, measured multiline text cells, left/center/right alignment, vector borders, retained inline typography and link annotations. Rows remain indivisible. Header plus first row are reserved together before drawing; subsequent page promotions repeat the measured bold header. Row measurement retains scalar metrics and per-cell text snapshots; shaped lines stream during drawing. Oversized header/row groups fail explicitly and close the document rather than clipping or publishing partial output. Images inside cells remain explicitly unsupported.

Evidence: 70 export tests passed. A parsed 90-row Markdown table produces multiple real PDF pages, all 90 foxes and numbered rows, exactly 90 links, right-aligned annotation ends at the expected padded edge, repeated headers on every page containing rows and subsequent paragraph text. Separate tests recover thirty foxes from a wrapped cell beside adjacent text and reject a row taller than the usable page, including rejection of finish after failure.

Limits: no split-row support, images in cells, content-aware column allocation, landscape overflow policy, tagged table structure or independent visual inspection yet. Current app backend remains WebKit; no current app export or TestFlight delivery is claimed. The earlier table rejection test was replaced by actual table acceptance, not removed without replacement.

Direct unsigned Xcode simulator compilation succeeded for arm64/x86_64, terminal exit 0 and BUILD SUCCEEDED; log work/pdf-tables-xcode.log. No fresh MCP build claim because the previous bridge was unavailable.
