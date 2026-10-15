# R08: Neue Metadaten einer bestehenden iCloud-Freigabe

Stand: 15. Oktober 2026. Die Änderung wurde lokal implementiert und durch Regressionstests geprüft. Dieser Nachweis bestätigt keine Live-CloudKit-Funktion, keinen Geräte- oder App-Lauf und keine Veröffentlichung.

## Befund und begrenzte Korrektur

Der private Owner-Sync erzeugte neue Kommentar-, Antwort- und Revisionsrecords ohne `CKRecord.parent`. Die initiale Freigabe und der Teilnehmer-Sender setzten diesen nativen Parent bereits. Neue Metadaten des Owners gelangten dadurch nicht in die bestehende Freigabehierarchie.

Der gemeinsame Outgoing-Record-Pfad in `ICloudSyncEngine` setzt jetzt ausschließlich für **neue** Kommentare, Antworten und Revisionen den Parent eines bereits bestätigten Page-/Space-Roots. Dazu wird die kanonische Payload mit Record-ID und Revision abgeglichen und ihre Seiten-ID gegen die vorhandenen nativen Systemfelder aufgelöst. Ein Page-Root trägt seine Freigabe in `share`; eine enthaltene Seite hat einen `parent`, dessen Root die passende `share`-Referenz besitzt.

Vor der lokalen Bereitstellung des Upload-Assets werden das aktuelle Konto, die Seite, der Root und die konkrete `CKShare` erneut gelesen. Identität, Zone, Bibliothek, Art, bestehende Parent-/Share-Verbindung, private Freigabe und Owner-Rolle müssen übereinstimmen. Das Konto und die zwischengespeicherte Verbindung werden anschließend erneut verglichen. Der Root muss bereits auf dem Server existieren. Die neue Parent-Referenz verwendet `.none`.

Alle neuen asynchronen Schritte prüfen die aktuelle Engine und Generation. Nach einer Unterbrechung werden keine alten Assets bereitgestellt; geänderte lokale Revisionen, neue Konflikte und bereits laufende Vorbereitungen werden abgefangen. Vor der Rückgabe wird auch jeder zuvor vorbereitete Batch-Eintrag erneut mit der Outbox verglichen. Eine Serverquittung für neu zugeordnete Metadaten muss den erwarteten Parent bestätigen, bevor der Outbox-Eintrag entfernt wird.

Ein fehlgeschlagener Freigabe-Lookup erhält seine Cloud-Diagnose und lässt die Outbox bestehen. `CancellationError`, CloudKit-Abbruch und überholte Vorbereitung erzeugen keinen Speicherfehler. Bereits für den abgebrochenen Batch angelegte Assets werden freigegeben.

## Apple-Beleg

Der Root-Agent hat Apples Dokumentation über das Xcode-MCP abgefragt. Die vorhandene Antwort ist unverändert als [apple-DocumentationSearch.json](apple-DocumentationSearch.json) erhalten; Originalpfad und SHA-256 stehen in [evidence.json](evidence.json). Dieser Teilauftrag hat keinen weiteren MCP- oder Cloud-Aufruf ausgeführt.

- [Shared Records](https://developer.apple.com/documentation/cloudkit/shared-records): Bei einer Hierarchiefreigabe gehören die Nachfahren des Roots zur Freigabe.
- [CKRecord.parent](https://developer.apple.com/documentation/cloudkit/ckrecord/parent): Die native Parent-Referenz bestimmt die Hierarchie, verlangt `.none` und einen vorhandenen oder im selben Save gespeicherten Parent.
- [CKShare](https://developer.apple.com/documentation/cloudkit/ckshare): Eigene Anwendungsreferenzen ersetzen die native Parent-Beziehung nicht.

## Lokale Prüfnachweise

| Prüfung | Ergebnis | Nachweis |
| --- | --- | --- |
| RED, tatsächlicher gemeinsamer Outgoing-Record-Pfad | Exit 1; Kommentar, Antwort und Revision ohne Parent; 6 fehlgeschlagene Assertions | [red.log](red.log) |
| GREEN einschließlich Negativfälle | Exit 0; 17 Definitionen mit 39 Fällen | [green.log](green.log) |
| Bestehende iCloud-Regressionen mit neuem Testumfang | Exit 0; Testläufe mit 70 und 79 Definitionen | [cloud-regression.log](cloud-regression.log) |
| Owner-Receipts, ursprüngliche Vorbereitung und Manifest-Schutz | Exit 0; 5 Definitionen | [share-scope-regression.log](share-scope-regression.log) |

Die neuen Negativfälle prüfen private Seiten; unveränderte Parent-Zuordnung bestehender Records; keine automatische Freigabe neuer Seiten/Spaces/Bilder; falsche Payload-ID/Revision; fehlende oder fremde Root-/Share-Verbindung; fehlende Owner-Rolle; öffentliche statt privater Freigabe; Stop, lokale Bearbeitung, neu empfangenen Konflikt oder gleichzeitige Vorbereitung während des Lookups; Abbruchbehandlung sowie falsche und richtige Parent-Quittungen. Reine Prüfparameter bilden die schreibgeschützten nativen CloudKit-Felder ab; es werden weder private APIs verwendet noch reale Serverberechtigungen erteilt.

Vor dem tatsächlichen RED scheiterte ein Versuch am nicht schreibbaren Standard-Modulcache. Ein Zwischenlauf der erweiterten Tests scheiterte an der Namensgleichheit von `Testing.Comment` und `SkriptumCore.Comment`; die neuen Tests verwenden anschließend den qualifizierten Typ. Beide Zwischenlogs sind mit Pfad in der Evidenzdatei vermerkt und werden nicht als Verhaltensnachweis gewertet. Die finalen Läufe verwendeten einen bereits vorhandenen lokalen Modulcache.

Die vollständigen Befehle, Exitcodes und SHA-256-Werte der geprüften Quelldateien und Logs sind in [evidence.json](evidence.json) dokumentiert. `git diff --check` für den geänderten Engine-Pfad und die neuen Tests war erfolgreich. `requirements_gap` hat die endgültigen Scope-, Konto-/Generation-, Abbruch- und Quittungsgrenzen unabhängig geprüft und keinen Befund gemeldet; das ist eine Codeprüfung mit lokalen Regressionen, keine Live-CloudKit-Abnahme.

## Bewusst offene Grenzen

- Bereits früher ohne Parent privat gespeicherte und bestätigte Kommentare oder Revisionen werden **auch bei einem späteren Edit** nicht automatisch neu geteilt. Ihr vorhandener nativer Zustand bleibt erhalten. Eine nachträgliche Migration benötigt eine eigene, nachweisbare Freigabeentscheidung.
- Neue Seiten, Spaces und Bildassets werden nicht automatisch einer bestehenden Freigabe hinzugefügt. Diese Änderung erweitert keinen Freigabeumfang.
- Der strenge Manifest-Guard beim erneuten Öffnen einer Owner-Freigabe bleibt unverändert. Sichere Manifest-Erweiterung und Wiederöffnung nach geänderten Inhalten sind eine getrennte offene Aufgabe.
- Die Tests verwenden lokale Records und eine eingesetzte Parent-Auflösung. Konto-/Serverkette und tatsächlicher Empfang bei einem Teilnehmer wurden in diesem Teilauftrag nicht live ausgeführt. Offizielle SDK-Builds und der gemeinsame Integrationslauf werden vom Root-Agent separat dokumentiert.
