# Tatsächlicher geplanter PCC-Lauf auf dem Mac

15. Oktober 2026 · Ausgangsstand `b781ba7` · bekannte Haupt-App, nativer Mac-Debug-Kandidat mit normaler Xcode-Signatur. Keine neue Kompilierung, Portalaktion, Veröffentlichung oder Anbieterumstellung während dieser Prüfung.

## Ergebnis

Ein eigener synthetischer Auftrag wurde über **Bibliothek → Geplante Aufgaben** erstellt, nach tatsächlicher PCC-Zugangsprüfung und ausdrücklicher Textfreigabe aktiviert und nach Fälligkeit erfolgreich ausgeführt. Die echte Oberfläche zeigte anschließend eine gespeicherte Zusammenfassung mit Anbieter und Modell **Apple Private Cloud Compute**. Dies ist eine reale Anbieterantwort, kein Test-Fixture.

Auftrag: „Fasse diesen selbst erstellten Testtext in einem kurzen deutschen Satz zusammen. Keine Änderungen am Original.“ Kontext ausschließlich die eingebaute QA-Seite „Schreiben auf dem Mac“. Einmalig am 15.10.2026 um 07:44 CEST, höchstens ein Termin, Inputbudget 32.000 Tokens (konservativer Prüfwert 1.815), Outputlimit 512, Ausführungsmodus geöffnete App im Vordergrund. Die echte Prüfung bestätigte eine Kostenobergrenze von 0 USD für den aktuell berechtigten PCC-Zugang. Daraus folgt keine pauschale oder dauerhafte Kontoberechtigung, Rechnungsbestätigung oder Garantie unveränderlicher Apple-Bedingungen.

Beobachtete Antwort:

> Schreiben auf dem Mac umfasst einen eigenen Satz mit Markdown, Tastatur und iCloud sowie einen wachsenden Text im zweiten Abschnitt.

Die Oberfläche zeigt zusätzlich wörtliche Markdown-Codezäune um die Antwort; dieser Darstellungs-/Prompt-Polish bleibt offen. Belege: `completed-result.txt`, `completed-result.png`.

## Aktivierung, Vordergrund und Aufräumen

- Die Aktivierung schloss das Prüfblatt tatsächlich und kehrte zu einer befüllten Aufgabenliste zurück; kein leeres Blatt. `activated.txt/.png`. Bei einer späteren Beobachtung war auch das äußere Aufgabenblatt verschwunden, ohne weiteren expliziten Schließen-Klick. Erneutes Öffnen funktionierte; die Aufgabe blieb aktiviert. Diese zusätzliche Schließbewegung ist als UI-Nuance erhalten, nicht als Datenverlust gewertet.
- Vor Fälligkeit blieb die Aufgabe aktiv ohne Ergebnis. Nach Fälligkeit zeigte eine reine AX-Beobachtung zunächst weiterhin kein Ergebnis. Ein Klick in den unkritischen Titelbereich hielt das Aufgabenfenster ausdrücklich im Vordergrund; anschließend war das Ergebnis sichtbar. Es wurde weder eine neue Aufgabe noch eine manuelle zweite Anfrage angelegt. Die genaue Dispatch-/Antwortlatenz ist aus den UI-Aufnahmen nicht messbar.
- Nach dem einzigen Termin verschwand der nächste Termin, die Aufgabenbeschriftung blieb zunächst „Aktiv“. Anschließend über den tatsächlichen Abbrechen-Button abgebrochen; Endzustand **Abgebrochen**, Ergebnis erhalten. `task-cancelled.txt`. Keine zukünftige QA-Aufgabe bleibt aktiviert.
- Der gesamte tatsächliche Markdown-Editorwert stimmt nach dem Lauf exakt mit dem bekannten Original überein: **151 UTF-8-Bytes**, einschließlich letzter Zeilenschaltung, ohne Trimmen verglichen. `original-source-after.txt`, `original-exact-comparison.json`. Kein Ergebnis wurde in das Original übernommen.
- Alle Blätter geschlossen und ausschließlich eigene QA-App per Cmd-Q beendet. Anschließendes Prozessinventar um **07:45:46 CEST** enthält keinen Scriptum-Prozess. CUA und Xcode an Hauptagenten freigegeben.

## Isolation und Grenzen

Vor dem Start war kein Scriptum-Prozess aktiv. Eigene Instanz PID 48470 mit neuem Root `pcc-task-completion-20261015` im Application-Support-Bereich des App-Containers und nicht primärer Bibliotheks-ID `DBD672E9-D971-4A25-AF70-802C67F9FD64`. Nur selbst erzeugter Fixturetext; keine persönlichen Manuskripte, Zugangsdaten oder Roh-Systemlogs gelesen. iCloud wurde nicht aktiviert. Keine Datei-/TCC-Sperre wurde umgangen.

Der Lauf belegt einen tatsächlichen nativen Mac-PCC-Planungspfad und Originalerhalt. Er belegt keine Ausführung bei beendeter App, iOS-Hintergrundausführung, andere Anbieter, umfassende Antwortqualität oder neue Auslieferung dieses Quellstands. Verpflichtende physische Geräteprüfungen bleiben entfernt.

Die native Aufnahme liefert JPEG-Bytes. Die Originaldateien bleiben unverändert als `.jpg` erhalten; gleichnamige `.png` sind ausschließlich native Formatkonvertierungen ohne Beschnitt, Skalierung oder Annotation. `CAPTURE-FORMATS.json` enthält die Hashes der Originale.
