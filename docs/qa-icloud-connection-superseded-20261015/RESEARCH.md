# Apple-MCP-Recherche zum neuen iCloud-Fehler

Die vier tatsächlichen DocumentationSearch-Aufrufe erfolgten über Apples offizielles Xcode-MCP. Die vollständigen Antworten bleiben lokal in work/review-release-20261014; APPLE_MCP_SOURCES.json bindet Antwortdateien und Dokumentinhalte mit SHA256.

## Maßgebliche Apple-Aussage

[NSURL.standardizingPath](https://developer.apple.com/documentation/foundation/nsurl/standardizingpath) und [NSString.standardizingPath](https://developer.apple.com/documentation/foundation/nsstring/standardizingpath) beschreiben, dass ein /private-Präfix abhängig vom tatsächlichen Vorhandensein des resultierenden Dateisystemziels entfallen kann. [URL.standardizedFileURL](https://developer.apple.com/documentation/foundation/url/standardizedfileurl) liefert einen standardisierten Dateipfad. Daraus darf keine vom Erstellungszustand unabhängige Verbindungsidentität abgeleitet werden.

Die lokale Foundation-Gegenprobe auf macOS27 zeigt denselben unveränderten URL-Pfad vor/nach Anlegen von Support/ICloudSync, aber unterschiedliche standardizedFileURL.path-Werte. Der neue Regressionstest verwendet danach die tatsächliche ICloudSyncJournal-Erstellung in der Verbindungsreihenfolge. Das bisherige Produkt erzeugt dabei Connection.superseded. Dies ist unser App-Fehler, kein CKError von Apple.

## CloudKit-Kontext

[CKSyncEngine](https://developer.apple.com/documentation/cloudkit/cksyncengine-5sie5) beschreibt lebenszyklusübergreifend gespeicherten Engine-Zustand sowie gezielte sendChanges/fetchChanges für unmittelbaren Abgleich; der automatische Zeitplan ist nicht garantiert. [CKAccountChangedNotification](https://developer.apple.com/documentation/cloudkit/ckaccountchangednotification) beschreibt Kontostatusänderungen und deren erneute Statusabfrage. Keine dieser Dokumentationen erklärt unseren eigenen Superseded-Code als Anlass, den Nutzer pauschal bei iCloud ab-/anzumelden oder CloudKit zurückzusetzen.

Die jetzige Korrektur bleibt deshalb beim nachgewiesenen lokalen Identitätsfehler. Sie ändert keine Kontozulassung, keine CloudKit-Rechte, keine Datenbank und keine Journale. Kontowechsel- und Disconnect-Fences werden weiterhin geprüft. Apples Hinweise zum Entfernen kontofremder lokaler Cloud-Caches werden nicht als Auftrag zum Löschen lokaler Manuskripte interpretiert.
