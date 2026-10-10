# Independent native PDF artifact inspection

The actual PDF was produced by the running iOS27 app at sourcea065148 via the real export dialog, using the existing synthetic image fixture and Standard/A4 defaults. Its native provenance is recorded separately under ../native. The file was copied without regenerating it. SHA256 dc257fe5ca59d6b2e8858edb11bdc7c54bc17e0fd10da8a068a73bb39821cdd3; 99278 bytes.

Poppler pdfinfo accepted the file: one page, A4 595.28 × 841.89 points, rotation0, no JavaScript, no encryption. Independent Poppler rasterization was visually inspected at1300px height: complete readable heading, blue/gold landscape image with correct16:9 aspect, and the complete following sentence; no clipping, overlap or blank extra page. Independent pypdf extraction confirms expected heading and following sentence and one embedded image. Receipt and actual PDF/raster/text are retained here.

Open finding: PDF is not tagged (no StructTreeRoot). Text extraction and visual fidelity do not prove accessible reading order, heading/image semantics or screen-reader navigation. This gap needs an export implementation and acceptance decision before accessible PDF can be claimed.

macOS Preview GUI opening was attempted through CUA with bundle/display-name targets; both getApp calls returned timeoutReached. No opened native Preview window is claimed. Poppler and pypdf evidence remains authoritative within its scope.

This one-page synthetic Standard/A4 sample does not close long-manuscript pagination, all profiles/theme combinations, PDF accessibility, physical-device or Files roundtrip acceptance. Existing current-source unsigned Release compilation passed separately, ../RELEASE_BUILD.json; no signed archive/upload occurred.
