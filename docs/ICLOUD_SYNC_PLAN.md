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

CloudKit-Code, Containerberechtigung und Zwei-Geräte-Synchronisation sind derzeit noch nicht umgesetzt bzw. nachgewiesen. Die bisherigen Workspace-Server-Prüfungen belegen diese Anforderungen nicht.

Apple-Referenzen: https://developer.apple.com/documentation/CloudKit/CKSyncEngine-5sie5 und https://developer.apple.com/videos/play/wwdc2023/10188/
