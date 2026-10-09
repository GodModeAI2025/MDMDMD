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


## Übernahme geplanter Vorschläge — Modellgrenze

`LocalScheduleSession.review(proposalID:)` und `accept(proposalID:)` beziehen Vorschläge ausschließlich aus dem validierten dauerhaften Scheduling-Zustand und dessen tatsächlichem Lauf/Task. Die unveränderliche Anbieterbindung muss einschließlich genauer Anbieter-/Modellbytes passen. Der aktuelle eigene Bibliothekslocator, Owner-/Space-/Seiten-Scope, erlaubte Blöcke, vollständiger Quelldigest und Quellrevision werden vor einer neuen Übernahme erneut geprüft. Offene Journale, gelöschte Blöcke und Papierkorb in der Hierarchie sperren die Übernahme. Der vollständige resultierende Text bleibt auf 8 MiB begrenzt.

Der Vergleich liefert Original/Vorschlag in Dokumentreihenfolge, ohne Schreibzugriff oder neuen KI-Aufruf. Übernahme setzt ausschließlich replace-Operationen auf erlaubten Blöcken ein; die feste UUID-Sortierung der Operationen macht Wiederholungen eindeutig. `LibraryStore.applyProposal` speichert Textänderung, alte Revision und Übernahmereceipt in derselben atomaren Bibliothekstransaktion. Der vorhandene dauerhafte Änderungsbeobachter bleibt beteiligt. Kein getrenntes Scheduling-Flag behauptet eine Übernahme. Eine genaue Wiederholung liefert die ursprüngliche Receipt, auch nach späteren Benutzeränderungen und Bibliotheksneustart, ohne erneut zu schreiben. Abweichender Payload unter derselben Vorschlags-ID wird zurückgewiesen. Alte Ergebnisse ohne Anbieter-/Modellprovenienz bleiben lesbar, werden aber nicht übernommen.

Fünf neue Tests prüfen lesenden Vergleich/genaue Unicodebytes/unveränderte andere Blöcke, atomare Receipt und Wiederholung nach Neustart, veralteten Digest/Revision/Anbieter, offene Journale/Papierkorb/fremden Owner, geänderte Replaybytes und den integrierten Weg vom kontrollierten Provider über die persistente Queue bis zur realen Session-Übernahme. Die fokussierte Regression besteht mit **26 Tests**. Xcode MCP `BuildProject` besteht (Receipt 148, 7,633 Sekunden, keine Fehler). Nachweise: `work/local-scheduled-acceptance-final-tests.log`, `work/shared-catalog-qa/local-scheduled-acceptance-build.json`.

Die Modellgrenze ist inzwischen über einen ausdrücklichen Übernahmebutton und Vergleichsdialog in der nativen Ergebnisoberfläche angeschlossen, wie unten geprüft. Live-Anbieter, Preis-/Zugangsaktivierung, Hintergrundlauf, Shared-Document-Übernahme und neuer TestFlight-Nachweis bleiben offen.


## Nativer Vorschlagsvergleich und Übernahme

Ergebniszeilen öffnen einen eigenen Vergleich mit Original und Vorschlag je betroffenem Block in Dokumentreihenfolge. Nur nach „Änderungen übernehmen“ wird die vorhandene Modellgrenze aufgerufen. Bei aktueller Übernahmereceipt erscheint „Bereits übernommen“ mit Zeitpunkt; spätere Benutzeränderungen werden nicht erneut ersetzt. Seitenänderungen lösen eine neue Prüfung aus, und ein abweichender Stand sperrt den Button mit Erklärung. Vor dem Commit wird weiterhin frisch geprüft, sodass eine inzwischen geänderte Seite nicht allein aufgrund eines alten sichtbaren Dialogs übernommen werden kann. Eine stabile Auswahlbindung am Aufgaben-Dialog besitzt die Präsentation; die Ergebnis-Sektion präsentiert selbst keine Sheet.

Die Geräteprüfung verwendet ausschließlich im DEBUG-Build vorhandene, ausdrücklich gestartete isolierte Fixtures (`--scriptum-local-proposal-ui-qa`). Sie erzeugen eine neue temporäre Bibliothek und persistente Scheduling-Ergebnisse über einen kontrollierten Executor, ohne vorhandene Manuskripte, Credentials, Netzwerkaufrufe oder reale Zugangsfreigaben. Diese Testoberfläche ist im Release-Build ausgeschlossen. Der erste Prüfversuch deckte einen Präsentationsabbruch auf; nach Korrektur wurden Vergleich, Übernahme, erneute Prüfung, Schließen/Wiederöffnung und Veraltung erneut vollständig über tatsächliche UI-Interaktionen geprüft.

Xcode MCP Build besteht (Receipt 162, 5,116 Sekunden, keine Fehler). Optimierte Release-Kompilierung für generisches iPhone/SDK 27 mit `CODE_SIGNING_ALLOWED=NO` besteht (`work/local-proposal-ui-fixed-release.log`). Der gewöhnliche erste Shell-Build scheiterte zuvor an gesperrten Compiler-Caches; der autorisierte lokale Build bestand. Signierung/Provisionierung wurde dadurch nicht geändert.

Die native UI-Abnahme bei 402 pt/default Dynamic Type besteht: exakte kombinierende Akzente/Emoji, passende Übernahme, identische Receipt bei erneuter Prüfung und Wiederöffnung, erklärter veralteter Vorschlag mit gesperrtem Button, Rückkehr zum Manager. Quellmanifest vor/nach identisch (285 Dateien); Sitzung beendet (Receipt 180). [Prüfbericht und Screenshots](qa-local-proposal-ui/REPORT.md). Die Modellregression mit 26 Tests bleibt der Nachweis für atomare Speicherung und Prozess-/Bibliotheksneustart; der UI-Test prüft Dialogwiederöffnung innerhalb derselben App-Sitzung.

Offen bleiben echte automatische Anbieteraktivierung/Preise/Hintergrundläufe, geteilte Dokumente, iPad-/Accessibility-Größen, ein signierter neuer TestFlight-Build und die Datumsdarstellung entsprechend der späteren vollständig lokalisierten Oberfläche. Der englisch konfigurierte Simulator zeigt derzeit englische Datumsbestandteile neben deutschen App-Texten.


## Native Aktivierungsgrenze und Ausführungsaufruf

`LocalScheduleSession.prepareActivation` liest ausschließlich einen gespeicherten eigenen Entwurf/pausierten Task, prüft die genaue immutable Anbieter-/Modellbindung und den separat gelieferten Owner-Budgetrahmen und ruft den ausgewählten Executor-Preflight auf. Es wird keine Inferenz gestartet. Nach dem asynchronen Preflight werden Uhrzeit, Quote, Quellrevision/Digest und Scheduling-Version erneut geprüft. Die Anzeige zur Bestätigung erhält ein höchstens 60 Sekunden gültiges, nicht persistiertes Ticket mit Scope, Seite, Anbieter/Modell, Modus, Taskbudgets und Quote; Credentials werden nicht in dieses Ticket kopiert.

`activate(reviewID:)` konsumiert das Ticket einmalig, prüft aktuellen Task/Version/Dokumentstand, ruft den real anzuschließenden Zugangs-/Quote-Preflight erneut auf und verweigert erhöhte Preisobergrenze, geänderte Token-/Preisversion, verlorenen Zugang, abgelaufene Quote/Bestätigung oder veränderten Dokumentstand. Uhrzeit wird nach asynchroner Arbeit erneut gelesen. Erst danach aktiviert der vorhandene atomare Scheduling-Kern den Task mit frischem Owner-Grant. Neustart stellt keine noch ausstehende Bestätigung wieder her.

`runDue` verbindet diese Session mit dem vorhandenen Dispatcher, prüft gespeicherte Anbieter-/Modellbindungen gegen den verwendeten Executor und übernimmt ausdrücklich gelieferte Budgetrahmen je Währung. Nach einem Fehler wird der tatsächlich gespeicherte Laufzustand neu geladen; Ungewissheit/Reservierungen verschwinden nicht aus der Oberfläche durch einen alten Snapshot. Der Dispatcher beansprucht jetzt ausschließlich Läufe seiner genauen Anbieterbindung und eigenen Bibliotheks-/Owner-Scope. Andere fällige Anbieterbindungen bleiben ohne Lease/Dispatch/Abweisung in der Queue und können vom passenden Executor verarbeitet werden.

Sechs neue Tests bestehen: doppelte Preflight-Prüfung/einmalige Zustimmung/dauerhafte Aktivierung mit anschließendem kontrollierten Session-Lauf; verlorener Zugang/erhöhte Quote/Ablauf/Bestätigungsneustart ohne Aktivierung; geänderte Seite oder Abbruch; zwei Anbieterbindungen ohne gegenseitige Abweisung; Fristablauf während asynchroner Prüfung; Dokumentänderung während asynchroner Prüfung. Die fokussierte Regression besteht mit **32 Tests** (`work/local-schedule-activation-final-tests.log`). Xcode MCP Build besteht (Receipt 181, 7,507 Sekunden, keine Fehler).

Dies ist die native Orchestrierungsgrenze mit kontrollierten Test-Executors, keine reale Freigabe oder Anbieterinferenz. Die Oberfläche aktiviert weiterhin keine Aufgaben. Vertrauenswürdige konkrete Zugang-/Modell-/Preisrichtlinien, Bestätigungsdialog und lifecycle/background-Aufrufer müssen angeschlossen werden. Aktuelle OpenAI-Preise wurden anhand der [offiziellen Preisübersicht](https://developers.openai.com/api/docs/pricing) geprüft; es wurden keine Preiswerte oder angeblichen Rechnungsreceipts ohne entsprechende Laufbindung in den Code übernommen.

**Historischer Befund, inzwischen durch die folgende Integration bearbeitet:** Die ursprüngliche native Persistenz legte pro lokaler Bibliothek einen eigenen Scheduling-State an und bewies dadurch keinen gemeinsamen geräteweiten Owner-Monatsrahmen. Die folgende Budgetautorität ergänzt diese Grenze. Eine eigene geprüfte Änderung des einmal aufgenommenen Owner-Rahmens bleibt weiterhin offen.


## Gemeinsames Gerätebudget über eigene Bibliotheken

`LocalScheduleAccountBudgetStore` führt einen atomar gespeicherten lokalen Owner-Ledger pro Installation/Owner-Identität in `AccountBudgets`. Alle normalen `LocalScheduleSession`-Ausführungen verwenden ihn zusätzlich zum Bibliotheks-Ledger. Währung und UTC-Monat bleiben getrennte Grenzen; Reservierungen verschiedener Bibliotheken und Spaces zählen auf denselben Owner-Rahmen. Der Rahmen wird nach ausdrücklicher Aktivierungsbestätigung dauerhaft aufgenommen und kann durch einen anderen Task oder eine andere Bibliothek nicht erhöht/zurückgesetzt werden. Nach dieser asynchronen Aufnahme werden Bestätigungsfrist und Dokumentstand erneut geprüft.

Eine Registry liefert denselben Actor an gleichzeitig geöffnete Bibliotheken. Gleichzeitiges Öffnen teilt dieselbe laufende Bootstrap-Operation; ältere Fehlerantworten dürfen eine neuere Operation nicht aus der Registry entfernen. Die Migration liest und validiert bestehende private Scheduling-Dateien auch noch nicht geöffneter Bibliotheken, bevor neue Reservierungen möglich sind. Dies geschieht abseits des Main Actor. Andere Owner, widersprüchliche Rahmen oder beschädigte Zustände werden nicht durch leere Budgets ersetzt. No-Follow-Dateipersistenz bleibt verbindlich; von FileManager gelieferte `/tmp`-Aliasse werden aus dem ursprünglichen Stammverzeichnis rekonstruiert. Reguläre fremde Metadateien werden ausgelassen, Symlink-Einträge abgewiesen.

Der Dispatcher reserviert das gemeinsame Budget vor dem Bibliotheksbudget. Der globale Betrag ist dauerhaft gespeichert, bevor ein Anbieteraufruf zugelassen wird. Eine lokale, mit Lease/Fence bestätigte Abweisung vor Dispatch darf anschließend die globale Reservierung freigeben. Nach dem dauerhaften lokalen Dispatch-Marker wird auch global der Versandzustand gespeichert; ein Fehler an dieser Stelle startet keine Inferenz und hält die Reservierung konservativ. Nach Dispatch/unklarem Ausgang gibt es keine automatische Freigabe. Fehlende bestätigte Abrechnung lässt einen fertig empfangenen Text als Ergebnis bestehen und hält seine Preisobergrenze. Nur bestätigte Kosten führen zur Abrechnung. Quellstand, Quote-Frist und reservierter UTC-Monat werden unmittelbar vor dem Executor-Aufruf erneut geprüft.

`BudgetLedger.mergeConservatively` übernimmt validierte alte Ledger, ohne einen vorhandenen Hold aus einer alten lokalen Freigabe abzuleiten. Widersprüchliche unveränderliche Run-/Quote-/Scope-Fakten oder Rahmen sperren die Migration. Alte Reservierungen ohne globalen Versand-Fence bleiben explizite Legacy-Einträge und können keine neue Ausführung freigeben. Eine bestätigte globale Abrechnung wird durch ältere lokale Snapshots nicht rückgängig gemacht.

Zehn neue Tests prüfen zwei echte eigene Bibliotheken mit gemeinsamem Owner, parallele Restbudget-Reservierungen, identischen Actor bei parallelem Öffnen, Neustart mit ungewissem Betrag ohne Freigabe, bestätigte Abrechnung/ungesendete Freigabe/Schreibfehler vor Aufnahme, Bootstrap ungeöffneter Legacy-Nutzung und widersprüchliche Rahmen, lokale Reservierungs-Schreibfehler mit erst nach dauerhaftem Reject erfolgender Freigabe, globale Dispatch-Schreibfehler ohne Executor-Aufruf, abgelaufene Bestätigung nach globaler Aufnahme sowie UTC-Monats-/Quote-Ablauf während Dispatch-Persistenz.

Die fokussierte Regression besteht mit **42 Tests** (`work/local-account-budget-verified-tests.log`). Die standalone Scheduling-Suite besteht mit **28 Tests in vier Suites** (`work/local-account-budget-module-tests.log`). Xcode MCP Build besteht (Receipt 185, 4,506 Sekunden, keine Fehler; `work/shared-catalog-qa/local-account-budget-verified-build.json`). Dies belegt native Gerätebudget-Koordination und kontrollierte Executor-Verträge, keine echten Rechnungen oder Live-Anbieteranfragen.

Die Grenze ist geräte-/prozesslokal und benötigt keinen betriebenen Dienst. Ein zweites Gerät oder eine künftige App-Extension erhält dadurch kein gemeinsam gesperrtes Ausführungsbudget. Konservative Holds nach einem Crash zwischen den beiden Persistenzen bleiben bis zu einer getrennt geprüften Reconciliation erhalten; es wird kein pauschaler Refund oder Retry aus ihrem Alter abgeleitet. Owner-Rahmenänderung, Aufbewahrung/Auslagerung alter Ledger-Belege, Stressprüfung sehr vieler Bibliotheken, konkrete reale Preis-/Zugangspolitik, Aktivierungsoberfläche und Background-/Lifecycle-Aufruf bleiben erforderlich. Keine neue TestFlight-Veröffentlichung ist damit belegt.
