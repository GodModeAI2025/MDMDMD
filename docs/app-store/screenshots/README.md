# App-Store-Screenshots (deutsche Oberfläche)

Aufgenommen am 13.10.2026 aus dem Quellstand ce4d90b (Branch fix/compact-writing-viewport), Build 6 (CURRENT_PROJECT_VERSION 6), Debug-Build für den Simulator, iOS 27.0, helle Darstellung, Statusleiste per `simctl status_bar override` auf 9:41, 100 % Akku, volle Balken. Geräte: neu angelegte Simulatoren "Scriptum Store iPhone 17 Pro Max 20261013" und "Scriptum Store iPad Pro 13 20261013" (iPad Pro 13-inch M5). Bedienung über die Xcode-MCP-Bridge (DeviceInteractionSynthesize), Aufnahme mit `simctl io screenshot`, danach nur Alpha-Kanal entfernt (alle Pixel waren deckend), keine Skalierung.

Beispielinhalt: selbst geschriebener Essay "Langsam schreiben" (zwei Kapitel, Überschriften, Liste, fett/kursiv, Tabelle, Fußnote) im Space "Essays" mit den Seiten Vorwort, Nachwort, Ideensammlung, Morgenroutine, Quellen; zweiter Space "Notizbuch". Der Inhalt wurde als `library.json` im Simulator-Container der App angelegt (Format der App, keine Eingabe per Tastatur). Die Versionen unter "Verlauf" (Vorwort, Essay) stammen aus demselben Seed. Keine Konten, keine Anbieteranfragen, keine Schlüssel, kein KI-Ergebnis.

| Nr. | Datei (iphone-6.9 und ipad-13) | Zeigt | iPhone | iPad |
|---|---|---|---|---|
| 1 | 01-schreibflaeche-tastaturleiste.png | Schreibfläche mit Software-Tastatur und Zusatzleiste (Fett, Kursiv, Überschrift, Liste, Link, Rückgängig, Wiederholen, KI-Symbol, Tastatur schließen); Markdown-Zeichen gedämpft, Auszeichnung sichtbar | 1320 x 2868 | 2064 x 2752 |
| 2 | 02-spaces-seiten.png | Space "Essays" mit benannten Seiten, Favorit, Recherchematerial, Manuskript-Wortzähler. iPad: echte Dreispalten-Ansicht mit Seitenleiste, Seitenliste und Editor | 1320 x 2868 | 2064 x 2752 |
| 3 | 03-gliederung-statistik.png | Seiteninfo: Gliederung (zwei Kapitel), Schreibstatistik, Schreibziel mit Fortschrittsbalken | 1320 x 2868 | 2064 x 2752 |
| 4 | 04-fassungen-vergleichen.png | Echter Versionsvergleich (Verlauf der Seite "Vorwort"): historische gegen aktuelle Fassung | 1320 x 2868 | 2064 x 2752 |
| 5 | 05-export-theme-vorschau.png | Export-Dialog mit Theme-Einstellungen (Titel, Inhaltsverzeichnis an) und Live-Vorschau des PDF | 1320 x 2868 | 2064 x 2752 |
| 6 | 06-manuskript-kapitelreihenfolge.png | "Manuskript zusammenstellen": Kapitelreihenfolge Vorwort, Langsam schreiben, Nachwort | 1320 x 2868 | 2064 x 2752 |

Keine Ersatzscreens nötig: alle sechs Bildschirme existieren im Build.

## Auffälligkeiten (nicht behoben, nur festgehalten)

- Datumsangaben erscheinen englisch gemischt ("13. Oct at 09:44"), weil die App keine deutsche Lokalisierung für Systemformate mitbringt. Gilt für 02 und iPad 04.
- Im Manuskript-Dialog steht der Button "Edit" (englisch), im Seiteninfo-Panel hat das Schreibziel (250) kein sichtbares Etikett.
- Der Versionsvergleich zeigt beide Fassungen als Rohtext untereinander, ohne farbige Markierung der Änderungen.
- Unfokussierte Blöcke zeigen Tabelle und Fußnote als Markdown-Quelltext; die Darstellung folgt erst in der Vorschau.
- Vor Upload prüfen, ob diese Punkte in den Store-Bildern stören; gegebenenfalls Quelltext oder Beispieldaten anpassen und neu aufnehmen.
