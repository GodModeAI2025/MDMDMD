# Scriptum 1.0.1 (8): finaler Release-Kandidat

Quellcommit `1b0df605067563ffc7a39febe0f0d4e4bb8fa020`, auf main integriert. Korrekturen und lokale Regressionen: [Prüfbericht](../../qa-release-20261014/README.md).

## Bestätigt

- Finales signiertes Release-Archiv erfolgreich erstellt; App-Store-IPA erfolgreich exportiert. Alle 25 tatsächlichen Distributionsprüfungen bestehen: unter anderem gültiges Store-Profil, Produktions-iCloud, PCC, Push, beide Runtime-Gates und TestFlight-Fähigkeit. [Verifier](distribution-proof.json). Das Entwicklungsarchiv vor Re-Signierung weist kein Produktions-Cloud-Environment auf; dessen Verifierresultat ist separat erhalten und kein Distributionsnachweis.
- Die final exportierte IPA und das Archiv liegen dauerhaft im in [STATE.json](STATE.json) angegebenen Arbeitsverzeichnis. SHA256 steht in [ipa.sha256](ipa.sha256). Der frühere Kandidat `6e978e8` bleibt getrennt erhalten und ist nicht der finale Upload-Kandidat.
- Apple CloudKit: Schema validiert, additiv nach Produktion bereitgestellt, nachgelesen und mit Development identisch. Neue Typen ohne öffentliche Rollenfreigaben.
- App Store Connect: 1.0.1 angelegt, Versions- und Prüfinformationen gespeichert; automatische Veröffentlichung nach Freigabe gewählt und gespeichert. [Screenshot](production-draft.png). Der Build ist noch nicht ausgewählt.

## Tatsächliche Auslieferungsgrenze

Der Upload schlägt mit „App Store Connect access for SP73Z8JWXM is required“ fehl. Der zweite Versuch erlaubt die reguläre Aktualisierung der bestehenden Xcode-Kontositzung und schlägt gleichfalls fehl. [Fehlernachweis](upload-failure.log). Keine neue Anmeldung oder Vertragsannahme wurde durchgeführt.

Build 8 ist daher **noch nicht hochgeladen, verarbeitet, TestFlight zugewiesen oder zur Produktionsprüfung eingereicht**. Eine Signatur oder ein vorbereiteter Store-Entwurf ersetzt diese Schritte nicht. Die bereits als „Bereit für Vertrieb“ angezeigte Version 1.0.0 (7) ist davon getrennt.

Nächste Schritte nach erneuerter Xcode-Anmeldung: finalen Build 8 hochladen, Apple-Verarbeitung bestätigen, erforderliche Exportcompliance anhand der unveränderten Systemkryptografie ausfüllen, Mark–Intern zuweisen und nachlesen. Danach Build 8 im Produktionsentwurf auswählen und zur Prüfung einreichen. Hardware- und Mehrgerätetests sind ausdrücklich keine Pflicht.

Zusätzlich: Der Account Holder muss Apples Hinweis zum aktualisierten Paid Applications Schedule bearbeiten. Der vorbereitete [Scriptum-Datenschutzabschnitt DE/EN](../../legal/privacy-policy.website.html) muss auf der vorhandenen öffentlichen Datenschutzseite ergänzt werden; im aktuellen Browser-Readback fehlt Scriptum. Der In-App-Link ist vorhanden. Keine falsche Null-Datenerfassungs-, 20-Sprachen- oder Laufzeit-Aussage ergänzt.
