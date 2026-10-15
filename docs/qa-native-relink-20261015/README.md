# Portables Neu-Linken der nativen Grammatik-Frameworks

15. Oktober 2026. Die bisherige Framework-Erzeugung benötigte absolute Pfade zum lokalen Checkout und Gluon-/Maven-Arbeitsbestand. Ein neues internes Eingabepaket enthält jetzt die 1.926 tatsächlich benötigten gepinnten Dateien: beide Native-Objects, Runtime-Archive, ABI-Header, iOS-Fallback samt generiertem Quelltext, alle 1.888 Ressourcen und unveränderte Builder-/Kompatibilitätsquellen. Die Rezeptpfade sind relativ; Apple-SDKs und persönliche Signierschlüssel sind nicht enthalten.

## Tatsächlicher Nachweis

Das Paket wurde in einen anderen Ordner mit Leerzeichen kopiert und aus einem dritten Arbeitsverzeichnis ausgeführt. Der unveränderte Framework-Builder kompiliert den iOS-Kompatibilitätscode, linkt beide arm64-Frameworks, prüft die öffentlichen Symbole und Ad-hoc-Signaturen, validiert alle Ressourcendateien und erstellt das XCFramework. Alle Schritte waren erfolgreich. Die Inputs werden vor dem Compileraufruf vollständig geprüft; unbekannte oder geänderte Dateien, Symlinks, Pfadausbrüche und vorhandene Ausgabeordner werden abgelehnt.

20 Werkzeugtests bestehen, davon sieben neue für das Relink-Paket. Root hat den neuen Paketbauer, Runner und die Tests unabhängig gelesen und Quell-/Beleghashes erneut gegen die aktuelle Ablage geprüft.

Das neue iOS-Framework ist vollständig bytegleich zum vorherigen finalen Kandidaten. Auf dem Mac sind alle 16 belegten Mach-O-Inhaltssektionen bytegleich; UUID, Linkedit beziehungsweise Signaturposition unterscheiden sich. Es wird deshalb keine vollständige Mac-Binary-Gleichheit oder neue Laufzeitprüfung behauptet. Objekt- und Runtime-Archive bleiben entsprechend ihren ursprünglichen Hashes gebunden.

## Reproduktion und Erhaltung

[Rezept und Voraussetzungen](../../Research/NativeWritingQuality/NativeRelinkKit.md), [Paketbauer](../../Research/NativeWritingQuality/prepare_native_relink_kit.py), [Runner](../../Research/NativeWritingQuality/relink_native_kit.py).

Das tatsächlich verschobene Eingabepaket liegt unter `work/native-quality-relink-20261015/relocated inputs/Grammar Relink Kit`. Die erzeugten Frameworks liegen daneben in `relinked-frameworks`. Das doppelte `kit-original` wurde erst nach vollständigem Manifest- und Dateivergleich entfernt, anschließend wurde das erhaltene Paket erneut geprüft. Das Originalmanifest bleibt hier als KIT_MANIFEST.json erhalten; CLEANUP.json belegt freigegebenen Speicher und unveränderte Quellen/Archive. Große Objects und Frameworks bleiben außerhalb von Git.

## Verbleibende Grenzen

Dies schließt das portable technische Framework-Neu-Linken aus den erhaltenen Binary-Objects. Es ersetzt keine Neukompilierung von LanguageTool/Graal/JDK und Sprachdaten aus vollständigen bevorzugten Quellen. Bestehende V3- und portugiesische Source-ZIPs sind vorhanden und frisch hashgeprüft; V3 enthält den späteren portugiesischen Quellen-/Synthesis-Nachweis noch nicht. SDK-/Datenkorrespondenz, App-Rekonstruktion mit Bibliotheksaustausch, neue Entwicklersignierung/Installation und vollständige Distributionsarbeit bleiben offen. Der bisherige Beleg hat den iOS-Fallback-Object-Hash nicht aufgezeichnet; das Paket bindet dessen jetzige Bytes und generierte Quelle ausdrücklich ohne rückwirkende Attestierung.

Keine App wurde installiert, gestartet, mit dieser Engine ausgeliefert oder hochgeladen. Die native Engine bleibt aus den regulären Produktionsabhängigkeiten ausgeschlossen. R14 und das vollständige App-Ziel sind nicht abgeschlossen.

## Ergänzender tatsächlicher Host-Lauf

Root hat anschließend das **neu gelinkte Mac-Framework** mit den unveränderten bestehenden Native-Prüfungen ausgeführt. Alle fünf Gruppen bestehen: 29 feste Sprach-/Spannenfälle, 29 Korrekturkontrollen, fünf lange Textabschnitte, ABI-/Puffergrenzen und kontrollierte Heap-Erschöpfung ohne Teilantwort. Netzwerk war im Prozess gesperrt. Die tatsächliche neue Framework-Datei ist in host-verification/STATE.json gehasht. Dies ergänzt den vorherigen reinen Binary-/Symbolvergleich durch reale Hostausführung. Kein App-, Simulator- oder iOS-Lauf wurde gestartet.
