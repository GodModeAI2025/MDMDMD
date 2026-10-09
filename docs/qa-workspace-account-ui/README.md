# Workspace account UI — native QA

Actual Xcode MCP/mcpbridge verification on 2026-10-09. Built application sources at b9664caccb6ccd4b0c1b3b618bf1f9c745d65c13; e982d66 subsequently changed documentation only. No production source, scheme, deployment configuration, real account or Keychain data changed.

## Obtained coverage

Owned session `Workspace Account UI QA`, workspace `workspace-DLfPWODlFK`, simulator `Arche Rules QA` (iOS 27, 402 × 874). Actual installed app PID 81720 remained the same throughout, with no observed crash.

1. Launch → Spaces und Bibliothek öffnen → built-in 54-word welcome page → Alle Seiten → Dateien menu → Konto und Cloud.
2. Unconfigured inspector accurately reports Cloud-Dienst nicht eingerichtet, offline writing/export availability, and that login does not establish synchronization. Apple sign-in and existing-session check are accessibility Disabled.
3. Fertig dismisses to the same welcome library; reopening Dateien → Konto und Cloud succeeds with same PID and content.
4. Simulator Settings light/auto-off changed temporarily to dark. Inspector changes its official Apple button style and remains readable.
5. Larger accessibility text was enabled and slider readback 100% confirmed. Inspector body wraps and scrolls; compact navigation title becomes fully readable after scroll. Only upper and middle content were inspected at maximum; lower Apple/session controls were not scrolled into view at maximum.

Every event has prior captured hierarchy/screenshot and returned after-event hierarchy/screenshot. Touches use calculated hit points. Slider hit-point drag had no effect; documented screenshot-thumb fallback set 100% and later restored 50%.

## Findings

- Disabled Apple sign-in remains visually full contrast and prominent in light and dark appearance, suggesting availability despite actual accessibility Disabled state (capture-05 and capture-dark screenshots).
- At maximum accessibility text, initial large navigation title truncates to “Konto und C…” (capture-max-dark screenshot); after scrolling the compact title is complete (capture-max-scroll).
- No overlapping inspector body text or crash observed in obtained coverage.

## Limits

No iPad simulator appears among eligible Xcode run destinations; only “My Mac (Designed for iPad)” is an actual Mac target. iPad coverage was therefore unavailable and was not replaced by Mac proof. Full returned discovery saved in destinations-full.json.

Ordinary sheet close/reopen is black-box evidence only; it does not prove internal workspace registration remains attached. No internal runtime/kernel probe, configured cloud deployment, Apple sign-in, restore, logout, deletion, cloud sync or production account was exercised.

## Cleanup

Settings restored: light selected, automatic off; larger accessibility text off; text-size slider 50%. Readback evidence settings-14 and settings-19. Session stopped, PID 81720 stopped, assigned workspace closed; all per-call bridge helpers exited 0. Cleanup receipts included.
