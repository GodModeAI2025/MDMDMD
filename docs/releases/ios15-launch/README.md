# Scriptum iOS 1.0.1 (15): Startbutton-Kandidat

Korrigiert den gemeldeten Startbutton ohne Reaktion. Der Präsentationsanker sitzt wieder im Szenenhintergrund; Öffnungsanforderungen bleiben bis zur bestätigten Präsentation erhalten. [Ursache, Apple-MCP-Quellen und lokale Prüfungen](../../qa-launch-button-20261015/REPORT.md).

Aus sauberem Quellstand f2ee2b0e97ef138bf10313480fd128e7bdc053a2 archiviert. Release-Archiv mit Swift-Warnungen als Fehler und App-Store-Connect-Export erfolgreich. Alle 25 Distributionsprüfungen der tatsächlich entpackten IPA-App bestehen, einschließlich Signatur, Production-CloudKit, Push und PCC. 15 fokussierte lokale Tests bestehen. Das Archiv erhält die iCloud-Verbindungskorrektur aus iOS14.

**Noch nicht hochgeladen oder in TestFlight verfügbar.** Die konkrete Bildschirmprüfung Appstart → Button → Alle Seiten wartet auf die bereits angefragte eng begrenzte Simulator-Ausnahme. Der bisherige automatische Freigabeblock aus „Gerätetests raus“ wird nicht umgangen. Die TestFlight-Notizen sind nur ein vorbereiteter Entwurf. Lokale Tests und Signaturen belegen keine funktionierende Bildschirmnavigation und keinen Live-iCloud-Abgleich.

Die bisherigen Store-Einreichungen werden nicht zurückgezogen oder ersetzt. Der Mac-Stand bleibt bei Build16. Das vollständige professionelle App-Ziel bleibt offen.

Archive, Export, entpackte App und vollständige Logs sind unter dem in STATE.json genannten Arbeitsverzeichnis erhalten. Ausschließlich der eigene neu erzeugte DerivedData-iOS-Cache wurde nach vollständigem Hash-Abgleich entfernt; derselbe Abgleich wurde danach wiederholt. CLEANUP.json dokumentiert erhaltene Artefakte und freigegebenen Speicher. Gemeinsame Abhängigkeiten bleiben erhalten.
