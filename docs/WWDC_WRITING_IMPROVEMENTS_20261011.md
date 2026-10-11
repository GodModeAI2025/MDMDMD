# WWDC-Wissen für Scriptum

Auswertung vom 11. Oktober 2026. Grundlage: das bereitgestellte `wwdc.zip`, gezielt ausgewählte Sessions und die tatsächlich installierten SDK-Deklarationen. Die Bestandsaufnahme umfasst 187 Wissens-/Quelldokumente. Archiv-Hash und verwendete Texte sind in [reference-inputs.json](qa-wwdc-writing-20261011/reference-inputs.json) gebunden; das Archiv bleibt unverändert. Enthaltene Router-, Skill- und Skriptdateien wurden als Begleitmaterial behandelt.

## Umgesetzt und geprüft

| Erkenntnis | Änderung in Scriptum | Nachweis |
|---|---|---|
| S-0014: `reorderable` und `reorderContainer` registrieren die Zeilen bereits selbst | Die zusätzliche Drag-Registrierung am inneren Ziehgriff wurde entfernt. Sie verhinderte den tatsächlichen Fingerdrag. | Zwei native iPad-Drags funktionieren; abschließender Lauf prüft Eingabe, Drag, Undo/Redo und erneutes Öffnen. |
| S-0016/S-0017: Werkzeugleisten sollen den tatsächlich verfügbaren Platz nutzen | Die sieben Aktionen haben getrennte Sichtbarkeitsprioritäten. Das Seitenmenü bleibt angeheftet, weitere Aktionen sind im systemeigenen Überlauf erreichbar. | iPhone Hoch-/Querformat und iPad-QA-Modal zeigen getrennte Controls und erreichbare Menüs. |
| S-0071/S-0019: Arbeit beim Darstellen und Scrollen begrenzen | Die Markdown-Projektion wird einmal beim Aufbau einer Zeile berechnet und als unveränderlicher Wert für Schrift, Darstellung und Hilfsfunktionen wiederverwendet. | Bestehende Projektions-/Blocktests und native Schreibregression bestehen. Keine gemessene FPS- oder Latenzzusage; Vorbereitung großer Blöcke im Hintergrund bleibt eine weitere Optimierungsaufgabe. |
| S-0011: Fremde Inhalte und vorherige Ausgaben sind Kontextdaten | Frühere Chatbeiträge sind nun ein JSON-Array aus Rolle und Text. Die Anwendungsanweisung trennt vergangene Antworten vom aktuellen Auftrag. | Ein reproduzierender Test zeigt zuvor drei statt zwei Anfrageabschnitte; nach der Änderung bleiben Struktur und exakte Unicode-Daten erhalten. Das ersetzt keine Berechtigungs- oder Übernahmeprüfung. |

Die KI-Dialoge für Lektorat, Überarbeiten und Zusammenfassen wurden nativ geöffnet und geschlossen, ohne Texte zu senden. Der Image-Playground-Dialog meldet im geprüften Simulator die tatsächliche Nichtverfügbarkeit und lässt Fotos-/Dateiimport erreichbar.

## Apple Intelligence: Entscheidungen aus dem SDK-Abgleich

S-0044 und S-0056 bestätigen den Nutzen von getrennten Modellfähigkeiten, Profilen und kontrolliertem Kontext. Scriptum behält seinen ausdrücklich gewählten Anbieter und seine anfragebezogenen Schreibprofile. Die Beispiele zum automatischen Wechsel zwischen Modellen rechtfertigen keinen stillen Anbieterwechsel oder eine Weitergabe der vollständigen Bibliothek.

Die Tokenzählmethoden im aktuellen SDK gehören zum `SystemLanguageModel`. Beim verwendeten `PrivateCloudComputeLanguageModel` ist `contextSize` ein asynchroner, werfender Getter. Deshalb werden die Aussagen der allgemeinen Session nicht als identische PCC-API übernommen. Eine vollständige Lösung für große Manuskripte braucht Modellgrenzen, alle Instruktionen/Referenzen/Verläufe und ein atomar zusammengesetztes, revisionsgebundenes Ergebnis. Eine Zeichenschätzung und ein gekürzter Text sind dafür kein Abnahmenachweis.

S-0031 behandelt fein aufgelöste Textnavigation und zusammenhängendes Lesen. Die Archivmetadaten nennen teils „English Original“, obwohl der enthaltene Text übersetzt ist. Konkrete APIs werden deshalb am SDK verifiziert. `accessibilityLinkedGroup` allein macht die derzeitigen inaktiven Block-Buttons nicht zu vollwertigen Text-Eingabeelementen. Diese Verbesserung erfordert die passende Textkomponente und eine echte VoiceOver-Prüfung.

## Grenzen der aktuellen Nachweise

Die native Prüfung verwendet echte Scriptum-Views in `CompositeWritingQAHost` mit neuen temporären Bibliotheken. Die zusätzliche Modalnavigation unterscheidet sich vom regulären Dateibrowser/Workspace. Volle Split-/Resize-, VoiceOver-, Dynamic-Type-, Hardware-Tastatur-, Langmanuskript- und Live-KI-Abnahme bleiben offen.

Ein zunächst vermuteter Undo-Bytefehler wurde zurückgenommen: `library.json` war während aktiver Eingabe noch die Baseline; aktuelle Änderungen lagen in `edits/*.json`. Der abschließende Vergleich verwendet ausdrücklich `journal.current` und den nach abgeschlossenem Journal gespeicherten Stand. Undo, Redo und erneutes Öffnen stellen ihre jeweiligen Block-IDs und UTF-8-Bytes exakt wieder her. Der notwendige Absatztrenner beim Verschieben einer Tabelle gehört bereits zur Umordnung.

Die vollständige R01–R15-Abnahme, aktuelle Signierung/iCloud-Berechtigungen und die Auslieferung dieses Stands über TestFlight bleiben verbindlich. Die verwendeten Texte führen keine neue externe Speicher-Cloud oder zusätzliche Modellbibliothek ein.
