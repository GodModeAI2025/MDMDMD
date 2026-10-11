# Public manuscript PDF service

ExportEngine.renderSemanticPDFManuscript uses the same semantic chapter assembly as HTML/DOCX/EPUB/blog exports. Existing assembly was extracted into one internal helper without changing namespace rules: independent chapter parsing, generated chapter headings, remapped heading links, chapter-prefixed footnotes and image paths. Cancellation checks now precede assembly and each chapter. PDF work stays in ExportWorker and returns the common artifact/warnings contract.

The larger fixture exposed a paragraph-first endnote orphan: a note number could stay on the prior page while its body moved. Number and first body fragment are now reserved together, measuring the body's actual18pt indent. Named links target the number's final actual page, which now also contains its first text fragment. Image/code-first note admission remains open.

Evidence:97export tests pass, including existing shared-format regressions. Actual nine-page public PDF fixture retains100foxes, both chapter titles in order, separate same-named notes, same-named images in80×40and40×80upright dimensions, heading targets on pages0/7and note targets on pages7/8with their actual texts. Independent strict pypdf reports zero warnings. Empty chapters and invalid chapter heading targets throw; unfinished chapter1fence cannot consume chapter2. The first reader script incorrectly expected a catalog named-destination tree; Quartz resolves its internal names into explicit annotation Dest arrays, which were subsequently inspected directly.

Direct unsigned Xcode simulator compilation passed for final production source, arm64/x86_64, terminal exit0/BUILD SUCCEEDED (work/pdf-manuscript-final-xcode.log).

Limits: no new complete visual/native manuscript acceptance, all-theme matrix, full resource/PDF-UA/assistive proof or UI switch. Active app preview/export remain WebKit. Structural tagging stays opt-in/default false. Signing/CloudKit/MCP approval gates remain open; no upload or new TestFlight installation occurred.
