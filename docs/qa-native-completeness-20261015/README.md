# Textprüfung: unvollständige Antworten verwerfen

15. Oktober 2026. Eine explizit unvollständige LanguageTool-Antwort wurde bisher wie eine vollständige Antwort decodiert. Das konnte bei leerer Trefferliste als abgeschlossene Prüfung ohne Hinweise erscheinen oder Teilvorschläge zur Übernahme anbieten.

Der gemeinsame Decoder beendet jetzt den gesamten Lauf mit `QualityError.incompleteResults`. Die Oberfläche verwendet die vorhandene Fehleranzeige und meldet die unvollständige Prüfung. Der Lauf liefert keine Teilvorschläge und setzt seinen Fortschritt nicht bis zum Ende fort. Dies gilt für den ausdrücklich gewählten eigenen Regelserver sowie den noch nicht ausgelieferten nativen Kandidaten. Vorhandene `warnings` müssen einen echten booleschen Status enthalten. Fehlende `warnings` bleiben kompatibel mit vollständigen kompakten und älteren Antworten. Der tatsächliche gepinnte LanguageTool-6.6-Serializer bestätigt diesen Vertrag; Quellfingerprints und Zeilen stehen in UPSTREAM_CONTRACT.json.

## Tatsächlich geprüft

Die unveränderte neue Regressionstestdatei wurde zuerst gegen den unveränderten Produktcode ausgeführt: Exit 1 mit 30 Issues. Besonders aussagekräftig: beide Reviewer bearbeiteten alle vier Manuskriptabschnitte und meldeten 4/4 trotz unvollständigem zweiten Abschnitt. Nach dem Fix bestehen dieselben fünf Testdefinitionen (acht parametrisierte Fälle). Die gesamte Textprüfungs-Suite besteht mit 68 Testdefinitionen, 89 ausgeführten Fällen und keinen Skips. Der Korrekturpfad, Quellschutz, Unicode, Abbruch und bestehende vollständige Engine-Antworten bleiben darin abgedeckt.

Die neuen Prüfungen sichern leere und gefüllte Teilantworten, beide Engine-Herkünfte, ungültige Statusdaten sowie den Stopp nach Abschnitt zwei einschließlich unterbliebener weiterer Serveraufrufe und Fortschrittsmeldungen. Es wurde ausschließlich ein Transport-Stub benutzt, kein persönlicher Text versendet. Root hat den minimalen Produktdiff und die Tests unabhängig geprüft.

## Compiler- und Auslieferungsstand

Der neue Xcode-MCP-Kompilieraufruf wurde vor der Kompilierung wegen einer erneut erforderlichen Agentenfreigabe zurückgewiesen. Das erneute Öffnen des bereits freigegebenen Skriptum-Projekts hat eine konkrete Anfrage im Xcode-MCP-Menüleistensymbol vorgemerkt. Ein neuer iOS-SDK-Build dieses Diffs ist damit noch nicht bestätigt. Es gab keinen App- oder Simulatorstart.

Der zuvor erstellte iOS15-Startbutton-Kandidat enthält diese spätere Textprüfungsänderung nicht; seine unveränderte Artefaktbindung bleibt erhalten. Kein neuer Upload oder Store-Eingriff. Der native Sprachengine-Kandidat bleibt außerhalb der Produktionsabhängigkeiten und R14 bleibt offen.
