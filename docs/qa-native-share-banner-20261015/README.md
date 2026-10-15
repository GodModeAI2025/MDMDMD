# Nativer Mac-Freigabedialog: Fehlerzustand nach Done

15.10.2026. Enger Fix nach einer vom Hauptagenten beobachteten echten Mac-Freigabe: Dialog geöffnet und erneut geöffnet, danach ein roter allgemeiner Synchronisationsfehler trotz Diagnose `ready /0/0/0 /none`. Die tatsächliche Fehlerdomain des damaligen Callbacks wurde nicht erfasst; deshalb wird nicht behauptet, jener konkrete Fehler sei nachweislich Cocoa3072 gewesen.

## Ursache im Code und Korrektur

`MacPageInspector.swift` schrieb sowohl Vorbereitungsfehler als auch den generischen `didFailToShareItems`-Callback dauerhaft in `library.saveError`. Die Sync-Sitzung verwaltet dagegen `connectionError`/`failureCode` unabhängig und schreibt diesen Bibliotheksbanner nie. Ein später erfolgreicher Sync konnte den fremden Fehlerkanal folglich nicht aufräumen. Der allgemeine Fallbacktext nannte dabei fälschlich Synchronisation statt den Freigabevorgang.

Der Coordinator nutzt jetzt `NSCloudSharingServiceDelegate.sharingService(_:didCompleteForItems:error:)`. Apple dokumentiert diesen Callback ausdrücklich für das Schließen des Cloud-Freigabedialogs; er ersetzt die generischen didFail/didShare-Aufrufe. `nil` ist ein Abschluss ohne gemeldeten Fehler. Ausschließlich `NSCocoaErrorDomain` mit3072 (`NSUserCancelledError`) wird als ausdrücklicher Benutzerabbruch still behandelt. CloudKit20, URL-999, fremde Domains mit3072 und echte Konfigurations-/Speicherfehler bleiben Fehler.

`WritingLibrary.iCloudShareError` ist nun ein eigener beobachteter Zustand. Die drei Methoden Begin/Confirm/Complete binden ihn an einen UUID-Präsentationstoken. Ein bestätigtes aktuelles Öffnen oder erfolgreicher Abschluss räumt nur diesen eigenen Zustand auf. Ein Abbruch vor bestätigtem erneutem Öffnen lässt einen noch ungelösten vorigen Freigabefehler stehen. `saveError` wird weder überschrieben noch auf Sync-Erfolg gelöscht. Die Bannerpriorität bleibt lokale Speicherfehler, dann Freigabefehler, dann Einladungsrouting. Bekannte CloudKit-, Session-, Konto- und Owner-Diagnosen behalten ihre konkrete Meldung; unbekannte native Fehler nennen ausdrücklich die iCloud-Freigabe.

Native Callbacks prüfen den konkreten Service, die ursprüngliche Bibliothek, den Scope, die Session und deren vorhandene Verbindungsrevision. Erfolgs- und Fehlerpfad der asynchronen Vorbereitung verwenden dieselben Kontextprüfungen. Alte Dialoge können daher nach einem Seiten-/Bibliotheks-/Verbindungswechsel keine neue Fehlermeldung eintragen oder eine neue Verbindung synchronisieren. Die Revision ist nur eine lesende Sicht auf die bestehende `generation`; kein neues Verbindungsmodell.

## Prüfung

- `focused-green.log`: Session1184, Exit0, **40 Definitionen /95 Fälle**, inklusive Sharing- und Foreground-Regressionsschutz.
- Danach identifizierte die unabhängige Review zwei eng begrenzte späte Callback-Risiken; beide wurden korrigiert.
- `final-lifecycle.log`: Session64341, Exit0, **14 Definitionen /19 Fälle** auf den finalen Quellen; darin sieben neue Präsentationsdefinitionen /zwölf Fälle. Geprüft werden Done, dokumentierter Abbruch, echte Fehler, Textschutz, lokale Speicherfehler, bestätigter Retry, alte/andere Tokens und `stop`/erneuter Verbindungsversuch mit derselben Sessioninstanz.
- Zwei davor fehlgeschlagene Testkompilierungen wegen einer falsch platzierten Switch-Klammer sind unverändert erhalten (`focused.log`, `focused-final.log`); sie sind keine behaupteten Produkt-RED-Nachweise.
- Abschließender unabhängiger Readback bestätigt beide Reviewkorrekturen ohne Restbefund. `git diff --check` erfolgreich.

```sh
swift test --disable-automatic-resolution --no-parallel --filter 'sharePresentation|unavailableICloudAccountRetryRefreshesDiagnosisAndSharingPreservesItsCode|unprovisionedICloudSessionCannotActivateAfterStopOrCreateSyncFiles|ICloudForegroundRefreshTests'
```

Die protokollierten Läufe verwendeten zusätzlich den vorhandenen separaten Scratch-Pfad `work/markdown-image-import-20261015/swift-build` im Task-Arbeitsverzeichnis. Es wurden weder Apps/Simulatoren noch echte CloudKit-Anfragen durch diese Tests gestartet. Die wirklichen SDK-/Mac-Dialog-Nachweise und die Schema-Bereitstellung verantwortet der Hauptagent separat.

`SOURCE_HASHES.json` bindet vier Produktdateien und die Testdatei. `SDK_HEADER_EVIDENCE.txt` dokumentiert die primären lokal gelesenen Apple-Header samt Hashes und Signaturen. `LIFECYCLE.diff` zeigt die Änderungen gegenüber den vor diesem Teilauftrag gesicherten drei UI-/Library-Quellen; der kleine Diagnose-/Revisionsteil in ICloudLibrarySession ist durch den finalen Quellhash gebunden. Alle Originalkopien und Logs bleiben unter `work/share-banner-lifecycle-20261015`; erfolgreiche Testfixtures räumen sich selbst auf. Keine vorherigen QA-Belege oder Nutzerdaten wurden verändert.
