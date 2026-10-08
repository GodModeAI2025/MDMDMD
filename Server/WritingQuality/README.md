# Eigener LanguageTool-Regelserver

Dieser Server ergänzt die native iOS27-Prüfung. Kein öffentlicher Dienst wird vorkonfiguriert. Er prüft Regeln, keine cloud-exklusiven KI-Regeln; KI-Lektorat bleibt beim ausdrücklich gewählten Skriptum-Anbieter.

## Reproduzierbarer lokaler Start (macOS arm64)

```sh
python3 Server/WritingQuality/bootstrap.py --work-directory /absolute/path/to/task/work
/absolute/path/to/task/work/writing-quality-runtime/jdk-21.0.12.1+1-jre/Contents/Home/bin/java -cp /absolute/path/to/task/work/writing-quality-runtime/LanguageTool-6.6/languagetool-server.jar org.languagetool.server.HTTPServer --port 8097
python3 Server/WritingQuality/verify_engine.py --distribution /absolute/path/to/task/work/writing-quality-runtime/LanguageTool-6.6 --output /absolute/path/to/task/work/quality-engine-evidence.json
```

Keine globale Java-Installation, kein LaunchDaemon, kein `--public`, kein CORS-Freigabeschalter. Der Prozess bleibt nur bis zu seinem expliziten Ende aktiv. Mit Ctrl-C stoppen. Kein fastText-Modell installiert: automatische Erkennung ist schwächer; Skriptum fordert explizite Sprache.

## Distribution und Integrität

- LanguageTool **6.6**, offizielle HTTPS-Distribution `https://languagetool.org/download/LanguageTool-6.6.zip`, SHA-256 `53600506b399bb5ffe1e4c8dec794fd378212f14aaf38ccef9b6f89314d11631`.
- Dieser LT-Hash wurde aus dem über die offizielle TLS-Domain bezogenen Archiv berechnet und hier als reproduzierbarer Pin festgehalten. Kein separat veröffentlichter Publisher-Hash oder Signatur wurde gefunden/verifiziert; keine Behauptung einer Publisher-Signatur.
- Adoptium Temurin JRE **21.0.12.1+1**, macOS aarch64, offizielles Temurin-Release; SHA-256 `dec50fc6f9fcd4fe3ae8cabf5a5fa68f6afc48841f7698e468e9aa5d54beed84` stimmt mit dem von `api.adoptium.net` veröffentlichten Paket-Checksum überein. GPG-Signatur nicht geprüft.
- Referenzen: https://dev.languagetool.org/http-server und https://api.adoptium.net/v3/assets/latest/21/hotspot?architecture=aarch64&image_type=jre&os=mac . Der Metadata-Endpunkt ist aktuell; Bootstrap verwendet feste Versions-URL und Hash.
- Redistribution/Serverbetrieb muss die jeweils mitgelieferten LGPL/MPL/Apache/GPL-Lizenztexte der Komponenten beibehalten. Die großen Distributionsarchive und Runtime werden nicht im App-Repository gespeichert oder in die iOS-App eingebaut.

## Tatsächliche Verifikation

ENGINE_EVIDENCE.json enthält ausschließlich synthetische Beispiele aus den heruntergeladenen Regeln, die gegen die reale lokale Engine geprüft wurden. 60 Katalogeinträge ergeben **31 primäre Sprachen**, nicht 60 und nicht32: `de-DE-x-simple-language` ist eine deutsche Variante. In **29** verschiedenen primären Sprachen wurde mindestens ein echter Nicht-Rechtschreib-Regeltreffer ausgeführt. `crh` und `uk` wurden in diesem Lauf nicht durch ein solches Beispiel bewiesen. Die Kategorien enthalten auch Stil/Punktuation/typografische Regeln: das beweist regelbasierte Sprachprüfung, nicht gleiche Grammatikqualität in jeder Sprache. Native Apple-Grammatikabdeckung wird davon unabhängig behandelt.

## Nutzung von iPhone/iPad

`localhost` des Macs ist nicht `localhost` des iPhones. Der App-Client akzeptiert ausschließlich einen bewusst konfigurierten **HTTPS**-Basisendpunkt (z.B. `https://writing.example.internal/v2`), keine URL-Credentials und keine Redirects. Ein eigener TLS-Reverseproxy mit gültiger/auf dem Gerät vertrauter Zertifikatskette und zugriffsbeschränktem Netz muss die Engine bereitstellen; ungeschützte öffentliche Veröffentlichung ist nicht Bestandteil dieser lokalen Verifikation. Root App setzt keinen Standardendpunkt. Das Loopback-HTTP-Protokoll ist nur die lokale Engine-Verifikationsstrecke, kein in die App eingebauter HTTP-Fallback. Eine erreichbare HTTPS-Route auf dem Gerät bleibt separat zu verifizieren.

Anfragen maximal100KB UTF-8, Antworten maximal2MB, maximal5000 Treffer. Fehler, fehlende Sprachbestätigung, TLS-Vertrauen und Abbruch werden zurückgegeben; kein anderer Anbieter übernimmt still. Jede Korrektur ist an volle Quellbytes und Revision gebunden und muss manuell übernommen werden.
