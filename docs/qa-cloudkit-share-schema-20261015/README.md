# CloudKit-Freigabeschema in Production

Am 15.10.2026 fehlte `cloudkit.share` sowohl in Development als auch in Production des Containers `iCloud.com.mobilebox.Skriptum`. Die vorhandenen Typen waren `ScriptumItemV1`, `ScriptumSharedImageV1` und `Users`. Die früheren Schemaexporte in `qa-release-20261014` bestätigen diesen Ausgangszustand.

Der [isolierte native Mac-Test](../qa-share-dialog-mac-20261015/README.md) hat eine synthetische Development-Bibliothek synchronisiert und erstmals erfolgreich eine private CKShare-Freigabe angelegt. Dadurch erzeugte CloudKit den Systemtyp `cloudkit.share`. Der tatsächliche native Apple-Dialog ließ sich öffnen und erneut aufrufen; kein Teilnehmer wurde hinzugefügt oder eingeladen.

Die CloudKit Console zeigte anschließend genau eine zusätzliche Record Type Definition: `cloudkit.share` mit neun Feldern und den von Apple erzeugten Rollenrechten für diesen neuen Systemtyp. `ScriptumItemV1`, `ScriptumSharedImageV1`, `Users` und sämtliche Indizes blieben laut vollständigem Diff unverändert. Der Diff wurde vor dem Deployment gespeichert (`deployment-diff.txt`, `deployment-diff.jpg`). Die privaten CKShare-Objekte behalten im App-Code `publicPermission = .none`.

Die additive Schemaänderung wurde in Production bereitgestellt. Apple bestätigte ausdrücklich **Changes Deployed — The schema is deployed to Production** (`deployed.txt`, `deployed.jpg`). Die erneut geladene Production-Ansicht zeigt danach alle vier Typen einschließlich `cloudkit.share` (`production-types.txt`, `production-types.jpg`). Es wurden keine Nutzerdatensätze im Portal gelesen, migriert oder gelöscht.

Damit ist die fehlende Produktionsschema-Voraussetzung behoben. Dies allein beweist weder eine Einladung/Annahme durch ein zweites Konto noch den gesamten Freigabeablauf auf dem betroffenen iPhone. Der separate native Mac-Test fand nach Schließen des Dialogs eine widersprüchliche rote Fehlermeldung trotz bereiter Synchronisation; deren Korrektur wird separat geprüft.
