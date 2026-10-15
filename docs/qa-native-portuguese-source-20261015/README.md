# Portugiesisch: editierbare Quelle des tatsächlich verwendeten Taggers

15. Oktober 2026 · Ausgangsstand 34c8126 · R14-Auslieferungsvorbereitung. Kein App-Target, keine Produktionsabhängigkeit, kein Store-/TestFlight-Status und keine Anbieterwahl wurde geändert.

## Ergebnis

Der alte Maven-SCM-Verweis auf `portuguese-dict-tools` ist für diese Suche veraltet. Das offizielle [portuguese-pos-dict-Repository](https://github.com/languagetool-org/portuguese-pos-dict/tree/a6169eda21a11cc4fc6de241cbed3cc9912322d2) besitzt den passenden Tag v1.2.0, Commit a6169eda21a11cc4fc6de241cbed3cc9912322d2. Das tatsächlich geladene Archiv ist auf SHA256 dd771c85ed0b8bd439d73477021225c621fa07730824b32a6f4bca969124f898 gebunden. Das Release-POM liegt unter results/java-lt und verwendet PT_DICT_VERSION; die frühere Suche nur nach einem Root-POM war nicht ausreichend.

**Alle 16.679.668 unterschiedlichen Form-/Lemma-/POS-Zeilen des tatsächlichen Maven-Taggers stimmen mit der Neugenerierung aus den editierbaren Originaldaten überein.** Der identische SHA256 der vollständigen byte-sortierten Zeilen lautet 264b14639f4ae3826134e182fec1a37b216095e4de6214e26debcc49075fb145. Kein Frequency-Suffix wurde entfernt, kein Unicode normalisiert und kein Tag umgeschrieben. [Vollständiger Prüfnachweis](ROW_EQUIVALENCE.json).

Die mit dem Git-Tag eingecheckten Binärdateien sind dagegen älter: Vier der 13 Release-Ressourcen sind byte-identisch, neun verschieden; keine fehlt. Der alte Tagger-Snapshot enthält 16.643.167 statt 16.679.668 Zeilen. Diese Gegenprobe bleibt erhalten und wird nicht als erfolgreicher Binärabgleich ausgegeben. Der erfolgreiche Vergleich betrifft die editierbaren Morphologie-/Flexionsquellen und den tatsächlich eingesetzten Release-Tagger, nicht diese alten Snapshot-Binärdateien.

## Tatsächliche Reproduktion

Die unveränderten Originalgeneratoren inflect-nominals.pl und conjugate-verbs.pl erzeugen Nomen, Adjektive und Verben einschließlich der ursprünglichen Klitika. Alle drei Prozesse enden mit Exit0 und ohne stderr. Der Build liest 204 exakt an das Quellarchiv gebundene Eingabedateien einschließlich Flexio.pm und sämtlicher Verbmodelle. Nur zwei reine Perl-Buildmodule wurden in einem eigenen lokalen Ordner aus CPAN bereitgestellt; keine systemweite Installation und keine neue App-Abhängigkeit. Ihre Archive und Moduldateien sind in PERL_DEPENDENCIES.json gebunden.

Der vorhandene geprüfte Java17/Morfologik-Decoder liest das reale gepinnte Maven-JAR und den alten Tag-Snapshot vollständig aus. Der verwendete eigene Decoder steht jetzt dauerhaft unter Research/NativeWritingQuality/DumpDictionary.java. MORPHOLOGY_COMMANDS.json und DECODE_COMMANDS.json enthalten die tatsächlich ausgeführten Argumentlisten. Originale Lizenzen, Dokumentation und Build-Anweisung sind unverändert unter upstream erhalten; sie werden nicht zu einer MIT-Lizenz umgedeutet.

verify_portuguese_source.py bindet die 204 Eingaben erneut an das Archiv, übernimmt exakt die belegten ASCII-/Kommentar-Buildschritte und vergleicht sämtliche generierten und decodierten Felder. Der abschließende Vergleich nutzt die Systemsortierung mit einem 64M-Puffer statt großer Python-Zeilenmengen. Sechs Werkzeugregressionen bestehen: unverändertes Unicode/Tags, belegte Kommentarbereinigung, fehlerhafte/überlange Zeilen, genaue Sortierfingerprints, geänderte Quellen/Symlinks und Python3.9-kompatibles Streaming-Hashing. Ein erster eigener Verifier-Lauf endete vor jeder Ausgabe am nicht verfügbaren hashlib.file_digest von System-Python3.9; die Streaming-Korrektur und der erfolgreiche finale Lauf sind getrennt erfasst.

Das lokale SourceMaterials.zip enthält 23 Einträge mit Quellarchiv, Build-Abhängigkeiten, Werkzeugen, Originalhinweisen und Prüfrezepten. Sämtliche Dateien wurden aus dem fertigen ZIP erneut gelesen und gehasht. [Paketbeleg](SOURCE_PACKAGE.json). Das große Archiv liegt ausschließlich im eigenen work/native-quality-portuguese-20261015/source-materials; Hashes und Manifest sind im Git. Es wurde nicht veröffentlicht.

## Grenzen

Dies schließt die veraltete portugiesische Quellversionssuche und den vollständigen editierbaren Tagger-Zeilenabgleich. Synthesis-/Spelling-Daten, byte-identische FSA-Erzeugung, übrige Datenartefakte und abschließende native Relinking-/Distributionsmaterialien bleiben separat offen. Das ist weder eine Rechtsfreigabe noch ein vollständiger Herkunftsnachweis sämtlicher 13 Ressourcen. Der vorhandene 20+-Sprachenanspruch wird damit nicht vorschnell als erreicht erklärt. Die gewöhnliche App enthält den nativen Sprachdaten-/Framework-Baustein weiterhin nicht; iOS12 bleibt der unverändert ausgelieferte iCloud-Korrekturbuild.

## Aufräumen und Wiederherstellung

Sechs große, ausschließlich in diesem Lauf erzeugte Zeilendateien (insgesamt 4.385.734.608 Bytes) wurden nach SHA256-Gruppierung und vollständigem Gzip-Leserückvergleich durch 545.529.762 Bytes komprimierte Nachweise ersetzt. Identische sortierte Kopien teilen sich ein exakt rücklesbares Backup. Jede ursprüngliche Datei ist über den Eintrag in CLEANUP.json bytegenau wiederherstellbar. Quellarchive, originale Quelldateien, Abhängigkeiten, kleine Generatorausgaben, Decoder, Rezepte und Logs bleiben erhalten. Dies entfernt keine persönlichen Dokumente oder früheren Prüfnachweise. Vor dem erneuten Verifier-Aufruf ist die betreffende decodierte TSV-Datei mit dem in CLEANUP.json benannten Gzip-Backup wiederherzustellen.

Die sechs neuen Verifier-Tests und sechs bestehenden Archiv-Sicherheitsregressionen bestehen. Da keine App-Quelldatei oder App-Abhängigkeit geändert wurde, wurde die zuvor bestandene 811-Test-App-Suite nicht erneut ausgeführt und kein weiterer Xcode-Build als neu behauptet.
