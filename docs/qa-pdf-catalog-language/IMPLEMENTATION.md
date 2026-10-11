# Semantic PDF document and structure language

The first actual CGPDF fixture reproduced a missing Catalog /Lang even though the logical Document had its own language. The PDF catalog defines the default natural language unless an element/marked-content override applies ([ISO 32000 syntax](https://pdf-issues.pdfa.org/32000-2-2020/clause07.html)). A targeted full-language override also reproduced SDK27 Attributes.language reducing fr-FR to fr; SDK_REGION_BEFORE.txt captures that actual value.

PDFDocumentWriter validates and normalizes supplied BCP47 syntax, then adds a narrow incremental catalog update after existing Quartz xref/Alt normalization. Original bytes stay intact. The same Catalog ID/generation is republished with /Lang and minimum /Version /1.4 if required; trailer metadata/IDs and old object offsets remain. A full zero-indexed classic xref table avoids the independently reproduced pypdf correction warning from a sparse nonzero subsection. This is deliberately limited to freshly generated unencrypted classic Quartz output; it is not an imported/signed/encrypted/general PDF repair tool.

Root/group/paragraph/figure language now uses the public C CGPDFStructureElementSetLanguageIdentifier setter via its CF_REFINED_FOR_SWIFT import. The SDK header explicitly declares this public setter for OS27. Its exact BCP47 string preserves region/script; the Swift Attributes.language overlay otherwise loses that specificity. Link descendants retain their parent's language. Text streams and glyph ownership do not change.

Validation follows well-formed syntax and duplicate rules, case formatting and fixed grandfathered tags from [RFC5646](https://www.rfc-editor.org/rfc/rfc5646.html). Underscores are converted to hyphens; invalid nonempty/empty tags fail, nil leaves metadata unspecified. The 255-byte bound is explicit. This does not validate current IANA registration or guarantee language/voice/grammar availability, nor does it assert a specific language for user content that the author labeled incorrectly.

## Evidence

Five new tests cover missing catalog language, exact original-byte prefix preservation/idempotence, tagged/plain regional language, malformed/duplicate/injection/trailing-newline tags and nil/unsupported input, default logical-document language and an independent fr-FR override. Full-suite logs and final unsigned build receipts identify the actual integration check.

The six fixtures represent three exact language tags, two pages each, before/after catalog update. Each fixture also has a real paragraph language set through the public C setter. A strict independent pypdf reader verifies catalog/tree tags, /Prev, page count, equal extracted text and unchanged content streams/geometry with zero warnings. Poppler renders all six before/after page pairs pixel-identically. Both unique page rasters were visually inspected (all three language pairs have identical hashes for each corresponding page). One fox remains extractable in each two-page document. These are synthetic metadata/preservation proofs, not linguistic correctness or a PDF/UA certificate.

Reproduce by setting SCRIPTUM_PDF_LANGUAGE_QA_OUTPUT when running PDFCatalogLanguageTests, then run independent-reader.py with that directory and SCRIPTUM_PDFTOPPM. fixtures/ retains the exact QA PDFs and inspected page images; INDEPENDENT_READER_RESULT.json records reader/pixel checks.

## Native and release gates

Fresh native-agent read finds old NativePickerOwnedProxy approval dialog PID24613, MCP Permission disabled/server not running. No permissions/dialog/server/bridge/session/install/device action occurred. Actual app preview/export/native reader/VoiceOver order and pronunciation remain unverified. Semantic app activation remains Debug-only --scriptum-semantic-pdf-ui-qa; Release still uses WebKit. Complete PDF/UA, structure/links/table-header accessibility, mixed-language manuscripts, resource/theme/Files/native acceptance and current-source signing/TestFlight remain open. R01-R15 and pending confirmations are unchanged.

Final integration: 602 Swift Testing headline with three optional skips and all 58 XCTest passing. Final unsigned iOS Release and Debug Simulator builds succeed; source and binary hashes are recorded.
