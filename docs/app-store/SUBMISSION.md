# Einreichungsunterlagen und offene Nachweise

Stand 11. Oktober 2026, lokaler Quellstand 258e12d. Vorbereitung für Scriptum, Bundle com.mobilebox.Skriptum, iOS/iPadOS 27. Kein aktueller Portal-Livecheck und keine Übermittlung an Apple in dieser Vorbereitung.

## Review-Notiz – englischer Textentwurf

Den folgenden Text erst mit einem vollständig geprüften, ausgewählten Release-Build verwenden. Funktionspfade am tatsächlichen Build erneut nachvollziehen; optionale KI-/iCloud-Ergänzungen sind unten gesondert beschrieben.

> Scriptum is a native Markdown writing and knowledge workspace for iPhone and iPad. Its local writing workflow does not require an AI-provider account.
>
> To review the writing workflow, create a local library and a Space, add a page, enter Markdown headings and text, and open the page tools to inspect the outline, statistics, and writing goal. Add an image or a table, then use Export to select a format and layout theme. Preview the document and share the completed export through the system share sheet. Multiple pages can be assembled into a manuscript with an explicit chapter order. Original writing pages remain available independently of their exports.
>
> Third-party acknowledgements are available in the app's native Settings bundle. The app does not use an advertising tracking SDK. Exporting and copying blog text do not automatically publish content to a website or external messaging service.

Keine Demo-Zugangsdaten erfinden oder private Schlüssel ins Git übernehmen. Ob für tatsächlich aktivierte Zusatzfunktionen ein Review-Zugang benötigt wird, ist vor Auswahl des Release-Builds zu klären. Ansprechpartner, Telefonnummer und erreichbare E-Mail müssen in App Store Connect endgültig hinterlegt werden; Tester-Adresse und Review-Kontakt sind unterschiedliche Angaben.

## Funktionsbezogene Ergänzungen vor der endgültigen Review-Notiz

| Bereich | Erforderlicher Nachweis vor Übernahme in die endgültigen Unterlagen |
|---|---|
| iCloud/CloudKit | Aktuelle Signierung mit Container/APNs, produktives Schema, reale Synchronisation/Freigabe auf zwei Geräten sowie Rollen/Kommentare/Antworten/Erledigen |
| KI mit API-Schlüsseln | Reale Anbieteranfragen, Auswahl/Kontext/Abbruch/Fehler und Zustimmung zur Weitergabe; Anbieter und gesendete Inhalte müssen vor Versand klar erkennbar sein |
| ChatGPT-Abo-Zugang | Tatsächliche kommerzielle Autorisierung und Live-Inferenz; keine Gleichsetzung mit einem normalen ChatGPT-Abonnement ohne Integrationsberechtigung |
| Apple PCC | Reale Berechtigung und Verfügbarkeit am Gerät mit Sprach-/Regionsprüfung; keine pauschale Offline- oder Geräteverfügbarkeitszusage |
| Textprüfung in 20+ Sprachen | Zwanzig tatsächlich integrierte Grammatik-/Stilsprachen; Wörterbücher und abgeschlossene Null-Ergebnis-Checks genügen nicht |
| Geplante Aufgaben | Reale OS-Ausführung/Abbruch/Settlement; keine garantierte minutengenaue Hintergrundausführung |
| Accessibility | Native VoiceOver, größere Schrift, Tastatur, Kontrast/Bewegung nach aktueller Evaluation; keine Accessibility-Labels allein aus Quellcode ableiten |

Diese Punkte bleiben Teil des verbindlichen Produkts. Die vorsichtige Store-Beschreibung ist kein Vorschlag, sie aus dem Release-Ziel zu streichen.

## Datenschutz und Compliance

Die [Datenschutztexte DE/EN](../legal/README.md) sind Arbeitsfassungen. Vor Einreichung braucht es eine öffentlich erreichbare Datenschutz-URL und Support-Seite, endgültige Verantwortlichenangaben und eine am Release-Build geprüfte In-App-Verlinkung. Eine private GitHub-Datei ist keine geeignete öffentliche Datenschutz-Seite.

App-Privacy-Angaben in App Store Connect müssen anhand der tatsächlichen Datenflüsse ermittelt werden. Das vorhandene Privacy Manifest enthält keine Tracking-Domains und erklärt den UserDefaults-Zugriff, ersetzt aber nicht den Fragebogen. Lokale Manuskripte, optionale Anbieter-Übermittlungen, OAuth-Accountkennungen, Support und Diagnose/TestFlight sind getrennt zu prüfen. „Keine Datenerfassung“ oder „nicht mit der Person verknüpft“ nicht allein aus fehlender Werbeanalytik ableiten. Grundlage: Apples [App Privacy Details](https://developer.apple.com/app-store/app-privacy-details/).

Apple fordert bei externer KI die klare Offenlegung der Weitergabe personenbezogener Daten und ausdrückliche Erlaubnis vor dem Versand. Die alten Workspace-Dienst-Zustimmungsmodelle sind kein Nachweis dafür, dass jeder aktuelle KI-Pfad dies erfüllt. Review-Aufzeichnung und Netzwerk-/Quellprüfung für die final aktivierten Pfade müssen den Nachweis liefern. Grundlage: [Guideline 5.1.2](https://developer.apple.com/app-store/review/guidelines/).

Die bekannte Build-2-Exportdeklaration war ausdrücklich freigegeben und abgeschlossen. Sie ersetzt keine Quell-/Binärprüfung eines neuen Builds. Aktuelle Quellen nutzen Apple-Systemkryptografie unter anderem für HTTPS, Keychain und SHA256; die endgültige Verschlüsselungsdeklaration ist an den tatsächlich hochgeladenen Build und seine Abhängigkeiten zu binden. Die bestehende Freigabe des Nutzers zum Ausfüllen bleibt erhalten; es wurde hier kein neues Formular gespeichert.

Altersfreigabe, Preis/Verfügbarkeit, DSA-Händlerangaben und sonstige regionale Fragebögen müssen mit den tatsächlichen Inhalten/Funktionen beantwortet werden. Keine Altersfreigabe aus dem App-Genre erraten. Der Settings-Lizenzbereich muss im signierten App-Paket enthalten sein; sämtliche finalen Abhängigkeiten und Lizenztexte nochmals abgleichen.

## Aktueller Lieferstand und Reihenfolge

Aktueller lokaler Nachweis: 618 Swift-Testing-Headline-Tests, vier optionale Skips, 58 XCTest; unsignierte Simulator-/Release-Kompilierung. Der neueste gespeicherte externe Audit unter releases/build3/current-20261011 meldet PCC aktiviert, iCloud/Push nicht aktiviert und lediglich den älteren Build 2 im internen Test. Das ist ein datierter Nachweis, kein hier erneuerter Portalstatus.

1. Die gesamte [R01–R15-Abnahme](../ACCEPTANCE_STATUS_20261010.md) am vollständigen Produkt abarbeiten; bestehende konkret angefragte Capability-Freigabe auflösen, ohne sie durch automatische Provisionierung zu umgehen.
2. Passende Profile und produktive CloudKit-Konfiguration herstellen; aktuellen Quellstand signiert archivieren und den vollständigen Signierungsverifier ausführen.
3. Hochladen, Verarbeitung/Export-Compliance/Zuordnung zur internen Gruppe einzeln bestätigen und genau diesen Build auf Geräten installieren und prüfen.
4. Aktuelle DE/EN-Screenshots erzeugen, öffentliche Support-/Datenschutzseiten prüfen, Kontakte/Preis/Fragebögen vervollständigen und Store-Texte mit dem tatsächlichen Build abgleichen. Verfügbarkeit des vorgeschlagenen lokalisierten App-Namens in App Store Connect prüfen; es wurde kein Name reserviert oder geändert.
5. Erst dann den geprüften Build und vollständige Metadaten zur Apple-Prüfung einreichen. Nach Genehmigung manuell veröffentlichen, wenn diese vorgeschlagene Release-Option bestätigt bzw. im Portal übernommen wurde.

`readyForSubmission: false` ist daher absichtlich gesetzt. Kein aktueller signierter Archive/Upload, keine neue interne Installation, kein App-Review-Submit und keine öffentliche Veröffentlichung sind durch diese Unterlagen belegt.
