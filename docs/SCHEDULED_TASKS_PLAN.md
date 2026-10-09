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

1. Native Aktivierung mit geprüfter Zugangs-/Preisbindung; lokale Entwurfsverwaltung und persistente Task-/Anbieter-/Budgetkonfiguration sind vorhanden.
2. Dispatcher mit frischem Capture, echten Adaptern, überprüfbaren Quotes, Budget-/Generation-/Lease-Prüfung, Streaming-Abbruch und dauerhafter Ungewissheit nach Versand.
3. Best-Effort-Hintergrundregistrierung und Vordergrund-Catch-up; kein zweiter betriebener Dienst.
4. Ergebnisliste und Vorschlagsvergleich; Übernahmereceipt innerhalb der ursprünglichen Bibliothekstransaktion, ohne aktive Edit-Journale zu umgehen.
5. Native Lauf-/Neustart-/Fehler-/Anbieter-/Budget-/Accessibility-Prüfung und signierter TestFlight-Nachweis.

## Aktueller Nachweis

Fünf neue native Modelltests prüfen exakten gewählten Kontext/Digest, fremde Scope-/Anbieter-/Budget-/Block-Abweisung, offene/trashed Hierarchie, Aktivierung/Neustart/Fälligkeit ohne Server und unveränderten Text über 3 MiB. Dies belegt lokale Eigentumsaufnahme und Queue-Verhalten, keinen tatsächlichen KI-Aufruf, Hintergrundstart oder bezahlten Request. Echte Anbieterarbeit ist damit noch nicht belegt; die inzwischen ergänzte native Entwurfsverwaltung ist unten dokumentiert.

Die vollständige standalone Scheduling-Suite besteht mit **28 Tests in vier Suites**. Die native Scheduling/Budget-Filterauswahl im Haupt-Package besteht mit **34 Tests**, einschließlich der fünf neuen Tests. Xcode MCP `BuildProject` besteht (Receipt 125, 5,143 Sekunden, keine Fehler). Nachweise im Aufgaben-Workspace: `work/local-schedule-authority-tests.log`, `work/local-scheduling-module-tests.log`, `work/local-scheduling-regression.log`, `work/shared-catalog-qa/local-schedule-authority-build.json`. Diese ausgewählten Tests ersetzen keine vollständige App-Abnahme oder einen neuen TestFlight-Upload.

## Dispatcher-Vertrag

`LocalScheduleDispatcher` verbindet fällige lokale Läufe mit Claim/Lease, aktuellem Capture, separatem Anbieter-Preflight, reserviertem Budget, vor Versand gespeichertem Request-Bezug und Ergebnisaufnahme. Preise, Hintergrund-Eignung, Berechtigung und tatsächliche Ausführung stammen aus `LocalScheduledExecutor`; die Orchestrierung erfindet diese Angaben nicht. Modell-/Anbieterprovenienz und Preisversion müssen zur festgelegten Bindung passen. Quellrevision und genaue Bytes werden nach Preflight erneut geprüft. Ergebnisse ersetzen keine Dokumente automatisch.

Der Kern kann ausschließlich vor Dispatch eine Reservierung wieder freigeben. Nach Dispatch bleibt ein unterbrochener/unklarer Lauf dauerhaft executionUncertain und wird beim nächsten Start nicht blind wiederholt. Eine vollständig erhaltene Antwort ohne bestätigte Abrechnung bleibt als Ergebnis erhalten, während ihr Budget gehalten wird. Nur eine tatsächlich bestätigte Kostenangabe führt zur Abrechnung. Vorschläge speichern jetzt auch Anbieter-/Modellprovenienz; alte gespeicherte Vorschläge ohne diese optionalen Felder bleiben lesbar.

Sechs zusätzliche Dispatcher-Tests mit ausdrücklich kontrollierten Test-Executors bestehen: einmalige Zusammenfassung/Neustart und Abrechnung, Unterbrechung ohne Wiederholung, Preflight-Abweisung ohne Versand, unbekannte Abrechnung mit gehaltenem Budget, Vorschlag/Provenienz ohne Dokumentmutation, abweichendes Modell ohne Ergebnisveröffentlichung sowie Freigabe vor Dispatch und Verweigerung danach. Die vollständige Scheduling-Suite besteht weiterhin mit **28 Tests**. Xcode MCP Build besteht (Receipt 126, 5,264 Sekunden, keine Fehler). Logs: `work/local-dispatcher-final-tests.log`, `work/local-dispatcher-module-regression.log`, `work/shared-catalog-qa/local-schedule-dispatcher-build.json`.

Der Dispatcher hat noch keinen nativen UI-/Timer-/Background-Aufrufer. Der Provider-Adapter ist nun angeschlossen wie unten beschrieben. Diese kontrollierten Tests beweisen weder einen echten KI-Aufruf noch reale Preise, Abrechnung oder Hintergrundarbeit. Die verbleibenden Integrationsschritte oben bleiben verbindlich.

## Provider-Anbindung

`ScheduledAIExecutor` verwendet das bestehende `AIProvider`-Streaming für den fest gebundenen Zugang und das fest gebundene Modell. Aufnahme benötigt getrennte reale Access-Prüfung, freigegebene Ausführungsmodi und eine vertrauenswürdige Preis-Quote mit passender Version, Frist, Währung und Grenzen. Diese Prüfer/Quote-Konfiguration werden ausdrücklich injiziert; ohne ihre echte native Einrichtung entsteht keine belegte automatische Ausführung. Der Byte-/Envelope-Inputwert ist eine konservative Aufnahme-Schranke, kein gemessener Anbieter-Tokenizer oder Abrechnungsnachweis. Verlässliche Modell-/Preisobergrenzen bleiben Voraussetzung für eine Aktivierungsoberfläche.

Nur die genau erlaubten Blöcke werden als JSON-Daten verpackt; erweiterte Grants oder fremde Ziele werden abgewiesen. Antworttokens sind im echten Request begrenzt. Ausgaben sind auf 1 MiB begrenzt und benötigen ein ausdrückliches completed-Event; weitere Events danach oder unvollständige Streams werden zurückgewiesen. Es gibt keinen Anbieterwechsel. Der aktuelle Provider-Stream liefert keine bestätigte Kostenreceipt, daher bleibt confirmedCostMicros nil und Budget gehalten. Der persistierte Request-Bezug ist lokale Korrelation; er wird nicht als vom Anbieter bestätigte Request-ID oder Idempotenzgarantie ausgegeben.

Vorschläge müssen ein strikt geprüftes replacements-JSON liefern: keine unbekannten Felder, doppelten Objektkeys (auch escaped aliases), wiederholten Block-IDs oder Ziele außerhalb der freigegebenen Menge. Die Daten werden nicht automatisch angewandt. Dokumenttext bleibt Dateninhalt und kann keine anderen Ressourcen/Tools freigeben.

Fünf zusätzliche Adapter-/Decoder-Tests bestehen, darunter echte Request-Konstruktion über einen kontrollierten AIProvider, ausgewählte Blöcke/Unicode-Streaming, fehlender Zugang/Background-Modus ohne Versand, explizites Stream-Ende, erweiterter Kontext/zu kleines Inputbudget sowie mehrdeutige/außerhalb liegende Vorschläge. Die kombinierte lokale Autorität-/Dispatcher-/Adapter-Auswahl besteht mit **16 Tests**. Xcode MCP Build besteht (Receipt 127, 5,237 Sekunden, keine Fehler). Logs: `work/scheduled-ai-executor-final-tests.log`, `work/shared-catalog-qa/scheduled-ai-executor-build.json`.

Die Verbindung ist Code-/Request-/Stream-Vertragsevidenz, kein Live-Test der entfernten Anbieter. Native Zugangs-/Quote-Bindung, Aufgabenaktivierung, Dispatcher-Aufrufer, Hintergrundausführung, echte Rechnungsreceipts und Vorschlagsübernahme bleiben offen.


## Native lokale Aufgabenverwaltung

`LocalScheduleSession` speichert Aufgaben über den Scheduling-Kern in einer nach tatsächlicher lokaler Owner-/Bibliotheksidentität getrennten Ablage. Die Owner-ID bleibt in den Bibliothekseinstellungen stabil; beschädigte Identität oder ein fremder gespeicherter Scope sperren Änderungen. Anbieter und Modell werden als unveränderliche private Bindung gespeichert, ohne API-Schlüssel. Ein Entwurf prüft die aktuelle eigene Seite, Hierarchie, Edit-Journale und Budget-/Kontextgrenzen; er aktiviert keine KI-Ausführung.

Die native Oberfläche ist über Dateien und die Seitenaktionen erreichbar. Sie bietet Seitenwahl, Zusammenfassung oder Änderungsvorschlag, einmalige/tägliche/wöchentliche/monatliche Termine, Ende/Anzahl, Anbieter-/Modellwahl, Budgets und Tokenlimits. Gespeicherte Entwürfe erscheinen ausdrücklich als „Entwurf · noch nicht aktiviert“. Abbruch wird dauerhaft im Kern gespeichert; vorhandene aktive Aufgaben können über den geprüften Kern pausiert werden. Ergebnisse und Vorschläge werden angezeigt, Änderungen noch nicht übernommen. Der Dispatcher wird von dieser Oberfläche noch nicht gestartet.

Die fokussierte Auswahl besteht mit **17 Tests**, darunter zwei neue Manager-Tests für gespeicherten Entwurf, erneutes Laden, exakte Anbieterbindung und Abbruch. Xcode MCP Build besteht (Receipt 130, 4,366 Sekunden, keine Fehler). Nachweise: `work/local-task-manager-final-tests.log`, `work/shared-catalog-qa/local-tasks-ui-final-build.json`.

Die normale App wurde auf dem 402-pt-iPhone-Simulator über Xcode MCP geprüft: Manager öffnen, QA-Entwurf speichern, Manager schließen/wiederöffnen und denselben Entwurf abbrechen bestehen. Der Quellstand blieb während der Prüfung unverändert. [Prüfbericht und Screenshots](qa-local-tasks-ui/REPORT.md). Das erneute Öffnen belegt Persistenz innerhalb derselben App-Sitzung; Kaltstartpersistenz und echte Ausführung wurden im UI nicht geprüft. Kosmetisch offen sind der doppelte PCC-Anbieter-/Modellname und das englische Datumsformat in der deutschen Oberfläche. iPad, VoiceOver, Hintergrundausführung und ein neuer signierter TestFlight-Build sind noch nicht bestätigt.
