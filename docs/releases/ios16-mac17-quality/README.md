# Scriptum 1.0.1 — iOS 16 und nativer Mac 17

Beide Builds stehen seit dem 15. Oktober 2026 in **Mark – Intern** mit dem tatsächlichen Status **Im Test** bereit. Die Gruppe enthält nun 18 Builds. Der [zurückgelesene Gruppenstatus](testflight-group-state.txt) und der [vollständige Screenshot](testflight-group-full.jpg) belegen iOS 16 und Mac 17 getrennt. Der zusätzliche [Bildschirmausschnitt](testflight-group.jpg) zeigt nur Mac 17. Exportcompliance und die deutschen Testnotizen wurden gespeichert und zurückgelesen; der Portalabschluss wurde um 12:39:31 CEST bestätigt.

| Plattform | Build-ID | Upload angenommen (CEST) | Interner Status |
| --- | --- | --- | --- |
| iOS 1.0.1 (16) | `fb3ead1b-b26b-47f2-a6c4-f01d19e0ef26` | 15.10.2026, 12:32:41 | Im Test |
| macOS 1.0.1 (17), nativ | `b689f9f1-c875-41fb-b32b-b02303d7e57f` | 15.10.2026, 12:32:30 | Im Test |

## Enthaltene Korrekturen

Archiviert wurde der saubere Quellstand **9358bde9749d5a18d79d39743467a89d49ffa65f**. [SOURCE.json](SOURCE.json) bindet Versionsnummern und acht relevante Quelldateien. Deren Hashes wurden nach dem Upload erneut sowohl gegen den Arbeitsstand als auch gegen den Commit geprüft; alle stimmen überein ([EVIDENCE_CHECK.json](EVIDENCE_CHECK.json)).

- **Startbutton:** `f2ee2b0e97ef138bf10313480fd128e7bdc053a2` stellt den Szenenhintergrund als Präsentationsanker wieder her und erhält Öffnungsanforderungen bis zur bestätigten Präsentation. 15 lokale Zustands-, Fenster- und Navigationsprüfungen bestanden. Der konkrete Bildschirmablauf bleibt ungeprüft. [Befund und Apple-MCP-Recherche](../../qa-launch-button-20261015/REPORT.md).
- **Unvollständige Textprüfung:** `6530e6db0df73b7d54896daec63eeaec4bb2ef4b` verwirft explizit unvollständige Regelserverantworten einschließlich Teilvorschlägen. Die unveränderten Regressionen schlugen vorher fehl und bestehen nach dem Fix; der damals vollständige Lauf umfasste 68 Definitionen und 89 ausgeführte Fälle. [Nachweis](../../qa-native-completeness-20261015/README.md).
- **Linktexte und Bildbeschreibungen:** `392b71a1e68dee2408eba4474ae0323617c4b3c2` ermöglicht deren Textprüfung bei weiter geschützten Zielen und Markdown-Strukturen. Der abschließende Hauptlauf bestand mit 73 Definitionen und 113 Fällen; danach bestanden zwei zusätzliche Definitionen mit fünf Fällen. Ein einzelner kombinierter Lauf mit 75 Definitionen wird nicht behauptet. [Regressionen und Grenzen](../../qa-quality-link-prose-20261015/REPORT.md).
- **PDF-Überschriften mit Bildern:** `06a48fb6c2bb3dd0a8d8e263c127912f83fa9dc0` setzt interne Sprungziele an das erste sichtbare Bild einer Überschrift. Beide fokussierten Regressionen bestehen; die Export-Suite bestand mit 125 ausgeführten Definitionen und 146 Fällen, bei einem optionalen Skip. Ein erzeugtes PDF wurde zusätzlich unabhängig geparst und visuell geprüft. Die Bildüberschrift besitzt weiterhin kein umschließendes H1-Element; dies ist keine PDF/UA-Zertifizierung. [PDF-Nachweis](../../qa-pdf-image-heading-20261015/REPORT.md).

Die zuvor ausgelieferte iCloud-Verbindungskorrektur aus iOS 14 / Mac 16 bleibt enthalten. Die oben verlinkten Einzelberichte beschreiben ihren damaligen Stand. Ihre damaligen fehlenden SDK-Builds beziehungsweise Uploads werden durch die unten dokumentierten neuen Builds ergänzt. Der ältere lokale iOS-15-Kandidat bleibt unverändert an seinen eigenen Quellstand gebunden und wurde nicht nachträglich umetikettiert.

## Build, Signatur und Upload

Xcode-MCP akzeptierte das bereits geöffnete Projekt beim erneuten Öffnungsaufruf. Die Projektfreigabe ist damit erledigt. Anschließend bestanden der iOS-SDK-Build (6,503 s) und der Mac-SDK-Build (5,207 s), jeweils ohne gemeldete Fehler. Die kleinen MCP-Belege liegen in diesem Verzeichnis. Diese SDK-Builds fanden vor der reinen Aktualisierung der Buildnummern statt; die folgenden Archive entstanden aus dem oben gebundenen finalen Release-Commit.

Beide Release-Archive und beide App-Store-Connect-Exporte endeten erfolgreich. Die App-Ziele wurden mit Swift-Warnungen als Fehler gebaut; in der gepinnten `swift-markdown`-Abhängigkeit verbleiben bekannte Sendable-Warnungen. Ein vollständig warnungsfreier Build wird daher nicht behauptet. Auszüge und Hashes der vollständigen lokalen Logs sind erhalten.

Die tatsächlich exportierten und entpackten Apps bestehen **25 von 25 iOS- und 28 von 28 Mac-Distributionsprüfungen**: Signatur, Profil, Production-CloudKit, Push, PCC sowie native Mac-Plattform und Sandbox. Die Mac-Installer-Signatur einschließlich Apple-Zertifikatskette besteht ebenfalls. Die separate native Grammatik-Erweiterung ist in beiden App-Payloads ausgeschlossen. [iOS-Prüfung](ios-distribution-verification.json), [Mac-Prüfung](mac-distribution-verification.json), [Installer](mac-package-signature.txt).

Beide Uploads endeten mit Exit 0, `Upload succeeded` und `EXPORT SUCCEEDED`; die vollständigen kleinen [iOS-](ios-upload.log) und [Mac-Uploadlogs](mac-upload.log) liegen hier. Die lokalen IPA-/PKG-Hashes in [ARTIFACTS.json](ARTIFACTS.json) identifizieren die separat geprüften Exporte. Xcode paketiert und signiert für den Upload aus denselben Archiven erneut; diese Hashes sind **keine unabhängig nachgewiesenen Empfangshashes der Apple-Payloads**.

## Offene Nachweise und erhaltene Einreichungen

Appstart → „Spaces und Bibliothek öffnen“ → Seitenliste wurde für diese Builds noch nicht im Simulator oder auf dem betroffenen iPhone ausgeführt. Auch ein erfolgreicher Live-iCloud-Abgleich auf diesem iPhone ist nicht belegt. Die eng begrenzte Simulator-Ausnahme bleibt offen; die vom Eigentümer gestrichenen verpflichtenden Gerätetests sind keine zusätzliche Freigabevoraussetzung. Es wurde kein Simulatorstart als Umgehung ausgeführt.

Die vorhandenen Store-Einreichungen **iOS 11** (`4625ac11-3d3e-455a-9db9-395d8766bc2d`) und **Mac 14** (`64c9f5f0-8444-491d-96b6-0e88590a1e10`) bleiben bestehen. Diese interne TestFlight-Auslieferung zieht sie weder zurück noch ersetzt sie sie und ist keine neue Produktionsfreigabe. Das vollständige R01–R15-Ziel einschließlich nativer Sprachprüfung bleibt offen.

Große Archive, Exporte, entpackte Apps und vollständige Buildlogs bleiben lokal unter `work/release-ios16-mac17-quality` erhalten. Das **nach den Uploads** erfasste [Artefaktmanifest](LOCAL_ARTIFACT_MANIFEST.json) umfasst 105 Dateien und 189.399.494 Bytes. Git enthält hier nur die kompakte Quell-/Artefaktbindung, Prüfergebnisse, Notizen und Portalbelege.

Alle 105 Manifestdateien wurden vor und nach der Bereinigung vollständig gegen ihre Hashes geprüft. Entfernt wurden ausschließlich die beiden eigens für diesen Release erzeugten DerivedData-Verzeichnisse mit zusammen 661.792.065 Bytes. Signierte Archive, Exporte, entpackte Prüfpayloads und Nachweise blieben erhalten. [Bereinigungsbeleg](CLEANUP.json).
