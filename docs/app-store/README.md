# Scriptum – Apple-Einreichung und Store-Auftritt

Stand: 11. Oktober 2026. Quellstand für diese Vorbereitung: 258e12d. **Arbeitsfassungen; nicht an Apple übermittelt und nicht einreichungsbereit.**

Die vom Nutzer eingefügte app-store-optimizer-Vorlage dient als Orientierung für Positionierung, Lokalisierung und Screenshot-Reihenfolge. Ihre pauschalen Ranking-, Keyword-Volumen- und Conversion-Aussagen sind keine belegten Daten über Scriptum. Es werden keine erfundenen Bewertungen, Nutzerzahlen oder Wettbewerber-Rankings verwendet. Kein zusätzlicher Agent oder dauerhaftes Monitoring wurde eingerichtet.

## Direkt verwendbare Entwürfe

- [Deutsche Store-Texte](listing.de-DE.txt) und [strukturierte Felder](metadata.de-DE.json)
- [Englische Store-Texte](listing.en-US.txt) und [strukturierte Felder](metadata.en-US.json)
- [Screenshot-Briefing](SCREENSHOTS.md)
- [Review-Unterlagen und Einreichungsstand](SUBMISSION.md)
- [Feldprüfung](validation.json), reproduzierbar mit `python3 docs/app-store/validate_metadata.py`
- [Datenschutz DE/EN](../legal/README.md)

Positionierung: Markdown-Schreiben und Wissensarbeit, mit geordneten Seiten und offenen Exportformaten. Primärkategorie: Produktivität. Keine zusätzliche Kategorie ohne konkreten Nutzen. Name: „Scriptum: Markdown Editor“. Deutsche Unterzeile: „Fokus für deine Ideen“. Englische Unterzeile: „Write, organize, export“.

Keywords sind relevante Suchhypothesen, keine gemessenen Volumen-/Schwierigkeitswerte. Die Felder vermeiden fremde App-/Firmennamen, Preisangaben, Rankings sowie Dopplungen des App-Namens. Nachfrage und Conversion können nach dem Start anhand tatsächlicher App-Store-Connect-Daten bewertet werden. Bewertungen sollten neutral über Apples Systemdialog erbeten werden, ohne Belohnung oder Vorauswahl zufriedener Personen; die Vorlage begründet keine solche Funktion oder Kampagne.

Die Beschreibungen sind Kandidatentexte für eine abgenommene Version. Sie ersetzen keinen Funktionsnachweis. Die aktuelle R01–R15-Matrix bleibt vollständig bindend. iCloud-Zusammenarbeit, verifizierte Live-KI, ChatGPT-Abo-Zugang, PCC und zwanzig tatsächlich geprüfte Grammatik-/Stilsprachen sind weiterhin Produktziele, werden aber bis zum Nachweis nicht als verfügbare Store-Funktionen beworben. Ebenso keine PDF/UA-, Ende-zu-Ende-Verschlüsselungs-, Null-Aufbewahrungs- oder garantierte Hintergrundzeit-Zusage.

Support-/Datenschutz-URL, Review-Kontakt, Copyright und Preis bleiben im JSON bewusst `null`, bis die endgültigen Angaben und öffentlichen Seiten vorliegen. Das sind keine Werte für einen Upload. Es wurde kein Preis-/Abo-Modell erfunden. Manuelle Veröffentlichung nach Apple-Freigabe ist die vorgeschlagene Auslieferungsoption; sie wurde nicht im Portal gesetzt.

## Aktuelle Apple-Referenzen

- [App-Name, Untertitel, Datenschutz-URL](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information/): Name und Untertitel jeweils höchstens 30 Zeichen; öffentliche Datenschutz-URL erforderlich.
- [Versionsfelder](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information/): Beschreibung höchstens 4.000 Zeichen, Werbetext höchstens 170 Zeichen, Keywords höchstens **100 Bytes**. Die UTF8-Bytegrenze wird zusätzlich zur Zeichenzahl geprüft.
- [Screenshot-Spezifikationen](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/)
- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/): vollständige, zutreffende Metadaten und eine funktionierende App; klare Offenlegung und ausdrückliche Erlaubnis vor Weitergabe personenbezogener Daten an externe KI.

Diese Quellen wurden bei der Vorbereitung gelesen. Eine bestandene Feldprüfung ist keine Apple-Prüfung, Veröffentlichung oder vollständige Abnahme.
