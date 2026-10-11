# Semantic roles and language; SDK figure issue

Internal taggedStructure opt-in (renamed from taggedParagraphs, still defaults false) now propagates real H1–H6, P and Code roles through semantic traversal. Each text element has the input language via the installed SDK's CGPDFStructureElement.Attributes language API. Tagged and untagged PDFKit extraction are compared directly; tagging does not change extracted text. Normal app export remains WebKit.

The attempted figure implementation revealed a SDK serialization defect: passing Attributes.alternativeText creates /AltText rather than standard /Alt on the Figure structure element. The original test correctly rejected absent /Alt, and that failure and independent strict-reader dictionary receipt are retained. Tagged figure drawing is now explicitly rejected with a typed export error. Untagged existing image rendering is unchanged; a partially tagged image export is not silently returned. Alternative text remains in the semantic input for a future standards-correct solution.

Validation:77export tests passed. The new actual PDF test verifies H1/P/H2/Code order and de language on every text element, exact PDFKit tagged-vs-untagged extracted text, and retained emoji. The figure gate test rejects its known unsupported path. The initial fixture had a recursive nested require macro compile error, fixed by separate provider initialization. Its exact punctuation expectation also revealed reader whitespace around emoji; comparison now proves tag neutrality, not arbitrary copy/search text equivalence. General punctuation extraction fidelity remains open.

Direct unsigned Xcode simulator build passed for final production source, arm64/x86_64, terminal exit0/BUILD SUCCEEDED (work/pdf-roles-xcode-final.log).

Open: standards-correct figure Alt, language at document root, list/quote/table/endnote hierarchy, link object references, repeated headers/artifacts, logical reading order, full assistive-technology and PDF/UA acceptance. No app route switch, Release archive or TestFlight upload.
