# Native Grammatik: Austausch-Framework in der tatsächlichen Mac-App

Am 15.10.2026 wurde der neu gebaute Kandidat aus dem bereits freigegebenen Xcode-Projekt `ScriptumNativeQualityCandidate.xcodeproj` mit dem Skill `device-interaction` tatsächlich ausgeführt. Zweck dieses engen Laufs war der Funktionsnachweis des lokal neu gelinkten und erneut signierten dynamischen Grammatik-Frameworks im normalen App-Dialog.

## Identität und Isolation

Das verwendete App-Binary lag unter `/Users/markzimmermann/Library/Developer/Xcode/DerivedData/ScriptumNativeQualityCandidate-cipawecyyjibgoawjlcybocjrcuy/Build/Products/Debug/Scriptum.app`. Debug-Library-SHA256: `ecbb37edf92988a95c57bb48a47938f836d3c115a9f030a3edca58eac3be4f14`; eingebettetes Framework-SHA256: `d07be66220e83d75eca99366182971589c3cba4d93f215b1ed42bcb08d5fbec9`. Beide Hashes wurden unmittelbar vor dem Start gegen `MAC_APP_PROOF.json` erneut geprüft, ebenso `codesign --verify --deep --strict`. Der offizielle Xcode-MCP-Build war erfolgreich in **9,896 Sekunden**; Receipt und Buildlog liegen hier. Der Hauptagent hatte Ressourcen- und Payloadvergleich zuvor getrennt geprüft; diese strukturellen Belege sind in der kopierten `MAC_APP_PROOF.json` gebunden.

Start ausschließlich mit `--scriptum-mac-qa-root /Users/markzimmermann/Library/Containers/com.mobilebox.Skriptum/Data/tmp/ScriptumGrammarReplacementQA-20261015`. Die neue synthetische QA-Bibliothek zeigte zunächst den automatisch erzeugten Willkommenstext. Normale Bibliotheken wurden nicht geöffnet. iCloud und KI wurden nicht aktiviert. Die QA-Daten bleiben erhalten.

## Ausgeführter UI-Ablauf

1. Synthetische Seite „Schreiben auf dem Mac“ geöffnet und im normalen Markdown-Quelltexteditor durch `witness.md` ersetzt: normaler deutscher Satz „Es ist schöne Wetter.“, derselbe Satz als Inline-Code, die reservierte URL `https://example.invalid` sowie `Café 🦊` mit decomposed Akzent.
2. Schreiben → Textprüfung → Prüfeinstellungen geöffnet. Tatsächliche Werte: **Eigenen Prüfserver verwenden = aus**, **Lokale Grammatik und Stil = an**, **Textsprache = German**. Der Dialog bezeichnete die Prüfung als lokal; es wurde kein Server, Account oder KI-Anbieter eingerichtet.
3. **Text prüfen** ausgeführt. Ergebnis: genau **ein** Hinweis für „schöne Wetter“ im normalen Absatz. Die Codekopie und URL erschienen nicht als zusätzliche Hinweise. Der echte Grammatikdialog bot **Ersetzen durch „schönes Wetter“** an und erklärte die fehlende Kongruenz beziehungsweise den möglichen fehlenden Artikel. Das entspricht dem erwarteten Witness für `SCHOENE_WETTER`; die interne Regel-ID ist im UI nicht sichtbar und wird daher nicht als ausgelesen behauptet.
4. Ersatz übernommen. Die automatische Nachprüfung beendete sich mit **0 Hinweisen**. Danach **Korrektur rückgängig** betätigt: erneut genau **1 Hinweis** für die ursprüngliche Textstelle.
5. Dialog geschlossen. Die echte Quelltextansicht zeigte wieder den kompletten ursprünglichen Witness einschließlich Inline-Code, URL, kombinierendem Akzent und Emoji. Anschließend regulär über Exportieren → MD → Datei sichern in `after-undo-export.md` exportiert.

Der Export ist **87 Bytes** und stimmt **bytegenau** mit `witness.md` überein. SHA256: `7a279cb0a8326265779c69d1e692fbc0ada7f6cd4b54f4418d72f3d838cf06ce`. `byte-check.json` bindet die Prüfung. Dieser Nachweis gilt für den vollständigen Übernehmen-/Rückgängig-Zyklus. Vor Undo wurde der Ersatz über den Korrekturdialog und die automatische Nachprüfung mit 0 Hinweisen bestätigt; es wurde kein separater Export des Zwischenstands erstellt.

## Abschluss und Grenzen

Der isolierte Prozess **PID11402** wurde regulär mit Befehl-Q beendet; `process-exit.json` bestätigt das Ende. Die 174 erfassten Swift-Quelldateien blieben zwischen Start und Ende unverändert. Der Hauptworkspace wurde per Xcode-MCP auf **Skriptum / Any iOS Device (arm64)** zurückgestellt und MCP freigegeben. Der UI-Prüfagent änderte keine Produktdateien.

Die tatsächlichen Screenshots und AX-Bäume sind im Tooltranskript erhalten, nicht als lokale Rasterdateien. Bei „Text prüfen“ und „Korrektur rückgängig“ exponiert der AX-Baum breite Listenzeilen: Ein Klick auf deren Mitte löste nichts aus, der anschließend anhand des Screenshots lokalisierte sichtbare Button funktionierte. Der Grammatikhinweis und der Ersatzbutton ließen sich direkt über AX öffnen beziehungsweise betätigen.

Dieser einzelne deutsche App-Lauf ist kein neuer Nachweis für die Qualität von 29 Sprachen, keine iOS-Ausführung und kein Store-, Cloud-, Account-, KI- oder Einladungsnachweis. Keine zusätzliche Anbieter- oder Stresstestserie wurde durchgeführt.
