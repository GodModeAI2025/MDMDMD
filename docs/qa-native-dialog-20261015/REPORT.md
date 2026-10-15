# Native Grammatikdialogprüfung — 2026-10-15

Die echte native Mac-Prüfung im ausdrücklich freigegebenen Kandidaten ist durchgeführt: lokale Engine, deutsche Korrektur, Undo innerhalb der Prüfsitzung, englische Korrektur und übergreifendes Undo nach Schließen funktionieren in den geprüften Fällen. Keine KI-Anfrage, kein iCloud und keine persönlichen Dateien.

## Lauf und Herkunft

- Offiziell geöffnet: workspace-ld9LTwWd5s, derselbe genehmigte candidate-final/ScriptumNativeQualityCandidate.xcodeproj-Pfad. Keine alternative Projektöffnung.
- Erster Build blockierte an fehlender Projektregistrierung von PageTableSession. Build- und Run-Fehler bleiben in receipts erhalten; dabei wurde kein Prozess gestartet.
- Root erneuerte allein die Source-Registrierung am selben Pfad über unveränderten Spec und sicherte den Vorgänger unter source-registration-backup. Genau ein neuer MCP-Run wurde gestartet: SkriptumMac / My Mac, buildErrors leer, PID 30005, RunProject-Log-20261015-100639.txt, launchSessionReference 754cdf3a80. Beleg grammar-dialog-native-final-run-2-RunProject.json.
- Tatsächlicher Prozesspfad und Argumente wurden geprüft: eigener ScriptumNativeQualityCandidate-DerivedData-Build mit --scriptum-mac-qa-root und ausschließlich dem vorbereiteten ScriptumGrammarRuntimeQA-Final-20261015-Root. Vor Start war kein anderer nativer Scriptum-Prozess aktiv.
- App-Metadaten: com.mobilebox.Skriptum, Build14, macosx. Gebautes Framework und Sources sind in STATE.json gehasht. Das Ressourcenbundle enthält tatsächlich 1888 Upstream-Dateien unter org sowie manifest.json und Info.plist (1890 Dateien insgesamt).

## Tatsächliche Interaktionen

1. Eigene synthetische Seite in Markdown geöffnet, DE-Quelle eingegeben. Sie enthält den unveränderten UpstreamExamples-Fall „Es ist schöne Wetter.“ (SCHOENE_WETTER) und denselben Fehler zusätzlich in Inline-Code, Fenced-Code und URL; außerdem kombiniertes e+Akzent und 🦊.
2. Schreiben → Textprüfung → Prüfeinstellungen zeigt „Lokale Grammatik und Stil“ eingeschaltet, eigener Prüfserver ausgeschaltet, German und den Hinweis auf LanguageTool6.6 ohne Netzwerk (02). Der Lektorat-Toolbarbutton öffnet weiterhin den KI-Dialog; dieser wurde ohne Start geschlossen. Die lokale Prüfung liegt im Schreiben-Menü.
3. „Text prüfen“ lieferte genau einen Hinweis im normalen Absatz. Dialog „Grammatik“ zeigt Original, Erklärung und „Ersetzen durch schönes Wetter“ (04/05). Code/URL wurden nicht als zusätzliche Fehler behandelt. Übernahme und automatische Nachprüfung führten zu null Hinweisen.
4. Tatsächlicher AX-Editorwert nach Übernahme entspricht als UTF-8 exakt der Ausgangsquelle mit nur dem ersten vorgesehenen Ersatz: 211→212Bytes. Geschützte Segmente, Unicode und letztes LF erhalten (06, de-corrected-ax.md).
5. Nach Schließen/Wiederöffnen verschwindet der nur dem Sheet gehörende Korrekturverlauf. Deshalb wurde die eigene Ausgangsquelle erneut eingegeben und Apply→„Korrektur rückgängig“ innerhalb derselben Prüfsitzung ausgeführt. Fehlerhinweis kehrt zurück, Redo wird angeboten (08). Nach Schließen ist der komplette AX-Editorwert exakt die 211Byte-Ausgangsquelle (09, de-undo-ax.md). Redo wurde angeboten, aber nicht ausgeführt.
6. EN-Fall: unverändertes „I live in la paz.“ aus UpstreamExamples (LA_PAZ), wiederum mit geschütztem Code/URL/Unicode. Der kurze gemischte Testtext wurde zunächst automatisch als Portuguese vorgeschlagen; English wurde ausdrücklich manuell gewählt (10). Das ist eine Grenze der automatischen Spracherkennung, kein stiller Sprachwechsel nach Start.
7. Lokale Prüfung: LA_PAZ-Hinweis mit „La Paz“, zusätzlich Apple-Rechtschreibhinweis „paz“ (11/12). Nach genau dieser Ortsnamenkorrektur: null Hinweise. AX-Quelle entspricht ausschließlich dem vorgesehenen Ersatz; sonst exakt unverändert, 174Bytes (13).
8. Dialog geschlossen, Format → „Textänderung rückgängig“ tatsächlich betätigt (14/15). Kompletter AX-Wert entspricht wieder exakt der englischen Originalquelle, 174Bytes. Damit bleibt Undo auch nach Sheet-Schließen im übergreifenden Verlauf verfügbar; der Sheet-Reset ist kein nachgewiesener Verlust dieser Funktion.

## Grenzen und UI-Beobachtungen

- Exakte Vergleiche beziehen sich auf den tatsächlichen AX-Editorwert, in UTF-8 gespeichert. Direkter Leseversuch der eigenen library.json wurde mit EPERM abgewiesen; das wurde respektiert, kein alternativer Dateizugriff und kein Kaltstartnachweis. Kein unabhängiger Persistenzbeweis auf Datenträgerebene.
- Deutscher und englischer Originalvorschlag funktionieren. Dies beweist nicht die linguistische Vollständigkeit aller Sprachen, Regeln oder Texte und keine iOS-Frameworkintegration.
- Die Textprüfung ist auf dem Mac sehr großflächig mit viel Leerraum; keine überlappenden/abgeschnittenen Korrekturtexte im tatsächlichen Lauf. Das englische LA_PAZ-Dialoglabel ist „Sonstiges“ entsprechend der Regelklassifikation.
- Mac-AX stellt Form-Zeilen teils nur als Row ohne enthaltenen Button dar. Der AX-Klick auf den Zeilenmittelpunkt trifft bei kurzen linksstehenden Buttons nicht immer; nach erfolglosem AX-Klick wurde ausschließlich die sichtbare Buttonfläche anhand frischem Screenshot geklickt. Das ist eine Automations-/AX-Grenze; echte sichtbare Buttons reagieren.
- 03 und 07 sind bewusst transiente Prüfläufe, 04/05/08/10/11/12/15 stabile Belege. Rohbilder sind unverändert als JPEG .jpg gespeichert, zusätzlich echte PNG-Formatkonvertierungen; kein Zuschneiden, Skalieren oder Retuschieren.

## Abschluss

Ursprüngliche Schreibansicht wiederhergestellt, keine Systemdarstellung geändert. Eigener PID30005 per offiziellem StopProject beendet; anschließendes ps bestätigt ihn nicht mehr vorhanden. Es wurde keine separate DeviceInteraction-Session eröffnet (native CUA-Prüfung), kein Sessionhandle verbleibt. Keine Source-/Produktionsdependency-/Git-/Portal-/Releaseänderung durch den Prüfer. Xcode und native CUA sind an Root freigegeben.
