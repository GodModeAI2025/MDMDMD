# Mac-Oberfläche: Bibliothek und Schreibfokus

15. Oktober 2026 · Ausgangsstand `2d06e2e` · native macOS-App

Die Bibliothek verwendet eine kompaktere Systemtypografie mit kleineren Vorschautexten und Datumsangaben. Der eingedrückte Scriptum-Schriftzug bleibt erhalten; das wiederholte Zitat am unteren Rand entfällt. Seitenliste und Navigation tragen weniger Papierfarbe. Das Manuskript erhält eine zurückhaltendere Papiermischung, feinere Kontur, feste Außenränder und eine zentrierte, auf 860 Punkte begrenzte Blattfläche. Gespeicherte Schreibschriften und Schriftgrößen bleiben erhalten. Der native Fenstertitel zeigt jetzt die ausgewählte Seite.

Die Werkzeugleiste gruppiert Ansichtswechsel, Textwerkzeuge/Lektorat und Ausgabe/Seiteninfo. Import, iCloud und Manuskriptzusammenstellung bleiben in der Menüleiste erreichbar. Bei knapper Breite greift der systemeigene Werkzeugleistenüberlauf; die Befehle bleiben zusätzlich in den Menüs verfügbar.

**Schreibfokus** blendet Bibliothek und Inspektor aus und ist über Werkzeugleiste sowie **Schreiben → Schreibfokus**, **⌥⌘F** erreichbar. Der Editor bleibt im selben Detail-Unterbaum. Vor dem Wechsel greift die bestehende Navigations-/Speicherprüfung. Das Öffnen der Seiteninfo macht der Bibliothek Platz; beim Schließen wird deren vorherige Sichtbarkeit wiederhergestellt. Die Bibliothek lässt sich als gemeinsamer Bereich verbreitern; ihre Navigation ist 200 Punkte breit. Die Seiteninfo erhält eine eigene Titelhierarchie.

## Durchgeführt

- Finaler nativer Mac-Build über den bereits freigegebenen Xcode-MCP-Workspace erfolgreich. Rohantwort und vollständiges Buildprotokoll liegen bei. Drei Warnungen betreffen unveränderte gemeinsame Quelldateien bzw. fehlende App-Intents-Metadaten; kein fehler- oder warnungsfreier Gesamtstand wird behauptet.
- Tatsächliche App mit `--scriptum-mac-qa-root` und der bestehenden isolierten Testbibliothek geöffnet. Helle und dunkle Schreibansicht, Bibliothek, Schreibfokus, Inspektor, Quelltext und Vorschau angesehen. Die Dateien mit `-final` im Namen stammen aus dem abschließenden Build; frühere Bilder bleiben als Zwischenstände erhalten.
- Eine zusätzliche Testseite erstellt und im Inspektor benannt. Markdown mit Überschriften, Liste, Zitat, Umlauten, japanischen Zeichen und mehrteiligem Emoji eingegeben. Nach App-Neustart und Größenänderung stimmt der gesamte aus der Accessibility-Ausgabe gelesene Quelltext exakt mit `witness.md` überein: 300 UTF-16-Codeeinheiten; die App zeigt 46 Wörter und 294 Zeichen.
- Fokus aus dem geöffneten Inspektor aktiviert: Bibliothek und Inspektor verschwinden, der Editor bleibt vorhanden. Rückkehr über denselben Kurzbefehl geprüft. Schreiben, Markdown und Vorschau gewechselt.
- Kritischen Ablauf **Inspektor öffnen → Window / Move & Resize / Left → Inspektor schließen** im finalen Build wiederholt. Kein weiterer Absturz in dieser Prüfung; die Bibliothek kehrt zurück. Native Spaltenänderungen können dabei die Fensterbreite vergrößern. Das ist keine Prüfung aller Fenster-/Monitoranordnungen.
- Native Rückgängig-Aktion nach dem Fokuswechsel über **Edit → Undo** wirksam geprüft. Die erste automatisierte ⌘Z-Beobachtung entfernte den Testzusatz nicht; diese Rohbeobachtung ist erhalten. Ein allgemeiner Nachweis sämtlicher Tastatur-/Undo-Szenarien wird daraus nicht abgeleitet.
- QA-Erscheinungsbild auf **System** zurückgestellt und Test-App beendet.

## Behobener Zwischenfehler

Zwei Zwischenstände stürzten beim Verkleinern bzw. Wiederherstellen der Bibliothek mit einer AppKit-Layout-Ausnahme ab. Der erste Aufbau verschachtelte einen weiteren nativen Split im Bibliotheksbereich und leitete Spaltensichtbarkeit aus der Fensterbreite ab. Der finale Aufbau verwendet einen gemeinsamen Bibliotheksbereich, explizite Inspektor-/Fokuswechsel, keine geometriegetriebene Zustandsänderung und unterdrückte Übergangsanimationen. Die genaue interne AppKit-Ursache ist nicht bewiesen; der zuvor fehlgeschlagene Ablauf besteht mit dem finalen Aufbau. `LAYOUT_DIAGNOSTIC.json` enthält begrenzte Diagnoseinformationen ohne Konto-/Hardwarekennungen; die ursprünglichen lokalen Absturzberichte bleiben erhalten.

## Abgrenzung

Dieser Stand ist gebaut und lokal visuell geprüft, **nicht erneut zu TestFlight hochgeladen**. Keine neue Prüfung persönlicher Bibliotheken, Live-iCloud, PCC, physischer Geräte oder vollständige Barrierefreiheitszertifizierung. Die iOS-/iPadOS-Quellen wurden in diesem Schritt nicht geändert. Beim automatischen Neustart nach einem Zwischenabsturz erschien die bereits bekannte Wiederherstellungsansicht des regulären Debug-Starts; dort wurden keine Inhalte geändert. Die eigentliche Abnahme erfolgte nach erneutem expliziten Start mit dem isolierten QA-Argument.

Grundlage für die Navigation: [Apple – NavigationSplitViewVisibility](https://developer.apple.com/documentation/swiftui/navigationsplitviewvisibility). Die drei visuell erkennbaren Bereiche sind als gemeinsam einklappbare Bibliothek und stabiles Editor-Detail angeordnet, damit der Mac-Schreibfokus die gesamte Bibliothek ausblenden kann.
