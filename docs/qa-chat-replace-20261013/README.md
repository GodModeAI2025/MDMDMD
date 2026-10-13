# QA Chat ersetzt Text (Build 5, Simulator, Fake-Provider), 2026-10-13

Gerät 7C64E426 (iPhone 17 Pro Max, iOS 27), Debug-Build mit SCRIPTUM_FAKE_AI=1, kein Netz, kein Login. Gesteuert über Xcode DeviceInteractionSynthesize. Rohdaten (Hierarchie und Screenshot je Schritt) in `ev/`.

Ausgangsblock: "Hier beginnt Ihr nächster Text. Schreiben Sie in offenem Markdown — Ihre Bibliothek ist auch offline verfügbar.Hallo"

| # | Punkt | Ergebnis |
|---|---|---|
| 1 | Kein Chat/Änderung-Picker mehr | PASS. Sheet zeigt nur Kontext-Karte, Verlauf, "Dein Auftrag" und den Hinweis "Fragen werden beantwortet. Änderungswünsche führt der Chat sofort im Text aus, mit „Rückgängig“." (`01-chat-sheet-no-picker.png`) |
| 2 | "Mach daraus ein Gedicht" ersetzt den Block | PASS. Block im Editor danach "Apfelkuchen", der zweite Absatz "Goldener Teig, warmer Duft." steht als eigener Block darunter (`03-page-after-gedicht.png`). Panel "Änderung übernommen" + Rückgängig, Blasen "Gern." / "Der Text ist ersetzt." / "Der Text wurde geändert.", Gedicht steht nicht im Chat (`02-gedicht-applied.png`). |
| 3 | Rückgängig stellt Originalblock exakt her | PASS. Nach Tap auf Rückgängig im Panel steht im Block wieder exakt der Ausgangstext, Kontextkarte ebenfalls (`04-after-undo-panel.png`). |
| 4 | Strict-Pfad "Ersetze den Text durch ein Gedicht über Apfelkuchen" | PASS. Kontextkarte/Block zeigt "Äpfel schälen, Teig bereiten, Apfelkuchen backen.", Panel "Änderung übernommen" + Rückgängig, Undo stellt den Originalblock her (`05-strict-applied.png`, `06-strict-after-undo.png`). Hinweis: im Chat steht bei diesem Pfad der neue Text als Assistent-Blase statt "Der Text wurde geändert." (anderer Pfad, nur Auffälligkeit). |
| 5 | "Was ist ein Haiku?" | PASS. Antwort "Das ist eine Antwort im Chat.", Seite unverändert, kein Änderung-Panel (`07-haiku-chat.png`). |
| 6 | Auswahl | PASS. Wort "Markdown" markiert, Kontext "Auswahl", nach "Mach daraus ein Gedicht" nur die Auswahl ersetzt: "…offenem Apfelkuchen" + neuer Absatz "Goldener Teig, warmer Duft. — Ihre Bibliothek…" (`08-selection.png`, `09-selection-scope.png`, `10-selection-applied.png`). |
| 7 | Ganze Seite | PASS. Toggle "Ganze Seite" setzt "Kontext: Seite", nach dem Prompt besteht die Seite nur noch aus "Apfelkuchen" und "Goldener Teig, warmer Duft." (Titel bleibt) (`11-whole-page-scope.png`, `12-whole-page-applied.png`). |

## Auffälligkeiten (keine Testfehler)

- Das Panel "Änderung übernommen" mit Rückgängig ist nach Schließen und erneutem Öffnen des Sheets weg (Chat-Verlauf bleibt). Der Editor-Rückgängig-Button ist nach der Chat-Änderung deaktiviert. Eine Änderung ist also nur im geöffneten Sheet rückgängig zu machen. Ursache nicht im Code geprüft.
- Der Gedicht-Text "Apfelkuchen\n\nGoldener Teig, warmer Duft." erzeugt zwei Blöcke; der zweite wird im Editor mit Label "Markdown" als Markdown-Block dargestellt.
- Der erste Lauf von Punkt 2 wurde nicht per Panel zurückgenommen, sondern der Block per Tastatur rekonstruiert. Der zweite Lauf (Punkt 3) belegt das exakte Undo. Der übrig gebliebene Absatz "Goldener Teig, warmer Duft." stammt aus Lauf 1 und ist Testdaten-Rest. Der Simulator-Seitenzustand am Ende ist durch die Tests verändert (Punkt 6 und 7 nicht zurückgenommen).
