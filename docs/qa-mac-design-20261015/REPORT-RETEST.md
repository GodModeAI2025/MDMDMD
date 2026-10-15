# Lektorat-Retest nach explizitem-Start-Fix

15. Oktober 2026 · Haupt-Mac-Kandidat nach erfolgreichem Build um 07:56:18. Vorherigen Fehlerbericht und Bilder unverändert erhalten. Keine Source-, Build-, Release- oder Portaländerung durch den Prüfer.

## Geprüft

- Neue eigene isolierte Bibliothek `mac-design-retest-20261015`, UUID `8C18F260-F975-4252-A8CF-0F657D1A194A`, ausschließlich synthetische Standardseite. Bekannte Haupt-App mit LaunchServices `--env SCRIPTUM_FAKE_AI=1` gestartet; vorhandener DEBUG-Adapter liefert lokal ohne Netzwerk. Kein echter Anbieteraufruf in diesem Retest.
- Lektorat öffnet stabil **leer** mit Kontext, Platzhalter und Starten. Kein Ergebnis, keine Übernehmen-/Verwerfen-Aktion vor Start. Das vorher beobachtete automatische Senden ist im tatsächlichen neuen UI-Lauf behoben. `16-retest-open-empty.txt/.png`.
- Ein einziges ausdrücklich betätigtes Starten erzeugt exakt die bekannte lokale Fake-Antwort „Äpfel schälen, Teig bereiten, Apfelkuchen backen.“. Damit ist der lokale Testadapter tatsächlich nachgewiesen; dies ist keine neue reale PCC-Inferenz. UI-Anbietername zeigt weiterhin die konfigurierte PCC-Auswahl und darf nicht als Nachweis eines echten Requests gelesen werden. `17-retest-local-fake-response.txt/.png`.
- Keine Übernahme. Original danach exakt **151 UTF-8-Bytes** einschließlich letzter Zeilenschaltung unverändert. `18-retest-original.txt`, `18-retest-original-comparison.json`.
- Dialog ist kleiner als vorher: Aufnahme 1120×1250 Pixel, ungefähr 560×625 Punkte inklusive Kopf-/Fußbereich. Kontext, Platzhalter und Start sind sichtbar.

## Weiterhin offen

Die Schließen-Beschriftung ist in Dunkel trotz foregroundStyle weiterhin dunkelblau und visuell kontrastarm. Dieser erste Kontrastfix ist im Retest **nicht bestanden**. Hauptagent informiert; native Button-Stilkorrektur folgt separat. Kein weiterer Versuch mit derselben alten Binärdatei als Erfolg gewertet.

## Abschluss

Schließen ohne Übernahme, Schreibansicht und ursprüngliche Darstellung **System** wiederhergestellt. Eigene Instanz PID60936 per Cmd-Q beendet; danach kein Scriptum-Prozess. CUA freigegeben. iCloud blieb aus; keine Zugangsdaten oder persönlichen Texte. Roh-JPEGs erhalten, PNGs nur per nativer Formatkonvertierung ohne Beschnitt/Größenänderung.
