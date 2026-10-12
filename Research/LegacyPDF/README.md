# Archived WebKit PDF route

`PaginatedPDF.swift` retains the former WebKit/UIPrintPageRenderer implementation byte-for-byte for historical verification. It is excluded from production targets. Normal page/manuscript PDF export and PDF live preview now share `ExportPDFRoute` and the semantic renderer; HTML previews continue to use WebKit.

Original path: `Sources/SkriptumExportUI/PaginatedPDF.swift`.
SHA256: `ac3e4886a48b815641e50f1e4c1fc2c45f54afa28ced21720366d7b95bb211b1`.

This archive is source history, not a supported second export mode or a fallback for renderer errors.
