# Scriptum: Startbutton öffnet die Bibliothek nicht

15. Oktober 2026. Eigentümermeldung: Nach Appstart zeigt „Spaces und Bibliothek öffnen“ den Klick, öffnet aber keine Bibliothek. Korrekturkandidat iOS 1.0.1 (15); zuvor intern ausgeliefert: iOS 14.

## Befund und Korrektur

Commit c6a63f8 verschob den UIKit-Präsentationsanker vom Hintergrund der DocumentGroupLaunchScene an den Hintergrund des Aktionsbuttons. Der Dokumentbrowser extrahiert diese Aktionen; der Hintergrund des Buttons ist deshalb kein verlässlicher montierter Präsentationsanker. Frühere tatsächliche Navigationsbelege mit dem Szenenhintergrund stehen in [der vorherigen Prüfung](../qa-icloud-entry-20261015/REPORT.md). Die aktuelle Ursache ist durch Quelltext und Eigentümermeldung begründet, wurde aber noch nicht in der laufenden neuen App reproduziert.

Der Anker befindet sich wieder im tatsächlichen Szenenhintergrund. Button und Hintergrund teilen ausschließlich eine leichte Öffnungsanforderung über SceneStorage mit demselben Schlüssel. Apples über Xcode-MCP gelesene Dokumentation bestätigt geteilte Werte innerhalb derselben Szene und getrennte Werte zwischen Szenen. Der Presenter wird ausschließlich aus dem Fenster des montierten Ankers ermittelt. Es gibt keine globale Fenstersuche.

Die Anforderung wird erst nach bestätigter Präsentation verbraucht. Neuere Klicks überleben ältere Callbacks. Während einer Präsentation oder Schließanimation wird das Ende des Übergangs abgewartet; falls UIKit keinen Transition-Coordinator liefert oder die Registrierung ablehnt, gibt es begrenzte Wiederholungen. Ein abgebrochener älterer Retry darf den Handle seines Nachfolgers nicht überschreiben. Ein schließender Bibliotheks-Host erfüllt keine neue Öffnungsanforderung.

Der sichtbare UIKit-Host hält seinen Coordinator bis zum Schließen; die Rückreferenz ist schwach. Die SceneStorage-Persistenz kann eine noch ausstehende Öffnungsanforderung nach Prozessende wiederherstellen. Sie enthält ausschließlich einen zufälligen Request-Token, keine Dokumentdaten.

## Nachweise

- 15 ausgeführte Tests in drei Swift-Package-Suites bestanden: sechs neue Öffnungszustandsprüfungen sowie bestehende Fenster- und Navigationspersistenzprüfungen. Der Filter enthielt zusätzlich NativeLibraryPickerTests; diese UIKit-Tests wurden auf macOS nicht ausgeführt und werden nicht mitgezählt.
- Xcode-MCP BuildProject: erfolgreicher iOS-SDK-Build nach der letzten funktionalen Änderung; 6,257 Sekunden, keine Fehler. Danach wurde ausschließlich die iOS-Buildnummer auf 15 gesetzt und über GetTargetBuildSettings bestätigt.
- Unabhängige Quelltextprüfung: keine weiteren konkreten Befunde nach Ergänzung der Cancellation-Abfrage.
- git diff --check bestanden.
- Apple-MCP-Quellen und vollständiges fokussiertes Testprotokoll liegen in diesem Verzeichnis. Die Quellhashes stehen in STATE.json.

## Noch offen

Der tatsächliche Ablauf Appstart → sichtbarer Button → Alle Seiten wurde für diesen Kandidaten noch nicht ausgeführt. Eine eng begrenzte Simulator-Ausnahme wurde angefragt, weil eine frühere automatische Freigabeprüfung Simulatorstarts unter der Anweisung „Gerätetests raus“ abgelehnt hatte. Die Anfrage bleibt offen. Die lokalen Zustandstests beweisen weder UIKit-Montage noch Szene-Umgebung oder erfolgreiche Bildschirmpräsentation.

Kein Upload und keine interne Auslieferung dieses Kandidaten sind hier bestätigt. Der iCloud-Abgleich auf dem betroffenen iPhone ist ebenfalls nicht nachgewiesen. Die bestehenden Store-Einreichungen werden nicht zurückgezogen oder ersetzt.
