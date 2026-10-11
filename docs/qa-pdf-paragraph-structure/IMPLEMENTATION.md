# iOS27 paragraph structure foundation

Uses actual iOS27/macOS27 CoreGraphics CGPDFStructureElement and marked-content sequence APIs from the installed SDK. A single logical P element attaches200line sequences across10pages. Sequence attachment errors throw and close the writer. Every sequence is balanced with defer. No ActualText substitution is used; Unicode remains in the original CoreText text runs.

The document writer's internal taggedParagraphs opt-in defaults false. The semantic renderer and active app export do not enable it yet: paragraph-only partial tagging must not be represented as complete accessibility. The paragraph renderer accepts a drawing callback so structural sequences can follow its actual line/page placement without retaining all shaped lines.

Evidence:75export tests passed on macOS27. Initial test assumed the root K child was an array; SDK output validly used one indirect paragraph dictionary, so the test was corrected to verify roleP and200content entries. Real PDFKit recovers all200foxes and numbered lines with no U+FFFC. Independent strict pypdf reader finds200unique(page-object,MCID)pairs, exactly matches marked page sequences, covers all10pages, retains200foxes, no U+FFFC and zero warnings. This avoids the earlier ActualText-based experiment's extraction regression.

Authoritative API references inspected locally: SDK CoreGraphics CGPDFContext.h New Tagged PDF Authoring and CGPDFStructureElement.h. Direct unsigned Xcode simulator compilation passed for arm64/x86_64, terminal exit0/BUILD SUCCEEDED (work/pdf-paragraph-tag-xcode.log).

Still open: document language/root metadata, heading/list/quote/figure/table/note roles, figure alt text, link annotation structure references, repeated-header/artifact semantics, logical reading order for all blocks and real assistive-technology acceptance. This is not PDF/UA certification, full accessibility, native app export or TestFlight delivery. No new visual pagination acceptance was claimed for this tag-only fixture.
