# PCC-Aufgabenplanung: begrenzter Zwischenstand

15. Oktober 2026 · Ausgangsstand `0292d27`

Der native Aufgabenadapter verwendet nach echter PCC-Zugangsprüfung eine eigene, auf Apples veröffentlichte Bedingungen begrenzte API-Kostenrichtlinie. Er lädt dafür keine OpenAI-/Anthropic-Preistabelle. Modell und unveränderliche Anbieterbindung, Vordergrundbetrieb, Token-Grenzen, Gültigkeit und Zugangsprüfung bleiben erforderlich. Ein nullwertiger Budgethöchstbetrag ist keine erfundene Rechnungsbestätigung. Die allgemeine Veröffentlichung von [Apple](https://developer.apple.com/private-cloud-compute/) belegt keine unveränderliche oder pauschale Berechtigung dieses konkreten Kontos.

Drei neue Factory-Fälle scheiterten zunächst an der fehlenden PCC-Richtlinie und bestehen nach der Korrektur. Ein weiterer Test prüft unzulässige Bindungen und Grenzen. Der abschließende ausgewählte Lauf meldet 80 + 15 + 8 = 103 Tests, darunter zwei optionale externe Prüfungen übersprungen: 101 tatsächlich ausgeführt, keine fehlgeschlagen. Provider-Antworten dieser Domain-Prüfungen sind ausdrücklich Fixtures.

In der echten, isolierten nativen Mac-App wurde eine einmalige Aufgabe ausschließlich für einen selbst erzeugten QA-Text geprüft und aktiviert: echter PCC-Zugangsweg, bestätigter Höchstbetrag 0 USD, Eingabegrenze konservativ 1.815, Ausgabegrenze 512 Tokens, ein Lauf. Die Zustimmung benennt Umfang und Empfänger. Der Status wurde aktiv; eine abgeschlossene Anbieterantwort oder ein Ergebnis wurde nicht beobachtet. Nach der Nutzerpriorisierung des iCloud-Fehlers wurde diese Testaufgabe zuerst pausiert und dann über die Oberfläche abgebrochen. Der letzte belegte Zustand ist Abgebrochen, keine Ergebnisse. Kein aktiver zukünftiger QA-Auftrag bleibt zurück.

Beim Aktivieren blieb zunächst ein leeres Blatt offen. Der Quellcode schließt es nach erfolgreicher dauerhafter Aktivierung ausdrücklich. Diese letzte Änderung ist für beide App-Ziele und den strengen Mac-Release kompiliert, aber die erneute tatsächliche Aktivierung nach dieser UI-Korrektur wurde wegen der iCloud-Priorisierung nicht ausgeführt. Ein vollständiger PCC-Aufgabenlauf bleibt offen. Auch die Abo-Aufgabenlücke bleibt bestehen.

Die Rohhierarchien zeigen zeitlich unterschiedliche Beschriftungsstände; sie sind historische Beobachtungen, keine Screenshots der endgültigen Dialogfassung. Dieser Quellstand ist neuer als Mac-TestFlight-Build 12 und wurde nicht hochgeladen. Die Übertragung einer realen PCC-Anfrage während der unterbrochenen QA wird durch das Ausbleiben eines Ergebnisses weder bewiesen noch ausgeschlossen.
