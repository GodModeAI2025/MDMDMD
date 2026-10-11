# Logical table rows and cells across pages

Internal tagged output creates Table/TR/TH/TD relationships. An oversized data row owns one TR and each cell owns one persistent TD across its page fragments. The initial header owns one TR with TH cells; repeated visual headers use nonstructural Artifact sequences and do not duplicate logical rows. Cell borders are also artifacts. Cell text streams through the existing measured placement and marked-content APIs with unchanged geometry.

Evidence:81export tests passed. A real five-page100-line table verifies only two logical rows (header/data), two TH and two TD cells and all100foxes. Independent strict pypdf verifies all parent links,103cell text sequences matching actual page MCIDs, all five pages' artifact sequences and zero warnings. The initial compile required explicit self.context capture in the escaping cell drawing callback; fixed before successful execution.

Direct unsigned Xcode simulator compilation passed for arm64/x86_64, terminal exit0/BUILD SUCCEEDED (work/pdf-table-tags-xcode.log).

Limits: Scope/Headers associations for table header cells remain required for complete table accessibility, plus full table navigation with assistive technology. No new visual raster claim for this tagged fixture; prior raster reviews cover its drawing primitives. List Lbl, link annotation OBJR, catalog language and full reading-order/PDF-UA/native app acceptance remain open. Tagged output stays internal/default off; active app route stays WebKit. No Release archive or TestFlight upload claim.
