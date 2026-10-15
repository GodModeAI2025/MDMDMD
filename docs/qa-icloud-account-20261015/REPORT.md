# Neue iPhone-Rückmeldungen: Speicher und Kontozugriff

15. Oktober 2026. Nach erneuter Browser-Anmeldung wurde das neue TestFlight-Feedback tatsächlich geöffnet und sein vollständiges Originalbild geprüft. Die bereits früher geprüften Build-8-Berichte werden nicht als neue Meldung ausgegeben.

## Zwei getrennte Befunde

1. Feedback `AJSX3xIaEsOZSGg0uVyFvDU`, übermittelt um 05:46 CEST: **1.0.1 (9), iPhone 17 Pro Max, iOS 27.2**. Im Dialog „iCloud-Freigabe → Personen einladen“ steht, dass der lokale Synchronisationsspeicher nicht geöffnet oder gesichert werden konnte. `testflight-build9-local-storage.jpg` und die bereinigten Angaben in `FEEDBACK.json` sind erhalten. Das passt zur alten Sammelmeldung für mehrere Speicher-/Projektionsfehler, beweist aber noch nicht, welcher einzelne Fehler auf dem Gerät auftrat. Die separat reproduzierte Base64-Kapazitätsüberschreitung ist in Build 10 korrigiert; sie wird nicht ohne Diagnose als bestätigte Ursache dieses Geräts behauptet.
2. Der direkt im Chat übermittelte Screenshot von **07:11:03** zeigt „iCloud derzeit nicht verfügbar“ und „Für Scriptum ist kein iCloud-Konto verfügbar“. Das ist ein anderer Fehlerpfad. Das Bild enthält weder genaue Buildnummer noch technischen Fehlercode. Die Testerübersicht zeigte zuletzt Build 9 auf demselben iPhone; eine genaue Zuordnung des neu angehängten Bildes bleibt deshalb gesondert zu bestätigen. `user-no-account.png` ist eine Lesekopie des originalen HEIC-Anhangs.

Der Code bildet sowohl `CKAccountStatus.noAccount` als auch `CKError.notAuthenticated` auf diesen Kontohinweis ab. Die reine Meldung unterscheidet die beiden nicht. Sie ist kein Beweis dafür, dass der Nutzer insgesamt nicht bei Apple/iCloud angemeldet wäre. Andere Zustände (restricted, temporarilyUnavailable, couldNotDetermine) und Einrichtungsfehler werden getrennt behandelt. Apple beschreibt die [Kontostatus-Abfrage](https://developer.apple.com/documentation/cloudkit/ckcontainer/accountstatus(completionhandler:)) als Prüfung des für CloudKit verfügbaren Kontozugangs; die [Statuswerte](https://developer.apple.com/documentation/cloudkit/ckaccountstatus) bleiben unterscheidbar.

## Bereits ausgelieferte Hilfe zur Eingrenzung

Build 10 enthält einen tatsächlich im Simulator geprüften Einstieg: sichtbarer Startbutton → Seitenliste → Wolkensymbol → iCloud. Auch das Seitenmenü hat einen direkten Zugang. Die Diagnose zeigt Version, Build, Betriebssystem, Sitzungszustand und begrenzten Fehlercode. `Account.noAccount` und `CloudKit.9` lassen sich damit unterscheiden, ohne Kontokennungen, Manuskripte oder unkontrollierte Fehlerbeschreibungen zu erfassen. Kein Authentifizierungs- oder Sandbox-Schutz wurde dafür umgangen.

iOS 1.0.1 (10) und native Mac 1.0.1 (13) sind nach abgeschlossener Verarbeitung und Export-Compliance in **Mark – Intern → Im Test** bestätigt. Das ist keine Bestätigung, dass der neue Build auf dem betroffenen Gerät bereits installiert wurde oder dessen Kontozugriff behoben ist. Verteilungs-/Store-Status und Nachweise stehen unter `../releases/ios10-mac13/`.

## Weitere Eingrenzung

Den tatsächlichen Fehlercode der bestehenden Diagnose mit dem installierten Build und der Aktion (Aktivierung, Synchronisieren oder Teilen) abgleichen. Bei bestätigtem lokalem Speicherfehler den erhaltenen Code gezielt reproduzieren; bei Kontozugriffsfehler den Apple-Status und dessen Aktualisierung untersuchen. Keine pauschale Ab-/Anmeldung empfehlen, keine persönlichen Cloud-Daten zurücksetzen und keinen erfolgreichen Mac-Test als iPhone-Beweis ausgeben. Zusätzliche physische Gerätetests werden nicht als neues verpflichtendes Release-Gate eingeführt.

Gespeichert sind nur die relevanten eigenen Nutzerbilder und die für die Fehlerzuordnung nötigen Angaben. Signierte Bild-URLs, Asset-Manifeste, E-Mail, Mobilfunkanbieter und allgemeine private Portal-/Sitzungsdaten wurden nicht in den Bericht übernommen.
