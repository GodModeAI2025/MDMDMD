# Neue semantische Sprachsonden

15. Oktober 2026. Neuer, vor Ausführung eingefrorener Entwurf mit 22 Primärsprachen, 44 Positiv-/Negativpaaren und 88 Texten. Kein Text stammt aus den bisherigen zwei Fixtures. Erwartete Rule-IDs fehlen bewusst; Marker, sprachliches Problem und zugelassene korrigierte Gesamtsätze waren vor der Ausführung festgelegt. Ein separates Vorabreview schließt den kontextabhängigen chinesischen Grammatikfall von der Wertung aus. 21 vorläufig brauchbare Grammatikpaare verbleiben. Alle 22 Stilexemplare sind optionale Redundanzsonden für einen knappen Sachstil. Dieses Stilprofil wurde nicht als zusätzlicher Kontext an die Engine übermittelt.

## Beobachtungen

Beide vorhandenen Engines laufen erfolgreich mit gesperrtem Netzwerk. Die native Ausführung und die JVM liefern für sämtliche 88 Texte dieselben vollständigen Match-Objekte einschließlich Ersetzungen, Spannen und Kategorien; beide kennzeichnen die Antworten als vollständig. Diese technische Parität ist ausdrücklich kein Sprachqualitätsnachweis.

- Grammatik: sechs von 21 wertbaren Fällen bieten die vorab erwartete vollständige Satzkorrektur; deren negative Kontrollen bleiben jeweils ohne Treffer. Weitere zwei Fälle treffen den Problemabschnitt, liefern aber nicht die vorab festgelegte Gesamtkorrektur. Diese Alternativen sind noch nicht sprachlich bewertet. 13 Fälle liefern keinen überlappenden Treffer.
- Stil: fünf von 22 Fällen bieten die gewünschte Straffung; deren negative Kontrollen bleiben ohne Treffer. 17 liefern keinen überlappenden Treffer. Da Redundanz kontextabhängig akzeptabel sein kann, sind fehlende Hinweise Lücken gegenüber dem gewünschten Stilprofil, keine bewiesenen Sprachfehler der Engine.
- Alle 44 negativen Texte bleiben in diesem begrenzten Lauf ohne Treffer. Der ausgeschlossene chinesische positive Fall bleibt vollständig im Rohprotokoll erhalten.

Katalanisch/Französisch liefern passende Grammatik-Ersetzungen mit `uncategorized`; die niederländische Stilstraffung kommt als `misspelling`, die rumänische als `uncategorized`. Die Rohkategorien werden nicht umetikettiert. Diese Ersetzungen belegen nicht automatisch die richtige Einordnung in den App-Filtern.

## Grenzen und Folgearbeit

Es handelt sich um autonom formulierte Sonden mit internem Zweitreview, nicht um extern validierte linguistische Abnahme. Der Korpus ist für die Bewertung der geforderten 20+ Sprachen bewusst noch unzureichend: ein Grammatik- und ein Redundanzphänomen pro Sprache ersetzen keine professionelle Abdeckung. Eine abweichende plausible Korrektur wird nicht als falsch umgedeutet. Neue, begründete Sonden müssen separat eingefroren werden; fehlende Treffer werden nicht durch passendere nachträgliche Erwartungen verdeckt.

Die Läufe prüfen native C-ABI und JVM direkt, nicht die App-Korrekturaufnahme oder iOS-Laufzeit. Der tatsächliche Source-/Revision-gebundene Anwendungspfad ist separat geprüft; diese neuen 88 Texte wurden dort noch nicht wiederholt. Peak Memory der nativen Hostausführung: 413.795.168 Bytes, Laufzeit rund 85,8 Sekunden; kein iOS-Leistungsversprechen. Alle 1.888 Ressourcen wurden vor dem Lauf erneut gehasht. Keine Produktionsaktivierung, kein Upload. Die Ergebnisse sprechen gegen eine pauschale 20-Sprachen-Fertigmeldung und bestimmen die nächste Qualitätsarbeit.

Die gesicherten Skripte enthalten die tatsächlichen lokalen Reproduktionspfade. Große Engine-/Runtime-Artefakte liegen weiter im Arbeitsverzeichnis. Die Erwartungen und Rohantworten sind unverändert; SHA256SUMS bindet die hier abgelegten Belege.
