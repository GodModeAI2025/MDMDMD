# Aufgabenfortschritt statt Konfigurationsstatus

15. Oktober 2026 · Ausgangsstand f5cc70a · Funktionscommit c9128ef · R09/R11. Lokale Weiterentwicklung nach dem internen iOS12-Upload; keine neue Veröffentlichung oder Änderung der bestehenden iOS11/Mac14-Store-Einreichungen.

## Konkrete Lücke

Der reale Mac-PCC-Lauf in [qa-pcc-task-completion-20261015](../qa-pcc-task-completion-20261015/REPORT.md) war erfolgreich und gespeichert, zeigte nach dem einzigen Termin aber weiter „Aktiv“. Die bisherige Aufgabenliste übersetzte ausschließlich den Konfigurations-Lifecycle. Ihre Datumsausgabe rief die Wiederholungsregel ohne Enddatum oder maximale Anzahl auf.

Die neue rein lesende Projektion ScheduledTaskProgress berücksichtigt erlaubte nächste Termine und die zur Aufgabe, Bibliotheks-/Account-/Space-Scope und aktuellen Generation gehörenden Läufe. Sie unterscheidet aktive Planung, ausstehende bzw. laufende Ausführung und beendete Planung. Der separate letzte Lauf nennt Erfolg, verfügbaren Vorschlag, Fehler, fehlende Freigabe, Budgetgrenze oder ungewisses Ergebnis. „Planung beendet“ behauptet keinen erfolgreichen Lauf und keine automatische Übernahme eines Vorschlags. Noch laufende/ausstehende Aufträge verhindern diese Abschlussanzeige auch nach dem letzten geplanten Termin. Historische Generationen aktivieren die neue Planung nicht.

Nur zulässige nächste Termine werden angezeigt. Bereits beendete Planungen zeigen keine wirkungslosen Pausieren-/Abbrechen-Aktionen. Pausierte/abgebrochene Konfigurationen bleiben unterscheidbar. Keine Migration und keine Schreiboperation: Lifecycle, Generation, Budgetreservierung, Laufhistorie, Ergebnis und Originaltext bleiben erhalten. Die Beschriftungen werden als LocalizedStringResource bis zur SwiftUI-Anzeige gereicht.

## Prüfung

Fünf feste Regressionen decken Einmaligkeit, Enddatum/Anzahl, parallele verbleibende Läufe, alte/fremde Aufgaben, inaktive Lebenszyklen und Neustart ohne veränderte Speicherbytes ab. Der rote Lauf nutzt eine Extraktion der bisherigen Lifecycle-/Regel-Anzeige in die neue Projektionsschnittstelle: alle fünf Tests scheitern mit 36 Assertions. Das ist keine erneute Laufzeitprüfung der alten App. Danach bestehen alle 94 gezielt ausgewählten Lifecycle-/Authority-/Fortschrittstests. Nach der abschließenden Vereinfachung besteht die gesamte Root-Suite: 811 tatsächlich ausgeführte Tests, vier ausdrücklich optionale Fälle übersprungen, null Fehler.

Beide tatsächlichen SDK-Kompilierungen über das freigegebene Xcode MCP sind erfolgreich: Skriptum / Any iOS Device (arm64) und SkriptumMac / My Mac. Die Belege zeigen keine Compilerfehler. Dies sind lokale Debug-Kompilierungen, keine neuen Archive oder TestFlight-Builds. Die anschließende enge iPhone17e-Simulatorprüfung besteht am identischen Funktionscommit c9128ef. Beide synthetischen abgeschlossenen Aufgaben zeigen die neuen Statusmeldungen und keine aktiven Planungsaktionen. Der Vorschlagsvergleich öffnet sich mit Original/neuer Fassung und lässt sich ohne Übernahme schließen. Eigener Prozess und Session wurden beendet. [Native Belege und Grenzen](ui/REPORT.md). Dies ist keine erneute echte PCC-Inferenz oder physische Geräteprüfung.

## Grenzen

Die Änderung fügt keine Providerfreigabe, garantierte iOS-Hintergrundzeit oder neue Inferenz hinzu. Sie schließt nicht den gesamten R09- oder R01–R15-Umfang. Wörtliche Codezäune in generierten Zusammenfassungen bleiben ein separater offener Punkt. Build12 bleibt der ausgelieferte iCloud-Korrekturstand; die bestehende Store-Einreichung bleibt auf ausdrücklichen Wunsch bestehen.
