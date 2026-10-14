# Release-Korrekturen vom 14. Oktober 2026

Basis der erneuten Prüfung: `0acb33e`, einschließlich der Weiterarbeit vom 12./13. Oktober. [Ausgangsbefunde](BASELINE_REVIEW.md) beschreiben den Stand vor diesen Korrekturen.

## Behoben

- Neue Bibliotheksseiten erzeugen keine unabhängigen leeren Markdown-Dateien mehr. „Neue Seite“ arbeitet in der Bibliothek; expliziter Markdown-Export schreibt den tatsächlich bearbeiteten Text. Vorhandene Dateien bleiben erhalten. Externe Dokumente behalten ihren eigenen Document-Speicherpfad.
- Tastaturinformationen stammen aus dem konkreten Editorfenster. Eine seitlich liegende schwebende Tastatur löst keine falsche vertikale Überdeckung aus. Geschlossene Editoren und ausdrücklich ausgeblendete Tastaturen beenden geplante Fokusversuche.
- Der Chat speichert, ob eine Änderung übernommen, abgewiesen oder zurückgenommen wurde. Abgewiesener Ersatztext bleibt sichtbar. Rücknahme im Panel prüft auch den vollständigen erwarteten Text. Die Rückgängig-Historie im Editor bleibt beim Wechsel zwischen Block- und Quellansicht erhalten; Fassungen bewahren frühere Texte dauerhaft. Der Folgebereich folgt der Länge des Ersatztexts. Ein inzwischen ungültiger Bereich bringt die Vorschau nicht zum Absturz.
- iCloud liegt direkt unter **Dateien → iCloud**. Das vom Code benötigte Schema fehlte zuvor. Es wurde mit Apples cktool validiert, additiv importiert und in Produktion bereitgestellt. Beide Umgebungen wurden anschließend exportiert und bytegenau verglichen. Keine Benutzerdatensätze wurden gelesen oder geändert. Die neuen Typen haben keine öffentlichen Rollenfreigaben.
- Version 1.0.1 / Build 8 aktiviert den iCloud-Runtime-Schalter. Vorhandene lokale Inhalte und Zugangsschlüssel behalten ihre getrennten Speicherpfade.

## Nachweise und Grenzen

Die komplette lokale Suite besteht: 713 Swift-Testing-Testmeldungen (vier optionale Skips) und 58 XCTest. Der lange gemischte PDF-Manuskript-Test wurde zusätzlich ausdrücklich ausgeführt und besteht. Elf Signierungsverifier-Regressionen bestehen. Xcode-/Archiv-/Distributionsnachweise werden dem tatsächlichen Release separat zugeordnet.

Der Eigentümer hat verpflichtende Geräte- und Mehrgerätetests ausdrücklich aufgehoben. Es gibt hier keinen neuen Geräte-, echten KI-Anbieter- oder Teilnehmer-Synchronisationsnachweis. Lokale CloudKit-Transport-, Konflikt-, Kommentar- und Rechteprüfungen ersetzen diese Laufzeitnachweise nicht. Eine integrierte Grammatik-/Stilprüfung in 20+ Sprachen ist weiterhin keine belegte Produktzusage. Bestehende native Prüfbelege bleiben historisch erhalten.

GitHub bleibt ein Code-Repository ohne Workflows. Signierte Archive und IPAs liegen dauerhaft außerhalb des Quellrepositories; hier stehen Prüfreport, Hash und Auslieferungsstatus.
