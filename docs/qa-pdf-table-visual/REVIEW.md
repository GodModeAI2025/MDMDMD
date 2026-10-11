# Independent table raster review

All seven final pages rendered with Poppler at 1100px and visually inspected. Before correction, emoji-bearing first cells had a lower baseline than neighboring plain links. The writer now measures the maximum first-line ascent across each row, aligns first baselines and includes each cell's resulting vertical offset in row-height admission. Subsequent lines keep their own advances. A real PDFKit regression compares recovered annotation baselines for 24pt and 12pt Georgia.

Final inspection: repeated bold headers on all seven pages, continuous cell borders, consistent right alignment and paired first baselines, rows 0–89 in sequence, visible emoji, no observed clipping/overlap, final paragraph below the last row. Scope is this synthetic two-column fixture, not all table layouts.

All 71 export tests passed after an infrastructure retry. The initial sandboxed PDFKit test helper stalled in AppKit/SkyLight TCC access; a sample confirmed the wait, the exact own helper was terminated and observed terminal, then the same suite passed with escalated execution. That aborted run is not a pass. Direct unsigned Xcode arm64/x86_64 simulator compilation passed for final production source, exit 0/BUILD SUCCEEDED (work/pdf-table-baseline-xcode.log).

Independent pypdf recovers all 90 foxes and 90 annotations; SHA in READER.json. It warns about an unused wrong-pointing object 10 at offset 0. Thus this is not a strict PDF-conformance pass. The PDF remains untagged. Active app route remains WebKit; tagged accessibility, row splitting, full mixed layouts and native app acceptance remain open.

The test-only SCRIPTUM_PDF_TABLE_QA_OUTPUT environment variable saves the real generated regression PDF for independent inspection; normal test assertions remain identical without it.
