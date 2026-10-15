# Native Mac: Vorlagen, Verweise, Tabellen und Anlagen

15. Oktober 2026 · Ausgangsstand `7b78afb` · R15-Integration

Die Mac-App nutzt jetzt die vorhandenen gemeinsamen Werkzeuge für **Neue Seite aus Vorlage** (⌥⌘N), **Seitenverweis einfügen**, **Verweise und Rückverweise**, **Anhänge und Verwendung** sowie strukturierte Tabellenbearbeitung im Block-Kontextmenü. Die Bibliothek bietet zusätzlich ihre gesamte Anlagenübersicht. Ein fenstereigener Verlauf erlaubt Zurück/Vorwärts (⌘[ / ⌘]); Sprünge zu Überschriften sind an die aktuelle Seitenrevision und die UTF-16-Position gebunden. Interne `scriptum://page/…`-Ziele werden in der aktuellen Bibliothek aufgelöst; Dateiimport verarbeitet ausschließlich Datei-URLs.

Die neue Oberfläche verwendet vorhandene Speicher-, Revisions- und Tool-Mutationsprüfungen. Tabellenkorrekturen übernehmen stets die erwartete Seite, Block-ID, Revision und ursprünglichen Blockbytes; nach einem erfolgreichen Commit rückt die Tabellen-Sitzung auf die neue Revision vor. Allgemeine Tool-Rücknahme heißt auf dem Mac nun „Textänderung rückgängig“, da sie auch Tabellen und eingefügte Verweise umfasst.

## Tatsächlich geprüft

- 50 bestehende, ausgewählte Regressionstests bestanden: Vorlagen/Seitenarten, Links/Rückverweise, Navigationsgeschichte, Anlageninventur/-prüfung, Blockmutation und native Schreib-/Tool-Zulassung sowie Markdown-Tabellen. Das Protokoll enthält vier Swift-Testing-Läufe mit 16 + 1 + 21 + 12 Tests. Diese Tests prüfen unter anderem frische Vorlagenidentitäten, Medienerhalt, stale Revisionen, Schreibfehler, angrenzende Bytes und CRLF/Unicode. Sie ersetzen keine UI-Prüfung.
- Xcode MCP: finales natives Mac-Schema **SkriptumMac / My Mac** und iOS-Schema **Skriptum / Any iOS Device (arm64)** erfolgreich gebaut. Die Projektgenerierung wählte zunächst iOS; dessen erster erfolgreicher Build wird ausdrücklich nicht als Mac-Build geführt. Nach der UI-Abnahme wird ausschließlich die Mac-Buildnummer auf 12 erhöht; der abschließende Mac-Build prüft diese Metadaten. Die UI-Interaktionen verwenden identische Swift-Quellbytes noch mit Buildnummer 11.
- Tatsächliche App mit dem bestehenden `--scriptum-mac-qa-root` geöffnet. Eine 68-Byte-PNG-Datei über den nativen Dateidialog angehängt; Schreibziel 1200 und Schlagwort `kapitel` gesetzt, Seite als Vorlage markiert. Die neue Seite übernimmt den **gesamten Markdown-Quelltext bytegleich**, einschließlich Bildverweis. Schreibziel, Schlagwort und Seitenart „Schreiben“ sind in der neuen Seite sichtbar; die ursprüngliche Vorlage bleibt unverändert.
- In der neuen Seite eine Markdown-Tabelle ergänzt. Im strukturierten Dialog `1` zu `2 café` geändert, tatsächlich rückgängig gemacht und wiederholt. Der vollständige Seitenquelltext unterscheidet sich danach ausschließlich um diese erwartete Tabellenzelle. Ein unbestätigter weiterer Zellentext verhindert stilles Schließen; „Weiter bearbeiten“ erhält den Entwurf. Nach Rücksetzen dieses Entwurfs schließt „Fertig“ ohne weitere Textänderung.
- Einen Verweis auf **Am Schreibtisch** in der ursprünglichen Vorlage eingefügt. Die Übersicht zeigt den ausgehenden Link; dessen Auswahl öffnet die Zielseite und aktiviert die passende Überschrift. Die Zielseite zeigt den tatsächlichen Rückverweis auf **Kapitel aus Vorlage**.
- Zurück/Vorwärts über die Menüleiste mit laufender Texteingabe geprüft. Der Zusatz wurde am tatsächlichen Cursor zwischen Bild und Tabelle eingefügt. Die anfängliche Testannahme „⌘End bewegt den Cursor ans Dokumentende“ war falsch; macOS scrollte nur. Die korrigierte Auswertung belegt den exakten Zusatz bei unveränderten ursprünglichen Bytes. Der **gesamte Quelltext bleibt nach anschließendem App-Neustart exakt gleich**. Beide Annahmen stehen in `navigation-assertions.json`.
- Die Anlagenübersicht prüft das Bild als Datei, zeigt zwei aktive Seitenverweise und die vorhandenen historischen Verweise. Anlagendetails und der Seitenaufruf daraus funktionieren. Nach diesem Sprung bleibt die ursprüngliche Vorlage vollständig unverändert.
- Alle geöffneten Testblätter und die isolierte App am Ende geschlossen. Keine persönlichen Bibliotheksinhalte bearbeitet.

## Beim Prüfen korrigiert

Native Mac-Listen führten die ursprünglich schmalen Buttons als ganze Zeilen im Accessibility-Baum. Klicks in deren Mitte lösten die Aktionen nicht aus. Vorlagen, ausgehende Links, Überschriftenauswahl und aktive Anlagenverweise erhalten deshalb volle Zeilenbreite und passende Mac-Button-Darstellung. Die entsprechenden Abläufe wurden danach erfolgreich wiederholt.

Die gemeinsame iOS-Toolbar des Tabellenblatts zeigte auf dem Mac lediglich „Schließen“ und den ersten History-Button. Der Mac erhält eine eigene untere Aktionszeile mit **Schließen, Rückgängig, Wiederholen und Fertig**, einschließlich Schutz noch nicht übernommener Zellentexte. Die iOS-Toolbar bleibt bestehen.

## Grenzen und Release

Der direkte Lesezugriff auf die isolierte App-Containerdatei war durch macOS gesperrt, auch außerhalb der Shell-Sandbox. Er wurde nicht umgangen. Native UI-Quelltextvergleiche und die vorhandenen Domain-Tests liefern die beschriebenen Nachweise; eine zusätzliche direkte Auswertung sämtlicher gespeicherter Block-IDs wird nicht behauptet. Die hier gesicherten Texte sind ausschließlich eigene QA-Texte.

Dieser Schritt schließt die genannten Mac-Funktionslücken. Er beweist **nicht den vollständigen R01–R15-Umfang**. Live-iCloud/PCC, 20+ umfassend geprüfte native Grammatiksprachen, endgültige Native-Engine-Distribution und weitere dokumentierte Anforderungen bleiben separat offen. Die obligatorischen physischen Gerätetests bleiben gemäß Nutzerentscheidung entfernt. Die bisher bekannten Compilerwarnungen werden in den Buildprotokollen erhalten.

Die neue Mac-Version wird als Build 12 zur Auslieferung vorbereitet. Upload, serverseitige Verarbeitung und interne TestFlight-Zuordnung werden in einem eigenen Release-Beleg nachgewiesen; diese UI-Prüfung behauptet keinen TestFlight-Erfolg.
