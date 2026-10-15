# iCloud mit umfangreicher Fassungshistorie

15. Oktober 2026 · Aufbau auf `2c595ef`. Ausschließlich eigene synthetische Daten.

## Reproduzierter Fehler und Korrektur

Ein gültiger Sync-Projektionscheckpoint unter 64 MiB konnte bei der Ablage seiner Warteschlange scheitern: Binäre Nutzdaten werden dort als Base64 in JSON kodiert und überschreiten dadurch die bisher ebenfalls auf 64 MiB begrenzte Transportdatei. Derselbe Fehler betraf den dauerhaft gespeicherten Eingang. Dies ist keine Behauptung einer allgemeinen 64-MiB-Grenze für jede Bibliothek.

Zwei Regressionen reproduzierten den Fehler zunächst: ein Manuskript mit sechs historischen Fassungen scheiterte mit `capacityExceeded`; sieben eingehende 7-MiB-Datensätze scheiterten mit `capacity`. Die dauerhaften privaten Transportdateien erlauben jetzt 128 MiB einschließlich Kodierung. Die bisherigen Grenzen pro Datensatz, Bild, Netzwerkbatch (64 MiB) und Datensatzanzahl bleiben bestehen. Andere Nutzer derselben Dateihilfe behalten ihren bisherigen 64-MiB-Standard.

Die Übergabe eines Dokumentzustands an die Warteschlange und die Quittierung eines CloudKit-Batches erfolgen jeweils gesammelt. Das vermeidet wiederholte vollständige JSON-Schreibvorgänge für jede einzelne Fassung. Erst nach vollständiger Validierung und erfolgreicher Speicherung werden die exakt bestätigten Fassungen quittiert. Neuere lokale Bearbeitungen bleiben erhalten; ungültige Bestätigungen oder fehlgeschlagene lokale Schreibvorgänge entfernen keine ausstehenden Änderungen. Tests prüfen diese Fehler- und Konkurrenzfälle.

## Reale native Production-Prüfung

Eine DEBUG-Fixture erzeugte über die öffentlichen LibraryStore-Operationen eine Seite mit etwa 585 kB synthetischem Text und 90 gespeicherten Fassungen. Enthalten sind deutsche Umlaute, ein zerlegter Akzent, Emoji und CRLF. Der eigene importierte Bibliotheksbereich ist von der primären Nutzerbibliothek getrennt. Anfangs zeigte die Aktivierung **92 ausstehende Änderungen**.

Die vorhandene native Mac-Debug-App wurde mit der bestehenden Entwickleridentität und dem vom Profil erlaubten Production-Entitlement geprüft. Der tatsächliche Sync durchlief die private CloudKit-Produktionsdatenbank und endete mit **Status ready, ausstehend 0, empfangen 0, Konflikte 0, Fehler none**. AX- und Bildschirmnachweise liegen hier. Der Lauf dauerte mehrere Minuten; ein zwischenzeitlicher Fortschrittsindikator wurde nicht vorschnell als Erfolg oder Deadlock bewertet. Nach Abschluss wurde die QA-App regulär beendet; Xcode hat anschließend die normale Debug-Signatur wieder aufgebaut. Der temporäre Production-Override ist entfernt, Entwicklungspush ist gesetzt und die tiefe strenge Signaturprüfung besteht (`DEBUG_RESTORED.json`).

Es wurden keine persönlichen Texte übertragen und keine bestehende Benutzerzone, Freigabe oder Schemaeinstellung zurückgesetzt. Der eigene Testbereich bleibt zur Nachprüfbarkeit erhalten. Dieser Lauf belegt weder einen zweiten Empfang des großen Manuskripts noch zwei Geräte, den betroffenen iPhone-Build, TestFlight oder CKShare. Der getrennte kleine Production-Empfang aus einem leeren lokalen Speicher ist in `../qa-icloud-feedback-20261015/REPORT.md` dokumentiert.

## Verifikation

- Betroffene Modelltests: **128 bestanden**, keine übersprungen.
- Vollständige Root-Suite: **803 tatsächlich ausgeführte Tests bestanden** (745 Swift Testing und 58 XCTest); vier optionale Tests wurden übersprungen. Die gemeldeten Swift-Testing-Zahlen enthalten diese vier und werden nicht als ausgeführt gezählt.
- Rote Ausgangsprotokolle und vollständige grüne Protokolle sind lokal unter `work/icloud-manuscript-20261015` erhalten; Größen und SHA-256 stehen in `CHECKS.json`. Prozess-Samples und allgemeine Systemlogs bleiben ausschließlich lokal und werden nicht ins Git aufgenommen.

- Endgültiger nativer Mac- und generischer iOS-arm64-Build über Xcode MCP bestanden (`MAC_MCP_BUILD.json`, `IOS_MCP_BUILD.json`). Release-Archivierung und Distribution werden separat dokumentiert.

## Bezug zur aktuellen Nutzerfehlermeldung

Der Nutzer hat präzisiert, dass der angebliche Menüpunkt gar nicht sichtbar war und „Spaces und Bibliotheken öffnen“ direkt einen Text öffnet. Das ist ein eigenständiger, im iPhone-Code nachvollzogener Einstieg-/Navigationsfehler. Seine Korrektur und tatsächliche Simulatorprüfung werden in `../qa-icloud-entry-20261015/REPORT.md` dokumentiert. Die neuen TestFlight-Feedbackeinträge selbst konnten wegen der weiterhin erforderlichen App-Store-Connect-Anmeldung noch nicht gelesen werden. Kein erfolgreicher Mac-Test wird als Beweis für den betroffenen iPhone-Sync ausgegeben.
