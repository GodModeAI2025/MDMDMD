# SkriptumWritingQuality API

`QualityDocument(source:revision:)` ist ein unveränderlicher Prüf-Snapshot. `QualityFinding` enthält `range` (UTF16), Original, Regel-ID, Art (`spelling/grammar/style/other`), Engine, Nachricht und angebotene Ersetzungen. `finding.applying(replacement,to:currentDocument)` prüft Revision, vollständige UTF8-Quellbytes, Surrogatgrenzen, geschützte Markdown-Bereiche und angebotene Ersetzung; gibt Markdown zurück oder wirft. App registriert die Übernahme als Undo-Transaktion. Nach jeder Übernahme erneut prüfen; verbleibende alte Treffer sind bewusst stale.

`finding.context` enthält den wörtlichen Zusammenhang aus demselben Prüf-Snapshot: höchstens 80 vollständige Zeichen vor und nach dem Treffer, begrenzt durch Zeilenumbrüche. Kürzungen sind ausdrücklich gekennzeichnet. Der Korrekturdialog zeigt die Originalstelle fett und unterstrichen im Zusammenhang. Die Anzeige interpretiert keine Markdown-Syntax und benötigt keine erneute Manuskriptprojektion. Kontext ist ausschließlich Anzeige; die Freigabe einer Ersetzung bleibt an die vollständigen Quellbytes und Revision gebunden.

- `LocalStyleReviewer.check(document)`: lokale **Basis**-Stilregeln (unmittelbare Wortwiederholung), keine umfassende Grammatikbehauptung.
- iOS27 `await NativeWritingReviewer.check(document, spellingLanguage:)`: tatsächliches `UITextChecker.requestGrammarChecking` und Rechtschreibung. `spellingLanguages` listet allein SPELL-Wörterbücher. Grammatik-Sprache richtet sich nach systemseitiger Verfügbarkeit; aus der Wörterbuchliste wird keine20-Sprachen-Grammatikzusage abgeleitet. Native Callback-Ergebnisse werden vor dem Actor-Wechsel in Sendable-Treffer konvertiert. Abbruch invalidiert genau einmal den wartenden Callback; spätere Systemantwort wird verworfen.
- `LanguageToolConfiguration(endpoint:)`: verlangt explizites HTTPS ohne URL-Credentials/Query/Fragment. `LanguageToolClient.languages()` fragt live den eigenen Katalog ab, `check(document, language:)` bestätigt Sprache und prüft den maskierten Snapshot. `LanguageCatalog.distinctLanguageCount` zählt primäre Sprachen, keine regionalen/einfachen Varianten.

Die Markdown-Projektion maskiert konservativ Code, URLs, HTML, komplette Links/Medien und Syntaxmarker unter Erhaltung sämtlicher UTF16-Offets. Deshalb wird Link-Beschriftung bei Inline-Links bewusst nicht korrigiert. Überlappende Treffer werden übersprungen. Neue Markdown-Markierungen/Zeilenumbrüche in angebotenen Ersetzungen können nicht übernommen werden. Der Client verwendet ephemere URLSession ohne Cache/Cookies, verweigert Redirects, begrenzt Bytes und validiert Kategorien/Offsets. Keine öffentlichen Standards, keine KI-Regeln, keine stillen Fallbacks.

Die Root-App muss den Task und dessen Request-ID halten, ein Ergebnis nur bei unveränderten Revision/Quellbytes anzeigen/übernehmen, Fehler sichtbar machen und den Task bei Schließen/Neustart abbrechen. Keine Prüfung gilt durch die Existenz eines Pickers als verifiziert.

## Gebündelte native Regeln: Integrationsschnittstelle

`BundledRuleReviewer(engine:)` prüft den maskierten Snapshot in vollständigen Abschnitten und verwendet denselben validierenden Decoder wie der eigene Regelserver. Die Herkunft wird vom Aufrufer festgelegt (`LanguageTool 6.6 · lokal`); Antwortmetadaten können sie nicht überschreiben. Die Engine muss die angefragte Sprache ausdrücklich in ihrem Katalog führen. Es gibt keinen automatischen Wechsel zu einem Server oder KI-Anbieter.

`BundledGrammarEngine.check(text:language:)` ist ein synchroner Treibervertrag: pro Aufruf einen eigenen nativen Isolate erzeugen und auf demselben Thread vollständig abbauen, auch bei Fehlern. Ein prozessweiter serieller Worker begrenzt die gleichzeitigen nativen Prüfungen über alle Fenster hinweg auf eine. Abbruch beendet den wartenden Swift-Aufruf sofort; ein bereits laufender nativer Abschnitt darf seinen Speicher freigeben, sein Ergebnis wird verworfen. Die nächste native Prüfung wartet auf diesen Abbau. Das ist keine Unterbrechung mitten in einer nativen Regel und keine Laufzeitgarantie für einzelne Regeln.

Fehler oder Abbruch eines späteren Abschnitts liefern keine teilweise erfolgreiche Prüfung. Korrekturen bleiben manuell, an Originalbytes und Revision gebunden und durch die Markdown-Strukturprüfung geschützt. Diese Schnittstelle aktiviert keine Engine in der App. Der Graal-Treiber und seine Ressourcen bleiben bis zur fertigen Produktions- und Lizenzintegration unter `Research/NativeWritingQuality` ausgeschlossen.

## Regelkategorien

LanguageTool-Typografie, Zeichensetzung, Leerzeichen, Formatierung und nicht zugeordnete Hinweise erscheinen unter **Sonstiges**. Sie erhöhen nicht die Grammatikzahl. Explizite Grammatik-/Stil-/Rechtschreibtypen und die belegten kanonischen Kategorien `GRAMMAR`, `AGREEMENT`, `GENDER_AGREEMENT`, `STYLE`, `TYPOS` werden entsprechend zugeordnet; unbekannte, aber begrenzte Typmetadaten bleiben als Sonstiges nutzbar. Wortwiederholungen gehören wie bei den lokalen Regeln zur Stilprüfung. Leere oder überlange Typmetadaten bleiben ungültig.

Eine gespeicherte Test-Fixture mit frischen Antworten der realen lokalen LanguageTool-6.6-Engine prüft 29 synthetische Sprachbeispiele durch den gemeinsamen App-Decoder, einschließlich eines zuvor abgewiesenen persischen Leerzeichen-Typs. Die Fixture wird ausschließlich in Test-Bundles eingebunden. Das belegt Antwortverarbeitung, keine umfassende Grammatik-/Stilqualität in 29 Sprachen und keine native Apple-Sprachabdeckung.


## App-runtime integration checkpoint · 15 October 2026

`BundledGrammarRuntime` verifies the pinned LanguageTool 6.6 manifest and every raw resource before constructing the private native driver, off the UI actor. Runtime availability requires an explicit `ScriptumGrammar` framework build dependency; the regular app project still excludes the unshipped binary/data package. Shared Textprüfung integration can combine this native grammar/style route with matching Apple spelling only, without silent provider fallback. `NativeWritingReviewer.check(... includingGrammarAndStyle: false)` omits system grammar/basic-style work for that combination; existing callers retain their original default behavior.

[Actual verification and scope](../../docs/qa-native-app-runtime-20261015/README.md): 59 module tests, 29 unchanged native host examples, full-resource validation, measured memory repair and actual Mac/iOS candidate compile/link/sign evidence. A new generated candidate's UI run still requires Xcode's owner approval. Source/relinking/distribution work, broader linguistic acceptance and production availability remain incomplete.
