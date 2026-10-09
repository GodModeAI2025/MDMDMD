# Independent attachment layout/contrast follow-up

**PASS** for source correctness and scoped security. Reviewed AttachmentDashboardSheet-only diff after89baf07.

Total remains visible; optional usage/history counts move into an initially collapsed DisclosureGroup. Its @State belongs to the stable summary child, so changing filter/count inputs preserves the person's expansion choice instead of driving new audits or mutating results. Expanding reveals the same count semantics and library-wide explanatory text. Native DisclosureGroup preserves system expand/collapse accessibility and avoids manual gesture/hit-area code.

Status/warning text now explicitly uses Color.primary while icons retain semantic orange/secondary styling. This prevents warning meaning from depending solely on a low-contrast orange caption, with literal status descriptions retained. The reusable warning label preserves localized keys and symbols. Detail stale text stays explicit; opening callbacks and stale navigation guards are unchanged.

No engine, filtering, task identity, persistence, authorization or file-access changes; no security regression identified. Rebuilt phone/iPad screenshots must confirm first-screen attachment reachability and actual contrast; this source review does not certify full accessibility or appearance coverage. No source/device mutations performed.
