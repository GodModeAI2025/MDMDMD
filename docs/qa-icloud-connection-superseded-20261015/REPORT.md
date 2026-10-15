# iCloud12: Connection.superseded beim ersten Verbindungsaufbau

15. Oktober 2026 · Eigentümerdiagnose aus iOS1.0.1(12), iOS/iPadOS27.2.0 · Ausgangsstand b770ec0. Neue lokale Korrektur für iOS14/Mac16. Kein Löschen oder Zurücksetzen von App-/CloudKit-Daten und kein Wechsel des iCloud-Kontos.

## Ursache und Apple-MCP-Recherche

Connection.superseded wird von Scriptums eigener ICloudOwnerConnectionChoice.confirm erzeugt. Die App erfasst vor einem asynchronen Verbindungsaufbau eine lokale Freigabe-Revision und prüft sie vor jeder Zulassung erneut. Der Runtime-Key nutzte dabei directory.standardizedFileURL.path.

Beim ersten Aufbau existiert der ICloudSync-Unterordner noch nicht. Die tatsächliche Journalinitialisierung legt ihn an. Foundation kann anschließend beim selben URL-Wert das /private-Präfix aus dem standardisierten Pfad entfernen. Der bisherige berechnete Runtime-Key ändert sich; die App erzeugt unter dem neuen Key eine andere Revision und lehnt ihren eigenen unveränderten Aufbau als überholt ab. Die gezielte Regression erzeugt exakt .superseded, bevor eine CloudKit-Verbindung nötig ist. Die null Zähler der Eigentümerdiagnose passen zu diesem Pfad, beweisen aber nicht allein jeden Aspekt der betroffenen Gerätesitzung.

Die ausdrücklich beauftragte Recherche wurde mit Apples offiziellem Xcode-MCP DocumentationSearch ausgeführt. Apples Foundation-Dokumentation beschreibt die existenzabhängige Standardisierung ausdrücklich. [Apple-Quellen und Rechercheresultat](RESEARCH.md), [Antwort-/Dokumenthashes](APPLE_MCP_SOURCES.json), [unveränderte Eigentümerdiagnose](OWNER_DIAGNOSTIC.txt).

## Korrektur ohne Lockerung der Zulassung

Der Verbindungskey wird jetzt bei der Konstruktion aus einer stabilen physischen Identität des existierenden Vorfahren plus den noch fehlenden Komponenten gebildet. Frische Instanzen erhalten vor und nach Ordnererzeugung dieselbe Identität; Systemalias-Schreibweisen teilen den Disconnect-Fence. Diese Auflösung dient ausschließlich der flüchtigen Runtime-Identität. Die tatsächliche Dateizugriffs-URL bleibt unverändert und wird weiterhin über die bisherigen no-follow-, Eigentümer-, Modus-, Größen- und Revisionsprüfungen geöffnet.

Weder confirm noch Kontowechsel-/Disconnect-Prüfungen werden entfernt, blind wiederholt oder als Erfolg verschluckt. Eine echte veraltete Freigabe wird weiter abgewiesen. Eine fehlgeschlagene persistente Disconnect-Schreiboperation bleibt auch unter Systemaliasen im Prozess gesperrt. Keine neue Migration, Datenlöschung, Rechteänderung, Credential-Operation oder öffentlicher Server.

## Reproduktion und Prüfung

Zwei neue feste Tests scheitern gegen den unveränderten Produktcode mit sechs Issues: echte erste Journalerzeugung zwischen Freigabeaufnahme und Bestätigung sowie Systemalias-/Disconnect-Fence vor und nach Verzeichniserzeugung. Der erste wirft genau .superseded. Danach bestehen die 15 gezielt ausgewählten Verbindungs-/Vordergrundtests. Eine dritte Regression bestätigt zusätzlich, dass ein Symlink-Verzeichnis trotz gleicher physischer Runtime-Identität weiterhin keinen Metadatenzugriff oder Enable erlaubt und die Originalbytes unverändert bleiben.

Beide offiziellen Xcode-MCP-SDK-Builds bestehen ohne Compilerfehler: iOSarm64 und nativer Mac. Die erste vollständige Root-Ausführung wartete später im unveränderten PDF-Export synchron auf Apples FontRegistry-XPC-Dienst; der tatsächliche Prozess-Sample und Logs bleiben erhalten. Nur die exakt identifizierten eigenen Testprozesse wurden nach dieser Diagnose beendet. Der Lauf wird nicht als bestanden ausgegeben.

Anschließend bestehen zwei klar getrennte frische Läufe auf demselben Funktionsstand: die gesamte übrige Suite mit 691 tatsächlich ausgeführten Tests und drei optionalen Skips sowie die isolierte Export-Suite mit explizitem --no-parallel, 123 ausgeführten Fällen und einem optionalen Skip. Zusammen **814 tatsächlich ausgeführte erfolgreiche Tests, vier optionale Skips**. Es wurden keine Tests entfernt oder umgeschrieben, um den ursprünglichen Stillstand zu verbergen. [Zählung und Grenzen](STATE.json).

## Auslieferung und offene Laufzeitgrenze

Die zuvor bereits hochgeladenen iOS13/Mac15-Archive enthalten den alten Runtime-Key und wurden deshalb nach dem neuen Eigentümerfeedback intern nicht freigegeben. Neue korrigierte Archive verwenden iOS14/Mac16. Die bestehende iOS11-Store-Einreichung bleibt wie beauftragt bestehen; keine Einreichung wird hier zurückgezogen oder ersetzt.

Dies ist ein durch Apple-Dokumentation gestützter, real reproduzierter und lokal korrigierter App-Fehler. Ein erfolgreicher Live-Abgleich auf dem betroffenen iPhone wird nicht behauptet. Kein Gerätetest wird zur Releasevoraussetzung gemacht und die frühere automatische Ablehnung nicht umgangen. Der vollständige R01–R15-Umfang bleibt offen.
