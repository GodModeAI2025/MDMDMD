# Local Tasks UI QA

Native Xcode MCP session Local Tasks UI QA, workspace workspace-8LDnl5qbLc, Arche Rules QA simulator, iPhone portrait 402 × 874 pt. Normal launch arguments. InstallAndRun succeeded; application remained Running throughout.

Frozen source manifest: 268 source/config files, SHA256 `b3b901421bd156cfdd4e9c60fd453bda81fde4363d2a58fd68244e3e69abba07`, identical before/after.

Verified through actual UI:
- Welcome launch → visible Spaces und Bibliothek öffnen → welcome editor. The first offscreen/duplicate hierarchy hitPoint at y437 had no effect; alternate actual visible library button y278 worked.
- Editor overflow → Seitenaktionen → Geplante Aufgaben opens native manager.
- Neue Aufgabe form shows welcome page preselected, summary result, one-shot date one hour in future, German context scope notice, default Apple PCC. Empty prompt correctly disables Entwurf speichern.
- Entered only authorized prompt QA – lokale Aufgabe, nicht ausführen; Entwurf speichern became enabled. Saved inactive draft; exact full prompt and Entwurf · noch nicht aktiviert appeared.
- Closed manager and reopened via same menu; draft remained present. This demonstrates same-process manager persistence, not cold-launch persistence.
- Abbrechen changed only that QA draft to Abgebrochen; cancel control disappeared. Left canceled QA record as authorized receipt. No AI requests, execution, activation, invitation, portal change, provisioning, or document edits performed.

Visual observations: manager and form headings/buttons readable without overflow at 402 pt. Task row has redundant provider/model display Apple Private Cloud Compute · Apple Private Cloud Compute and English date locale 10. Oct 2026 at 02:02 within German interface. Cosmetic improvement recommended. Long prompt field scrolls within its input; full prompt fits manager row in this test. Lower creation form sections require normal scroll; not fully inspected, unchanged defaults.

Screenshots: tasks-06 empty manager; tasks-07 new form; tasks-09 saved draft; tasks-13 reopened draft; tasks-14 canceled draft. Matching hierarchy and receipt JSON alongside.

Session ended via DeviceInteractionEndSession (tasks-end.json); proxy retained. Actual provider execution, cost/consent activation, background execution, iPad layout, cold launch persistence and physical device are outside this QA scope and unverified.
