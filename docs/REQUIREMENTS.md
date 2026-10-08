# Skriptum — verbindlicher Umfang
Ziel: professioneller nativer Markdown-Editor für Autoren und Wissensarbeiter auf iOS/iPadOS 27, vollständige Pages/Spaces-Arbeitsweise aus den zehn Referenzbildern, verifizierter interner TestFlight-Build. Kein Merkmal gilt durch bloße Existenz einer Oberfläche als fertig.

## Abnahme
- R01: Offline-Bibliothek mit Spaces, Seiten, Unterseiten, Favoriten, Suche, Tags, Papierkorb und Wiederherstellung.
- R02: Verlustfreies Markdown, Schreib-/Quelltextansicht, Fokus, Gliederung, Statistiken, Schreibziele, Tastatur und Accessibility.
- R03: Dauerhafte Speicherung, Autosave, Undo/Redo, Revisionen, Konflikterkennung, Wiederherstellung nach Prozessabbruch.
- R04: Dateien-App Import/Export; Paket, Markdown, HTML, PDF, DOCX, EPUB; zusammenstellbare Manuskripte und Exportprofile.
- R05: Auswahl-/Seiten-/Space-Chat, Streaming, Abbruch, expliziter Kontext und prüfbare KI-Patches ohne Änderungen außerhalb erlaubter Ziele.
- R06: OpenAI API-Key, Anthropic API-Key, Apple PCC und berechtigter ChatGPT-Abo-Login; Fähigkeiten pro Zugang, sichere Credentials, keine stillen Anbieterwechsel. Kommerzieller OAuth-Zugang und PCC benötigen reale Berechtigungsnachweise.
- R07: Slash-Menü, Blockaktionen, Bilder, Visualisierungen, Quellenreferenzen, Prompt- und Assistentenregelblöcke.
- R08: Verankerte Kommentare, Versionsvergleich, Urheberschaft, geteilte Spaces/Seiten mit Rollen und vererbten Rechten, gleichzeitige konfliktarme Bearbeitung.
- R09: Persistente geplante Aufgaben, Budgets, verlässliche autorisierte Serverausführung, kontrollierte Änderungen; optionale Website-Veröffentlichung als Ausbau.
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
