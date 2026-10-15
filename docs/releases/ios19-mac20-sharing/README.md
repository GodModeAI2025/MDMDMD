# Scriptum 1.0.1 — iOS 19 und nativer Mac 20

Release-Kandidat für die korrigierte Bibliotheksöffnung, iCloud-Freigaben und Markdown-Bildimport. **Noch nicht hochgeladen oder für TestFlight freigegeben.** Die bestehenden Store-Einreichungen iOS 11 / Mac 14 bleiben bestehen.

Die [Startprüfung](../../qa-launch-runtime-20261015/README.md) enthält den tatsächlich reproduzierten Fehler, den ebenfalls fehlgeschlagenen ersten Kandidaten und den erfolgreichen Ablauf Öffnen → Dateibrowser → erneut öffnen. Die [Freigabeprüfung am nativen Mac](../../qa-share-dialog-mac-20261015/README.md) belegt den Apple-Systemdialog für eine eigene synthetische Development-Bibliothek. Dabei wurde eine widersprüchliche rote Fehlermeldung erkannt. Die gezielte Korrektur bestand anschließend zwei tatsächliche Öffnen/Done-Durchläufe ohne Fehlerbanner, jeweils mit iCloud-Diagnose ready/none und Zählern 0/0/0. [Nachtest](../../qa-share-dialog-completion-20261015/README.md).

Die vollständige lokale Suite besteht mit 862 Swift-Testing-Definitionen / 1.098 Fällen und 58 XCTest-Fällen; vier optionale Definitionen wurden übersprungen. Die danach ergänzten engen Guards gegen verspätete Dialog-Rückmeldungen bestehen zusätzlich 14 fokussierte Definitionen / 19 Fälle. Die ursprüngliche neue Testdatei enthielt vor Korrektur einen Klammerfehler; der fehlgeschlagene Compileversuch bleibt separat erhalten. Alle 13 Tests des Distributionsprüfers bestehen.

Das fehlende `cloudkit.share`-Schema ist bereits in Production bereitgestellt und zurückgelesen. [Schemaänderung und Apple-Bestätigung](../../qa-cloudkit-share-schema-20261015/README.md). An vorhandenen Datentypen, Indizes oder Nutzerdaten wurde dabei nichts geändert.

[Geplante deutsche Testnotizen](TestNotes-de.txt). Aktuelle SDK-/Test-, Signatur-, Upload- und Portalnachweise werden nur nach tatsächlichem Erfolg ergänzt. Dies ist keine Store-Veröffentlichung und kein Nachweis für die Annahme einer Einladung durch ein zweites Konto.
