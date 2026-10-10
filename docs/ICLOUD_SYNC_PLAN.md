# iCloud-Synchronisation

Verbindliche Nutzerentscheidung: kein eigener Cloud-Dienst. Die lokale Bibliothek bleibt die Offline-Arbeitsgrundlage. CloudKit private database und CKSyncEngine übertragen Änderungen zwischen Geräten desselben iCloud-Kontos. Kein zusätzlicher Scriptum-Login, Betreiberendpunkt oder eigener Server.

## Umsetzung

1. Vorhandene Server-Kontooberfläche aus der produktiven Navigation entfernen und durch iCloud-Status ersetzen. Bestehende lokale Dokumente und ihre IDs bleiben unverändert; keine automatische Übertragung vor klarer iCloud-Aktivierung.
2. Dauerhafte lokale Änderungswarteschlange und pro Bibliothek stabile CloudKit-Zone. Eigene Records für Spaces, Seiten, Kommentare und Revisionen; Bilder als CKAssets. Große Markdown-Inhalte ebenfalls als Assets, damit lange Manuskripte keine Record-Grenzen überschreiten. API-Schlüssel, Anbieter-Tokens und private KI-Verläufe werden nicht übertragen.
3. Änderungen erst nach bestätigtem Servererfolg quittieren. CKSyncEngine-Zustand atomar speichern. Offline, erneute Übertragung, Prozessabbruch und abgelaufene Tokens ohne Datenverlust behandeln.
4. Konflikte revisionsgebunden prüfen. Unterschiedliche gleichzeitige Textänderungen als erhaltene Konfliktversionen sichern statt stiller Zeitstempel-Überschreibung. Lokale offene Editierjournale nicht durch empfangene Änderungen überschreiben.
5. iCloud-Abmeldung/Kontowechsel stoppt Übertragung und trennt Sync-Zustand; lokale Inhalte bleiben erhalten. Übertragung in ein anderes Konto erfordert ausdrückliche Aktivierung.
6. CloudKit-Container und Signierungsberechtigungen für com.mobilebox.Skriptum prüfen/konfigurieren; Entwicklungs- und Produktionsschema getrennt nachweisen. CKShare für Freigaben auf Seiten-/Space-Ebene, ohne eigene Kontoverwaltung.
7. Tatsächliche Zwei-Geräte-Prüfung mit demselben iCloud-Konto, Offline-Wiederanlauf, konkurrierenden Änderungen und Bildern; anschließend signierter TestFlight-Build mit Produktionscontainer.

Der private CloudKit-Transport und die lokale Synchronisationsanbindung sind implementiert und lokal geprüft. Containerberechtigung, Produktionsschema und tatsächliche Zwei-Geräte-Synchronisation bleiben unbestätigt. Die bisherigen Workspace-Server-Prüfungen belegen diese Anforderungen nicht.

Apple-Referenzen: https://developer.apple.com/documentation/CloudKit/CKSyncEngine-5sie5 und https://developer.apple.com/videos/play/wwdc2023/10188/

## Freigabehierarchie

`ICloudShareRecordPlan` bestimmt eine eigene Record-Hierarchie je Seiten- oder Space-Freigabe. Nur ausgewählte Seiten, deren Kommentare und historische Revisionen sind enthalten. Der Root hat keinen Parent; weitere Records hängen ausdrücklich unter diesem Root. Bilder erhalten je Freigabe einen stabilen eigenen Alias-Record mit derselben Quellbild-ID. Das kanonische private Bild bleibt außerhalb der Freigaben. So kann ein Bild in zwei getrennt freigegebenen Dokumenten vorkommen, ohne die beiden Hierarchien oder private Seiten zu verbinden.

Diese Entscheidung folgt Apples [CKShare-Hierarchie](https://developer.apple.com/documentation/cloudkit/ckshare) und [Parent-Beziehung](https://developer.apple.com/documentation/cloudkit/ckrecord/parent): CloudKit teilt anhand von `parent`, nicht anhand beliebiger Referenzfelder. Der lokale Record-Plan ist noch keine gespeicherte CKShare-Freigabe. Alias-Übertragung, Aktualisierung/Widerruf, Prüfung überlappender Freigaben, native Einladungsoberfläche und Shared-Database-Transport bleiben erforderlich.
