# Skriptum — verbindlicher Umfang
Ziel: professioneller nativer Markdown-Editor für Autoren und Wissensarbeiter auf iOS/iPadOS 27, vollständige Pages/Spaces-Arbeitsweise aus den zehn Referenzbildern, verifizierter interner TestFlight-Build. Kein Merkmal gilt durch bloße Existenz einer Oberfläche als fertig.

## Aktuelle Vorrangentscheidungen (14. Oktober 2026)

Die neuesten direkten Nutzerentscheidungen haben Vorrang vor älteren Abnahmeformulierungen in diesem Dokument und in datierten Prüfberichten:

- Verpflichtende physische Geräte-, Device-Interaction- und Mehrgerätetests entfallen. Bestehende Prüfnachweise bleiben erhalten. Lokale Datenintegritäts-/Regressionstests, Release-Kompilierung, tatsächliche Signierung und serverseitige Auslieferungsnachweise bleiben erforderlich. Eine nicht ausgeführte Laufzeitprüfung wird nicht als bestanden dargestellt.
- Der direkt gesendete KI-Änderungsauftrag wird sofort revisionsgebunden angewandt und ist rückgängig zu machen. Ein zusätzlicher Freigabe-/Übernahmedialog ist dafür nicht gewünscht. Der tatsächliche Empfänger und Arbeitsbereich bleiben sichtbar; abgewiesene Ergebnisse werden nicht als angewandt angezeigt. Manuell ausgewählte Rechtschreib-/Grammatikkorrekturen behalten ihren eigenen Vorschlagsdialog.
- iCloud gehört direkt ins Dateien-Menü. Das Produktionsschema und beide Runtime-/Distributionsberechtigungen sind am 14. Oktober bestätigt; die alte Quelleinschätzung „nicht provisioniert“ ist historisch.
- TestFlight und die Produktionsauslieferung sind ausdrücklich beauftragt. Geräteinstallation ist keine Freigabevoraussetzung. Upload, Apple-Verarbeitung, Exportcompliance, interne Gruppe und Produktionsprüfung werden separat nachgewiesen.
- Die Jimdo-Veröffentlichung der vorbereiteten Datenschutztexte wird auf ausdrücklichen Wunsch gesondert behandelt. Kein Jimdo-Kontozugriff in diesem Release-Schritt.

Diese Entscheidungen ändern Prüfverfahren und Bedienung; sie streichen keine Funktionen und begründen insbesondere keine unbelegte 20-Sprachen-, Anbieter- oder Synchronisationszusage.

## Verbindliche Korrektur: iCloud statt eigenem Dienst
Der Nutzer hat ausdrücklich festgelegt: kein eigener Cloud-Dienst, Synchronisation über iCloud. Eigene Workspace-Server, Betreiber-Anmeldung, PostgreSQL, Hosting und Server-Bibliotheksauswahl sind keine Produktvoraussetzungen mehr. Die bisherigen Prüfungen bleiben historische Entwicklungsnachweise. Lokale Dokumente bleiben erhalten.

Die Bibliothek synchronisiert über Apples private CloudKit-Datenbank; spätere Freigaben verwenden CKShare und die geteilte Datenbank. Die Anmeldung erfolgt über das iCloud-Konto des Geräts. KI-Anbieteranmeldung und API-Schlüssel sind davon unabhängig. R08 bleibt als Funktionsziel erhalten, wird über Apple-Dienste realisiert. R09 wird ohne eigenen Server über persistente lokale Aufgaben und die tatsächlich verfügbaren iOS-Hintergrundmöglichkeiten umgesetzt; eine garantierte zeitgenaue Ausführung bei geschlossener App darf nicht versprochen werden.

R08 umfasst ausdrücklich Zusammenarbeit über iCloud sowie verankerte Kommentare in Dokumenten, Antworten als Kommentar-Threads und Erledigt/Wiederöffnen. Lokale Speicherung dieser Funktionen ersetzt keine tatsächlich nachgewiesene Freigabe und Zusammenarbeit zwischen Teilnehmern.

## Abnahme
- R01: Offline-Bibliothek mit Spaces, Seiten, Unterseiten, Favoriten, Suche, Tags, Papierkorb und Wiederherstellung.
- R02: Verlustfreies Markdown, Schreib-/Quelltextansicht, Fokus, Gliederung, Statistiken, Schreibziele, Tastatur und Accessibility.
- R03: Dauerhafte Speicherung, Autosave, Undo/Redo, Revisionen, Konflikterkennung, Wiederherstellung nach Prozessabbruch.
- R04: Dateien-App Import/Export; Paket, Markdown, HTML, PDF, DOCX, EPUB; zusammenstellbare Manuskripte und Exportprofile.
- R05: Auswahl-/Seiten-/Space-Chat, Streaming, Abbruch, expliziter Kontext und prüfbare KI-Patches ohne Änderungen außerhalb erlaubter Ziele.
- R06: OpenAI API-Key, Anthropic API-Key, Apple PCC und berechtigter ChatGPT-Abo-Login; Fähigkeiten pro Zugang, sichere Credentials, keine stillen Anbieterwechsel. Kommerzieller OAuth-Zugang und PCC benötigen reale Berechtigungsnachweise.
- R07: Slash-Menü, Blockaktionen, Bilder, Visualisierungen, Quellenreferenzen, Prompt- und Assistentenregelblöcke.
- R08: Verankerte Kommentare, Versionsvergleich, Urheberschaft, geteilte Spaces/Seiten mit Rollen und vererbten Rechten, gleichzeitige konfliktarme Bearbeitung.
- R09: Persistente geplante Aufgaben, Budgets, autorisierte lokale Ausführung mit den tatsächlich verfügbaren iOS-Hintergrundmöglichkeiten, kontrollierte Änderungen; optionale Website-Veröffentlichung als Ausbau.
- R10: Adaptive iPhone-/iPad-Fenster, mehrere Dokumentfenster, VoiceOver, Dynamic Type, Hardwaretastatur, Drag-and-drop.
- R11: Qualitätsnachweise für Datenintegrität, lange Dokumente, Unicode, Accessibility, Offline/Fehlerpfade, parallele Änderungen und Provider-Verträge.
- R12: Signierter Release-Archive, Upload, serverseitig abgeschlossene Verarbeitung, Compliance und Zuordnung zur internen TestFlight-Gruppe separat nachgewiesen.

## Architekturentscheidungen
SwiftUI Shell; TextKit Editor; offener Markdown-Inhalt plus stabile Metadaten. Domain-Core ohne UI/Provider-Abhängigkeit. Revision-gebundene Patches. Credentials nur Keychain. Kein Produktionsplaceholder. XcodeGen project.yml ist Projektquelle. iOS 27 Document-API mit Undo und koordinierten Reader/Writer. Bibliotheksindex ist aus Dokumenten rekonstruierbar.

## Erste Arbeitswelle
1. Core: Codable Space/Page/Block/Comment/Revision, Bibliotheksoperationen, sichere atomare Speicherung, revisionsgebundene Patch-Validierung, Tests zuerst.
2. UI: native Bibliotheks-/Space-/Seiten-Shell mit TextKit-Quelltexteditor, Suche, Favoriten, neue Seite, Inspector und Aktionen; eigenes UI-Modell bis Core integriert wird.
3. Release: Xcode-MCP öffnen, SDK/Signierung/Apple-Zugänge feststellen, Projekt erzeugen und App integrieren.
Alle weiteren Anforderungen bleiben offen bis ihre Abnahme nachgewiesen ist.

## Ergänzung professionelle Schreib-App (2026-10-09)
R13–R15 sind verbindlich in PROFESSIONAL_WRITING_PLAN.md definiert: gemeinsame Export-Themes mit Live-Vorschau und Blog-Ausgabe; integrierte Grammatik-/Stilprüfung in 20+ tatsächlich unterstützten Sprachen und KI-Lektorat; geeignete Ulysses-Funktionen für Wissensarbeit und Manuskripte. Die ursprüngliche Abnahme bleibt unverändert.

## Produktfokus (2026-10-12, Vorrang vor der ursprünglichen Gewichtung)
Auf Basis des TestFlight-Feedbacks zu Build 3 ([Feedback](qa-testflight-feedback-20261012/README.md)) legt der Eigentümer fest: Scriptum ist ein Markdown-Editor im Sinn von Ulysses mit Sonderfunktionen für KI. Es ist keine Notion- oder Pages-Nachbildung.

Verbindlich für alle weiteren Arbeiten:
- Die Schreibfläche steht im Vordergrund. Dauerhafte Symbole, Block-Griffe, Leisten und Dialoge treten zurück. Antippen bearbeitet, langes Drücken verschiebt einen Block. Die blockweise Verschiebung bleibt.
- Formatieren geschieht über eine Tastatur-Zusatzleiste (Fett, Kursiv, Überschrift, Liste, Link, Rückgängig, Tastatur schließen). Markdown-Zeichen bleiben im Text, werden aber gedämpft und die Auszeichnung sichtbar gestaltet. Der Text wird dafür nie verändert.
- Die Schreibposition muss beim Tippen immer sichtbar sein, auch mit Tastatur. Wer einen Block wählt, bekommt die Tastatur.
- KI-Aktionen (Lektorat, Überarbeiten, Zusammenfassen) wirken auf die Auswahl, sonst auf den aktiven Block, sonst auf die ganze Seite, ohne Vordialog. Das Ergebnis erscheint als prüfbarer Vorschlag mit Übernehmen und Verwerfen.
- Der Assistent antwortet auf die Aufgabe des Nutzers und gibt nicht den Seitenkontext wieder. Antworten werden lesbar dargestellt.
- Zusammenarbeit, iCloud-Freigaben, geplante Aufgaben und Spaces-Regeln gehören nicht in die primäre Schreiboberfläche. Funktionen bleiben erhalten, solange sie nicht stören.
- Abnahme für diese Punkte erfolgt mit eingeblendeter Software-Tastatur, nicht nur anhand von Frames.
