# Ukrainische LanguageTool-Daten 6.6.0: zusätzliche Quellenbelege

Stand: 15.10.2026. Isolierte Recherche; keine Produktionsabhängigkeit, Sprache, App- oder Projektdatei geändert. Keine Freigabe zur Veröffentlichung oder Weitergabe des gesamten Rohdatenarchivs.

Die konkrete Maven-JAR trägt selbst eine ausdrückliche LGPL-2.1+-Erklärung für die LanguageTool-Wörterbücher. Die unterschiedliche Lizenz des Root-Wörterbuchs ist deshalb kein Beleg dafür, dass die LT-JAR ausschließlich unter CC BY-NC-SA steht. Der vollständige Zusammenhang zwischen allen bearbeitbaren Quellen und den ausgelieferten Binärdaten bleibt jedoch unvollständig nachgewiesen.

Neu gegenüber dem bisherigen `SOURCE_REVIEW.json`: fünf semantische CSV-Ressourcen sind anhand des tatsächlichen Gradle-Kopierpfads bytegenau ihren bearbeitbaren Dateien zugeordnet; dadurch **11 statt 6 von 17 Ressourcen**. Ein späterer, besser belegter Quellkandidat wurde gefunden. Dessen 47 neue, vorab ausgewählte Lemmata kommen sämtlich mit identischem Lemma/Stem im veröffentlichten POS-Wörterbuch vor. Dies ist ein Kandidatenhinweis, kein vollständiger Rebuild.

## Lizenzgeltungsbereiche

| Material | Primärer Beleg | Belastbare Aussage |
|---|---|---|
| Root-Daten und Programme | [Root-README, festes Commit](https://github.com/brown-uk/dict_uk/blob/8eb833b901bb77798d6f37e213880db10c462c87/README.md#license), lokal Zeilen 113–119 | Daten: CC BY-NC-SA 4.0; Programme: GPL 3+. Upstream unterscheidet ausdrücklich die Lizenzen abgeleiteter Projekte. |
| `morfologik-ukrainian-lt-{version}.jar` | [Derivat-README, festes Commit](https://github.com/brown-uk/dict_uk/blob/8eb833b901bb77798d6f37e213880db10c462c87/distr/morfologik-ukrainian/README.md), lokal Zeilen 3–7 | Dieses konkrete LT-Artefakt wird ausdrücklich LGPL 2.1 oder später zugeordnet. Die dokumentierte Ausnahme ist artefaktspezifisch. |
| Tatsächlich genutzte 6.6.0-JAR | `upstream/jar/jar-README.txt`, Zeile 14; `upstream/jar/jar-hunspell-README.txt`, Zeile 6; [offizieller Maven-POM](https://repo.maven.apache.org/maven2/ua/net/nlp/morfologik-ukrainian-lt/6.6.0/morfologik-ukrainian-lt-6.6.0.pom) | Die JAR nennt Analyse-, Synthese- und Rechtschreibwörterbuch und enthält selbst „Licensed under LGPL 2.1 or above“. Die Rechtschreibressource hat zusätzlich eine eigene LGPL-Erklärung. |
| `morfologik-ukrainian-search` | Dasselbe Derivat-README, Zeilen 22–26 | Apache 2.0 betrifft das getrennte Suchartefakt. Dessen README wird im LT-JAR-Task ausdrücklich ausgeschlossen; es ist keine alternative Lizenz für die LT-JAR. |

Die Ausnahme beseitigt nicht automatisch Fragen zur Weitergabe eines vollständigen `dict_uk`-Quellarchivs oder zur Erfüllung sämtlicher Bedingungen im nativen App-Vertrieb. Dafür werden hier keine Rechte neu zugeschrieben. Die technisch identischen CSV-Dateien sind in beiden Kontexten nachgewiesen; eine pauschale Neulizenzierung des übrigen Root-Baums wird nicht behauptet.

## Ressourcenbindung

Die lokale JAR hat SHA256 `3ff49f9b989e3c50eb8d96f4385906b3562b638607aeeddaffd90939695b66a5`. Die frisch gelesene offizielle Maven-Prüfsumme und Gradle-Moduldatei bestätigen dieselben Bytes. Die 17 Ressourcen zählen ohne `META-INF`.

| Ressourcen | Zuordnung | Ergebnis je Kandidat |
|---|---|---|
| Zwei READMEs, drei `.info`, `tagset.txt` | `distr/morfologik-ukrainian/src/main/resources/…` | 6 bytegenau |
| `verb.csv`, `adv.csv`, `adj.csv`, `noun.csv`, `numr.csv` unter `ua/net/nlp/dict_uk/semtags/` | `data/sem/{name}`; `processResources` kopiert diese Dateien ausdrücklich an das JAR-Ziel | 5 bytegenau; neue bevorzugte Quellenbindung |
| `org/languagetool/resource/uk/VERSION` | Root-`VERSION`, laut `processResources` direkt kopiert | Echter Unterschied: Quelle `6.6.0-SNAPSHOT\n`, JAR `6.6.0\n` |
| `ukrainian.dict`, `ukrainian_synth.dict`, `ukrainian_synth.dict_tags.txt`, `ukrainian_tags.txt`, `hunspell/uk_UA.dict` | Generierte Ressourcen; Pfade und Aufgaben sind in `SOURCE_BINDING.json` aufgeführt | 5 nicht rekonstruiert |

Vollständige Pfade, Bytezahlen und beide SHA256-Werte je Paar: `SOURCE_BINDING.json`. Die Zuordnung folgt dem [fest gepinnten Gradle-Build](https://github.com/brown-uk/dict_uk/blob/8eb833b901bb77798d6f37e213880db10c462c87/distr/morfologik-ukrainian/build.gradle), insbesondere Zeilen 85–98. Sie beruht nicht allein auf gleichen Dateinamen.

## Besserer Quellkandidat und verbleibende Rekonstruktion

Die öffentliche Commit-Historie enthält nach dem bisherigen Kandidaten `4787f7a` noch [8eb833b](https://github.com/brown-uk/dict_uk/commit/8eb833b901bb77798d6f37e213880db10c462c87) vom 25.03.2025, 13:06:37 UTC. Maven datiert die [6.6.0-Dateien](https://repo.maven.apache.org/maven2/ua/net/nlp/morfologik-ukrainian-lt/6.6.0/) auf 13:09 desselben Tages. Der spätere Commit ergänzt tatsächliche Lexikondaten. Dies widerlegt die frühere Annahme, der 24.03.-Kandidat sei der letzte Commit vor Veröffentlichung, ohne den neuen Commit allein dadurch als Release-Tag zu beweisen.

Aus dem Commit-Diff wurden vor dem Binär-Lookup alle 47 neuen Erstspalten-Lemmata ausgewählt, die als solche in keinem alten `data/dict/*.lst` standen. Alle 47 lieferten im unveränderten POS-Wörterbuch einen Eintrag mit identischem Stem. Rohantwort: `probe/new-commit-lookups.tsv`; Auswahl und Begründung: `probe/new-commit-queries.json`; Eingabe-, Code- und Bibliothekshashes: `probe/new-commit-lookups-receipt.json`. Eine Quellregel kann weitere Formen erzeugen; der Lookup belegt daher weder die Abwesenheit aller Wörter aus einer vollständigen alten Expansion noch alle Eingaben des Release-Builds.

Auch der neuere Commit enthält weiterhin die SNAPSHOT-Version. Das enthaltene `publish.sh` verweigert eine Veröffentlichung bei SNAPSHOT. Ein unveränderter Checkout allein ist damit nicht der dokumentierte Release-Zustand. Außerdem setzt der LT-Build `ltToolsVersion` von außen voraus; eine Festlegung für diesen Build wurde in den geprüften Build-/README-/Shell-/Properties-Dateien des Archivs nicht gefunden.

Der nächste technische Schritt ist eine isolierte, überprüfte Expansion des neueren Kandidaten aus `data/dict`, `data/affix` und den Groovy-Generatoren. Danach müssen die vollständigen Analyse-, Synthese-, Tag- und Rechtschreibdaten einschließlich Frequenzen mit der JAR verglichen werden. Für einen exakten Binary-Rebuild fehlen noch die Release-Konfiguration und der tatsächlich benutzte `languagetool-tools`-Stand. Root-`expandForCorp` verlangt bis zu 5,2 GB JVM-Heap; dieser Auftrag hat den Build nicht ausgeführt. Der offene Rechts-/Distributionspunkt ist separat von dieser technischen Prüfung zu behandeln.

## Reproduzierbarkeit und Grenzen

`scripts/verify_source_binding.py` liest gepinnte TAR-/ZIP-Dateien ohne Upstream-Code auszuführen und prüft Archivpfade, Doppeleinträge, Größen, Artefakthashes und explizite Kopierzuordnungen. `scripts/prepare_candidate_queries.py` reproduziert die vorab eingefrorene Auswahl bytegleich. Der POS-Lookup ist auf maximal 100 Wörter und 128 MB JVM-Heap begrenzt. Keine Geräte-, Simulator- oder App-Tests.

Der erneute Lauf der hier gespeicherten Prüfscripte ist in `REPLAY.json` dokumentiert: Quellenprüfung 0,24 s, Abfrageauswahl 0,23 s, POS-Lookup 0,79 s, jeweils Exitcode 0. Quellenbindung, eingefrorene Auswahl und sämtliche Lookup-Rohbytes stimmen mit der ursprünglichen Recherche überein. Die Vorher-/Nachher-Hashes sämtlicher geprüfter Eingaben sind gleich; nur neue Prüfausgaben wurden ins isolierte Work-Verzeichnis geschrieben. Das Ergebnis bleibt 11/17 bytegenaue Ressourcen und 47/47 gleiche Lemmata bei den genannten offenen Grenzen.

Erneute Prüfung in ein neues Ausgabeverzeichnis:

```sh
python3 docs/qa-native-ukrainian-source-20261015/scripts/verify_source_binding.py \
  --work-root /Users/markzimmermann/Documents/Codex/2026-10-08/mach/work \
  --output /private/tmp/scriptum-ukrainian-source-recheck
```

Der Befehl wird im Repository ausgeführt und erwartet die unveränderten Archive im lokalen Work-Verzeichnis; sie werden wegen ihres Umfangs nicht nochmals im Repository gespeichert. `REPLAY.json` hält den tatsächlich ausgeführten erneuten Lauf fest. `QA.json` bindet Code und Resultate an SHA256; `SHA256SUMS` schützt die erhaltenen Forschungsartefakte. Beide Kandidatarchive und alle ursprünglichen Prüfunterlagen bleiben erhalten. Produktionsfreigabe, Quellenmirror-Freigabe und vollständiger Preferred-Source-Nachweis bleiben offen.
