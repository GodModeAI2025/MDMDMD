# CloudKit-Teilen: Fehlerursache und Bild-Assets

Stand: 15.10.2026; lokale Korrektur im gemeinsamen Arbeitsbaum, keine Auslieferung durch diesen Prüfschritt. Vorherige Import- und Freigabeverwaltungsänderungen wurden erhalten.

## Bestätigte Fehler

1. Der bisherige Transport brach beim ersten `saveResults`-Fehler ab. Bei atomaren Saves kann der Root lediglich `batchRequestFailed` (22) tragen, während der eigentliche Share-Fehler später folgt. Die RED-Probe zeigt `CloudKit.22` statt der vorhandenen Ursache12; auch zusätzliche Ergebnis-IDs und doppelte Request-IDs wurden bisher akzeptiert.
2. Der Bildalias erhielt dieselbe `CKAsset`-Instanz wie das kanonische Bild. Die Probe mit einer echten lokalen Payloaddatei löste Apples `NSInvalidArgumentException` aus: „You cannot set the same asset on multiple records“. Der vorherige Test hatte keinen Asset-Payload und konnte den Defekt deshalb nicht erfassen.

## Korrektur

Der Transport sammelt zunächst sämtliche Einzelfehler als `CKError.partialFailure`. Erst wenn kein Fehler vorliegt, akzeptiert er die exakt vollständige Menge eindeutiger erwarteter IDs einschließlich Zonen und Recordtypen sowie genau den erwarteten `CKShare`. Fehlende oder ungültige Erfolgsantworten können eine konkrete Serverablehnung nicht verdecken. Konto-/Abbruch-/Aktualitätsprüfung vor der lokalen Bestätigung, atomarer Save, optimistische Schreibpolicy und expliziter Freigabeumfang bleiben erhalten.

Jeder Bildalias erhält eine eigene `CKAsset(fileURL:)`-Instanz für dieselben unveränderten lokalen Bytes. Fehlende/falsche Payloads werden abgewiesen. Die Regression prüft zwei unabhängige Freigaben desselben kanonischen Bildes ohne Änderung der privaten Ausgangsrecords.

Die Diagnose wertet auch verschachtelte Teilfehler mit maximal acht Ebenen aus. Sichtbar werden ausschließlich feste Fehlercodes und eigene Meldungen, keine Serverbeschreibungen, Recordnamen oder Kontodaten. Code12 verweist auf die nötige Korrektur der App bzw. iCloud-Konfiguration statt einer endlosen Wiederholungsaufforderung.

## Nachweise

- `red.log`: Terminalhandle30032, Exit1, Signal6 der Testunterprozesse wegen des echten CKAsset-Vertragsverstoßes.
- `result-red.log`: Terminalhandle18609, Exit1; sieben Testdefinitionen mit19 Fehlern vor dem Fix. Die unveränderte alte Ergebnisprüfung war dafür lediglich in die intern testbare Methode `savedResult` extrahiert.
- `green.log`: Terminalhandle6363, Exit0; **29 Definitionen /79 Fälle** bestanden. Darin acht neue Ergebnisdefinitionen /24 Fälle sowie der bestehende, nun mit realem Asset ausgeführte Buildertest. Bestehende Reopen-, Account-, Cancellation-, Receipt- und Metadatenprüfungen bleiben grün.
- `FIX.diff` zeigt ausschließlich die drei lokalen Sharing-Korrekturen gegenüber den vor diesem Teilauftrag gesicherten Quellen. Deren SHA256 stehen in `BASELINE_HASHES.json`; die Kopien selbst bleiben unter `work/cloud-share-errors-20261015`. `SOURCE_HASHES.json` bindet die finalen drei Produkt- und zwei Testdateien.
- Unabhängige abschließende lesende Review ohne Befund. `git diff --check` erfolgreich.
- `CLEANUP.json` belegt das gezielte Entfernen der eigenen beim RED-Absturz verbliebenen Testdatei nach Inhaltsprüfung. Logs, Originalquellen und bisherige QA bleiben erhalten.

## Reproduktion

Im Repository ausführen, ohne App-/Simulatorstart oder Cloudzugriff:

```sh
swift test --disable-automatic-resolution --no-parallel --filter 'shareSave|nativeSharePreparation|ownerShare|iCloudDiagnosticsDistinguishAccountStorageAndServiceFailuresWithoutLeakingPayloads'
```

Der protokollierte Lauf nutzte zusätzlich den bereits vorhandenen getrennten Scratch-Pfad `work/markdown-image-import-20261015/swift-build` im Task-Arbeitsverzeichnis. Die beiden RED-Läufe verwenden den damaligen Vorzustand; der finale Stand muss grün sein.

## Apple-Vertrag und Grenzen

Primäre lokale SDK-Belege: `CloudKit.framework/Headers/CKError.h`, Zeilen145–150 (`batchRequestFailed=22` und Auswertung der anderen Einzelfehler); `CKAsset.h`, Zeilen38–42 (separate Assets je Record); `CKShare.h`, Zeilen73–79 und118–127 (private benutzerdefinierte Zone, Parent-Hierarchie, Root und Share in derselben Operation). Gelesen aus dem aktuellen iPhoneOS-SDK unter `/Applications/Xcode.app`.

Die produktive Systemschema-Frage (`cloudkit.share`) und deren Bereitstellung bearbeitet der Hauptagent separat. Der [Apple-Developer-Forums-Bericht840248](https://developer.apple.com/forums/thread/840248) beschreibt ein passendes Fehlerbild; er ersetzt keinen Nachweis des eigenen Containers. Diese lokale QA behauptet weder eine erfolgreiche echte Freigabe noch Teilnehmer-Synchronisation, ein neues SDK-Archiv oder eine TestFlight-/Store-Auslieferung.
