# Actual long native PDF export — independent inspection

Frozen source8f07ba3 (application codea065148). The existing synthetic composite-large fixture was exported through the running iOS27 app's real editor/export/share UI. Native provenance and document hashes are recorded separately under ../native. This is the actual exported file, not an independently regenerated facsimile.

Artifact459309bytes, SHA256d8b8aba7a7cc2cf5693e276da22e4c80d2fb20c25070b62fcf189f09c80cfe4b. Poppler pdfinfo confirms321A4pages595.28×841.89pt, no encryption/JavaScript. pypdf examines every page: none has empty extracted text; all8000expected repeated prose paragraphs, both headings and code are present. Separate macOS PDFKit reads321pages and8000paragraphs too. Scripts and machine-readable receipts are retained.

Poppler rendered pages1,161,321; root visually inspected all three. Headings/bold/italic/code on page1 are readable; middle prose and final partial page are readable. No clipping or overlap observed in these sampled renders. All321pages were text-inspected, but only three independently rendered pages were visually inspected; no broader pagination or performance guarantee is inferred.

Confirmed open defect: all8001expected fox emoji characters are absent from both pypdf and PDFKit extracted text. They remain visibly rendered as color glyphs on all three sampled pages. Therefore visual preservation is demonstrated for those samples, but Unicode copy/search/accessibility fidelity is not. The existing untagged-PDF gap also remains (noStructTreeRoot). Do not mark complete semantic or accessible PDF export from this evidence. Fix needs to preserve correct text and structural reading semantics, not merely set a Tagged flag or blanket whole-document replacement text.

This synthetic repeated-prose Standard/Georgia12/A4 case does not establish mixed long-manuscript table/image/footnote pagination, all profiles/themes, Files roundtrip or physical-device performance. No signed archive/upload occurred.
