# Integration: Bildimport und Verwaltung bestehender iCloud-Freigaben

Der gemeinsame Quellstand besteht **1.069 ausgeführte Testfälle aus 854 Testdefinitionen**. Vier optionale Tests sind übersprungen: Live-Preis-HTTP, erfasste offizielle Preisunterlagen, Produktions-Picker mit Dokumentfixtures und das öffentliche lange Mischmanuskript. Alle acht Suite-Aufrufe enden erfolgreich; der vollständige `swift test`-Prozess endet mit Exit 0. [Maschinenlesbares Ergebnis](TEST_RESULTS.json), [vollständiges Log](swift-tests.log).

Offizielle Xcode-MCP-Builds desselben Implementierungsstands:

| Ziel | Zielplattform | Ergebnis |
| --- | --- | --- |
| Skriptum | Any iOS Device (arm64) | erfolgreich, 9,849 s, keine Buildfehler |
| SkriptumMac | My Mac, nativer AppKit/SwiftUI-Target | erfolgreich, 8,776 s, keine Buildfehler |

Die Originalantworten und vollständigen Buildlogs liegen neben diesem Bericht. Es wurden ausschließlich SDK-Builds ausgeführt. Keine App, kein Gerät und kein Simulator wurde gestartet. Die vorhandene Xcode-Projektfreigabe wurde erneut erfolgreich verwendet; eine weitere Bestätigung war nicht erforderlich. Ein warnungsfreier Gesamtbuild wird nicht behauptet.

## Enthaltene Korrekturen

Bestehende bestätigte iCloud-Freigaben lassen sich nach normaler Bearbeitung erneut für Personen und Rechte auswählen. Der neue Verwaltungsweg liest native Root-/Share-/Ownerdaten, erweitert keine Inhalte und ersetzt keine fehlende Freigabe. Die strenge ursprüngliche Manifestprüfung bleibt für noch unbestätigte Erstellung/Retry bestehen. Konto-, Sitzungs-, Fenster- und Abbruchgrenzen einschließlich des abschließenden Actor-Awaits sind geprüft. [Einzelnachweis](../qa-owner-share-reopen-20261015/README.md).

Der ausdrücklich gewählte Markdown-Ordner liefert ausgewählte Texte und deren lokale PNG-/JPEG-Bilder. Ein einzelner Dateizugriff erteilt keinen Zugriff auf Nachbarbilder. Originaltext, BOM, Zeilenenden und Bilddaten bleiben erhalten; der Ordner wird weder zur Bibliothek noch automatisch vollständig importiert. Relative Bildziele werden durch unveränderliche Metadaten auf interne Bilddateien abgebildet. Preview, Inventar und Export lösen dieselben bytescharfen Ziele auf. Der echte Export–Entpacken–Reimport-Test sichert auch Unicode-ZIP-Namen. Fehlende Bilder und ein ungültiges zweites Dokument erzeugen keinen Teilimport.

## Schutz bei unterschiedlichen App-Versionen

Bibliotheken und Pakete mit solchen Bildzuordnungen verwenden Format 2. Page-/Image-Cloudpayloads sowie historische Revisionen mit diesen Metadaten verwenden ebenfalls Format 2. Die äußeren Shared-Store- und Owner-Baseline-Checkpoints sind zusätzlich geschützt; ein verschachtelter Bibliotheksversionswert allein war für ältere Leser nicht ausreichend. Inhalte ohne solche Metadaten bleiben im bisherigen Format 1.

`MarkdownCloudCompatibilityTests` prüft die tatsächlichen serialisierten Versionen, aktuelle Roundtrips, absichtliches Herabsetzen auf v1 und erneutes Öffnen/Bearbeiten geteilter Checkpoints. Die Legacy-Gate-Fixture charakterisiert die tatsächlich in `6d70cdf` vorhandenen `schemaVersion == 1`-Klauseln; sie startet keine alte App. [Altquell-Gates und Hashes](../qa-owner-share-reopen-20261015/LEGACY_CLOUD_VERSION_GATES.json). Ältere Apps können neue Aliasinhalte deshalb nicht bearbeiten. Für solche Inhalte müssen alle beteiligten Apps aktualisiert werden. Text-only Shared-Drafts und opaque Outbox-Payloadbytes benötigen keine neue Aliasdekodierung.

## Bindung und Auslieferungsgrenze

[SOURCE.json](SOURCE.json) bindet den geprüften Implementierungs-/Test-/Projektstand an seine vollständigen SHA-256-Werte und den bisherigen HEAD. Der gesamte R01–R15-Umfang bleibt offen. Neue Freigaben ohne lokalen Receipt, explizite Erweiterung einer bestehenden Freigabe und umfassende native Sprachprüfung sind hier nicht abgeschlossen.

Dieser Nachweis ist ein lokaler Integrationsstand nach iOS 17/Mac 18. Er bestätigt keinen neuen TestFlight-Upload, keine Store-Einreichung und keine erfolgreiche iCloud-Runde auf dem betroffenen iPhone. Die bestehenden Store-Einreichungen iOS 11/Mac 14 bleiben unverändert.
