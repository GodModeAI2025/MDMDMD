# Local activation UI — final wording and expiry verification

2026-10-10, Xcode MCP, Arche Rules QA simulator, portrait402 x874pt. Full device-interaction skill read; fresh isolated DEBUG --scriptum-local-activation-ui-qa fixture. Source frozen throughout observations;301-file SHA256 before/after manifests IDENTICAL. After manifest was captured immediately following last observation236 and BEFORE ending session237. No source edits by QA agent.

Start228/install229 succeeded. Manager230 captured/read. Ready task review opened via actual button hitPoint102.2,759.5 (231). Normal review includes correct page/provider/model/future date/prompt and summary details.

## PASS observations

- Actual elapsed expiry: opening capture231 timestamp02:53:27.986, next capture232 timestamp02:54:29.278,61.292seconds later. MCP observation calls were slow; wait on same live handles in bounded<60s chunks, no artificial clock or time manipulation. Capture232 shows Freigabe abgelaufen. Bitte neu prüfen. and actual Aufgabe aktivieren Button Disabled.
- Scrolled using actual content hitpoints to budget233. Exact final wording Berechnete Preisobergrenze pro Lauf is visible/readable, with USD0 amount and remaining budget/UTC-month details. Expired disclosure remains and button Disabled. No clipping/overlap in tested402pt layout.
- Tapped fresh Neu prüfen hitPoint201,813.8 (234). Actual details restored, expiry disclosure removed, Aufgabe aktivieren enabled. No activation tap.
- Closed via actual Schließen235: both tasks remain Entwurf · noch nicht aktiviert. No cancellation. Scrolled236: both drafts and Noch keine Ergebnisse visible. No inference or production data mutation.
- App Running on all captures; no crash or presentation disappearance. End237 confirms Session stopped; lightweight bridge retained.

## Limits

Controlled fixture establishes actual activation review wording, elapsed expiry disabling, recheck renewal, draft preservation and absence of displayed outputs. No real provider/model/price HTTP/API keys/inference, activation repeat, physical device/TestFlight, CloudKit, iPad or accessibility-size Dynamic Type verified here. English Oct/at dates reflect simulator locale amid German app copy, as previously noted.
