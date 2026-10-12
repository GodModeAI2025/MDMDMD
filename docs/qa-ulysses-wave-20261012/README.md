# Ulysses-Refocus-Welle, native Abnahme mit Software-Tastatur (2026-10-12)

Stand: Branch `fix/compact-writing-viewport` @ 7760bf6, Simulator-Build (`generic/platform=iOS Simulator`, CODE_SIGNING_ALLOWED=NO).
Gerät: "Scriptum Keyboard Recipe 20261012" (7C64E426-46D0-4635-87C6-EE41CC6BFAC3), iPhone 17 Pro Max, iOS 27.0, 440x956 pt.
Treiber: Xcode-MCP-Bridge über den Proxy, Session "Scriptum Ulysses Wave", Vorgehen nach `docs/qa-keyboard-recipe-20261012/README.md` (Messungen mit Tastatur vor jedem `kbd`, nach `kbd` genau ein Tap auf den Textblock).
Belege liegen als `<Schritt>.json`, `<Schritt>-hierarchyPath.txt`, `<Schritt>-screenshotPath.png` in diesem Ordner. Quelltext wurde nicht angefasst.

Ausgangslage: Das Gerät hatte schon einen Seiteninhalt aus dem Recipe-Lauf (Absatz endet auf "verfügbar.Hallo"). Das ist der Vorher-Stand, nicht Testdaten dieses Laufs.

## Ergebnis

| Nr | Prüfpunkt | Ergebnis |
|---|---|---|
| 1 | Tastatur, aktiver Block sichtbar, Leisten weg, Zusatzleiste | PASS (mit Layout-Mängeln, siehe unten) |
| 2 | Caret bleibt über der Tastatur | PASS (ein Lauf mit 30 Zeilen) |
| 3 | Zusatzleiste: Fett, Überschrift, Schließen, KI-Menü, Lektorat | PASS für Fett, Schließen, KI-Menü, Lektorat. Überschrift: FAIL bei mehrzeiligen Blöcken |
| 4 | Block-Chrome, Palette, Langdruck | PASS |
| 5 | Inline-Markdown, Erstzeilen-Überschrift | PASS für Dämpfung, Stil, Bytes und Erstzeilen-Font bei inaktivem Block. FAIL bei der Blockhöhe von Überschriftenblöcken |
| 6 | Querformat mit Tastatur | FAIL (Block-Editor bekommt im Querformat keine Software-Tastatur). Tastatur schließen, dann drehen: PASS |
| 7 | "Neue Markdown-Datei" | PASS |

## 1. Tastatur und aktiver Block (PASS)

Beleg: `03-kb-up*`.
- Tap auf den Absatz "Hier beginnt Ihr nächster Text": `Keyboard {{0,653},{440,245}}` im Baum, TextView `Keyboard Focused`.
- TextView `{{20,301.7},{192.7,110}}`, maxY 411,7. Zusatzleiste minY 565, QuickType-Zeile minY 609, Keyboard minY 653. Abstand TextView zur Zusatzleiste 153 pt, zur Tastatur 241 pt.
- Nicht vorhanden: "N Wörter", "Gespeichert", Lektorat/Überarbeiten/Zusammenfassen, `format-heading/bold/italic/list` (zum Vergleich ohne Tastatur sind alle da, `02-open*`, `22-dismiss*`).
- Zusatzleiste (y 565 bis 609): Fett, Kursiv, Überschrift wechseln, Liste, Link, Rückgängig (disabled), Wiederholen (disabled), KI-Aktionen, Tastatur schließen. Alle neun vorhanden.

Mängel, die die Messung nicht zeigt:
- Der aktive Absatz ist nur 192,7 pt breit (inaktive Blöcke 400 pt). Rechts daneben sitzt das ⋯ (Button 32x44). Der Text bricht nach 3 bis 5 Wörtern um (`03-kb-up-screenshotPath.png`). Das ist die Schreibfläche, auf die es ankommt, und sie ist weniger als halb so breit wie der Bildschirm.
- Die Zusatzleiste ist transparent. Text und Überschriften der Seite laufen darunter durch und überlagern Symbole, z. B. "Konzentriert schreiben" in `03-kb-up`, `28-inline-md-clear`, `32-heading`. Lesbar ist die Leiste nur über den Symbolen selbst.

## 2. Caret-Sichtbarkeit (PASS, schwacher Test)

Beleg: `04-after-typing*`, `05-caret-retap*`.
- Per `kbd` 30 Zeilen "Zeile N" an den Absatz angehängt (Tastatur dabei unten, wie im Recipe). Der Block wuchs auf 770 pt.
- Danach Tap auf die letzte sichtbare Zeile (y 773, liegt dort, wo gleich die Tastatur steht). Tastatur kam zurück (`Keyboard {{0,653},{440,245}}`), die Seite scrollte so, dass die Caret-Zeile "Zeile 30 w 2" bei y 510 bis 532 liegt. TextView maxY 532,3 < Zusatzleiste 565 < Tastatur 653. Abstand zur Leiste 33 pt.
- Einschränkung: Das Caret wurde per Tap platziert, nicht durch Tippen bei sichtbarer Tastatur (das geht mit dem Treiber nicht, jedes `kbd` blendet die Tastatur aus). Dass der Editor beim echten Tippen nachscrollt, ist damit nicht bewiesen, nur dass er beim Einblenden korrekt scrollt.
- Nebenbefund: ` w 2` aus meinem Befehl wurde als Text getippt (Zeile endet "Zeile 30 w 2"), weil alles nach `kbd ` wörtlich ist. Kein App-Fehler.

## 3. Zusatzleiste und KI

- Fett (`06-select-word`, `07-bold`): Doppeltap auf "Zeile" markiert das Wort, Fett setzt `**Zeile**`, Auswahl bleibt erhalten, Marker grau, Wort fett. Journal: `# **Zeile** 20`. PASS.
- Überschrift auf einzeiligem Block (`12-cycle1..4`): `# ` -> `## ` -> `### ` -> ohne Präfix. Zyklus korrekt. PASS.
- Überschrift auf mehrzeiligem Absatz: FAIL. Der erste Tap setzte `# ` vor jede Zeile des Blocks (Journal in der Sitzung: `# Zeile 1` bis `# Zeile 30`; reproduziert mit zwei Zeilen: `# Hier beginnt ...\n# Zweite Zeile im Block`, Beleg `32-heading*`). Erwartbar wäre nur die Zeile mit dem Caret oder nur die erste Zeile. Die Folgetaps änderten dann nur noch eine einzelne Zeile (`### Zeile 16`), der Zyklus ist bei Mehrzeilern also nicht konsistent.
- Tastatur schließen (`22-dismiss*`, ohne Fokus, vorher `21-sel-closed` mit Tastatur): Keyboard-Element weg (0 Treffer), TextView ohne `Keyboard Focused`, "147 Wörter", "Gespeichert 23:35", Lektorat/Überarbeiten/Zusammenfassen und die aA/B/I/Liste-Zeile (`format-*`) sind wieder da. PASS. Anmerkung: Der zuletzt aktive Block behält danach sein ⋯ (`Absatz block actions`).
- KI-Menü (`13-ki-menu`): Lektorat, Überarbeiten, Zusammenfassen, Chat. PASS.
- Lektorat (`14-lektorat`, `15-consent-cancel`): Tap öffnet sofort das Freigabe-Sheet "KI-Anfrage freigeben" (Empfänger Apple Private Cloud Compute, "Inhalte dieser Anfrage: Absatz, 80 Zeichen"). Ich habe dort nicht freigegeben ("Mit Apple verarbeiten" nicht getippt), sondern "Abbrechen". Dahinter steht das Assistenten-Panel "Lektorat" mit "Bereich: Absatz", Umschalter "Ganze Seite", Button "Starten" und dem Hinweis "Der Bereich Absatz wird an deinen gewählten KI-Zugang gesendet". Es gab kein Vordialog zur Auswahl der Aktion. Nichts wurde an einen Anbieter gesendet. PASS.
- Bereich Auswahl (`18` bis `20`): bei markiertem Wort zeigt das Sheet "Auswahl, 5 Zeichen", das Panel "Bereich: Auswahl". PASS.
- Bereich Seite: INCONCLUSIVE. Ich habe nur den Umschalter "Ganze Seite" im Panel gesehen, den Pfad ohne aktiven Block und ohne Auswahl nicht bis zum Sheet getestet.
- Nach dem Schließen des Panels kommt die Tastatur wieder (`16-panel-closed`).

## 4. Block-Chrome, Palette, Langdruck (PASS)

- Ohne aktiven Block (`02-open`, `24-reopen`, `40-reopen`): keine Elemente mit `blockDragHandle`, `ellipsis` oder `block actions`. Nur Block-Buttons.
- Aktiver Block: ein ⋯-Button direkt am aktiven Block (`03-kb-up`).
- Langdruck (1,2 s) auf einen inaktiven Block (`41-longpress`): Kontextmenü mit "Insert after", "Nach oben", "Nach unten", "Duplizieren", "Delete block". Zusätzlich funktioniert Halten und Ziehen: `drag 220 749 220 560 0.9 1.5` hat "Ihr erstes Projekt" um einen Block nach oben verschoben (`56-drag`, Journal). Tap öffnet den Editor.
- Einfügepalette über "Insert after" (`42-insert-after`): Absatz, Überschrift, Liste, Checkliste, Zitat, Code, Tabelle, Bild. Eingefügte Markdown-Bytes (Journal `insert-journal-blocks.txt`, `insert-edits-journal.json`): Absatz `\n\n`, Überschrift `## \n\n`, Liste `- \n\n`, Checkliste `- [ ] \n\n`, Zitat `> \n\n`, Code ```` ```\n\n```\n\n ````, Tabelle `|  |  |\n| --- | --- |\n|  |  |\n\n`. Kein "Text", "Quote" oder "Code" als Inhalt. Nach dem Beenden der App geflusht (`after-test-library.json`): ebenfalls keine Platzhalterwörter.
- Sprachmischung in der Oberfläche, die auffällt: "Insert after", "Delete block", "Absatz block actions", "Empty paragraph", Platzhalter "Tap to write…", Kontext "Markdown" über Überschriften im Bearbeiten. Im sonst deutschen UI sind das Lokalisierungslücken.
- Der Tabellenblock wird als Rohtext bearbeitet, in 136 pt Breite (`52-table`), das Gitter bricht unlesbar um.

## 5. Inline-Markdown (PASS) und Überschriftenhöhe (FAIL)

- Getippt (kbd): ` **fett** und *kursiv* Ende` an den Absatz. Journal-Bytes: `...verfügbar.Hallo **fett** und *kursiv* Ende\n\n`. Der getippte Text steht unverändert und vollständig (nur der Absatz davor, kein Zeichen verändert). Bildschirm (`28-inline-md-clear`): `**` und `*` grau gedämpft, "fett" fett, "kursiv" kursiv. PASS.
- Block mit `# Titel\nLegen Sie einen Space ...` (Titel per kbd vor den Absatz gesetzt, `35-type-title`): inaktiv (`38-scroll`) steht "Titel" in Überschriftengröße, die zweite Zeile "Legen Sie einen Space ..." in Fließtextgröße. PASS für den Erstzeilen-Font.
- Aber: Die Blockhöhe stimmt bei Überschriftenblöcken nicht. Aktiv hat der TextView 44 pt Höhe (`36-retap`: `{{20,369},{356,44}}`), der Block zeigt nur die erste Zeile, die zweite ist abgeschnitten, der lange Überschriftenabsatz in `08-heading1` zeigt nur "Hier beginnt Ihr". Inaktiv hat derselbe Block 556 pt Höhe, mit großer Leerfläche (`37-inactive`, `38-scroll`: TextView `{{20,166.7},{356,556.3}}`). Beides ist ein Höhenmessfehler.

## 6. Querformat (FAIL)

- Mit offener Tastatur im Hochformat auf landscapeLeft gedreht (`61-landscape`): Tastatur weg, Fokus weg (TextView ohne `Keyboard Focused`). Das war nach früheren Läufen erwartet.
- Erneuter Tap auf den Textblock im Querformat (`64-landscape-kb`, `65-landscape-retap2`, `66-landscape-other`, `69-ls-tap`, außerdem nach Neustart der App im Querformat `71-ls-tap-empty`): Es erscheint nur die Zusatzleiste (y 396 bis 440), aber nie die Software-Tastatur und nie `Keyboard Focused`. Der Schreibbereich bleibt `blockWritingView {{343,136.3},{613,198.7 bis 222.7}}`, die alte aA/B/I/Liste-Zeile sichtbar.
- Gegenprobe: Tap auf das Titelfeld "Seitentitel" im Querformat (`86-ls-title-tap`) bringt `Keyboard {{117,260},{722,177}}` und `Keyboard Focused`. Safari-Adressfeld auf demselben Gerät im Querformat ebenso (`Keyboard {{117,260},{722,177}}`). Der Simulator kann es also, nur der Block-Editor bekommt im Querformat keine Software-Tastatur.
- Folge: Im Querformat kann auf dem iPhone mit Software-Tastatur nicht im Block geschrieben werden. Messung "Editor über der Tastatur" ist deshalb nicht möglich, bewertet als FAIL. Beachten: Im Querformat zeigt die iPhone-17-Pro-Max-Ansicht die Seitenleiste (343 pt) und lässt dem Editor 613 x 222 pt.
- Tastatur schließen, dann drehen (`74` bis `76`): Hochformat Tastatur zu (Keyboard 0, Zusatzleiste 0), nach landscapeLeft 0, zurück nach portrait 0, keine Fokus. Tastatur öffnet sich nicht von selbst. PASS.
- Nebenbeobachtung: Nach der Querformat-Phase war im Hochformat zuerst nur die Zusatzleiste (y 912) ohne Tastatur sichtbar (`72-portrait`). Ein Tap auf den Textblock brachte die Tastatur zurück (`73-portrait-tap`).

## 7. "Neue Markdown-Datei" (PASS)

Querformat, Seitenleiste, Dateien-Menü, "Neue Markdown-Datei" (`83-dateien`, `84-new-md`): Seite "Unbenannt" erscheint und öffnet, im Container entsteht `Documents/Unbenannt.md` (0 Bytes). Nach dem Test gelöscht.

## Daten und Gerät

- `Documents/Skriptum/library.json` vorher: `67b61a272ba788bcc723a1d277a35938327df1a78962963594af32a8b93fe227`.
- Zwischenstand der Tests (nach dem Beenden der App): `ddddd58b54a2a5c4ad2c940ff7e35c9388b6094ea07cc9f841b1642669f8d2df` (Kopie `after-test-library.json`).
- Nachher (aus Sicherung zurückgespielt, `edits/` geleert, `Unbenannt.md` gelöscht): `67b61a272ba788bcc723a1d277a35938327df1a78962963594af32a8b93fe227`. Gleich wie vorher. Zwischendurch habe ich dreimal die App beendet und die Sicherung zurückgespielt, um saubere Ausgangslagen zu haben.
- Nur im Simulator-Container gelöscht. Kein iCloud, keine Signierung, kein Portal.
- Xcode-Run-Ziel war "Scriptum Keyboard Recipe 20261012" und ist es nach dem Lauf noch, es wurde nicht umgeschaltet. Session beendet, Gerät heruntergefahren.
- DD4D1567 (Regular Workspace QA) wurde nicht benutzt.
- Nicht getestet: Seite-Bereich der KI-Aktion (siehe 3), Tippen bei sichtbarer Tastatur (Treiber-Grenze), Rotation Hochformat zu Querformat mit erhaltenem Fokus, iPad, physisches Gerät.

## Priorisierte Mängel für die Entwickler

1. Querformat: Block-Editor nimmt keine Software-Tastatur an (Titelfeld schon).
2. Überschrift-Taste prefixt jede Zeile eines mehrzeiligen Absatzes.
3. Blockhöhe bei Überschriftenblöcken: aktiv 44 pt (Text abgeschnitten), inaktiv 556 pt.
4. Aktiver Absatz nur 192,7 pt breit neben dem ⋯.
5. Zusatzleiste transparent, Seitentext scheint durch.
6. Englische Strings ("Insert after", "Delete block", "Tap to write…", "Empty paragraph").
