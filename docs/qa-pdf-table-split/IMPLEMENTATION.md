# Tall table rows now render across pages

The actual internal table writer uses PDFTableRowPlanner for rows taller than the usable page minus repeated header. Paragraph measurement retains per-line ascents as scalar metrics. Each cell owns one streaming CoreText typesetter; fragments consume exactly their contiguous line ranges and verify complete consumption. Page promotions repeat the bold header. Cell rectangles, first-baseline alignment, column alignment, original inline typography and link annotations follow each fragment's actual page geometry.

The first oversized table row starts with its header on a fresh page. Ordinary rows still remain indivisible. A row's finished cells stay empty in later fragments. Named source/document data are unchanged; failed page-budget admission closes the writer and cannot return partial bytes.

Evidence: all 73 export tests pass. Real PDFKit regression now successfully exports the previously rejected 100-line Unicode cell, recovers every numbered line and all 100 foxes, verifies repeated headers, retained live links inside content bounds, and verifies one-page budget rejection plus rejection of finish after failure. The former oversized-row rejection assertion was replaced by acceptance and a meaningful bounded failure case.

Limits: no visual raster acceptance for this new tall-row fixture yet; earlier seven-page raster acceptance covers ordinary rows only. The active app backend remains WebKit. Cell images, adaptive column allocation, tagged table structure, full mixed-document/profile/native/physical acceptance remain open. This change does not claim full PDF accessibility or TestFlight delivery.

Direct unsigned Xcode simulator build passed (arm64/x86_64), terminal exit 0/BUILD SUCCEEDED, work/pdf-table-split-xcode.log. No new Release or native app UI proof is claimed.
