# Startbutton: tatsächlich reproduzierter Fehler

Am 15.10.2026 im vom Nutzer ausdrücklich genehmigten iPhone-Simulator-Ablauf geprüft. iPhone 18 Pro, iOS 27.0 (24A434), normale Scriptum-App ohne QA-Startargumente. Der Quellstand enthält die uncommittierten Import- und Freigabeänderungen; die für den Startweg relevanten Quell-Hashes stehen in BASELINE.json.

Die sichtbare Schaltfläche „Spaces und Bibliothek öffnen“ wurde am ausgelesenen Accessibility-HitPoint (201, 278.3) zweimal angetippt. Nach beiden Betätigungen blieb die App unverändert auf dem Startbildschirm. Prozess 38508 blieb aktiv; kein Absturz.

Das Laufzeitprotokoll meldet für SceneStorage eine Installation außerhalb des SwiftUI-App-Lebenszyklus, ein dauerhaftes Zurückgeben des Standardwertes und ein konstantes Binding ohne Aktualisierung. Diese Meldungen passen zum im Quellcode verwendeten SceneStorage-Transport zwischen extrahierter Aktion und Hintergrundansicht.

Vorher-/Nachherbilder, Hierarchien, vollständige App-Protokolle und Xcode-MCP-Receipts sind erhalten. Die Hierarchie enthält zusätzlich einen zweiten, nicht sichtbaren Button bei y=437; angetippt wurde ausschließlich der tatsächlich sichtbare Button bei y=278.3.

Diese Reproduktion ist kein Nachweis für iOS 27.2 oder CloudKit-Freigaben; es wurden keine Account-, Cloud- oder Dokumentänderungen durchgeführt. Ein Korrektur-Nachweis wird nach der Änderung separat ergänzt.

## Korrektur: tatsächlicher positiver Ablauf

Kandidat 1 (State und fullScreenCover direkt an der extrahierten Aktion) blieb ebenfalls zweimal wirkungslos; CANDIDATE1.json und candidate1-Belege sind erhalten.

Kandidat 2 legt den Zustand im App-Besitzer ab und übergibt der Aktion ein explizites Binding. Der Presenter hängt am tatsächlich montierten Szenenhintergrund. Dieser Kandidat wurde normal gebaut und gestartet. Der echte sichtbare Button führte bei einem Tap zu „Alle Seiten“, ohne automatisch einen Text zu öffnen. „Dateien → Zum Dateibrowser“ schloss die Bibliothek; erneutes Antippen des Startbuttons öffnete „Alle Seiten“ wieder. Keine SceneStorage-Diagnosen im Kandidat-2-Log. Belege candidate2-* und CANDIDATE2.json.

## iCloud-Freigabedialog im Simulator

Auf weitere ausdrückliche Nutzeranweisung wurde an der synthetischen Willkommen-Seite „Mehr → Dokument-Werkzeuge → Über iCloud teilen“ geöffnet. Der Appdialog erschien lesbar ohne überlappende Texte. „Freigabe öffnen“ meldete anschließend fehlenden iCloud-Kontozugriff. Kein Login, keine Teilnehmerwahl, keine Einladung, keine Textänderung. Damit ist der Appdialog und seine Kontozugriff-Fehlerdarstellung verifiziert; der native Apple-Freigabedialog und ein tatsächlicher CloudKit-Share sind hier ausdrücklich NICHT nachgewiesen.

Die App zeigt im lokalen Kandidaten weiterhin Build 17; dies ist keine neue TestFlight-Lieferung. Getestetes Simulator-OS 27.0, keine Aussage zu physischem iOS 27.2.

## Bereinigung nach der Laufzeitprüfung

Nach dem positiven Kandidat-2-Ablauf wurden ausschließlich die ungenutzten UIKit-Presenter/Anchor/Retry-Komponenten, der alte SceneStorage-Request-Gate und dessen Tests entfernt. Fensteraktionen verwenden wieder direkt die SwiftUI-Umgebung der tatsächlichen Bibliotheksansicht. Das Laufzeitprotokoll bindet den vor dieser Bereinigung geprüften Kandidaten; der finale native Mac-SDK-Build und die vollständige lokale Suite prüfen den bereinigten Quellstand separat. Es wird kein nachträglicher Simulator-Nachweis für diese reine Bereinigung behauptet.
