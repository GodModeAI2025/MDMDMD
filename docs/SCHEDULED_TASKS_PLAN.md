# R09 — Persistente Aufgaben auf dem Gerät

Dieser Plan ersetzt die frühere Server-Ausführung aufgrund der verbindlichen Nutzerentscheidung: Synchronisation und Zusammenarbeit über iCloud, kein betriebener Workspace-/Ausführungsdienst. Frühere Server-Pläne und Prüfberichte sind historische Entwicklungsnachweise.

## Produktverhalten

Eine Aufgabe gehört zu einer ausdrücklich gewählten lokalen Bibliothek, einem Space und einer Seite. Die Person wählt lesbare Blöcke oder die ganze Seite, KI-Zugang/Modell, einmaligen oder wiederkehrenden Termin, Ausführungsende/Anzahl und Budgets. Zusammenfassungen bleiben eigenständige Ergebnisse; Änderungen sind prüfbare Vorschläge mit Quellrevision und dürfen erst nach ausdrücklicher Übernahme den Text verändern.

Ausführung erfolgt lokal bei aktiver App und zusätzlich mit den tatsächlich verfügbaren iOS-Hintergrundmöglichkeiten. Das Betriebssystem garantiert keinen minutengenauen Start bei geschlossener App. Versäumte Termine werden dokumentiert; Wiederanlauf verarbeitet höchstens die jüngste fällige Instanz pro Aufgabe statt unkontrollierter KI-Aufrufserien. Eine weitere Geräteinstanz führt eine lokale Aufgabe nicht automatisch aus. Geräteübergreifende Aufgaben benötigen später ein über iCloud koordiniertes Ausführungsrecht; kopierte Konfiguration allein genügt nicht.

## Autorität und Kontext

`LocalScheduleAuthority` bindet sich an die aktuelle vollständig eigene `WritingLibrary` und deren tatsächlichen stabilen Locator. Owner-ID ist eine lokale Geräte-/Installationsidentität, kein angenommener Apple- oder Server-Login. Anbieterbindung und freigegebene Kontobudgets kommen aus nativen Einstellungen, nicht aus Aufgabentext oder Dokumentmetadaten.

Vor jeder Ausführung wird die aktuelle Bibliothek erneut geprüft: Owner/Bibliothek/Space/Seite/Anbieterbindung müssen passen; offene Edit-Journale, entfernte Blöcke und Papierkorb auf Seite oder Vorfahren sperren Aufnahme. Nur explizit lesbare Blöcke gehen in den Anbieter-Kontext. Zusammenfassung ohne Blockauswahl bezieht sich auf die ganze gewählte Seite. Die vollständige Seite bleibt nur für Revisions-/Digest-Prüfung im flüchtigen Capture; dieser ist nicht Codable und wird nicht als Aufgabenzustand gespeichert.

Dieser lokale Nachweis schafft kein CloudKit-Teilnehmerrecht. Geteilte Dokumente benötigen separat aktuelle Mitgliedschaft, Rolle und geerbte Rechte. Der aktuelle Adapter akzeptiert ausschließlich `WritingLibrary`, nicht `ICloudSharedSession`.

## Persistenz und Laufzustände

Der bestehende `SkriptumScheduling`-Kern ist im Haupt-Package und iOS-Ziel verknüpft. Er speichert Termine, Generationen, Läufe, Leases, Budgetreservierungen und Ergebnisse mit atomarer begrenzter No-Follow-Dateipersistenz. Quellen können bis zum vorhandenen 8-MiB-Dokumentlimit unverändert gehasht werden; Ausgabe-/Datei-/Tokenlimits bleiben eigene Schranken.

Aktivierung muss Dokumentautorität und Anbieter-Verfügbarkeit, Modellbindung, Ausführungsmodus und überprüfbare Preis-/Budgetgrenzen erfüllen. Ein gültiger `ExecutionGrant` belegt nur die Aufnahmeentscheidung des Kerns. Die native Oberfläche darf daraus keine tatsächlich laufende KI-Ausführung ableiten.

Ablauf: fällig → persistenter Lauf → Claim/Lease → frische Autorisierung → Budgetreservierung → vor Versand persistierter Request-Bezug → tatsächlicher Anbieteraufruf → Ergebnis/Quellnachweis → Abschluss/Abrechnung. Unbekannter Ausgang nach Versand hält Reservierungen und wird nicht blind erneut berechnet/ausgeführt. Pause, Abbruch und Änderungen prüfen bzw. erhöhen Generationen und sperren ältere Läufe.

## Anbieter und Hintergrund

Interaktiver Zugang und Hintergrund-Eignung sind getrennte Fähigkeiten. Adapter müssen den gewählten Zugriff tatsächlich prüfen. PCC/ChatGPT-Berechtigung, Region, Modell oder fehlende Credentials dürfen keinen stillen Anbieterwechsel auslösen. Fehlende oder veraltete verlässliche Preisobergrenzen sperren geldbegrenzte automatische API-Ausführung. Schätzungen sind keine bestätigte Rechnung. Tokens, Antwortgröße und Request-Anzahl bleiben unabhängig begrenzt.

Vor neuen iOS-27-App-Intent-/Background-APIs ist die entsprechende exportierte Apple-Anleitung zu konsultieren und das verfügbare SDK zu prüfen. Hintergrundarbeit benötigt sichere Abbruch-/Wiederaufnahmewege. Ergebnisbenachrichtigung setzt Opt-in voraus und ist keine Ausführungsautorität.

## Noch erforderliche Integration

1. Gerätegebundene persistente Task-/Anbieter-/Budgetkonfiguration und native Aufgabenverwaltung mit realen Statuswerten.
2. Dispatcher mit frischem Capture, echten Adaptern, überprüfbaren Quotes, Budget-/Generation-/Lease-Prüfung, Streaming-Abbruch und dauerhafter Ungewissheit nach Versand.
3. Best-Effort-Hintergrundregistrierung und Vordergrund-Catch-up; kein zweiter betriebener Dienst.
4. Ergebnisliste und Vorschlagsvergleich; Übernahmereceipt innerhalb der ursprünglichen Bibliothekstransaktion, ohne aktive Edit-Journale zu umgehen.
5. Native Lauf-/Neustart-/Fehler-/Anbieter-/Budget-/Accessibility-Prüfung und signierter TestFlight-Nachweis.

## Aktueller Nachweis

Fünf neue native Modelltests prüfen exakten gewählten Kontext/Digest, fremde Scope-/Anbieter-/Budget-/Block-Abweisung, offene/trashed Hierarchie, Aktivierung/Neustart/Fälligkeit ohne Server und unveränderten Text über 3 MiB. Dies belegt lokale Eigentumsaufnahme und Queue-Verhalten, keinen tatsächlichen KI-Aufruf, Hintergrundstart oder bezahlten Request. Echte Anbieterarbeit und native Aufgabenoberfläche sind noch nicht implementiert.

Die vollständige standalone Scheduling-Suite besteht mit **28 Tests in vier Suites**. Die native Scheduling/Budget-Filterauswahl im Haupt-Package besteht mit **34 Tests**, einschließlich der fünf neuen Tests. Xcode MCP `BuildProject` besteht (Receipt 125, 5,143 Sekunden, keine Fehler). Nachweise im Aufgaben-Workspace: `work/local-schedule-authority-tests.log`, `work/local-scheduling-module-tests.log`, `work/local-scheduling-regression.log`, `work/shared-catalog-qa/local-schedule-authority-build.json`. Diese ausgewählten Tests ersetzen keine vollständige App-Abnahme oder einen neuen TestFlight-Upload.
