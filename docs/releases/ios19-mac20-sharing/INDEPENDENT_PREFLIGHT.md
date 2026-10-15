# Unabhängiger Release-Preflight: iOS 19 / Mac 20

Stand: 15. Oktober 2026. Geprüfter Commit: `9e23018715740189994f7fb66580c4beb74e7b07`.

Kein konkreter Releaseblocker innerhalb der geprüften Quellbindung und Nachweiskette gefunden. Prüfung ausschließlich lesend; lediglich dieser Bericht wurde neu angelegt. Keine Tests, Builds, Appstarts oder Portalaktionen ausgeführt.

## Quellbindung

Die SHA-256-Werte wurden unabhängig sowohl gegen die Dateien im Arbeitsbaum als auch gegen die jeweiligen Git-Blobs des angegebenen Commits berechnet. Der Arbeitsbaum war vor Erstellung dieses Berichts sauber.

| Nachweis | Ergebnis |
| --- | --- |
| `../../work/release-ios19-mac20-sharing/SOURCE.json` (ab Repository-Wurzel) | 45 von 45 Dateien stimmen mit Commit und Arbeitsbaum überein; iOS 19, Mac 20, `cleanAtArchiveStart: true` |
| `docs/qa-native-share-banner-20261015/SOURCE_HASHES.json` | 5 von 5 Dateien stimmen überein, einschließlich finaler Lifecycle-Implementierung und Regressionstests |
| `docs/qa-share-dialog-completion-20261015/FINAL-COMPILE-SOURCE.json` | 176 von 176 Dateien stimmen überein; kein Quellenwechsel während des finalen Mac-SDK-Compiles dokumentiert |

Der finale Mac-Buildlog endet mit `BUILD SUCCEEDED`. Der dort dokumentierte Binary-Hash wurde in diesem Preflight nicht erneut am lokalen Buildprodukt verifiziert; bestätigt ist hier die Quellbindung des gespeicherten SDK-Nachweises.

## Nachvollziehbare Grenzen der Tests und UI-Prüfung

- Der vollständige Lauf dokumentiert 862 bestandene Testdefinitionen, 1.098 Swift-Testing-Fälle und 58 XCTest-Fälle bei vier expliziten optionalen Skips und Exitcode 0. Sein `FULL_SUITE_SOURCE.json` passt in 42 von 45 Dateien zum finalen Commit. Die genau drei Abweichungen sind `ICloudLibrarySession.swift`, `MacPageInspector.swift` und `ICloudSharePresentationTests.swift`; sie gehören zu den anschließenden Guards gegen verspätete Callbacks und ihren Tests. Der vollständige Lauf wird deshalb nicht als Lauf des finalen Quellstands ausgegeben.
- Für diesen finalen Stand liegen der erfolgreiche fokussierte Lifecycle-Lauf mit 14 Definitionen und 19 Fällen sowie die oben geprüften fünf Quellenhashes vor. Das gespeicherte `final-lifecycle.log` bestätigt den erfolgreichen Abschluss. Die beiden vorherigen Compilefehler der neuen Tests bleiben im QA-Verzeichnis erhalten und sind nicht als erfolgreiche Läufe gezählt.
- Die native Mac-Prüfung hat zwei reale Öffnen/Done-Zyklen des bestehenden Development-Freigabedialogs ohne roten Fehlerbanner und jeweils `ready`, `none`, Zähler 0/0/0 dokumentiert. Sie gehört zum Binary aus `SOURCE-BEFORE.json`. `SOURCE-AFTER.json` benennt genau die beiden anschließend geänderten Produktdateien. Der finale Guard-Stand wurde erfolgreich kompiliert, aber nicht erneut gestartet. Die dokumentierte Trennung ist konsistent.
- Der iPhone-Simulator-Nachweis zum Startbutton gehört zu Kandidat 2 vor dem nachfolgenden Cleanup; `docs/qa-launch-runtime-20261015/FINAL_SOURCE_REVIEW.md` begrenzt den abschließenden Nachweis auf statische Prüfung. Daraus folgt kein zusätzlicher physischer Geräte-, iPad-Mehrfenster- oder TestFlight-Lauf.

Archive, Distributionsexporte, Upload, Verarbeitung und Storestatus sind eigene Nachweise. Dieser Bericht bestätigt keinen Upload oder Veröffentlichungsstatus und fordert keine zusätzlichen Gerätegates.
