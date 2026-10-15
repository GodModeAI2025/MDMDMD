# Neuer iCloud-Fehler: Untersuchung und begrenzte Korrektur

15. Oktober 2026 · Grundlage `0292d27`; die zuvor begonnene PCC-Arbeit ist separat als `6a77dfb` erhalten.

## Offene Meldung

Der Nutzer meldet neues TestFlight-Feedback und weiterhin nicht funktionierendes iCloud. App Store Connect zeigt aktuell die Anmeldeseite. Die neuen Rückmeldungen, deren Screenshot, Buildnummer und konkrete Fehlermeldung wurden deshalb noch nicht gelesen. Eine bereits gestellte Frage nach genauer Meldung und installiertem Build ist offen. Die Anmeldung am iCloud-Gerätekonto wird nicht als Fehlerursache unterstellt. Der Befund aus `qa-testflight-feedback-20261014` betrifft ältere Berichte und ist keine Auswertung der neuen Meldung.

Die Xcode-MCP-Werkzeugliste enthält Build-/Dokumentations-/Crash-/Performance-Werkzeuge, jedoch kein TestFlight-Screenshot-Feedback-Werkzeug. Es wurden keine Sitzungsdaten oder Zugangstoken ausgelesen. Der vorhandene signierte iOS-Build-9-Nachweis bestätigt die CloudKit-Produktionsumgebung und den aktivierten Runtime-Schalter; er ist kein Beleg für funktionierenden Sync auf dem betroffenen iPhone.

## Tatsächlicher CloudKit-Nachweis

Der vorhandene Schutz mit Suchrechten auf Elternverzeichnissen ist bereits implementiert. Dafür wurde kein zweiter vermeintlicher Fix behauptet. Stattdessen wurde der reale Transport geprüft:

1. Eine eigene native Mac-QA-Bibliothek mit eigenem importierten UUID-Bereich wurde angelegt. Aktivierung und Übertragung in Development gelangen.
2. Das bestehende Apple-Entwicklerprofil erlaubt Development und Production. Eine lokale Debug-Kopie wurde mit derselben vorhandenen Entwickleridentität und dem ausdrücklich gesetzten Production-Entitlement signiert und geprüft. App-ID, Container und Sandbox blieben bestehen. Es handelt sich nicht um einen Store-/TestFlight-Build.
3. Die ausschließlich synthetische Seite und ihr Space wurden in die eigene Zone `Scriptum-c948690d-5b84-4304-9cfc-bb825146360e` der privaten Produktionsdatenbank übertragen. Anschließend zeigte die Sitzung keine wartenden Änderungen und einen Synchronisationszeitpunkt.
4. Ein unabhängiger lokaler Speicher mit derselben QA-Bibliotheks-ID startete nachweislich mit **0 Seiten**. Nach Aktivierung wurden Space und Seite aus der Produktionsdatenbank empfangen. Die Anzeige wurde **1 Seite**. Der vollständige native Markdown-Wert stimmt mit dem bekannten Fixture bytegleich überein: **149 Zeichen einschließlich abschließender Zeilenschaltung**.

Die erste AX-Extraktion verwendete einen zu breiten Whitespace-Trenner und verlor den letzten Zeilenumbruch. Der erhaltene vollständige AX-Snapshot und die korrigierte Extraktion mit ausschließlich horizontaler Einrückung belegen den exakten Wert. Es wurde kein Text durch diesen Auswertungsfehler geändert.

Während der Bedienung zweier gleichnamiger App-Kopien adressierte die UI-Automation eine weitere Instanz am normalen Buildpfad; einige Menüaktionen blieben wirkungslos. Beide von der Prüfung gestarteten Prozesse wurden beendet. Der Empfang wurde anschließend mit genau einer Instanz am eindeutigen ursprünglichen App-Pfad und erneut ausgelesener Production-Signatur erfolgreich wiederholt. Es wurden dabei keine persönlichen Texte angesehen oder bearbeitet. Dieses Automationsproblem wird nicht dem gemeldeten iPhone-Syncfehler gleichgesetzt. Nach der Prüfung hat Xcode die normale Debug-Signatur wieder aufgebaut; sämtliche Prüfinstanzen wurden beendet.

Die synthetischen CloudKit-Testbereiche bleiben zur Nachprüfbarkeit erhalten. Keine bestehende Benutzerzone, kein Schema und keine Freigabeberechtigung wurde zurückgesetzt. Dieser Nachweis betrifft eine einzelne native Mac-App mit unabhängigen lokalen Speichern. Er belegt weder das betroffene iPhone noch iOS/macOS-Übertragung, zwei Geräte, ein installiertes TestFlight-Paket, CKShare-Einladungen oder Zusammenarbeit.

## Nachgewiesene und korrigierte Fehlerdiagnose

Fehler in `CKSyncEngine`-Rückrufen und bei der Batch-Vorbereitung wurden bisher in `storageFailed()` ohne Ursache verworfen. Anschließende Abbruch-/Stopfehler konnten den tatsächlichen Anlass verdecken. Nun bleibt die verarbeitete Ursache als bereinigte Diagnose erhalten und wird nach CloudKit-Abbruch oder Generationswechsel weitergereicht. Ausstehende Dokumente werden nicht quittiert, entfernt oder zurückgesetzt.

Ein neuer Regressionstest ist mit vier Fällen zunächst fehlgeschlagen. Nach der Korrektur bleiben Ursache und dokumentbezogene Warteschlange erhalten. Die Diagnose unterscheidet außerdem Kapazitätsgrenzen, ungültige Änderungen, lokale Projektionsfehler, Konto-/Netzwerk-/CloudKit-Fehler. Sie gibt keine unkontrollierten `localizedDescription`-/`userInfo`-Inhalte aus. Die Zwischenprüfung hatte zwei falsche neue Testerwartungen (verwechselter CloudKit-Zahlenwert und Gleichheit von Sammel- und Einzelcode); beide sind im endgültigen Test auf die tatsächlichen definierten Codes und gleiche sichere Erläuterung präzisiert. Rote Protokolle bleiben erhalten.

Unter **iCloud → Diagnose** kann ein Nutzer nun App-Version, Build, Betriebssystem, Sitzungsstatus, zuletzt erfasste Zähler und begrenzten Fehlercode lesen bzw. über das native Teilen-Menü selbst weitergeben. Das erzeugt keine automatische Übermittlung, keine Kontokennung und keine Manuskriptprotokollierung. Die Diagnose gilt für die laufende Sitzung; es wird kein neuer dauerhafter Telemetriedienst eingerichtet. Auf dem Mac ersetzt eine gruppierte, scrollbare Form das zuvor mittig begrenzte Formular. Die tatsächliche Oberfläche zeigt Diagnose und Teilen-Button. Nach dieser Darstellung wurden lediglich Meldungstexte/Zählerbeschriftung präzisiert; finale Kompilierbelege sind separat erhalten.

## Verifikation und Grenze

- Betroffene Domain-Suite: **47 + 75 = 122 Tests ausgeführt und bestanden**, keine übersprungen.
- Nativer Mac- und generischer iOS-arm64-Build über Xcode MCP bestehen. Der strenge Mac-Release mit Swift-Warnungen als Fehler besteht ebenfalls; vorhandene Abhängigkeits-/App-Intents-Diagnosen bleiben im Rohlog. Kein allgemeiner Null-Warnungen-Nachweis.
- Native Mac-Production-Schreib-/Empfangsprüfung und exakter Markdown-Vergleich wie oben; tatsächliche Diagnoseoberfläche mit Bildschirmfoto/AX belegt.

**Die neue Nutzerfehlermeldung ist damit noch nicht behoben oder erklärt.** Die Fehlerweitergabe ist korrigiert; erfolgreicher kleiner Mac-Sync ersetzt ihre Reproduktion nicht. Kein neuer Release wurde hochgeladen, kein Review ersetzt und keine Veröffentlichung behauptet. Verpflichtende physische Geräte- oder Mehrgerätetests werden nicht wieder als Release-Gate eingeführt.

## Nächster Schritt zur Auslieferung

Nach der bestehenden Apple-Anmeldung: alle neuen Feedbackeinträge samt Build/OS/Screenshots sichern; die konkrete Fehlermeldung und ihren Schritt mit dem ausgelieferten iOS-Code abgleichen; diesen Fehler mit geeigneten eigenen Daten reproduzieren, beheben und durch Regression sichern. Danach neue iOS-/Mac-Archive signieren und prüfen, TestFlight-Verarbeitung sowie interne Verfügbarkeit tatsächlich bestätigen und erst den passenden verifizierten Build zur App-Store-Prüfung einsetzen. Upload, Verarbeitung, interne Freigabe, Review und Veröffentlichung bleiben getrennte Status.
