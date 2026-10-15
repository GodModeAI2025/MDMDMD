# Native Mac-Designprüfung — 15. Oktober 2026

Der gebaute Haupt-App-Kandidat wurde tatsächlich über CUA geprüft; keine Source-Änderung, neue Kompilierung, Veröffentlichung oder Portalaktion durch diesen Prüfer. Referenz: `01-user-workspace.png`. Eigene neue synthetische Bibliothek unter `mac-design-ui-20261015`, nicht primäre UUID `DBBE000B-D5D2-4580-A6AE-8F27AE1D7B32`; Prozess PID 55027. Vor Start kein Scriptum-Prozess aktiv.

## Sichtbare Verbesserungen

- Die dunkle schwere Papierkarte mit umlaufendem Abstand/Schatten aus der Nutzerreferenz ist entfernt. Der Editor hat eine durchgehende, zurückhaltende Papierfläche. Helle und dunkle Ansicht bleiben lesbar. `02-wide-light`, `13-wide-dark`.
- Toolbar enthält das beschriftete **Ansicht**-Menü und **KI**-Menü. Der kleine unbeschriftete Dreifachpicker ist ersetzt; der doppelte Fokus-/Sidebar-Button ist entfernt. Native macOS-Pillengruppen bleiben sichtbar: Ansicht, Format, Lektorat, KI und gemeinsame Export/Inspektorgruppe. Das ist keine vollständig flache Toolbar; die verbleibenden Gruppen sind die tatsächlich beobachtete OS-Darstellung.
- Seitenleisten-Glyphen sind konsistent monochrom; Text und Symbole wirken einheitlicher als in der Referenz.

## Tatsächliche Bedienprüfungen

- Ansicht-Menü zeigt in frischer AX-Hierarchie Schreiben, Markdown-Quelltext und Vorschau. Wechsel zu Markdown und zurück funktioniert. Die CUA-Appfensteraufnahme enthält die separate native Menüebene nicht: `03-ansicht-menu.png` und `07-ansicht-menu-keyboard.png` zeigen nur den hervorgehobenen Toolbar-Button und sind **kein visueller Beleg eines offenen Popovers**. Die zugehörigen AX-Dateien belegen die live geöffneten Menüeinträge; der tatsächliche Moduswechsel ist in `04-markdown` sichtbar. Keine weitere identische Capture-Wiederholung als Erfolg gewertet.
- Inspektor-Toggle schaltet seinen AX-Wert off/on/off korrekt und zeigt bzw. schließt Seiteninfo/Kommentare/Verlauf. Beim Öffnen wird die linke Bibliothek durch native Platzanpassung ausgeblendet, beim Schließen wiederhergestellt. `05-inspector-on`.
- **⌥⌘F** schaltet Schreibfokus ein und wieder aus. Kein zusätzlicher Fokus-Toolbarbutton nötig. `06-focus-on`.
- Native Window → Move & Resize → Left und anschließendes Ziehen am unteren Rand erreichen eine kompakte Standardfensterdarstellung. `09-narrow-native` ist 1802×1790 Pixel; `10-minimum-light` ist **1802×1200 Pixel**, etwa 901×600 Punkte Gesamtfenster und ungefähr 900×560 Punkte Inhalt nach Toolbar. Weiteres Verkürzen wird vom nativen Minimum geklemmt. Text, Seitenliste und Status bleiben sichtbar; keine überlappenden oder abgeschnittenen Inhaltszeilen. Der lange Fenstertitel wird normal gekürzt; KI/Export/Inspektor wandern in den nativen Toolbar-Überlauf.
- Dunkle kompakte Darstellung ist in `11-minimum-dark` erhalten; breite dunkle Darstellung in `13-wide-dark`.

## Echte Befunde und Grenzen

1. **Lektorat sendet beim Öffnen automatisch.** Obwohl kein Starten-Button betätigt wurde, zeigte der neue Dialog sofort eine überarbeitete Überschrift „Schreiben am Mac“ und Übernehmen/Verwerfen. Source bestätigt den Auslöser: `AssistantPanel.swift` .task ruft bei initialAction nach Kontowiederherstellung automatisch send() auf. Dies war eine reale PCC-Verarbeitung ausschließlich des eigenen synthetischen Texts, kein Fixture. Die geplante Prüfung „öffnen/schließen ohne Senden“ ist daher **fehlgeschlagen**. Der Hauptagent wurde sofort informiert; keine Übernahme und keine zusätzliche manuelle Anfrage. `12-lektorat-minimum-dark`. Ein anschließender Source-Fix ist hier noch nicht verifiziert.
2. Der Lektoratsdialog ist etwa 740×785 Punkte groß und wächst über das 901×600-Punkte-Elternfenster hinaus. Er bleibt auf diesem Display bedienbar, belegt aber kein auf 560 Punkte Inhaltshöhe angepasstes Dialoglayout. Die dunkle Schließen-Beschriftung hat visuell schwachen Kontrast; keine formale Kontrastmessung durchgeführt.
3. Die CUA-Aufnahmen enthalten den violetten OS-Fensterfreigabeindikator. Er wurde weder verändert noch als App-Design gewertet. Native Standardfensteraktionen wurden geprüft; kein unbelegter Vollbild-/Desktoprahmen-Nachweis aus diesem Indikator abgeleitet.

## Erhalt und Abschluss

Der gesamte tatsächlich aus dem Markdown-Editor gelesene Text stimmt nach allen Abläufen **exakt mit dem Original überein**, 151 UTF-8-Bytes einschließlich letzter Zeilenschaltung. `14-original-after.txt`, `14-original-comparison.json`. Keine Texteingabe oder Vorschlagsübernahme.

Ursprüngliche App-Darstellung **System** nach temporärem Dunkel wiederhergestellt; Schreibansicht, Inspektor aus und Fokus aus. `15-preferences-restored.txt`. Alle Blätter geschlossen, eigene QA-App per Cmd-Q beendet; danach kein Scriptum-Prozess vorhanden. CUA/Xcode an Hauptagenten freigegeben. iCloud blieb aus; keine persönlichen Manuskripte oder Zugangsdaten gelesen.

Native CUA liefert JPEG-Bytes. Unveränderte Originalaufnahmen sind als gleichnamige `.jpg` erhalten; die geforderten `.png` wurden ausschließlich per nativer Formatkonvertierung erzeugt (keine Größenänderung, kein Beschnitt, keine Annotation). `CAPTURE-FORMATS.json` dokumentiert dies. Keine vollständige HIG-, VoiceOver- oder Geräte-Zertifizierung.
