# Scriptum iCloud-Korrektur — iOS1.0.1(14), nativer Mac1.0.1(16)

Aus sauberem Quellstand **365b0abce3c47d7aa1a2474fc2e19fbc5f8a5ac6** archiviert, einschließlich der durch Apple-MCP-Recherche und feste Regressionen belegten Korrektur für Connection.superseded. [Ursache, Quellen, RED/GREEN und Grenzen](../../qa-icloud-connection-superseded-20261015/REPORT.md).

Die Runtime-Verbindungsidentität bleibt vor und nach dem ersten Anlegen des Sync-Verzeichnisses stabil. Tatsächliche Dateipfade, no-follow-, Account-, Disconnect- und Revisionszulassung bleiben erhalten. Kein Manuskript oder Journal wird gelöscht; weder CloudKit-Konsole noch iCloud-Anmeldung werden geändert. Enthalten sind außerdem die iCloud-Systempfadkorrektur aus Build12, die Aufgabenfortschrittsanzeige und die Fenster-/Aktionsleistenkorrekturen. Die zuvor hochgeladenen iOS13/Mac15 wurden nach dem neuen Fehlerbericht intern zurückgehalten.

## Tatsächliche lokale Freigaben

Beide Release-Archive bauen mit Swift-Warnungen als Fehler, beide App-Store-Connect-Exporte bestehen. Die tatsächlichen exportierten Apps bestehen **25 iOS- und 28 Mac-Distributionsprüfungen**, einschließlich CloudKit-Production, Push, PCC, Signatur/Profil und Mac-Sandbox. Installer-Signatur/Apple-Kette und 13 Verifier-Tests bestehen. Die separate native Grammatik-Erweiterung ist in keinem der beiden App-Payloads enthalten.

Die neue Verbindungskorrektur ist durch drei feste Regressionen abgesichert. Insgesamt bestehen 814 tatsächlich ausgeführte Tests auf demselben Funktionsstand in zwei erfolgreichen Läufen, mit vier optionalen Skips. Der erste vollständige Lauf blieb im unveränderten PDF-Export bei Apples FontRegistry-XPC stehen und wurde nach gesichertem Stack-Sample ausschließlich für die eigenen Testprozesse beendet; er wird nicht als bestanden ausgegeben. Die isolierte Export-Suite bestand danach vollständig im expliziten seriellen Testmodus. Geräte-/Simulatorprüfung ist keine zusätzliche Freigabevoraussetzung und wurde nicht als Umgehung gestartet.

## Upload und interne Auslieferung

Beide Builds sind vollständig verarbeitet. Exportcompliance und die vorbereiteten deutschen Testnotizen sind gespeichert und zurückgelesen. Beide stehen in der bestehenden Gruppe **Mark – Intern** mit je tatsächlichem Status **Im Test** zur Verfügung (ein Tester, nun 16 statt 14 Builds). iOS14 hat die ID 7c60fe9c-8635-46b4-ba88-57e4b0e26979; Mac16 hat die ID 4213c6d5-6131-4c98-b4f1-460fea173dad. Die älteren iOS13/Mac15 wurden nicht zugeordnet. [Gruppenbeleg](internal-group-final.txt), [iOS14](screenshots/ios14-in-test.jpg), [Mac16](screenshots/internal-testflight.jpg), [Status](STATE.json). Die separat lokal geprüften IPA-/PKG-Dateien sind in ARTIFACTS.json gehasht. Der Upload wird aus denselben Archiven erneut paketiert/signiert; die lokalen Exporthashes werden nicht als unabhängig nachgewiesene Empfangshashes von Apple ausgegeben.

Die bestehenden Store-Einreichungen iOS11 (4625ac11-3d3e-455a-9db9-395d8766bc2d) und Mac14 (64c9f5f0-8444-491d-96b6-0e88590a1e10) werden weder zurückgezogen noch ersetzt. Diese interne Auslieferung ist keine neue Produktionsfreigabe. Ein erfolgreicher Live-iCloud-Abgleich auf dem betroffenen iPhone wird weiterhin nicht behauptet; das vollständige R01–R15-Ziel bleibt offen.

Apple nahm beide korrigierten Uploads am 15. Oktober um 11:06:53 CEST (iOS14) und 11:06:58 CEST (Mac16) an. Die Upload-Protokolle und plattformspezifischen Build-IDs sind erhalten.

Große Archive, Exporte, entpackte Apps und vollständige Buildlogs bleiben unter work/release-ios14-mac16-icloud erhalten. Git enthält Quell-/Artefaktbindung, Prüfergebnisse, Notizen und Portalbelege. Rebuildbare, eigens erzeugte Buildcaches können nach vollständigem Hash-Abgleich der erhaltenen Archive/Exporte entfernt werden; bestehende Nachweise und gemeinsame SourcePackages bleiben erhalten.

## Bereinigung mit Erhaltungsnachweis

Der Upload ergänzt in beiden Archive-Info.plists ausschließlich den Distributionsbeleg. Nach Entfernen dieses neuen Feldes ließ sich jeweils der exakte ursprüngliche Datei-Hash rekonstruieren; alle anderen erfassten Artefakte waren unverändert. Das ursprüngliche Manifest bleibt erhalten. Anschließend wurden alle 58 Einträge vor und nach dem Entfernen ausschließlich der zwei eigens erzeugten DerivedData-Verzeichnisse erneut geprüft. 661.168.939 Bytes Buildcache wurden entfernt; Archive, Exporte, Signaturen und gemeinsame SourcePackages bleiben erhalten. [Prüfbeleg](CLEANUP.json).
