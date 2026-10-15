# Native Mac: Fenster, Werkzeuge und Symbole

15. Oktober 2026. Anlass ist der vom Nutzer angehängte Screenshot um 07:42:30. `01-user-workspace.png` ist die unveränderte PNG-Lesekopie dieses HEIC-Bildes. Der Nutzer hat aktuell kein iPhone zur Hand; zusätzliche Geräteaktionen werden nicht vorausgesetzt.

## 1. Schreibfenster — Erstbefund

Die drei Bereiche Bibliothek, Seitenliste und Text sind erkennbar. Der Text bleibt im Mittelpunkt und die Bibliothek verwendet native Auswahlzeilen. Sichtbare Schwächen: Der zusätzliche Fokusknopf ähnelt dem benachbarten Seitenleistenknopf; die drei kleinen Ansichtssegmente erklären sich nur über Symbole; KI ist nur über Funkeln zu erkennen. Die gerahmte, beschattete Schreibkarte und der umlaufende dunkle Rand machen die ruhige Schreibfläche unnötig schwer. „Neuer Space“ wirkt trotz verfügbarer Aktion ausgegraut.

Das violette Zeichen links oben ist die macOS-Freigabeanzeige, kein Scriptum-Icon. Es wird weder nachgebaut noch entfernt. Das Bild allein beweist keine Probleme mit Tastaturfokus, VoiceOver oder Kontrastverhältnissen und zeigt keinen iCloud-Fehler.

## Umsetzung

- Native kompakte, vereinte Titelleiste. Der doppeldeutige Fokusknopf entfällt; Schreiben → Schreibfokus und ⌥⌘F bleiben verfügbar. Der native Seitenleistenschalter bleibt erhalten.
- Ein beschriftetes Ansichtsmenü mit drei benannten, exklusiven Ansichtsoptionen ersetzt den kleinen Symbol-Segmentwähler. Lektorat bleibt direkt erreichbar; das KI-Menü erhält ein sichtbares „KI“. Export und Inspektor verwenden vertraute SF Symbols mit Hilfetexten. Der Inspektorschalter zeigt seinen Zustand.
- Die Papierfläche füllt den Textbereich ohne zusätzlichen Kartenrahmen oder Schatten. Der Editor begrenzt weiterhin die Textbreite. Subtile, an das Erscheinungsbild angepasste Papierfarbe bleibt erhalten; bei erhöhtem Kontrast entfällt die Textur.
- Bibliothekssymbole nutzen einheitliche monochrome Darstellung und ausgerichtete Bildspalten. „Neuer Space“ erhält wieder die normale Schriftfarbe einer verfügbaren Aktion.
- Die tatsächliche Prüfung fand zusätzlich einen Ablaufdefekt: Beim Öffnen des Lektoratdialogs startete `.task` automatisch eine Anbieteranfrage, während die Oberfläche noch „Starten“ anbot. Dieser automatische Aufruf entfällt. Kontext und Anbieter sind vor der ausdrücklich gestarteten Anfrage sichtbar. Der vorhandene Startbutton bleibt der Auslöser; Übernahme und Rückgängig-Funktionen bleiben erhalten. Im fehlgeschlagenen Erstversuch wurde ausschließlich der eigene synthetische QA-Text verarbeitet, kein persönliches Manuskript.

Diese Ausgestaltung ist eine Designentscheidung für Scriptum. Grundlage sind die Apple-HIG-Abschnitte [Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars), [Icons](https://developer.apple.com/design/human-interface-guidelines/icons), [Windows](https://developer.apple.com/design/human-interface-guidelines/windows) und [Materials](https://developer.apple.com/design/human-interface-guidelines/materials). Operative Klauseln aus den geladenen Apple-HIG-Referenzen: „Keep all icons consistent in size, detail, stroke thickness/weight, and perspective.“ und „Avoid custom window frames or controls, and don't try to replicate the system appearance.“

## Prüfung und Verteilungsgrenze

Der endgültige native Mac-Build und die iOS-arm64-Kompilierung sind über Xcode MCP erfolgreich. Der endgültige gemeinsame Dialog-Code kompiliert zusätzlich als iOS Release mit `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES` und `SWIFT_SUPPRESS_WARNINGS=NO`. Drei bekannte Sendable-Migrationswarnungen der gepinnten Markdown-Abhängigkeit und die App-Intents-Metadatenwarnung sind im ersten vollständigen Build sichtbar; die zwei Fokus-Closure-Konvertierungswarnungen aus dem ausgelieferten iOS-Archiv sind durch die explizit MainActor/Sendable typisierte verzögerte Aktion beseitigt. Inkrementelle Builds enthalten weiterhin den Metadatenhinweis. Keine pauschale Warnungsfreiheit wird behauptet. Sieben bestehende Fokusregressionen und zwei gezielte iCloud-Diagnosetests bestehen. `CHECKS.json` und die MCP-Belege trennen diese Prüfungen.

Die tatsächliche Laufzeitprüfung und akzeptierten Screenshots stehen in `REPORT-QA.md`. Sie belegt helle/dunkle Fenster, minimale Inhaltsgröße, Ansichtwechsel, Inspektor und Schreibfokus. Der dort erhaltene fehlgeschlagene Lektorat-Erstversuch wird durch `REPORT-RETEST.md` ergänzt: Öffnen ohne Anfrage, dann genau eine ausdrücklich gestartete lokale Fake-Antwort, ohne Übernahme. `REPORT-CONTRAST.md` dokumentiert die abschließende sichtbare Schließen-Aktion nach der nativen Tint-/Buttonkorrektur. Die Antwort des lokalen Testanbieters ist kein weiterer realer PCC-Nachweis. Der Originaltext bleibt in allen Durchläufen exakt erhalten. Dies ist kein pauschales Barrierefreiheitszertifikat; die native Popover-Ebene fehlt in den Appfensteraufnahmen, deren AX und tatsächlicher Moduswechsel sind separat erhalten.

Die Änderungen dieses Ordners sind zunächst lokal. Die bereits eingereichten iOS 1.0.1 (10) und Mac 1.0.1 (13) enthalten diese nachträgliche Designkorrektur nicht. Aktueller Verteilungsnachweis: `../releases/ios10-mac13/`. Keine zusätzliche physische Gerätepflicht, kein neuer Synchronisationsdienst und keine Änderung an Apple-Verträgen.
