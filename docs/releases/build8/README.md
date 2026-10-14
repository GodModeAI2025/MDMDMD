# Scriptum 1.0.1 (8): TestFlight und App-Store-Einreichung

Stand: 14. Oktober 2026. Quellcommit `1b0df605067563ffc7a39febe0f0d4e4bb8fa020`, vollständig in main integriert. [Korrekturen und Regressionen](../../qa-release-20261014/README.md).

## Auslieferung bestätigt

- Finales signiertes Release-Archiv und exportierte IPA; alle 25 tatsächlichen Distributionsprüfungen bestehen. Darunter gültiges App-Store-Profil, Produktions-iCloud, PCC, Push, beide Runtime-Schalter und TestFlight-Fähigkeit. [Verifier](distribution-proof.json).
- Nach der vom Eigentümer erneuerten Xcode-Anmeldung meldet der Upload am 14. Oktober um 19:28:17 `Upload succeeded` und `EXPORT SUCCEEDED`. [Uploadbeleg](upload-success.log). Die vorherigen fehlgeschlagenen Versuche bleiben historisch erhalten.
- Apple hat Build 8 verarbeitet. Build-ID `36b6a084-2d53-464d-8bdb-357dbbac5804`. Exportcompliance „Keinen der oben genannten Algorithmen“ gespeichert, entsprechend der bestehenden Systemverschlüsselung und bisherigen ausdrücklichen Freigabe. Keine zusätzliche eigene Verschlüsselungsbibliothek wurde eingeführt.
- **Mark – Intern zeigt 1.0.1 (8) mit „Im Test“.** [TestFlight-Nachweis](testflight-internal.png). Vorhandener interner Tester bleibt zugeordnet. Installation von Build 8 wurde nicht behauptet und ist nach Nutzerentscheidung keine Pflicht.
- **App-Store-Version 1.0.1 mit Build 8 zur Prüfung eingereicht; Status „Warten auf Prüfung“.** [Einreichungsnachweis](production-submitted.png). Automatische Veröffentlichung nach Apple-Freigabe ist gewählt. Apple-Freigabe und öffentliche Veröffentlichung stehen noch aus.

## Artefakte und Grenzen

Das finale Archiv und die geprüfte IPA liegen dauerhaft in den Pfaden in [STATE.json](STATE.json). [ipa.sha256](ipa.sha256) identifiziert die separat erhaltene verifizierte Export-IPA. Xcode hat für den Upload dasselbe finale Archiv erneut exportiert; upload-mode behält seine IPA nicht im angegebenen Exportverzeichnis. Der lokale IPA-Hash wird deshalb nicht als bytegenauer Hash des Transportpakets ausgegeben. Der Quellstand wurde unmittelbar vor Upload mit der Kandidatenquelle verglichen.

Das Entwicklungsarchiv vor App-Store-Re-Signierung hat kein Produktions-Cloud-Environment; sein separat erhaltener Verifier ist kein Distributionsnachweis. Der erste Kandidat `6e978e8` bleibt getrennt erhalten und ist nicht der finale Build.

CloudKit-Schema wurde bei Apple validiert, additiv in Produktion bereitgestellt und anschließend mit Development bytegenau verglichen. Neue Recordtypen haben keine öffentlichen Rollenfreigaben. In der Console ist derzeit keine weitere Änderung erforderlich. Aktivierung in der App: **Dateien → iCloud → iCloud aktivieren**. Dies beweist Konfiguration und Berechtigungen, nicht eine neue tatsächliche Teilnehmer-Synchronisation.

Physische Geräte-, Device-Interaction- und Mehrgerätetests sind auf ausdrücklichen Nutzerwunsch keine Pflicht. Echte KI-Anbieter-/Regions- und Teilnehmer-Synchronisationsnachweise sind weiterhin getrennte Grenzen; eine integrierte Grammatik-/Stilabdeckung in 20+ Sprachen wurde nicht zugesagt.

## Gesonderte Jimdo-Arbeit

Die veröffentlichte Datenschutzseite hat beim letzten aktuellen Browser-Readback keinen Scriptum-Abschnitt. [DE/EN-HTML](../../legal/privacy-policy.website.html) ist vorbereitet und der In-App-Link vorhanden. Der Eigentümer hat ausdrücklich entschieden: Jimdo wird gesondert bearbeitet. Kein Jimdo-Kontozugriff oder Website-Änderung in dieser Auslieferung. Dieser offene Punkt bleibt sichtbar; die beauftragte Apple-Einreichung ist davon getrennt durchgeführt.
