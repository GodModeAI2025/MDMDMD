# Native Mac: Zeilenabstand im Markdown-Quelltext

Am 15.10.2026 im regulären Debug-Build **1.0.1 (20)** mit dem Skill `device-interaction` geprüft. Es handelt sich um lokale UI-/SDK-Belege; kein Upload oder Store-Nachweis.

## Isolation und Revisionen

Die bestehende synthetische QA-Bibliothek wurde mit `--scriptum-mac-qa-root /Users/markzimmermann/Library/Containers/com.mobilebox.Skriptum/Data/tmp/ScriptumSourceCommands-20261015` und `--scriptum-mac-qa-library-id 8556B4CF-DFF3-42AF-BDC1-86B8BF170C5A` geöffnet. Ausschließlich die synthetische Seite „Schreiben auf dem Mac“ und ihre Space-bezogenen Schreibpräferenzen wurden verwendet. iCloud blieb aus. Normale Dokumente, Konten und KI wurden nicht berührt. Die QA-Daten bleiben erhalten.

Baseline auf Commit `50e76fe615e609cb362dd6959b3ab64199dd11f0`; der Quellstand wurde vor dem Baseline-Build gebunden. Während dieses Binary lief, änderte der Hauptagent ausschließlich den Mac-Quelltextadapter. Der endgültige Quellstand blieb vom finalen Build bis zum Prozessende unverändert. Vollständige Source- und Binary-SHA256 stehen in `baseline-runtime-source.json`, `final-runtime-source.json` und `final-source-after.json`.

## Tatsächlicher Baseline-Fehler

Format → Schreibdarstellung → zusätzlicher Zeilenabstand **0**, sichern; anschließend **20**, sichern. Die Einstellung war gespeichert, aber der Quelltext blieb optisch identisch. Auf den 2×-Screenshots lag Alpha ungefähr bei y=148, Beta bei y=188, Gamma bei y=228 und Kappa bei y=508. Die Auswahl „Gamma“ und der Text blieben unverändert. Der Fehler wurde vor dem Nachtest tatsächlich reproduziert.

## Nachtest

Der korrigierte Build lud nach Neustart den gespeicherten Wert20 und zeigte sofort größere Abstände. Danach wurden **20 → 0 → 20 → 0** im echten Dialog gespeichert. Der Quelltext wechselte sichtbar zwischen ungefähr40 und80Pixel Zeilenabstand im 2×-Screenshot; die Schrift blieb Monospace. Auswahl „Gamma“ beziehungsweise „Beta“ blieb über den jeweiligen Dialogwechsel erhalten.

Ein reiner Darstellungswechsel erzeugte keinen Texteingriff: Im nativen Menü Edit waren danach Undo und Redo deaktiviert. Anschließend wurde „Gamma“ einmal durch „GammaQA“ ersetzt, der Abstand von0 auf20 geändert und die Textänderung über **Edit → Undo → Redo → Undo** geprüft. Es wechselte exakt zwischen „Gamma“ und „GammaQA“; Abstand20 blieb wirksam. Der letzte Wechsel auf0 erhielt die ursprüngliche Auswahl „Gamma“ und den Originaltext.

Der Originaltext wurde anschließend über **Exportieren → MD → Exportieren und teilen → Datei sichern** regulär aus der App gespeichert. `source-spacing-crlf.md` ist **76Bytes**, enthält **10CRLF**, den decomposed Akzent `e + U+0301` und das Fuchs-Emoji. `export-byte-check.json` bestätigt die exakte Bytegleichheit mit dem eingesetzten Witness (SHA256 `a193ec3876c79d0ede7001e8945ab28174a61a512eb572b58aea285266cee432`). Darstellung und Undo/Redo haben weder Text noch Zeilenenden verändert.

## Build, Abschluss und Grenzen

Offizieller Xcode-MCP: zuerst Workspaceauflistung, dann `SkriptumMac / My Mac`. Baseline-Build erfolgreich in0,282s; finaler Mac-SDK-Build erfolgreich in4,2s, jeweils ohne Buildfehler. Codesign-Verifikation erfolgreich. Logs und unveränderte MCP-Receipts liegen hier.

Die Baseline-App PID99275 und die finale App PID1565 wurden mit Befehl-Q regulär beendet; separate `ps`-Belege bestätigen das Prozessende. Xcode wurde auf **Skriptum / Any iOS Device (arm64)** zurückgestellt. MCP ist freigegeben. Keine Produktdatei wurde vom UI-Prüfagenten geändert.

Die tatsächlichen Screenshots und AX-Ausgaben sind im Tooltranskript erhalten; es gibt keine lokale Rasterdatei. Angegebene Pixelpositionen sind visuell geschätzt. Ein Kontextwechsel unterbrach das Toolbar-Menü und den ersten Speicheranlauf; nach frischer Zustandsabfrage funktionierte das native Menü, nach Pausieren paralleler Browserbedienung der reguläre Speicherretry. Keine zusätzlichen Bedienwellen wurden daraus abgeleitet.

IME-Komposition, Leistungsstresstests, iOS, physische Geräte, Accounts, Cloud, KI und Release-Portale waren nicht Bestandteil dieses schmalen Tests. Die Nachweise bestätigen die konkreten oben ausgeführten Abläufe.
