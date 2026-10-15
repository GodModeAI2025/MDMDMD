# Bestehende iCloud-Freigaben nach Bearbeitung verwalten

Eine bestätigte Seiten- oder Space-Freigabe wurde zuvor erneut gegen den vollständigen ursprünglichen Manifestumfang geprüft. Schon eine normale Bearbeitung mit neuer Revision, ein Kommentar oder eine Unterseite konnte deshalb `changedManifest` auslösen und die Personenverwaltung verhindern.

Der neue Verwaltungszweig wählt den bestätigten, konto- und bibliotheksgebundenen Receipt über den weiterhin vorhandenen Root. Er liest die tatsächliche native CloudKit-Freigabe erneut, ohne Inhalte, Parents, Receipt oder optimistische Serverfelder zu schreiben. Die exakte Manifestbarriere bleibt für eine neue oder noch unbestätigte Freigabe bestehen. Neue Seiten und Bilder erweitern die Freigabe nicht automatisch; die bereits ausgelieferte separate Synchronisation neuer Kommentare/Revisionen bleibt bestehen.

## Apple-Nachweis

Die offizielle Xcode-MCP-Dokumentationssuche ist unverändert gespeichert. Apple beschreibt den [Initializer für eine vorhandene UICloudSharingController-Freigabe](https://developer.apple.com/documentation/uikit/uicloudsharingcontroller/init(share:container:)) mit der gespeicherten CKShare; der Root liefert deren native Share-Referenz. Der iOS-Dialog verwendet diesen Initializer bereits. Der korrigierte Vorbereitungspfad liefert nun diese bestehende Share auch nach gewöhnlichen Bearbeitungen. Der native Mac verwendet weiterhin NSSharingService mit derselben geprüften Share.

## Regression und Grenzen

- `receipt-red.log` reproduziert `changedManifest` für Seite und Space. Für diesen RED-Lauf wurde die vorherige Plan-/Digest-Aufnahme in die neue `managementOperation`-Methode extrahiert; es war **kein unveränderter Build des alten HEAD**. `transport-red.swift` bewahrt diese Variante, `receipt-regression.swift` die unveränderte anfängliche Regression.
- `receipt-green.log` zeigt dieselben beiden Fälle nach der Korrektur sowie den weiter strikten Retry-Fall grün.
- `management-tests-v2.log` enthält 25 erfolgreiche Testdefinitionen beziehungsweise 59 tatsächlich ausgeführte Fälle. Sie prüfen frische Root-/Share-Identität, beide Accountabfragen mit bytegenauem Unicodevergleich, Unterbrechung vor und nach jedem der sechs Lesevorgänge, abschließenden Actor-Await, zwischenzeitlichen Papierkorb und Disconnect aus einer zweiten Instanz einschließlich gescheiterter Persistenz. Der spätere Integrationslauf ergänzt den Bildalias-Payloadtest.
- Die Testadapter projizieren schreibgeschützte native Share-/Owner-Felder explizit. Sie manipulieren keine privaten CloudKit-Felder und rufen keine echten Konten auf.
- Die unabhängige statische Zweitprüfung fand zunächst eine fehlende Abbruchprüfung nach dem abschließenden Actor-Await und einen zu weit gefassten Cancellation-Catch. Beide sind korrigiert und durch die abschließende Zweitprüfung ohne verbleibenden konkreten Befund gelesen. Das ist kein Live-CloudKit-Nachweis.

Der Verwaltungsweg benötigt einen lokal bestätigten Receipt. Übernahme einer Freigabe auf einem anderen Eigentümergerät ohne diesen Receipt, explizite Erweiterung bestehender Freigaben und eine neue Freigabe nach vollständigem Widerruf sind durch diesen Schritt nicht umgesetzt. Serveränderungen nach der letzten Abfrage können weiterhin auftreten; die Leseabfolge ist keine atomare CloudKit-Transaktion.

Die auf Nutzerwunsch erneut ausgeführte Xcode-Projektanfrage war erfolgreich. Xcode verband das Projekt direkt; ein neuer Freigabedialog wurde nicht beobachtet. Keine App, kein Gerät und kein Simulator wurde für diese Prüfung gestartet. Der genaue betroffene iPhone-Ablauf bleibt live ungeprüft.

SDK-Builds und gemeinsame Integration werden im ergänzenden Integrationsnachweis dokumentiert. Dieser Quellstand ist zum Zeitpunkt dieses Berichts noch kein neuer TestFlight- oder Store-Build; bestehende Store-Einreichungen bleiben erhalten.
