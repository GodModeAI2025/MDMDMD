# Ulysses-Fix, native Nachprüfung mit Software-Tastatur (2026-10-13)

Stand: Branch `fix/compact-writing-viewport` @ a8ce4c4, Simulator-Build (`generic/platform=iOS Simulator`, CODE_SIGNING_ALLOWED=NO, Build erfolgreich), über das vorhandene Install-Verzeichnis drübergespielt. Quelltext, Branch und Xcode-Run-Ziel wurden nicht angefasst.
Gerät: "Scriptum Keyboard Recipe 20261012" (7C64E426-46D0-4635-87C6-EE41CC6BFAC3), iPhone 17 Pro Max, iOS 27.0, 440x956 pt (Hochformat), 956x440 (Quer).
Treiber: Xcode-MCP-Bridge über den Proxy, Session "Scriptum Fix QA", Vorgehen nach `docs/qa-keyboard-recipe-20261012/README.md`: Messungen mit Tastatur vor jedem `kbd`, nach `kbd` genau ein Tap auf den Block.
Belege: `<Schritt>.json`, `<Schritt>-hierarchyPath.txt`, `<Schritt>-screenshotPath.png` in diesem Ordner. Hashes in `SHA256.json`.
Hinweis zum Gerät: Die Installation hat den Container-Pfad gewechselt (neu 718FA22A...), der Inhalt von `library.json` war identisch (siehe unten).

## Ergebnis

| Nr | Prüfpunkt | Ergebnis |
|---|---|---|
| A | Querformat mit Software-Tastatur | PASS |
| B | Überschrift-Taste nur auf der Caret-Zeile | PASS (Logik), aber Folgefehler bei der Blockhöhe, siehe C |
| C | Blockhöhe Überschriften-/Roh-Blöcke | FAIL auf a8ce4c4 (44 pt mit Tastatur). Nachtest auf f7560b1: PASS für Titel-Block und Kurz-Mehrzeiler, TEILWEISE bei langen Roh-Blöcken (fest 132 pt) |
| D | Breite, ⋯ | PASS |
| E | Deutsche Strings | PASS |
| F | Alte aA/B/I/Liste-Zeile weg, Zusatzleiste opak | PASS |

## A. Querformat (PASS)

- Kalter Tap im Querformat auf einen inaktiven Block (`62b-a-cold-tap`, Block "Ihr erstes Projekt"): `Keyboard {{117,260},{722,177}}` im Baum, TextView `Keyboard Focused`, TextView `{{363,125.3},{222.3,34}}`, maxY 159,3. Zusatzleiste minY 172, Tastatur minY 260. Caret-Zeile liegt über der Leiste (13 pt Abstand).
- Absatz mit 2 Zeilen, Tastatur vorher per Tastatur schließen weg, dann Tap auf Zeile 2 (`18b-l-line2-settled`): Keyboard vorhanden, Fokus, TextView maxY 170,7 < Leiste 172. Das Caret steht sichtbar am Ende von Zeile 2 (Screenshot). Der sichtbare Streifen zwischen Seitentitel und Leiste ist nur etwa 36 pt hoch, die erste Zeile scrollt dafür unter den Titel.
- Hochformat tippen, dann nach landscapeLeft drehen (`11-p2l-rotate`, `11b-p2l-settled`): Tastatur bleibt (`Keyboard {{117,260},{722,177}}`), TextView weiter `Keyboard Focused`. Erneuter Tap im Querformat (`12-l-retap`): ebenfalls Keyboard und Fokus.
- Querformat mit Fokus nach Hochformat zurück (`19b-l2p-settled`): `Keyboard {{0,653},{440,245}}` und `Keyboard Focused`, der Fokus wird wiederhergestellt.
- Tastatur per Zusatzleiste schließen (`13-l-dismiss`: Keyboard 0, Fokus weg), drehen auf portrait (`14b`: Keyboard 0) und wieder auf landscape (`15b`: Keyboard 0): Tastatur öffnet sich nicht von selbst.
- Vorher (Welle 20261012): Im Querformat gab es nie eine Tastatur. Das ist behoben.

## B. Überschrift-Taste (PASS in der Logik)

- Absatz mit 2 Zeilen ("...verfügbar.Hallo" und "Zweite Zeile im Block"). Caret in der letzten Zeile (`23-b-cycle1..4`, Journal): Zeile 2 wird `# `, `## `, `### `, ohne. Zeile 1 bleibt unverändert.
- Caret in Zeile 1 (`26-b-first-cycle1..4`): nur Zeile 1 wird `# `, `## `, `### `, ohne. Zeile 2 bleibt.
- Absatz mit 32 Zeilen (Zeile 3 bis 30 per kbd angehängt, Caret in "Zeile 29", `30-b30-cycle1..4`): nur diese Zeile ändert sich (`# Zeile 29`, `## Zeile 29`, `### Zeile 29`, wieder ohne). Der Block hat danach weiter 32 Zeilen, keine andere Zeile hat einen Präfix.
- Der Fehler "jede Zeile bekommt `# `" von vorher ist weg.
- Folgefehler: Sobald eine Zeile ein `#` trägt, wechselt der Block in die Rohquelle-Ansicht (Beschriftung "Markdown") und schrumpft mit Tastatur auf 44 pt (siehe C). Beim 2-Zeilen-Fall (`23-b-cycle1-settled`) zeigt der 44-pt-Streifen nur die ersten beiden Zeilen, die bearbeitete Zeile mit dem Caret ist nicht sichtbar. Beim 32-Zeilen-Fall (`30-b30-cycle1`) sieht man nur die Caret-Zeile, vom Rest nichts.

## C. Blockhöhe (FAIL mit Tastatur)

Testblock `# Titel\nLegen Sie einen Space für Ihr Manuskript, Ihre Recherche oder Ihre Notizen an.` (Journal-Bytes bestätigt).

| Zustand | TextView/Button-Höhe | Beleg | Ergebnis |
|---|---|---|---|
| aktiv, Tastatur ausgeblendet (nach kbd) | 85 pt, "Titel" Überschriftengröße, Zeile 2 Fließtextgröße | `44-kbd`, `35-c-kbd` | PASS |
| inaktiv, keine Tastatur | 113 pt (Titel, 2 Zeilen, Leerzeile), kein 556-pt-Leerraum mehr | `51-e-insert`, `53-d-dismiss` | PASS |
| aktiv, Software-Tastatur oben | 44 pt, `{{20,463},{400,44}}` | `46b-c-titel-active-kb` | FAIL |
| inaktiv, Software-Tastatur steht (anderer Block aktiv) | 44 pt, `{{20,406.3},{400,44}}`, Zeile 2 abgeschnitten | `45b-c-active-kb` | FAIL |

- Beim FAIL-Fall zeigt der 44-pt-Streifen (`46b-...screenshotPath.png`) nur die leere Schlusszeile unter dem Text, der Block wirkt leer. Der Caret sitzt dort.
- Zusätzlich in einem Lauf (`36b-c-active-kb-settled`): Der aktive 44-pt-Rohblock lag bei y 736 bis 780, also hinter der Tastatur (Keyboard minY 653), und wurde nicht in den sichtbaren Bereich gescrollt. Das war direkt nach einer Folge aus 33-Zeilen-Block plus `kbd`. Im sauberen Neustart (`45`/`46`) stand der Block bei y 463 und war sichtbar. Nicht eindeutig reproduziert, deshalb nur Beobachtung.
- Dasselbe Verhalten für den Mehrzeiler aus B: aktiv 44 pt, obwohl 4 bis 33 Zeilen Inhalt.
- Ein reiner Absatz ohne Marker folgt dem Inhalt bis zum Viewport: 32 Zeilen, Tastatur oben 532 bis 583 pt, ohne Tastatur 655 pt (`29-b30-tap`, `30-b30-cycle4`, `32-c-dismiss`), Text intern scrollbar. Das funktioniert.
- Mutmaßung für die Entwickler (nicht verifiziert): Die Rohquelle-Ansicht bekommt mit Tastatur `sourceViewportHeight` = `max(44, ...)` und landet auf dem Minimum, ohne Tastatur stimmt die Höhe. `.frame(maxHeight:)` allein hebt die 44 pt nicht an, wenn `documentViewportHeight` bei sichtbarer Tastatur klein berechnet wird.

### Nachtest C auf f7560b1 (sourceViewportHeight Minimum 132)

Neu gebaut und installiert (BUILD SUCCEEDED, neuer Container 8DD1C026..., `library.json` vorher 67b61a27...). Belege: `r*`-Dateien in diesem Ordner.

| Zustand | Höhe | Beleg | Ergebnis |
|---|---|---|---|
| `# Titel\nLegen Sie ...`, aktiv, Software-Tastatur oben | 85 pt, `{{20,463},{400,85}}`, maxY 548 < Leiste 565, Caret hinter "Titel" sichtbar, beide Zeilen lesbar | `r05b-active-kb` | PASS (vorher 44) |
| derselbe Block, inaktiv, anderer Block aktiv, Tastatur oben | 113 pt, `{{20,468},{400,113}}`, Inhalt voll | `r06b-inactive-kb` | PASS (vorher 44) |
| derselbe Block, ohne Tastatur | 113 pt inaktiv | `r07b-nokb` | PASS |
| Absatz mit `#` auf einer Zeile (`# Zweite Zeile im Block ...`, Inhalt ca. 152 pt), aktiv, Tastatur oben | 132 pt, `{{20,322},{400,132}}`, maxY 454 < Leiste 565, Caret-Zeile sichtbar, oberste Zeile angeschnitten (intern gescrollt) | `r12b-heading-kb` | PASS mit Einschränkung (vorher 44, Caret-Zeile unsichtbar) |
| derselbe Block auf ca. 19 Zeilen verlängert (14 Zeilen per kbd), ohne Tastatur | 503 pt, folgt dem Inhalt | `r13-kbd-lines` | PASS |
| derselbe Block, aktiv, Tastatur oben | 132 pt, nur ca. 6 Zeilen sichtbar, Caret-Zeile sichtbar (y 442 < 565), intern scrollbar | `r14b-long-kb` | TEILWEISE |

Bewertung: "nicht 44 pt, Caret-Zeile über der Zusatzleiste" ist erfüllt. Offen: Mit Tastatur bleibt ein Roh-Block bei 132 pt stehen, auch wenn der Inhalt größer ist und über der Zusatzleiste noch etwa 390 pt Platz wären (Viewport 174 bis 565). Die Obergrenze `documentViewportHeight - Caption - 6` fällt mit Tastatur offenbar kleiner als 132 aus, sonst würde der Block weiter wachsen. Hinweis: Mein Tap auf (200,600) in `r14` traf wegen der verschobenen Lage den Link-Button der Zusatzleiste und fügte `[](https://)` ein. Das ist ein Bedienfehler des Tests.

Daten: `library.json` nach den Tests unverändert 67b61a27...; nach Zurückspielen und Leeren von `edits/`: 67b61a272ba788bcc723a1d277a35938327df1a78962963594af32a8b93fe227. Gerät heruntergefahren.

## D. Breite und ⋯ (PASS)

- Aktiver Absatz im Hochformat: TextView `{{20,301.7},{398,66}}`, also 398 pt statt 192,7 pt (inaktive Blöcke 400 pt). Querformat: 511 pt mit Seitenleiste, 706 pt ohne, jeweils gleich der Breite der inaktiven Blöcke.
- Andere aktive Blöcke sind nur so breit wie ihr Inhalt, ohne dass sich der Umbruch ändert: Überschrift 222,3 pt (`16b`), kurzer Absatz "Legen Sie ..." 353,7 pt (`42-tap-legen`).
- Tabelle (`52b-d-table`): TextView `{{20,463},{136.7,61}}`, monospaced, die drei Zeilen `|  |  |`, `| --- | --- |`, `|  |  |` stehen unumgebrochen und lesbar (vorher unlesbar umbrochen). Die Breite 136,7 pt entspricht dem Inhalt, nicht der vollen Breite.
- ⋯: genau ein `Blockaktionen:`-Button, am aktiven Block (`10-p-tap`, `52b`, `54b-d-switch`: Wechsel Tabelle zu Absatz, danach nur noch das ⋯ des Absatzes). ⋯-Frame `{{384,279.7},{36,28}}` direkt über dem Absatz (TextView beginnt bei 301,7): Frames überlappen 6 pt vertikal, im Screenshot überdeckt das ⋯ keinen Text. Das ⋯ sitzt über der ersten Textzeile, nie daneben.
- Nach Tastatur schließen (`53-d-dismiss`, `13-l-dismiss`): Der Block bleibt im Bearbeiten-Modus (TextView statt Button), das ⋯ bleibt genau einmal an diesem Block. Kein verwaistes ⋯ an einem inaktiven Block. Das ist dasselbe Verhalten wie in der Welle davor, hier nicht als Fehler gewertet.

## E. Deutsche Strings (PASS)

- Langdruck 1,3 s auf einen inaktiven Block (`50-e-longpress`, `56-e-lp`): "Darunter einfügen", "Nach oben", "Nach unten", "Duplizieren", "Block löschen". Palette "Block einfügen" mit Absatz, Überschrift, Liste, Checkliste, Zitat, Code, Tabelle, Bild, Schließen "Blockauswahl schließen".
- Leerer Absatz inaktiv (`59b-e-inactive-empty`): Platzhalter "Zum Schreiben tippen …", Accessibility-Label "Leerer Absatz". Aktiv und leer (`58b-e-para`): Platzhalter "Schreiben …".
- ⋯-Button: "Blockaktionen: Absatz/Überschrift/Tabelle". Überschrift über Roh-Blöcken: "Markdown" bzw. "Markdown-Tabelle".
- Im Baum bleiben englische Wörter ohne sichtbare Wirkung: Bild-Kinder in Buttons (`More` im ⋯, `Up`, `Down`, `duplicate` im Kontextmenü) und die System-Scrollbar-Labels. Nicht sichtbar im UI. Kein "Insert after", "Delete block", "Tap to write…", "Empty paragraph" mehr.

## F. Alte Formatzeile weg, Zusatzleiste opak (PASS)

- Kein Element mit `format-*` in irgendeinem der 321 Belege (Hoch- und Querformat, mit und ohne Tastatur, mit Fokus ohne Tastatur nach kbd).
- Aktiver Block mit Tastatur: nur Zusatzleiste (y 565 bis 609, Fett, Kursiv, Überschrift wechseln, Liste, Link, Rückgängig, Wiederholen, KI-Aktionen, Tastatur schließen). Querformat y 172 bis 216.
- Nach `kbd` (Tastatur ausgeblendet, Fokus bleibt) erscheinen unten die Seitenleiste "N Wörter / Gespeichert", "Lektorat / Überarbeiten / Zusammenfassen" und die Zusatzleiste (y 912). Das ist der Hardware-Tastatur-Zustand des Treibers, nicht die alte Formatzeile.
- Opak: Pixelstichprobe in der Leiste zwischen den Symbolen (x 376 bis 388, y 568 bis 604) liefert in Screenshots mit Seitentext direkt dahinter überall (244,243,247), also keine Durchsicht (`10-p-tap`, `29-b30-tap`, `30-b30-cycle1`, `45b`, `52b`). In `29-b30-tap` und `45b` läuft Text der Seite oben bündig in die Leiste hinein und wird sauber abgeschnitten.

## Daten und Gerät

- `Documents/Skriptum/library.json` vorher: `67b61a272ba788bcc723a1d277a35938327df1a78962963594af32a8b93fe227`. Nach der Installation im neuen Container gleich. Nach den Tests (`after-test-library.json`) gleich, die Block-Edits blieben im `edits/`-Journal. Nach dem Zurückspielen aus der Sicherung und Leeren von `edits/`: `67b61a272ba788bcc723a1d277a35938327df1a78962963594af32a8b93fe227`.
- Zwischendurch einmal App beendet und Sicherung zurückgespielt (Schritt 40), um den Testblock sauber aufzubauen.
- Kein KI-Zugang genutzt, nichts an Anbieter gesendet, keine Freigabe bestätigt. Kein iCloud, keine Signierung, kein Portal. Xcode-Run-Ziel nicht verändert. Gerät am Ende heruntergefahren. `DeviceInteractionEndSession` lieferte einen Fehler "data couldn't be read"; die Session wurde nicht weiter benutzt.
- Nicht getestet: iPad, physisches Gerät, Tippen bei sichtbarer Tastatur (Treibergrenze, jedes `kbd` blendet sie aus).

## Für die Entwickler

1. Rohquelle-Blöcke (Block mit `#` in einer Zeile, "Markdown"-Beschriftung) werden mit Software-Tastatur 44 pt hoch, aktiv und inaktiv, der Inhalt ist abgeschnitten. Ohne Tastatur stimmt die Höhe (85/113 pt). Betrifft auch jeden Mehrzeiler, auf dem die Überschrift-Taste benutzt wird.
2. Querformat, Überschrift-Taste und Breite sind in Ordnung.
