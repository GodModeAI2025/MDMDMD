# Portugiesische Formenbildung: vollständiger Quellabgleich

15. Oktober 2026 · Ausgangsstand a7593a9 · R14-Quellvorbereitung. Kein App-Target, keine Anbieterwahl, kein Upload und keine Store-Einreichung wurde geändert.

Alle **16.679.668** Form-/Lemma-/POS-Einträge des tatsächlich eingesetzten portugiesischen Synthesis-Wörterbuchs stimmen mit den zuvor aus 204 editierbaren Originaleingaben erzeugten Tagger-Zeilen überein. Alle **1.386** Tags entsprechen exakt der Tag-Inventardatei desselben Release-JARs. Der vollständige sortierte Zeilen-SHA256 lautet `264b14639f4ae3826134e182fec1a37b216095e4de6214e26debcc49075fb145`. [Ergebnis](ROW_EQUIVALENCE.json).

## Methode und Reproduktion

Der [vorherige Quellnachweis](../qa-native-portuguese-source-20261015/README.md) bindet die Originalgeneratoren und Eingaben an den offiziellen portugiesischen Release-Commit a6169eda21a11cc4fc6de241cbed3cc9912322d2. Sein vollständiger Ergebnisbeleg wird hier per SHA256 gebunden; der Vergleich übernimmt weder ältere Snapshot-Binärdateien noch eine Teilmenge.

Der unveränderte LanguageTool-6.6-Verbraucher [BaseSynthesizer.java](upstream/BaseSynthesizer.java) beschreibt die tatsächliche Abfrage: Schlüssel aus Lemma, `|` und POS-Tag, Ergebnis als Wortform. Quellarchiv und Originaldatei sind in [CONSUMER_SOURCE.json](CONSUMER_SOURCE.json) gehasht. Der ursprüngliche LGPL-Hinweis bleibt erhalten; der vollständige [LGPL-Text](../qa-native-portuguese-source-20261015/upstream/COPYING.txt) liegt bereits im Repository.

Der eigene Offline-Adapter `Research/NativeWritingQuality/SynthDictionaryRows.java` liest alle Einträge aus dem gepinnten Maven-JAR `portuguese-pos-dict-1.2.0.jar` (SHA256 fe8da88bb31b6372855741fbd81ee1c7477b4f8a0624d3dafd20ee23e184650e). Er vertauscht ausschließlich die belegten Schlüssel-/Ergebnisfelder zur gemeinsamen Form/Lemma/POS-Darstellung. Unerklärte Zusatz-Tags, mehrdeutige Schlüssel, Kontrollzeichen, leere Felder und überlange Datensätze werden abgewiesen. Unicode wird weder normalisiert noch durch Ersatzzeichen ausgegeben. Der tatsächliche komplette Decoderlauf endet mit Exit0 und 16.679.668 Einträgen.

`verify_synthesis_rows.py` nutzt eine begrenzte Systemsortierung und einen Streaming-Fingerprint. Der Vergleich muss sämtliche Quellzeilen und zusätzlich die vollständige Tag-Mitgliedschaft treffen. [Decoder-/Compile-Rezept](COMMANDS.json), [Verifier-Rezept](VERIFY_COMMAND.json), tatsächliche Logs und Ergebnis bleiben erhalten. Für eine Wiederholung sind die gepinnten lokalen Quelldaten beziehungsweise die im vorherigen Quellnachweis gebundenen Archive erforderlich.

Drei neue Python-Regressionen prüfen gültige vollständige Belege, manipulierte/ungültige Fingerprints sowie die unabhängig erforderliche Zeilen- und Tag-Gleichheit einschließlich verändertem Lemma, falschem Tag, Duplikaten und Schutz bestehender Ausgaben. Die sechs bisherigen portugiesischen Verifier-Tests bestehen ebenfalls: **neun Python-Tests insgesamt**. Der Java-Adapter besteht zwei exakte Unicode/POS-Beispiele und neun fehlerhafte Eingaben. Die App-Tests wurden für diesen reinen Forschungs-/Werkzeugschritt nicht erneut ausgeführt.

## Grenzen und Ablage

Dies belegt die vollständige inhaltliche Entsprechung der verwendeten Synthesis- und Tagger-Daten zu den nachgewiesenen editierbaren Morphologiequellen. Es belegt keine byte-identische FSA-Serialisierung, keine Spelling-Dateien, keine umfassende linguistische Qualität und keine fertige Lizenz-/Relinking- oder Distributionsfreigabe. Die gewöhnliche App enthält den nativen Baustein weiterhin nicht. R14 und der vollständige 20+-Sprachenanspruch bleiben offen. iOS12 in TestFlight und die bestehenden Store-Einreichungen bleiben unverändert.

Große Decoder-/Sortierdateien liegen ausschließlich unter `work/native-quality-synthesis-20261015`. Nach vollständigem Gzip-Rücklesevergleich werden sie komprimiert aufbewahrt; [CLEANUP.json](CLEANUP.json) benennt Originalpfade, Hashes und bytegenaue Wiederherstellung. Bereits vorhandene identische sortierte Nachweise werden gemeinsam genutzt. Persönliche Daten und ältere Belege bleiben erhalten.
