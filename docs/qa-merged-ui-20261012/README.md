# QA merged UI 2026-10-12 (HEAD 015e686)

Native Prüfung dreier Fixes auf Simulatoren. Quelltext-Stand: Branch fix/compact-writing-viewport, Sources identisch zu 015e686 (HEAD war zwischenzeitlich b06d6db, das ändert nur scripts/ und docs/; `git diff 015e686 HEAD -- Sources` ist leer). Nichts committed, nichts gepusht, Sources nicht angefasst, keine Anfrage an KI-Anbieter, kein iCloud, kein Signing.

## Werkzeug

- Primär Xcode-MCP-Bridge (`xcrun mcpbridge`, STDIO) über einen eigenen Proxy (`tools/proxy.py` ist die Kopie von `docs/qa-xcode-transport-and-license-bundle/REPAIRED_PROXY.py`, Socket unter /tmp/qpx). Aufrufe: XcodeOpenWorkspace, XcodeListWorkspaces, XcodeListRunDestinations, XcodeSwitchRunDestination, DeviceInteractionStartWorkspaceSession, DeviceInteractionInstallAndRun (baut mit Xcode), DeviceInteractionSynthesize, DeviceInteractionEndSession. XcodeBuildMCP wurde nicht gebraucht.
- Jeder Schritt: `<schritt>.json` (Bridge-Antwort), `<schritt>-hierarchyPath.txt`, `<schritt>-logsPath.txt`, `<schritt>-screenshotPath.png`. Treiber-Skripte in `tools/`.
- Run-Destination vorher `daisyiOS Actions QA 20261011`, nachher wiederhergestellt (`destination-restored.json`).
- Telefon: Scriptum Regular Workspace QA 20261011 (DD4D1567-..., 440x956). iPad: Scriptum iPad Window QA 20261012 (07414032-..., 834x1210).
- Die Telefon-Session wurde in der Mitte beendet (`end1.json`) und neu gestartet, um die Software-Tastatur zu bekommen (Simulator heruntergefahren, `start2.json` und `install3.json` sind die Antworten der Neustart-Aufrufe, Session-Name "... QA 3"). Ein erster Versuch mit dem alten Namen schlug fehl und ist nicht abgelegt.

## Wichtigste Einschränkung für A und B

Auf diesen Simulatoren erscheint **keine Software-Tastatur**, auch nicht nach Neustart des Simulators, `HardwareKeyboardLastSeen=0` und dem Menüpunkt "Tastatur einblenden" (Seitenaktionen, `showWritingKeyboard`). Die Hierarchie enthält nie ein `Keyboard`-Element (im früheren Lauf `qa-library-lifetime-20261012` war es noch da, Zeile `Keyboard, {{0,653},{440,245}}`). Die Simulator-App fehlt in diesem Xcode, ein Umschalten von "Connect Hardware Keyboard" war nicht möglich. Folgen:

- A kann nur über "Keyboard Focused" am TextView, sichtbaren Cursor im Screenshot und Tippen per kbd belegt werden, nicht über das Tastatur-Fenster.
- B wurde nur ohne Tastatur gemessen. Der alte Fehler (ScrollView 118.7pt, Editor 180pt) trat mit eingeblendeter Tastatur auf. Dieser Fall ist hier nicht reproduzierbar, also nicht widerlegt oder bestätigt.

## Ergebnis

| Check | Ergebnis |
|---|---|
| A Rotation: Fokus bleibt | PASS (Fokus, Cursor, Tippen); Tastatur-Fenster nicht prüfbar |
| A Gegenprobe: kein Fokus, keine Tastatur nach Rotation | PASS für "Titelfeld fokussiert" und "nie fokussiert"; echtes Tastatur-Schließen nicht prüfbar |
| B Landschaft: Editor nicht abgeschnitten | PASS ohne Tastatur; mit Tastatur INCONCLUSIVE |
| B Landschaft: Statusleiste weg, Schreibaktionen im Menü | PASS |
| B Hochformat unverändert | PASS |
| C Neue Markdown-Datei, Telefon (Hauptbibliothek) | PASS |
| C Neue Markdown-Datei, iPad Hauptfenster und zweites Bibliotheksfenster | PASS (siehe Vorbehalt Fensterzuordnung) |
| C Startbildschirm-Button "Neue Markdown-Datei" | FAIL für ".md": legt `Untitled.txt` an, Dokument öffnet sich nicht |

## A Rotationsfokus (Telefon)

Seite "Neue Seite" mit Block `# QA Kapitel\n\nCafé é 🦊 — **Fett**.\n`. Block per Tap fokussiert, Hierarchie `TextView ... Keyboard Focused`.

Lauf 1 (Dateien `focused-portrait`, `landscape*`, `portrait-return*`, `cycle2-*`), Lauf 3 nach Simulator-Neustart (`s3-*`):

| Schritt | Orientierung | TextView Keyboard Focused | Datei |
|---|---|---|---|
| Fokus gesetzt | Hochformat | ja | focused-portrait |
| nach Rotation | landscapeLeft | ja | s3-landscapeLeft, landscape-stable |
| getippt "L" | Querformat | ja, Text "LZ# QA Kapitel" | s3-type-landscape |
| zurück | Hochformat | ja | s3-portrait, portrait-return-stable |
| getippt "P" | Hochformat | ja, "LPZ#..." | s3-type-portrait |
| nach Rotation | landscapeRight | ja | s3-landscapeRight |
| zurück | Hochformat | ja | s3-portrait2 |

Gleiche Folge in Lauf 1 mit "Y" und "X" (cycle2-*). Also zwei volle Rotationspaare je Lauf ohne Fokusverlust, Tippen funktioniert nach jeder Rotation. Gegenüber `qa-library-lifetime-20261012/phone` (dort fielen "Keyboard Focused" und das Tastatur-Fenster in Querformat weg und kamen nicht zurück) ist das eine Verbesserung.

Cursor: In Lauf 1 stand der Cursor nach dem ersten Rotationspaar noch hinter dem getippten Z (`Z|# QA Kapitel`, Screenshot portrait-return-stable, das ist der Beleg fuer das erste Paar). Danach wurde vor dem zweiten Paar noch einmal in den Editor getippt (Titelfeld, dann Editor bei 248,296, Zwischenschritte tmp1/tmp2 nicht abgelegt); dieser Tap setzt den Cursor ans Ende der zweiten Zeile, deshalb landeten Y und X hinter `**Fett**.` (cycle2-landscape-right). Das kommt vom Tap, nicht von der Rotation. In Lauf 3 blieb der Cursor ueber zwei weitere Paare an der Stelle (`LP|Z`, s3-landscapeRight, s3-portrait2). In keiner beobachteten Rotation ging die Cursorposition verloren.

Gegenprobe: Ohne Software-Tastatur gibt es keine Möglichkeit, sie wegzuklappen (Tap auf die Wörterzähler-Zeile und Esc ändern den Fokus nicht, Tap auf den Titel wechselt nur den Fokus dorthin). Ersatz:
- Titelfeld fokussiert (Editor nicht): Rotation Quer und zurück, Titelfeld bleibt "Keyboard Focused", der Editor bleibt ein Button und holt sich den Fokus nicht (`inv-title-landscape`, `inv-title-portrait`).
- Seite neu geöffnet, nie fokussiert: Rotation Quer und zurück, nirgends "Keyboard Focused" (`inv-reopen`, `inv-nofocus-landscape`, `inv-nofocus-portrait`).
Das belegt, dass die Rotation keinen Fokus aus dem Nichts erzeugt. Der Titelfeld-Fall ist ein gueltiger Ersatz fuer das Schliessen der Tastatur: In beiden Faellen ist der Editor beim Verlassen des Fensters nicht First Responder und es liegt keine offene Fokusanfrage vor (`leavingWindow(wasFirstResponder: false)` in FocusRestoringTextView), also derselbe Codepfad. Der Fall "Tastatur bewusst geschlossen, dann rotieren" ist nicht getestet.

## B Landschaftslayout (Telefon, 956x440)

Gemessen aus den Hierarchiedateien (blockWritingView = ScrollView, Absatz content = TextView):

| Zustand | ScrollView | TextView | Datei |
|---|---|---|---|
| vorher, Querformat (alter Lauf, mit Tastatur) | 118.7pt hoch | 180.0pt | qa-library-lifetime-20261012/phone/landscape-stable |
| vorher, Hochformat (alter Lauf, mit Tastatur) | 269.7pt | 180.0pt | qa-library-lifetime-20261012/phone/focused-portrait |
| jetzt Querformat, Seite QA Kapitel | y 136.3 bis 359.0, 222.7pt | y 184.7 bis 359.0, 174.3pt | s3-landscapeLeft, s3-landscapeRight |
| jetzt Querformat, Seite mit 4 Zeilen und Überschrift in Zeile 4 | 222.7pt | 174.3pt | b-landscape-nomenu, b-landscape-focus |
| jetzt Querformat, nach 7 zusätzlichen Zeilen, Cursor am Ende | 222.7pt | 174.3pt (Cursor sichtbar, Text scrollt im Editor) | b-landscape-long |
| jetzt Hochformat | y 194.3 bis 777.0, 582.7pt | 534.3pt | focused-portrait, s3-portrait2 |

Der TextView endet überall genau an der Unterkante der ScrollView (359.0 bzw. 777.0) und ist nie höher als sie. Keine Abschneidung, auch bei langem Inhalt. Vorbehalt: ohne Tastatur ist der Viewport größer als im alten Fehlerlauf (222.7 statt 118.7). Der Wert 174.3 statt 180.0 zeigt, dass die Höhe jetzt angepasst wird, aber ob sie bei 118.7pt Viewport ebenfalls passt, ist hier nicht prüfbar. Dafür bräuchte es eine Software-Tastatur (Gerät oder Simulator mit abgeschalteter Hardware-Tastatur).

Compact-Höhe: Im Querformat zeigen die Screenshots (z.B. s3-landscapeLeft, b-landscape-nomenu) keine Statusleiste, keine untere Aktionsleiste (Lektorat/Überarbeiten/Zusammenfassen). Seitenaktionen-Menü (`b-landscape-menu`) enthält oben "Tastatur einblenden", dann den Abschnitt "Schreibaktionen" mit Lektorat, Überarbeiten, Zusammenfassen, danach Textänderung rückgängig/wiederholen, Geplante Aufgaben, Über iCloud teilen.

Hochformat: Statusleiste (Uhrzeit, WLAN, Akku) sichtbar, untere Leiste mit Lektorat (hitPoint 94.7,897.2), Überarbeiten, Zusammenfassen vorhanden (own-page, focused-portrait, portrait-return-stable, s3-portrait2). Unverändert gegenüber dem alten Lauf.

Hinweis zur Seite: Beim Zurück und erneuten Öffnen in Lauf 3 öffnete sich einmal die Seite 4F6927A9 (vier Zeilen, mehrere Abschnitte) statt der QA-Kapitel-Seite. Sie dient hier als zusätzlicher Mehrabschnitt-Fall. Die 43-Byte-Zeugenfolge `# QA Kapitel\n\nCafé é 🦊 — **Fett**.\n` ist auf Seite 2D6204A9 unverändert vorhanden (library-before.json).

## C Neue Markdown-Datei

Menüpunkt in "Dateien". Auf dem Telefon liegt er unter dem sichtbaren Menüausschnitt, Menü erst nach oben scrollen (`c-files-menu-scrolled`). Ein Tap auf die Hierarchie-Koordinate ohne Scrollen trifft die Liste darunter (`c-new-md-1` erste Versuche, nicht gezählt).

Telefon (Space "Mein Schreibraum", Hauptbibliothek im Hosting-Controller):
- Tap 1: `Documents/Unbenannt.md` (0 Byte) angelegt, Seite "Unbenannt" im Space importiert und geöffnet (`c-new-md-1`).
- Tap 2: `Documents/Unbenannt 2.md`, Seite "Unbenannt 2" geöffnet (`c-new-md-2`).
- Bibliothek: 6 Seiten und 5646 Byte vorher (`library-before.json`, SHA256 5bb67b73...), 8 Seiten und 6296 Byte nachher (`library-after.json`). Neue Seiten haben die Space-ID von Mein Schreibraum.
- "Neues Bibliotheksfenster" ist auf dem Telefon deaktiviert (erwartet, `c-files-menu`).

iPad (834x1210, Space "Mein Schreibraum"):
- Hauptfenster: `Unbenannt.md`, Seite "Unbenannt" geöffnet (`new-md-primary`).
- "Neues Bibliotheksfenster" (`new-window`, `new-window-stable`): zweites Fenster, im App-Umschalter drei Scriptum-Szenen (eine davon Altlast aus dem vorigen QA-Lauf, zeigt "Willkommen", `switcher`).
- Tap im vorderen Fenster: `Unbenannt 2.md`, Seite "Unbenannt 2" geöffnet, das andere Fenster zeigt in seiner Liste die neue Seite nicht (veralteter Zustand, `new-md-window2`).
- Tap im anderen Fenster (per Umschalter geholt): `Unbenannt 3.md`, Seite "Unbenannt 3" (`new-md-window-other`).
- Beide Fenster legen also Dateien im Documents-Wurzelverzeichnis an und importieren in den gewählten Space. Vorbehalt: Welches der beiden Fenster das "neue" ist, geht aus der Hierarchie nicht hervor. Vermutet wird, dass das vordere nach "Neues Bibliotheksfenster" das neue war. Beide Wege funktionieren, deshalb PASS.
- Bibliothek iPad: 2 Seiten und 1941 Byte vorher (SHA256 8c411b25...), 5 Seiten und 2917 Byte nachher.
- Auffällig: die Listen der beiden Fenster laufen auseinander (das zweite Fenster zeigte "Unbenannt 2" nicht, bis man dort selbst etwas tat). Kein Datenverlust, aber ein sichtbares Aktualisierungsproblem zwischen Fenstern (nicht Teil des Auftrags).

Startbildschirm (Telefon, Menü "More…" > "Neue Markdown-Datei", `c-launch-menu`, `c-launch-new-doc`, `-b`, `-c`):
- Der NewDocumentButton liegt in "More…" und ist in der Hierarchie auch als Button hinter dem Dateibrowser-Blatt aufgeführt.
- Ergebnis: `Documents/Untitled.txt` (0 Byte, englischer Name, Endung .txt) statt einer .md-Datei. Das Dokument öffnete sich in 18 Sekunden Beobachtung nicht, "More…" blieb deaktiviert, der Dateibrowser zeigt dauerhaft "LADEN ..." (Simulator-Dateianbieter, vermutlich unabhängig vom Fix).
- Vermutung zur Ursache (nicht geprüft): `MarkdownDocument.readableContentTypes` beginnt mit `.plainText`, die Dokumenterzeugung nimmt offenbar den ersten Typ. Wer die Endung .md will, sollte den Typ explizit als erstes führen oder in Info.plist deklarieren.

## Zustand nach dem Test

- Alle Test-Unbenannt-Dateien, `Untitled.txt` und die Test-Seiten wurden nur innerhalb der Simulator-Container entfernt bzw. die Bibliotheksdateien auf den Stand vorher zurückgesetzt (SHA256 Telefon 5bb67b73..., iPad 8c411b25...; nach Beenden der App geprüft). Der Telefon-Container wechselt bei jedem Xcode-Install seine UUID, die Daten wurden mitgenommen.
- Zwischendurch geänderter Inhalt auf dem Telefon (Tippen von Z, L, P, Y, X, Zeilenumbruch im Titel mit Rückgängig, sieben Zeilen auf Seite 4F6927A9) ist durch das Zurücksetzen auf `library-before.json` weg. Zwischenstände: `library-after-AB-edits.json`, `library-after-final.json`.
- Simulator-Einstellung `com.apple.keyboard.preferences HardwareKeyboardLastSeen` im Telefon: zeitweise auf 0 gesetzt (ohne Wirkung auf die Tastatur), zuletzt wieder auf 1 (Wert, den das Tippen per kbd ohnehin setzt). `com.apple.iphonesimulator ConnectHardwareKeyboard` wurde gesetzt und wieder gelöscht.
- Kontrolle der Wiederherstellung: `Documents/Skriptum/edits` ist auf beiden Containern leer (wie vorher), `library.json` hat auf beiden wieder die Vorher-SHA256, Documents enthaelt nur `Skriptum` (keine Unbenannt-Dateien, kein Untitled.txt). Container-Pfade nach dem letzten Install: Telefon .../Application/4E8E1D27-..., iPad .../Application/C1C1AD86-....
- Beide Simulatoren sind noch gebootet, die Apps beendet. Sessions beendet (`end.json`).
- SHA256 aller Beweisdateien: `SHA256.json`.

## Grenzen

- Keine Software-Tastatur (siehe oben), daher keine Aussage zum Verhalten mit Tastatur in Querformat und zum Schließen der Tastatur.
- Messungen über Hierarchie-Frames, nicht über Pixel.
- Ein Simulatorlauf pro Szenario, kein Gerätetest.
- C auf dem Telefon lief aus "Alle Seiten" ohne gewählten Space, also ueber den Fallback `spaces.first` (Mein Schreibraum). Ein explizit gewaehlter, nicht erster Space wurde nicht getestet; das iPad hat nur einen Space.
- Startbildschirm-Button: Verhalten im Simulator durch den hängenden Dateibrowser beeinflusst.
