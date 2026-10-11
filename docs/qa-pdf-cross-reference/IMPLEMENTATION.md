# Quartz absent-object cross-reference correction

The actual tall-row PDF's object9 was marked in-use at offset0 in its classic xref table, despite no object definition or reference existing. The ordinary-row fixture had the same issue at object10. The writer now finalizes its own generated PDF after closing Quartz: validates the single classic0-based20-byte-entry xref, all present object headers/offsets and trailer shape; marks only unreferenced/undefined zero-offset objects permanently free with generation65535. All byte lengths, content streams, actual object addresses and startxref remain unchanged. Imported, incremental, encrypted, object-stream and signed structures are outside this narrow contract. Referenced missing objects throw; no partial document is returned.

Reference: Adobe PDF1.7, section3.4 cross-reference tables, including permanently free entries linked to0 with generation65535: https://opensource.adobe.com/dc-acrobat-sdk-docs/pdfstandards/pdfreference1.7old.pdf

Evidence: all74export tests passed. A synthetic xref test verifies same-size correction, idempotence and rejection of a referenced missing object. Real generated five-page tall-row PDF opens in pypdf strict=True with zero captured warnings,100foxes and200annotations. All five Poppler renders are pixel-identical to the previously fully visually inspected tall-row PDF; no content or annotation rewrite. Receipt SHA retained.

Scope limits: strict pypdf readback is not ISO/PDF-UA conformance certification. No structural tags/accessibility have been added. The finalizer uses additional byte/text snapshots for conservative reference scanning; full long-manuscript memory/cancellation acceptance remains open. The active app backend stays WebKit. No fresh signed archive/TestFlight or native app export proof.

Direct unsigned Xcode simulator compilation succeeded for arm64/x86_64, terminal exit0/BUILD SUCCEEDED, work/pdf-xref-xcode.log. No new Release claim.
