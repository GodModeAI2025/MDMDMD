# Final account inspector visual verification

2026-10-09, actual Xcode MCP/mcpbridge, exclusively delegated session `Account Visual Final QA`, workspace `workspace-axVKJeu85j`, iPhone simulator Arche Rules QA 7D8F7063-DE3E-484B-8C58-E6EB0C97D4A6 (402 × 874). Installed and ran frozen production source. Inspector SHA256 before provided by owner and after verified: `87796e5994052d00581b149e09597a6fd804cd4d5556988eb9b04e96bc71fc49`.

## Obtained evidence

- `04-inspector-light`: inline Konto und Cloud title fully visible. Official Apple button visibly grey; hierarchy marks both Apple and existing-session controls Disabled. Unconfigured cloud status truthful. Paper surface intact.
- `12-text-max-confirmed`: actual Settings larger dynamic range enabled, slider 100%. First slider hierarchy hit point did not move the thumb; documented screenshot thumb fallback moved it successfully.
- `13-inspector-max-top`: title and Fertig fully visible at maximum accessibility size; body wraps.
- `14-inspector-max-middle`, `15-inspector-max-bottom`: observed ScrollView scroll hit point used twice. At 100% scroll the entire Apple button and multiline existing-session control remain visible and Disabled, with bottom space. No overlapping or unexpectedly clipped controls. Ordinary scroll viewport clipping above/below is expected.
- App PID remained 91956 through captures; no unexpected exit observed.
- `18-text-restored`: larger dynamic range 0, slider 50%, restored exactly. Appearance was observed light/automatic0 in `05-settings` and was never changed during this verification.

All interactions used the immediately preceding returned hierarchy and screenshot; captures were copied after each event. The Settings slider required screenshot thumb fallback after its calculated hit point had no effect. Adjacent screenshots/hierarchies preserve the before/after chain. No source, deployment config, credential or library content was edited.

## Scope limits

Dark mode was not repeated for this frozen correction. No eligible iPad simulator was available per owner discovery; no substitute was created. This verifies unconfigured UI layout only, not live Apple authorization, internal library-registration persistence, cloud sync or production deployment.

## Cleanup receipts

Actual Xcode MCP returned `Session stopped`; StopProject returned PID91956 `The app was stopped.`; XcodeCloseWorkspace returned `Closed workspace workspace-axVKJeu85j.` Each per-call helper exited 0, with no persistent owned bridge remaining.
