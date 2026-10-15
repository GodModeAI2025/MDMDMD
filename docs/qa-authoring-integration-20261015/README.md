# Gemeinsame Autoren- und iCloud-Korrekturen

Stand: 15. Oktober 2026, 13:01 CEST. Dieser Stand ist lokal geprüft; er ist noch nicht Bestandteil der zuvor ausgelieferten TestFlight-Builds iOS 16 / Mac 17.

## Enthaltene Änderungen

- [Gliederung](../qa-outline-commonmark-20261015/REPORT.md): Beide nativen Inspektoren verwenden den vorhandenen CommonMark-Parser. Codebeispiele und HTML erzeugen keine falschen Einträge; Setext- und verschachtelte Überschriften erhalten ihre ursprünglichen UTF-16-Sprungpositionen. Ein unveränderlicher, bytegenau verglichener Textstand verhindert veraltete Sprungziele. Die neue Quelldatei ist in beiden Xcode-Zielen registriert.
- [Neue Metadaten bestehender iCloud-Freigaben](../qa-icloud-owner-metadata-20261015/README.md): Neue Kommentare, Antworten und Revisionen erhalten den erneut bestätigten nativen Parent. Konto, Freigabe, Owner-Rolle, Generation, Konflikte und noch ausstehende Revision bleiben gebunden. Abbruch erhält die Outbox. Bereits früher privat bestätigte Metadaten, neue Seiten/Bilder und die Erweiterung vorhandener Freigabemanifeste bleiben außerhalb dieser Korrektur.
- [PDF-Überschriften mit Bildern](../qa-pdf-heading-structure-20261015/REPORT.md): Bild- und Textteile gehören zu genau einer H1–H6-Struktur, während Alternativtexte, Links und Sprungziele erhalten bleiben. Die separat durchgeführte Export-Suite bestand mit 128 ausgeführten Definitionen / 156 Fällen und einem optionalen Skip; eine tatsächlich erzeugte PDF wurde unabhängig gelesen und gerendert. Keine PDF/UA- oder VoiceOver-Zertifizierung.

## Projektverbindung und SDK-Builds

Der vom Eigentümer erneut angeforderte `XcodeOpenWorkspace`-Aufruf war erfolgreich. Xcode verlangte keine erneute Zustimmung. Die bestehende Verbindung lautet `workspace-GU0n2mrDHO`.

Nach `xcodegen generate` wurden die folgenden Aufrufe über Apples offizielles Xcode-MCP ausgeführt:

| Ziel | Ergebnis | Laufzeit |
| --- | --- | --- |
| Skriptum, generisches iOS-Gerät | Erfolgreich; keine gemeldeten Fehler | 8,859 s |
| SkriptumMac, nativer Mac | Erfolgreich; keine gemeldeten Fehler | 7,387 s |

Danach wurde das Ziel auf **Skriptum / Any iOS Device (arm64)** zurückgestellt. Keine App, kein Simulator und kein Gerät wurde gestartet. Die kompakten MCP-Antworten liegen hier; vollständige SDK-Logs sind lokal unter `work/authoring-integration-20261015` erhalten und in `LOCAL_LOGS.json` gebunden. Die Logs enthalten unter anderem den Hinweis zur übersprungenen App-Intents-Metadatenextraktion; ein vollständig warnungsfreier Build wird nicht behauptet.

## Abschließende Integrationstests

`swift test --filter 'SkriptumCoreTests|SkriptumWorkspaceModelTests'` endete mit **Exit 0**. Die zwei Swift-Testing-Zusammenfassungen melden 249 und 182 Definitionen: **428 bestanden**, drei optionale Tests übersprungen. Unter Berücksichtigung der 13 parametrisierten Definitionen mit 46 Fällen wurden **461 Swift-Testing-Fälle** ausgeführt. Dazu bestehen **5 XCTest-Fälle**: insgesamt **466 ausgeführte Fälle**, kein Fehler.

Die drei übersprungenen Tests betreffen den optionalen Produktions-Picker sowie zwei Preisquellen-/Netzwerkprüfungen. Sie werden nicht als ausgeführte Nachweise gezählt. Das vollständige Integrationslog ist erhalten. Die fokussierten Vorher-/Nachher- und Negativnachweise stehen in den oben verlinkten Einzelberichten.

`SOURCE.json` bindet 13 Quell-, Projekt- und Testdateien. Ihre Hashes wurden nach dem Integrationslauf erneut geprüft und blieben unverändert. Der unabhängige Teilreview fand keine zusätzlichen Probleme in der PDF-Struktur oder den Freigabe-, Abbruch- und Quittungsgrenzen des iCloud-Diffs.

## Auslieferungsgrenze

Diese Prüfung erstellt keinen neuen TestFlight-Upload und ändert keine Store-Einreichung. Die vorherigen internen Builds und deren konkrete Portalbelege sind in [iOS 16 / nativer Mac 17](../releases/ios16-mac17-quality/README.md) dokumentiert. Die ausdrücklich beibehaltenen Store-Einreichungen iOS 11 / Mac 14 bleiben bestehen. Der Startbutton und ein erfolgreicher iCloud-Abgleich auf dem betroffenen iPhone sind weiterhin nicht live nachgewiesen; verpflichtende Gerätetests werden daraus nicht abgeleitet. Das gesamte R01–R15-Ziel bleibt offen.
