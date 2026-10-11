# Link annotation object references

Internal tagged text paragraphs, figures and table cells now attach Link elements to their actual parent and use the iOS27 beginObjectReference/endObjectReference APIs around creation of exactly one URL/destination annotation. Each OBJR attaches to its Link element. Text/image/table drawing still uses its original geometry and existing safeLink policy. All object-reference scopes close with defer. Untagged and repeated artifact-header routes retain existing plain annotations.

Evidence:83export tests passed. Real PDFKit checks a text link and mixed image/table links, exact target sets and no duplicate annotations. Actual CoreGraphics parser checks the text Link's OBJR/Obj fields. Independent strict pypdf confirms one text OBJR and two mixed OBJRs reference precisely the existing annotations and each annotation has a StructParent key, with zero warnings. The initial compile needed explicit self.context capture for an escaping callback; corrected before tests passed.

Direct unsigned Xcode simulator compilation passed for arm64/x86_64, terminal exit0/BUILD SUCCEEDED (work/pdf-link-tag-xcode.log).

Limits: link glyph marked-content association, human-readable accessible labels and consolidation across wrapped runs/pages still require work. The current implementation creates a Link object per annotation rectangle; it does not claim one logical Link per Markdown inline. Full ParentTree/assistive link navigation acceptance, table Scope/Headers and list Lbl remain open. No new visual or physical-device acceptance. Tagged output still defaults off and active app export remains WebKit. No Release archive or TestFlight delivery claim.
