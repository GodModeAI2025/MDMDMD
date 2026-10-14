# Textprüfung: Kategorien und reale Antworten — 2026-10-14

## Behobener Fehler

Der App-Decoder ordnete Typografie, Zeichensetzung, Inkonsistenz und nicht kategorisierte Regeln pauschal der Grammatik zu. Er wies den gültigen LanguageTool-Typ `whitespace` vollständig ab. Ein solcher Treffer konnte dadurch die gesamte Prüfung scheitern lassen; die persische Regel `ReplaceLettersInSameLangs` liefert genau diesen Typ.

Die App zeigt solche Hinweise jetzt unter **Sonstiges**, einschließlich eines eigenen Filters und Dialogtitels. Explizite Fehlertypen und belegte kanonische Kategorien werden korrekt zugeordnet. Die französischen/griechischen `AGREEMENT`-Regeln und `GENDER_AGREEMENT` bleiben Grammatik. Wortwiederholung gehört wie bei der lokalen Prüfung zu Stil. Unbekannte, aber begrenzte Typmetadaten bleiben nutzbar; leere oder überlange Metadaten werden abgewiesen. Quellbytes, Revision, UTF-16-Bereiche und Markdown-Schutz bleiben Voraussetzungen jeder Ersetzung.

## Verifikation

- Die erste Regression lieferte **12 Fehler** bei 17 Kategoriebeispielen: falsche Zuordnung oder abgewiesene gültige Antwort. `rule-category-red.log` hält das Ergebnis fest.
- Ein zusätzlicher Rot-Grün-Schritt prüft die echten französischen/griechischen Agreement-Regeln sowie den kanonischen Geschlechtskongruenz-Typ.
- Der Textprüfungs-Testtarget im Gesamtprojekt bestand **50 Tests**, einschließlich Exportgrenzen und der neuen Testressource. Nach der letzten Agreement-Ergänzung bestanden beide betroffenen Tests erneut: **19 Kategoriebeispiele** und **29 reale synthetische Sprachantworten**.
- Der endgültige generische iOS-Debug-Build ist erfolgreich. Keine Installation, kein neuer Gerätetest, keine Signierung und kein Upload wurden daraus abgeleitet.

Die bereits vorhandene, gepinnte LanguageTool-6.6-Engine lief für diese Prüfung nur auf `127.0.0.1:8097`. Es wurden ausschließlich die vorhandenen synthetischen Regelbeispiele gesendet. Der Prozess wurde nach der Erfassung beendet; es wurde kein öffentlicher Dienst eingerichtet. Die vollständige Antwort-Fixture liegt in `Modules/SkriptumWritingQuality/Tests/SkriptumWritingQualityTests/Fixtures/LanguageTool66SyntheticResponses.json` und wird nur in Test-Bundles eingebunden. Herkunft und externe Runtime-Lizenzen sind in [Server/WritingQuality](../../Server/WritingQuality/README.md) dokumentiert. Keine neue Produktionsbibliothek wurde eingebaut.

## Aussagegrenze und R14

In der Stichprobe werden nach der Korrektur **4 Grammatik-, 5 Rechtschreib- und 23 sonstige Treffer** verarbeitet. Sie enthält keine Stiltreffer; das ist keine Aussage über die gesamten Stilregeln der Engine. Alle 29 synthetischen Antworten sind durch den App-Decoder nutzbar. Die Zahl 29 bezeichnet damit **Sprachbeispiele mit verarbeiteten Antworten**, nicht 29 umfassend belegte Grammatik-/Stilsprachen.

Die integrierte Grammatik-/Stilprüfung in 20+ Sprachen bleibt offen. Weder diese Antwort-Fixture noch ein Katalog beweist umfassende Qualität je Sprache, native Apple-Abdeckung oder eine dauerhaft vom Gerät erreichbare HTTPS-Route. Die TestFlight-/App-Review-Veröffentlichung von Build 8 bleibt der gesonderte ausgelieferte Quellstand. Diese Änderung ist noch nicht hochgeladen.

`verification.json` bindet die Prüfergebnisse an die Quell- und Fixture-Hashes. Die alten Engine-Nachweise wurden unverändert erhalten.
