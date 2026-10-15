# Tatsächlicher nativer Grammatikdialog auf dem Mac

15. Oktober 2026 · R14-Kandidat, keine Produktionsaktivierung und kein Upload.

Die auf Wunsch erneut angeforderte offizielle Xcode-Öffnung von `ScriptumNativeQualityCandidate.xcodeproj` war erfolgreich. Workspace: `workspace-ld9LTwWd5s`, am unveränderten bereits freigegebenen Projektpfad. Es ist keine weitere Öffnungsbestätigung offen.

Der erste tatsächliche Bau scheiterte an der veralteten Quelldateiliste: `PageTableSession` fehlte im zuvor erzeugten Kandidaten. Build/Run-Fehler bleiben unter `mcp` erhalten. Das ursprüngliche Projekt und die Spec wurden vor der Aktualisierung hashgeprüft gesichert; [Backup-Manifest](PROJECT_BACKUP_HASHES.json). XcodeGen hat die **unveränderte** Spec am selben Pfad neu ausgewertet, anschließend wurden die bisherigen isolierten QA-Startargumente exakt restauriert. Framework und Datenpaket wurden nicht ausgetauscht. [Rezept](SOURCE_REGISTRATION.json).

## Tatsächlich beobachtet

Im isolierten nativen Mac-Kandidaten lässt sich die lokale Engine auswählen und benutzen. Der eigene Server bleibt aus. Der Lauf aktiviert weder iCloud noch einen KI-Auftrag. Ein versehentlich geöffnetes Lektorat wurde ohne Starten geschlossen.

- Deutsch: „Es ist schöne Wetter.“ erzeugt den Grammatikhinweis `SCHOENE_WETTER`. Der [echte Dialog](05-de-correction-dialog.jpg) bietet „schönes Wetter“ sowie Ignorieren und Schließen an. Übernahme verändert nur den normalen Absatz; die automatische Nachprüfung meldet null Hinweise. „Korrektur rückgängig“ innerhalb derselben Textprüfung stellt den Ausgangstext wieder her.
- Englisch, ausdrücklich ausgewählt: „I live in la paz.“ erzeugt `LA_PAZ` und bietet „La Paz“ an. Zusätzlich erscheint ein Apple-Rechtschreibhinweis für „paz“; dies wird nicht als zweiter Grammatiknachweis umgedeutet. Nach Übernahme und Schließen des Dialogs stellt der vorhandene Editorbefehl „Textänderung rückgängig“ die vollständige Ausgangsquelle wieder her.
- Inline-Code, Fenced-Code, URL und kombiniertes Unicode bleiben in beiden Beispielen unverändert. Die Dateien `*-original.md`, `*-corrected-ax.md` und `*-undo-ax.md` enthalten die verglichenen Werte.

Der im Sheet gehaltene eigene Korrekturverlauf verschwindet beim Schließen. Der übergeordnete Editorverlauf bleibt erhalten, wie der englische Rückgängig-Lauf tatsächlich zeigt. Es wurde deshalb kein vollständiger Undo-Funktionsverlust behauptet oder durch eine ungetestete Quelländerung überdeckt.

## Beleggrenzen

Die exakten Vergleiche betreffen die über Accessibility gelesenen Editorwerte als UTF-8 einschließlich End-LF. Eine unabhängige direkte Lesung der eigenen Sandbox-`library.json` war mit EPERM verweigert; dies wurde respektiert. Der Lauf ist kein separater Dateisystem-/Kaltstart-, iOS-, Live-CloudKit-, PCC- oder Produktionsnachweis.

Die Kurztext-Spracherkennung schlug für das englische Beispiel zunächst Portugiesisch vor. Die tatsächliche Prüfung verwendete die manuell gewählte Sprache Englisch; die automatische Erkennung wird hier nicht als erfolgreich ausgegeben.

Dies schließt die frühere offene Xcode-Öffnung und die tatsächlich geprüften Mac-Dialog-/Korrektur-/Undo-Pfade. Die gewöhnliche App enthält das native Framework/Datenpaket weiterhin nicht. Native iOS-Ausführung, breitere linguistische Qualität sowie vollständige Source-/Relinking-/Distributionsarbeit bleiben offen. R14 ist nicht abgeschlossen. iOS12 in TestFlight und die vorhandenen Store-Einreichungen bleiben unverändert.

Die Git-Ablage bewahrt die unveränderten JPEG-Originale, AX-Texte, Quellvergleiche und MCP-Belege. Zusätzliche PNG-Formatkonvertierungen und das vollständige Aufnahmemanifest bleiben unter `work/native-quality-dialog-20261015` erhalten; die Dateien in dieser Git-Ablage haben ihren eigenen SHA256SUMS-Nachweis. Der eigene Testprozess wurde abschließend per MCP beendet.
