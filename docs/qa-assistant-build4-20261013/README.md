# QA KI-Assistent Build 4, 13. Oktober 2026

Simulator 7C64E426 (iPhone 17 Pro Max, iOS 27), Branch fix/compact-writing-viewport, Commit 8cbbfb0, bereits installierter Build. Bedienung per DeviceInteractionSynthesize (Touch-Rezept aus qa-keyboard-recipe-20261012). Kein Login, kein Anbieter, keine Anfrage gesendet, "Starten" und "Senden" nicht gedrückt. Belege in `ev/` (Screenshots und Hierarchien).

| Punkt | Ergebnis | Beleg |
|---|---|---|
| 1 Kontextkarte und Feld "Dein Auftrag" | PASS | ev/05-chat |
| 2 Auswahl / Absatz / Seite | PASS | ev/05-chat, 06-page, 17-chat |
| 3 Kein Freigabedialog | PASS (nur bis zum Senden geprüft) | alle Läufe |
| 4 Tastatur Hochformat | PASS mit Anmerkung | ev/08-field2 |
| 4 Tastatur Querformat | FAIL | ev/09-rot, 10-landscape-settled |
| 5 Lektorat-Panel mit Starten | PASS mit Anmerkung | ev/20-lekt |

## Details

1. Karte oben: Label "Kontext: Absatz", Vorschau, "Wird an Apple Private Cloud Compute gesendet", Umschalter "Ganze Seite". Unten: Überschrift "Dein Auftrag", Feld mit dunklem Akzentrahmen, Sendepfeil rechts im Feld (deaktiviert bei leerem Text).
2. Nur Caret im Block: "Kontext: Absatz". Nach Tipp auf "Ganze Seite": "Kontext: Seite", Vorschau beginnt mit der Überschrift, Umschalter heißt "Nur Absatz", Platzhalter wechselt zu "Was soll mit der Seite geschehen?". Mit "Alles auswählen" im Block: "Kontext: Auswahl" (auch im Lektorat-Panel).
3. In keinem Schritt erschien "KI-Anfrage freigeben". Das Senden selbst wurde bewusst nicht ausgelöst, der Punkt ist daher nur für Öffnen, Umschalten und Panelwechsel belegt.
4. Hochformat mit Tastatur: Karte, Umschalter Chat/Änderung, Feld und Sendepfeil (y ca. 547) bleiben sichtbar und erreichbar. Die Karte schrumpft auf zwei Zeilen Vorschau, der Leerzustandstext ("Mit dieser Seite arbeiten") wird hinter dem Umschalter abgeschnitten (unkritisch, nur Platzhalter).
   Querformat mit Tastatur: Layout kaputt, siehe Defekte.
5. Panel öffnet mit Titel "Lektorat", Kontextkarte und Button "Starten" (unten rechts). Nicht gedrückt.

## Defekte

- D1 (Querformat, Chat-Sheet, Tastatur oben): Das Feld "Dein Auftrag" (TextField, Rahmen y 217 bis 259 pt) und der Sendepfeil liegen unter der Tastatur bzw. deren Vorschlagsleiste (Tastatur sichtbar ab ca. y 215 pt von 440 pt). Der Auftrag ist nicht lesbar, der Sendepfeil nicht erreichbar. Das Sheet scrollt das fokussierte Feld nicht in den sichtbaren Bereich und gibt dem Inhalt keine Mindesthöhe.
- D2 (Querformat, gleiche Ansicht): Die Navigationsleiste ("Schließen", Titel, KI-Zugang-Button) überlappt die Kontextkarte, weil der Inhalt nach oben unter die Leiste geschoben wurde. Vorschautext und "Wird an ... gesendet" sind teilweise verdeckt.
- D3 (Lektorat-Panel, Fehlerzeile): Beim Öffnen steht schon eine rote, englische Fehlermeldung "The operation couldn't be completed. (FoundationModels.LanguageModelError error -1.)". Ob sie von einem früheren Lauf stammt oder beim Öffnen entsteht, ist nicht geklärt. Gehört in lesbares Deutsch, und ein frisch geöffnetes Panel sollte keinen alten Fehler zeigen.
- D4 (klein, Hochformat, Chat-Tab): Hinweistext unter dem Feld bricht mitten in den Anführungszeichen um ("Ersetze .." / "“ werden als Änderung ausgeführt"), ohne Tastatur. Mit Tastatur wird er auf eine Zeile gekürzt.

## Nachtest nach Fix 4749463 (kompaktes Querformat), 13. Oktober 2026

Neu gebaut (Simulator-Build), auf 7C64E426 neu installiert, nichts gesendet. Belege: `ev/r07-*` (Hochformat), `ev/r08-*` und `ev/r09-*` (Querformat).

| Punkt | Ergebnis |
|---|---|
| Querformat, Chat, Tastatur oben: Feld und Sendepfeil sichtbar | PASS (D1 behoben). Sendepfeil (y 184 bis 217 pt) und Feld "Dein Auftrag" liegen über der Tastatur, Vorschau und Auswahlzeile sind ausgeblendet. |
| Navigationsleiste überlappt die Kontextkarte nicht | Weitgehend PASS (D2). Die Karte beginnt bei y 60 pt, die Unterkante des Buttons "Schließen" reicht bis y 64 pt, also ca. 4 pt Berührung am Rand. Kein Text verdeckt. |
| Hochformat mit Tastatur | PASS. Feld (y 504 bis 547 pt) und Sendepfeil über der Tastatur, Chat/Änderung und "Kontextseiten/Prompts" bleiben sichtbar. |

Restpunkte:
- Querformat mit Tastatur: Das Feld ist auf eine Zeile (20 pt) zusammengedrückt und seine Unterkante wird von der Vorschlagsleiste der Tastatur um 1 bis 2 pt angeschnitten. Nutzbar, aber knapp.
- Nach der Drehung verschwindet die Software-Tastatur, bis man das Feld erneut antippt (bekanntes Simulatorverhalten laut Tastatur-Rezept).
- Der Chat zeigte nach dem Neustart schon eine Nutzernachricht "Korrigiere Rechtschreibung, Grammatik ..." (Text der Lektorat-Aktion), obwohl ich nur "Chat öffnen" getippt habe. Keine Antwort, kein Netzwerkzugriff erkennbar. Vermutlich wiederhergestellter Verlauf der früheren Lektorat-Öffnung; ob das Öffnen des Lektorat-Panels bereits eine Anfrage auslöst (davon zeugt auch die Fehlerzeile D3 im ersten Lauf), sollte der Entwickler prüfen.
- D3 (englische Fehlerzeile) wurde im Nachtest nicht erneut geprüft.
