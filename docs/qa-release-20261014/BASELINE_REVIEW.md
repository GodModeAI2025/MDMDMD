# Scriptum: Gesamtprüfung am 14. Oktober 2026

## Ergebnis

Die Anwendung wurde seit der Übergabe erheblich weiterentwickelt. Der geprüfte Arbeitsstand ist `0acb33e7bf01761fb0a81e990d20853249b7dcad` auf `fix/compact-writing-viewport`. Der Checkout ist unverändert und sauber. Das Produktionsziel bleibt pausiert; diese Prüfung ändert weder App-Code noch Apple-Konfiguration, Git-Branches oder Veröffentlichung.

Der unabhängige aktuelle iOS-Release-Build besteht. Die vollständige Root-Swift-Suite meldet 708 Swift-Testing-Tests, darin vier deklarierte optionale Skips, sowie 58 erfolgreiche XCTest. Alle elf Python-Tests des Signierungsverifiers bestehen. Das sind lokale Nachweise, keine vollständige Geräte-, CloudKit- oder Provider-Abnahme.

Aktuell authentifiziert in App Store Connect gelesen: **Version 1.0.0, ausgewählter Build 7, Status „Bereit für Vertrieb“**. Die Einstellung zur manuellen Veröffentlichung ist ausgewählt. Kein Veröffentlichungs- oder Vertragsbutton wurde betätigt. Die Aussage „Warten auf Prüfung“ in der Repository-Dokumentation ist überholt. Ein aktueller TestFlight-Gruppenstatus und die Installation auf einem echten Gerät wurden in dieser Prüfung nicht erneut gelesen.

## 1. iCloud: Zugang vorhanden, Aktivierung in dieser Version gesperrt

Der sichtbare Weg lautet **Bibliothek → Ordnersymbol „Dateien“ → „Bibliothek-Werkzeuge“ → „iCloud“** (`Sources/SkriptumApp/SkriptumApp.swift:159`). Bei angezeigter Tastatur kann die Seitenliste mit diesem Menü zurücktreten.

`ICloudLibrarySession.swift:34` verlangt `ScriptumICloudProvisioned == true`. Der Schlüssel fehlt sowohl in der aktuellen Projektkonfiguration als auch in der frisch kompilierten Release-App. Deshalb erscheint `ICloudSettingsView.swift:21–23` mit „Einrichtung noch nicht abgeschlossen“; der Aktivieren-Button wird nur im anderen Status angezeigt. Ein Anwender kann die fehlende Freischaltung nicht durch eine App-Einstellung beheben.

Der gespeicherte Build-7-Verifier bestätigt CloudKit-Container, CloudKit-Produktionsumgebung, Push und PCC, meldet aber ausdrücklich `iCloudRuntimeGate: false` und insgesamt `passed: false`. Die alte Aussage, iCloud-/Push-Berechtigungen seien noch nicht erteilt, darf nicht als aktueller Stand verwendet werden. Die neueren Release-Einträge beschreiben die Laufzeitsperre dagegen als bewusst beibehalten, bis Produktionsschema und echte Teilnehmer-Zusammenarbeit nachgewiesen sind.

**Bewertung: P1 für das verlangte Produktziel, P2 für die unklare Nutzerführung.** Nicht einfach den Schlüssel einschalten: Produktionsschema, Zwei-Geräte-Synchronisation, Freigabe/Rollen, Kommentare/Antworten und Konflikte müssen zuvor tatsächlich geprüft werden. Die Oberfläche sollte eindeutig „In dieser Version noch nicht verfügbar“ sagen und die Einrichtung nicht dem Anwender zuschreiben.

## 2. Reproduzierbarer Speicherfehler bei „Neue Markdown-Datei“ — P1

`WritingLibrary.swift:231–246` legt eine leere `Unbenannt.md` an und importiert deren Inhalt anschließend als unabhängige Bibliotheksseite. Das Bearbeiten dieser Seite läuft über `LibraryStore`, ohne den Pfad der angelegten Datei weiterzuführen.

Mit den **unveränderten tatsächlichen Projektmodulen** wurde in einer ausschließlich temporären neuen Bibliothek folgende Sequenz ausgeführt: Datei anlegen → importierte Seite mit `Geschrieben: Café é 🦊\n` bearbeiten → Datei und aktuelle Bibliotheksseite erneut lesen. Ergebnis:

- Die Bibliotheksseite enthält den geschriebenen Text.
- `Unbenannt.md` bleibt **0 Byte** groß.
- `fileEqualsLibrary=false`.

Der Text geht in dieser Sequenz nicht aus der Bibliothek verloren. Die Dateien-App erhält aber eine leere Datei, obwohl die Aktion eine Markdown-Datei verspricht. Der aktuelle Erzeugungstest prüft nur die leere Datei unmittelbar nach Erstellung und findet diese Abweichung nach Bearbeitung nicht. Nachweis: `actual-module-probes.json` und `file-proof.swift`.

Korrektur: Entweder die neue Datei im echten dokumentgebundenen Editor öffnen und koordiniert weiterschreiben oder die Aktion als neue Bibliotheksseite führen und den Dateiexport ausdrücklich getrennt anbieten. Keine stumme Verdoppelung in zwei auseinanderlaufende Dokumente.

## 3. Mehrfenster-Tastaturzustand verwendet fremde Fenster — P1

`PageWritingView.swift:414–416` nimmt aus `UIApplication.shared.connectedScenes` die erste aktive Szene und deren Key Window. Alle Editoren abonnieren gleichzeitig die globalen Tastaturbenachrichtigungen. Bei zwei aktiven iPad-Fenstern kann die Umrechnung daher auf ein anderes Fenster bezogen sein; Titel, Status und Aktionsleisten reagieren dann auf dessen Tastatur.

Die Quellverletzung der Fensterzuordnung ist bestätigt; ihr konkretes Stage-Manager-Bild wurde hier nicht neu aufgenommen. Die Erkennung muss an das eigene Editorfenster gebunden werden. Die bestehende lokale Anchor-/Scene-Lösung eignet sich als Grundlage. Vollständiger unabhängiger Editorbericht: `../project-review-20261014-editor.md`.

## 4. Chat meldet eine Änderung, obwohl die Speicherung abgelehnt wurde — P2

`PageAssistant.swift:146–150` macht aus einer Antwort mit Textmarkern stets „Der Text wurde geändert.“ Die Chatdarstellung ruft diese Funktion direkt auf. Sie berücksichtigt nicht, ob `applyChatEdit()` die Antwort tatsächlich übernommen hat.

Ein tatsächlicher Modul-Test mit einer zwischenzeitlichen Metadatenänderung reproduziert:

- `staleAIChangeApplied=false`.
- Der revisionsgebundene Speicher schützt das Dokument korrekt: „Der Vorschlag wurde nicht angewendet.“
- Die Anzeige für dieselbe Antwort lautet trotzdem „Der Text wurde geändert.“

Die Datenintegrität dieser Sperre ist positiv. Die Erfolgsmeldung muss jedoch an eine echte Übernahmebestätigung gekoppelt werden. Nachweis: `actual-module-probes.json`; UI-Verknüpfung in `AssistantPanel.swift`.

## 5. KI-Rückgängig und Kontext nach einer Änderung — offen

Der neue Chat übernimmt Änderungsaufträge sofort, entsprechend dem dokumentierten Build-4-Feedback des Eigentümers. Es ist keine unbeauftragte Abweichung, dass der alte Freigabedialog entfällt. Lektorat/Überarbeitung haben weiterhin einen Vorschlagsweg; ihr Öffnen startet die Anfrage automatisch.

Der Panel-Rückgängig-Zustand ist nur `@State`. Ein weiterer Auftrag setzt ihn zurück, und beim Schließen geht er verloren. Die gespeicherte native Fake-Provider-QA meldet zudem einen danach deaktivierten Editor-Rückgängig-Button. Andererseits zeichnet der aktuelle Domain-Pfad Werkzeughistorie auf und seine Tests bestehen; frühere Fassungen bleiben im Store erhalten. Deshalb wird hier **kein allgemeiner Verlust der Wiederherstellbarkeit behauptet**. Den tatsächlichen Editor-Rückgängig-Weg nach Sheet-Schließen, neuem Auftrag, Ansichtswechsel und Neustart gezielt prüfen.

Auswahl und aktiver Block werden mit festen UTF-16-Bereichen übergeben. Nach unterschiedlich langen Ersetzungen benötigen Folgebefehle eine gezielt geprüfte Bereichsaktualisierung. Die aktuellen Tests prüfen die initiale Bereichswahl und Marker-Auswertung, keine vollständige Folge mehrerer echter Provider-Änderungen.

## 6. Weiterer bestätigter Geometriebefund — P2

`BlockNativeEditor.swift:459–473` reduziert Tastatur und Zubehörleiste auf deren obere Y-Kante. Horizontale Grenzen werden nicht berücksichtigt. Eine schwebende iPad-Tastatur seitlich neben dem Text kann daher ein unnötiges Scrollen auslösen. Quellgeometrie bestätigt; echte Floating-Keyboard-/Split-Keyboard-Abnahme bleibt offen.

Andere unabhängige Review-Hinweise sind ausdrücklich Unsicherheiten, keine behaupteten Fehler: verzögerte Fokusversuche bei konkurrierenden Eingaben, extrem kleine Fenster, besondere UIKit-Dismissals und das einzige appweite Launch-Koordinator-Objekt bei mehreren Dateibrowserfenstern.

## 7. Architektur und vollständiger Anforderungsabgleich

| Bereich | Aktueller Befund |
|---|---|
| R01 Bibliothek/Spaces | Core und Facade vorhanden, lokale Persistenz-/Navigationsprüfungen bestehen; Mehrfenster-Seitenlisten bleiben laut neuer QA bis zur nächsten Aktion auseinander. |
| R02 Schreiben/Markdown | Ulysses-Fokus, gedämpfte Syntax, Tastatur-Zubehörleiste, Kontextmenü statt Dauergriffe, Fokus-/Höhenkorrekturen vorhanden. Neue native Software-Tastatur-QA ist versioniert. Große Accessibility-Größen und sehr kleine Fenster bleiben eigene Nachweise. |
| R03 Datenintegrität | Revisions-/Quellbyte-Sperren, atomare Speicherung, Entwurfsjournale, Konflikt- und Wiederherstellungstests bestehen. KI-Patch-Sperre im eigenen Modul-Test tatsächlich wirksam. Neuer Dateifehler siehe oben. |
| R04 Dateien/Export | Echter iOS-27-Document-Typ mit Undo vorhanden; neue Bibliotheks-Dateierzeugung ist entkoppelt. PDF/DOCX/HTML/EPUB/Markdown und Manuskripte bleiben implementiert; der lange PDF-Opt-in wurde bei dieser Suite übersprungen. |
| R05 KI-Kontext/Änderungen | Auswahl/Block/Seite und Streaming/Abbruch implementiert, Fake-Provider-UI-Belege vorhanden. Echte Anbieterantworten, Folgeänderungen, dauerhaftes Rückgängig und korrekte Übernahmebestätigung nicht vollständig belegt. |
| R06 Anbieter/Anmeldung | Getrennte OpenAI-/Anthropic-Schlüssel, ChatGPT-OAuth und PCC-Pfade vorhanden; Schlüssel im Keychain, kein stiller Fallback. PCC-Gate im Build vorhanden. Lokale Vertrags-/Mocktests ersetzen keine reale Provider-/Regions-/kommerzielle OAuth-Abnahme. |
| R07 Blöcke/Bilder/Regeln | Leere Vorlagen, native Blockverschiebung, Bilder und Tabellen erhalten; Bildblock/Anhänge und lokale Regeln im Code. Neuer geringerer UI-Chrome entspricht dem dokumentierten Eigentümerfeedback. |
| R08 iCloud/Zusammenarbeit | Private und geteilte CloudKit-Transporte, Rechte, Kommentare, Threads und Konflikte implementiert und lokal getestet. Runtime-Gate aus; keine echte Zwei-Teilnehmer-Abnahme in den neuen Belegen. |
| R09 Aufgaben/Budgets | Persistente lokale Aufgaben, Budgets und BackgroundTasks vorhanden. Keine garantierte zeitgenaue Ausführung bei geschlossener App; reale Provider-/OS-Ausführung weiter separat nachweisen. |
| R10 Adaptive UI | Drehungs-/Fokuskorrekturen und neue Keyboard-QA vorhanden. Fremdfenster-Tastaturzugriff ist Rückschritt. VoiceOver, Hardwaretastatur, Drag-and-drop, Floating Keyboard und vollständiges Multiwindow nicht vollständig abgenommen. |
| R11 Qualität | Aktueller vollständiger lokaler Build/Test erfolgreich; native Belege sind nach Commit/Simulator/Fake-Anbieter begrenzt. Keine komplette Geräte-/Stress-/Parallelitätsgarantie ableiten. |
| R12 Auslieferung | Neue Signierungs-/Upload-/Gruppenzuordnungsbelege für Builds 3–6 vorhanden. Apple zeigt aktuell Version 1.0.0 mit Build 7 „Bereit für Vertrieb“. Aktuelle Geräteinstallation/TestFlight-Gruppen wurden hier nicht erneut bestätigt. |
| R13 Export-Themes | Der semantische getaggte PDF-Renderer ist die normale Produktionsroute, auch in der frischen Release-Kompilierung. README behauptet fälschlich noch Debug-only. Alle 124 Export-Test-Headlines bestehen, einschließlich des übersprungenen langen Opt-ins. PDF/UA/accessible-reader-Abnahme weiterhin nicht bewiesen. |
| R14 Schreibqualität | Native Rechtschreibung/Grammatik, lokale Basis-Stilregeln und optionaler eigener LanguageTool-Server sind integriert. Keine belastbare neue 20+-Sprachen-Grammatik/Stil-Abnahme; die Wörterbuchliste ist dafür ausdrücklich kein Nachweis. |
| R15 Wissensarbeit | Tags, Vorlagen, Recherchematerial, Verweise, Manuskriptreihenfolge, Statistiken und Ziele im bestehenden Core/UI erhalten. Vollständige gemeinsame Produktabnahme bleibt erforderlich. |

## 8. Release, Lizenzierung und Projektpflege

- `project.yml` und frisch gebautes `Info.plist`: 1.0.0 (7), iOS 27, PCC-Gate true, iCloud-Gate fehlt.
- Release-Binary enthält weder `SCRIPTUM_FAKE_AI`, `DebugFakeProvider` noch den Fake-Gedicht-Marker. Die Fake-QA wurde damit nicht als realer Provider in diesen Release übernommen.
- Das erzeugte App-Bundle enthält `Settings.bundle/Root.plist`; Lizenzunterseiten und sechs tatsächlich verzeichnete Komponenten bleiben vorhanden. Keine neue Dependency gegenüber den fixierten Apple-/Swift-Markdown-Versionen gefunden.
- Kein verpflichtender eigener Cloud-Server in der Bibliothekszusammensetzung; alte Workspace-/Collaboration-Forschung bleibt getrennt. Einige ältere Clientmodelle sind weiterhin kompiliert, ohne daraus einen Produkt-Serverzwang abzuleiten.
- GitHub wurde live ausschließlich gelesen: Remote `fix/compact-writing-viewport` stimmt mit HEAD überein. `main` bleibt `5790018`; PRs 2 bis 7 sind offen, nur PR1 ist gemergt. Sauber/pusht bedeutet hier nicht „alles gemergt“. Es gibt keine GitHub-Workflows.
- `README.md`, `RELEASE_STATUS.md`, `PROFESSIONAL_WRITING_STATUS.md` und ältere ICLOUD/SUBMISSION-Statusseiten enthalten widersprüchliche, teilweise als aktuell überschriebene historische Aussagen. Besonders problematisch: PCC-/iCloud-Signierungsstand, Debug-only-PDF, erledigte Integrationen und Apples Prüfstatus. Historie erhalten, aber eine eindeutige aktuelle Kurzfassung ergänzen.
- Die ursprüngliche Build-7-IPA am im SHA-Nachweis genannten temporären Claude-Pfad ist nicht mehr vorhanden. Hash und Signierungsbericht bleiben erhalten; dieser Bericht wurde daher nicht gegen jene originalen Binärbytes erneut geprüft. Der frische Release-Build dieser Prüfung ist unsigniert und ersetzt kein Distributionsartefakt.
- Apple zeigt im Account zusätzlich einen Hinweis zur aktualisierten Paid Applications Schedule. Keine Vertragsannahme vorgenommen. Vor einer weiteren Einreichung muss der Kontoinhaber diesen tatsächlichen Account-Hinweis prüfen.

## Prüfumfang und Grenzen

Geprüft: Commit-Historie seit `ed0ed43`, alle geänderten Produktionspfade, App-/Package-Zusammensetzung, vorhandene Root-Tests, Release-Konfiguration, aktuelle Release-Binärmarker, Lizenzen/Settings-Ressource, Anforderungen R01–R15, erhaltene native QA, Signierungsbelege und aktueller Apple-Versionsstatus. Unabhängiger vollständiger Editor-/Window-Quellreview liegt zusätzlich vor. Das ist kein Versprechen, jede unveränderte Quellzeile manuell oder jede Funktion auf einem echten Gerät geprüft zu haben.

Keine App-Code-Korrektur, kein Commit/Merge/Push, kein CloudKit-Schalter, keine Veröffentlichung. Die neuen Test- und Berichtdateien liegen außerhalb des Repositorys unter `work/project-review-20261014`.

## Empfohlene Reihenfolge

1. Den Dateierzeugungs-/Speichervertrag korrigieren und nach tatsächlichem Editieren/Schließen/Dateien-App-Wiederöffnen prüfen.
2. iCloud-Nutzeranzeige eindeutig machen; Produktionsschema und echte Synchronisation/Zusammenarbeit abnehmen, dann die Laufzeitfreischaltung in einem neuen signierten Build.
3. Tastaturzustand pro Fenster und Floating-Keyboard-Geometrie korrigieren, zwei Fenster tatsächlich testen.
4. KI-Übernahmebestätigung und dauerhaft zugängliches Rückgängig/Folge-Kontext prüfen.
5. Aktuellen Release-/Git-Stand konsolidieren; übrige R01–R15-Geräte-/Sprach-/Provider-Nachweise abschließen.
