# Mac: Papierfläche und Bibliothek · 15. Oktober 2026

Die weitere Überarbeitung betrifft die native Mac-Oberfläche. Der Editor erhält eine vom Arbeitsuntergrund abgesetzte Papierfläche mit zurückhaltender Kontur, kleinem Radius und weichem Schatten. Der Rand wird in schmalen Bereichen kleiner; dabei bleibt derselbe Editor-Unterbaum erhalten. Bei erhöhtem Kontrast entfällt der Schatten und die Kontur wird deutlicher. Die bestehende Papiertextur berücksichtigt bereits erhöhten Kontrast.

Die Bibliothek und die Seitenliste tragen weniger Papierfarbe. Ein Trenner grenzt Suche und Seitenauswahl voneinander ab. Seitentitel haben eine Serifenschrift und können zweizeilig wachsen; Vorschautext und Datum berücksichtigen die Hervorhebung der nativen Auswahl. Die Wort-/Zeichenzählung steht direkt auf dem Blatt unter einer feinen Linie. Auch die Willkommensansicht verwendet die neue Fläche und einen begrenzten, linksbündigen Textbereich.

## Tatsächlich geprüft

- Native Mac-Builds über den vorhandenen, freigegebenen Xcode-MCP-Workspace erfolgreich; Rohantwort und vollständiges letztes Buildprotokoll liegen bei.
- Laufende App mit dem bestehenden Debug-Argument `--scriptum-mac-qa-root` und einer eigenen Testbibliothek gestartet. Hell, Dunkel, Willkommensansicht, Schreiben, Markdown und Vorschau angesehen und als echte Screenshots gesichert.
- Seitentitel im Info-Inspektor geändert. Mit macOS **Window → Move & Resize → Left** auf die Mindestbreite von etwa 900 Punkten verkleinert. Inspektor, Textumbruch, Statuszeile und Werkzeugleiste bleiben sichtbar; die bestehende automatische Ausblendung der Bibliothek greift.
- Eigenen Markdown-Testtext mit Überschriften, Zitat, Liste, Fettdruck, Umlauten, japanischen Zeichen und mehrteiligem Emoji eingegeben. Sein vollständiger Quelltext ist nach Ansichtswechsel/Größenänderung und nach Beenden/erneutem Start exakt in der tatsächlichen Accessibility-Ausgabe des Quelltexteditors enthalten. Die App zeigt 75 Wörter und 487 Zeichen. Die beiden Ausgaben sind erhalten.
- Die QA-Darstellung auf **System** zurückgestellt und die Test-App geschlossen.

## Geltungsbereich

Dieses UI-Update wurde nicht erneut zu TestFlight hochgeladen. Die Release-Belege für Mac Build 11 bleiben unverändert. Die parallel vorhandenen, uncommitteten Lektorats-/Forschungsänderungen wurden beim lokalen Build mitkompiliert, gehören aber nicht zum Mac-UI-Commit. Es wurde keine neue native Grammatikbibliothek in das reguläre Projekt aufgenommen.

Die Prüfung erfolgte in der isolierten Debug-Bibliothek. Beim ersten Öffnen des regulären Debug-Starts erschien dessen vorhandener Hinweis auf einen nicht mehr vorhandenen Bibliothekspfad; dort wurden keine Inhalte geändert. Die visuellen und Persistenzbelege stammen ausschließlich aus dem anschließenden ausdrücklich isolierten Start. Keine neue Prüfung persönlicher Bibliotheken, mehrerer Geräte, Live-iCloud, PCC oder vollständige Barrierefreiheitszertifizierung wird behauptet.

`light-final.png` und `dark-final.png` zeigen die überarbeitete Schreibansicht. `light-inspector.png` und `narrow-inspector.png` halten die Inspektorprüfung fest. `preview.png` zeigt die bestehende Exportvorschau mit ihrem eigenen Stil; `welcome.png` den neuen Leerzustand. Frühere Zwischenansichten bleiben erhalten.
