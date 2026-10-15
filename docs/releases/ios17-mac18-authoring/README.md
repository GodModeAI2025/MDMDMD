# Scriptum 1.0.1 — iOS 17 und nativer Mac 18

Beide Builds sind seit dem 15. Oktober 2026 in **Mark – Intern** mit dem tatsächlichen Status **Im Test** verfügbar. Die Gruppe enthält nun 20 Builds. Verarbeitung, Exportcompliance und deutsche Testnotizen sind abgeschlossen. Der Portalstatus wurde um **13:18:45 CEST** zurückgelesen: [Gruppenstatus](testflight-group-state.txt), [kompakter Screenshot beider Builds](testflight-current-builds.jpg), [vollständiger Screenshot](testflight-group-full.jpg).

| Plattform | Build-ID | Upload angenommen (CEST) | Interner Status |
| --- | --- | --- | --- |
| iOS 1.0.1 (17) | `ac8a0001-1fcd-4c7d-b0d7-ccb3bd236f26` | 15.10.2026, 13:14:13 | Im Test |
| macOS 1.0.1 (18), nativ | `38080dd3-f198-4066-bde4-473e5855030f` | 15.10.2026, 13:14:20 | Im Test |

## Quellstand und Änderungen

Die Release-Archive entstanden aus dem sauberen Commit **05841db91be6b9f1e02e117e96788e39cc077b4e**. [SOURCE.json](SOURCE.json) bindet elf Quell-/Projektdateien; [EVIDENCE_CHECK.json](EVIDENCE_CHECK.json) prüft sie gegen Commit und aktuellen Arbeitsbaum.

- **Gliederung:** Beide nativen Inspektoren nutzen den CommonMark-Parser. Code/HTML erzeugen keine falschen Überschriften; unterstrichene und verschachtelte Überschriften erhalten korrekte ursprüngliche Sprungpositionen. [Regressionen](../../qa-outline-commonmark-20261015/REPORT.md).
- **PDF:** Bild- und Textteile einer Überschrift gehören zu einer gemeinsamen H1–H6-Struktur; Alternativtexte, Links und Sprungziele bleiben erhalten. [PDF-Nachweis](../../qa-pdf-heading-structure-20261015/REPORT.md).
- **iCloud-Freigaben:** Neue Kommentare, Antworten und Revisionen auf bereits geteilten Seiten erhalten nach erneuter Konto-/Owner-/Share-Prüfung den vorhandenen nativen Parent. Abbruch und zwischenzeitliche Änderungen erhalten ausstehende Daten. Bereits privat bestätigte Metadaten werden nicht nachträglich geteilt; neue Seiten/Bilder erweitern vorhandene Freigaben nicht automatisch. [Regressionen und Grenzen](../../qa-icloud-owner-metadata-20261015/README.md).
- **Privacy-Manifest:** Die produktiven Datei-Metadatenzugriffe sind jetzt als `NSPrivacyAccessedAPICategoryFileTimestamp` mit `C617.1` für eigene Container und `3B52.1` für ausdrücklich freigegebene Dateien erklärt. `CA92.1` für UserDefaults bleibt enthalten. Die tatsächlich exportierten Apps enthalten das bytegleiche Manifest; Tracking bleibt deaktiviert. [Payload-Prüfung](PAYLOAD_CHECKS.json), [Apple-Gründe](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype).

Die zuvor ausgelieferten Korrekturen für den Startbutton und die iCloud-Verbindungsidentität bleiben enthalten. Die Forschungsarbeit zur nativen Grammatik aktiviert keine zusätzliche Engine im ausgelieferten Produkt.

## Prüfung und Auslieferung

Der [Integrationsnachweis](../../qa-authoring-integration-20261015/README.md) bindet erfolgreiche offizielle Xcode-MCP-SDK-Builds für iOS und nativen Mac sowie **466 ausgeführte Core/Workspace-Fälle** bei drei optionalen Skips. Die separate Export-Suite besteht mit **156 Fällen** und einem optionalen Skip. Version-/Projektmetadaten und Privacy-Manifest wurden anschließend aktualisiert; die getesteten Implementierungen sind unverändert. [Unabhängiger Release-Preflight](INDEPENDENT_PREFLIGHT.md).

Beim auf Wunsch erneut ausgeführten `XcodeOpenWorkspace` wurde das Projekt direkt verbunden. Xcode verlangt aktuell keine zusätzliche Freigabe; es wurde kein neuer Zustimmungsdialog beobachtet. Die beiden kompakten Projektverbindungsantworten liegen hier. Keine App, kein Gerät und kein Simulator wurde in dieser Auslieferungsrunde gestartet.

Beide Release-Archive, beide Exporte und beide Uploads endeten erfolgreich. App-Ziele wurden mit Swift-Warnungen als Fehler gebaut. Die vollständigen Logs enthalten bekannte Sendable-Warnungen der gepinnten Markdown-Abhängigkeit und Hinweise zur App-Intents-Metadatenextraktion; ein warnungsfreier Build wird nicht behauptet. Logauszüge und Hashes sind erhalten.

Die tatsächlich exportierten Apps bestehen **25/25 iOS- und 28/28 native Mac-Distributionsprüfungen**, einschließlich Signatur, Profil, Production-CloudKit, Push, PCC und nativer Mac-Sandbox. Auch die Mac-Installer-Signatur besteht. Die separate native Grammatik-Payload bleibt ausgeschlossen. Die Privacy-Manifeste wurden zusätzlich gegen die Quelle gelesen; diese Kontrolle ist separat vom Signaturprüfer dokumentiert.

[ARTIFACTS.json](ARTIFACTS.json) bindet die lokal geprüften IPA-/PKG-Dateien. Xcode paketiert/signiert für den Upload aus denselben Archiven erneut; dies sind keine unabhängig nachgewiesenen Empfangshashes der von Apple verarbeiteten Payloads. Die vollständigen kleinen Uploadlogs liegen hier.

## Grenzen und Erhaltung

Der konkrete Ablauf Appstart → „Spaces und Bibliothek öffnen“ → Seitenliste und erfolgreicher iCloud-Abgleich auf dem betroffenen iPhone bleiben live ungeprüft. Die ausstehenden optionalen Simulator-/Gerätebelege werden nicht als zusätzliche Freigabevoraussetzung behandelt. Die bestehenden Store-Einreichungen **iOS 11** und **Mac 14** wurden weder zurückgezogen noch ersetzt. Diese interne TestFlight-Auslieferung ist keine neue Store-Einreichung, App-Review-Genehmigung oder Veröffentlichung.

Das gesamte R01–R15-Ziel bleibt offen. Als nächster konkreter iCloud-Punkt ist die Verwaltung einer bereits bestehenden Freigabe nach normaler Bearbeitung zu korrigieren: Der vorhandene Manifest-Abgleich kann derzeit die Wiederöffnung verhindern. Neue Inhalte dürfen dabei nicht ungefragt geteilt werden. Markdownimport relativer Bilder und die umfassende native Sprachprüfung bleiben ebenfalls offen.

Archive, Exporte, entpackte Prüfpayloads und vollständige Logs bleiben lokal unter `work/release-ios17-mac18-authoring` erhalten. Das nach den Uploads erstellte [Artefaktmanifest](LOCAL_ARTIFACT_MANIFEST.json) umfasst **105 Dateien / 190.156.568 Bytes**. Alle Dateien wurden vor und nach der Bereinigung vollständig gehasht. Entfernt wurden ausschließlich die zwei eigenen DerivedData-Verzeichnisse mit **662.850.701 Bytes regulärem Dateiinhalt**. [Bereinigungsbeleg](CLEANUP.json).
