# Scriptum release status

Updated 2026-10-14. This page distinguishes the development candidate from the delivered TestFlight build. The complete [R01–R15 requirements](REQUIREMENTS.md) remain binding.

## Current release: 1.0.1 (8)

[Current verification report](qa-release-20261014/README.md) records the writing, AI, undo, keyboard and file-creation repairs, complete local regressions and the separate 95,744-word mixed-manuscript PDF test. Mandatory device and multiple-device gates were removed by the owner. Existing device evidence remains historical.

The final signed export passes all 25 distribution checks. Upload succeeded after the owner renewed Xcode access. Apple processing and export compliance are confirmed. **Mark – Intern shows 1.0.1 (8), Testing.** The same build is **submitted for production, Waiting for Review**, with automatic release after approval. It is not yet approved or published. [Build 8 receipts](releases/build8/README.md).

iCloud is directly under **Dateien → iCloud**. The deployed production schema contains `ScriptumItemV1` and `ScriptumSharedImageV1`; both runtime gates and actual distribution entitlements pass. The Console needs no additional configuration now. Live participant sync and actual provider/region behavior are not inferred from those receipts.

**Separate work by owner instruction:** Jimdo publication of the prepared DE/EN privacy section. The last fresh public-page readback did not contain Scriptum. No Jimdo login or publication performed.

The pre-existing 1.0.0 (7) is separately shown as Ready for Distribution.

## Historical candidate notes (October 12)

- Production code is separated from unshipped prototypes in `Research/`; 455 relocated tracked files retain their exact source bytes. QA evidence and licenses remain versioned. GitHub is the code repository, with no workflows.
- The ordinary editor now applies native keystrokes against the displayed syntax frame. The 43-byte Unicode witness survives editing, durable checkpoint and reopening exactly; rejected drafts are preserved separately. [Evidence](qa-input-frame-20261011/REPORT.md).
- Full local verification for the editor change: 655 Swift Testing headlines (four optional skips) and 58 XCTest, plus unsigned Release compilation. Ten signed-archive-verifier regression tests pass.
- The initial white HTML preview capture was taken before load completion; the stable preview renders correctly. The candidate adds loading/error feedback for page and HTML export previews. Official Xcode MCP verifies the loading indicator followed by actual content on first opening and after closing/reopening the regular page preview; the HTML export caller compiles in Release. [Evidence](qa-preview-loading-20261011/README.md).

## Additional export fix awaiting integration

A separate `fix/epub-author-metadata` branch omits invalid empty EPUB creator metadata. All 124 export-test headlines (one optional skip), unsigned Release compilation and six current-renderer EPUBCheck validations pass. Three 24-chapter profiles preserve paragraph/Unicode/table/footnote/TOC counts independently. [Evidence](qa-epub-conformance-20261012/README.md). Actual Apple Books import requires a concrete confirmation after automatic approval rejected its potential library/synchronization side effect. PR #2 remains at the previously presented `2c2fcf5` commit.

## Selection correction awaiting integration

A separate `fix/structural-selection-retention` branch preserves selected text when an unchanged block is duplicated or moved, including when a native text field is recreated with a new Markdown projection. Two intermediate corrections failed native QA. The final correction also handles actual last-block duplication, which appends separators, and remaps selection when the existing native frame rebases. Final local verification passes 662 Swift Testing headlines (four optional skips), 58 XCTest and unsigned iPhoneOS Release. Fresh official Xcode MCP native verification preserves the full “Foo” highlight after the actual last-block duplication, with unchanged source hashes and no provider request. [Evidence](qa-selection-relocation-20261012/README.md).

The regular Markdown export produces the exact 43-byte Unicode witness. The system Files save dialog did not expose actionable hierarchy controls, so save/import/reopen acceptance remains incomplete. [Partial evidence](qa-markdown-files-20261012/README.md).

## Production PDF integration awaiting integration

A separate `fix/production-semantic-pdf` branch makes the semantic tagged renderer the regular shared route for PDF preview and page/manuscript export. Native regular-launch preview and actual system-share PDF pass with unchanged original source. All 124 export tests pass with the 95,744-word/three-profile opt-in enabled. The unused WebKit PDF class is preserved in Research and removed from the native target. Reader compatibility limits and final Release evidence are recorded in [production PDF QA](qa-production-semantic-pdf-20261012/README.md); tagged output does not certify PDF/UA. Native long/media/theme, accessible-reader and full R13 acceptance remain open.

## Resizability investigation

Regular native phone verification found that rotating the focused editor loses the writing surface to the file-browser root. A foreground-presentation experiment failed and was reverted. A fresh iPad pass reproduced the same failure with the scene-configuration hypothesis, so that change was reverted. The independent writing-bar API modernization remains; it does not fix rotation. [Investigation and retained failures](qa-resizability-20261012/README.md). R10 remains open.

## Library presentation lifetime candidate

A separate `fix/library-presentation-lifetime` candidate retains the library hosting controller independently of the decorative document-browser background, using only the anchor view’s own window. Final unsigned Release compilation passes. Fresh ordinary iPad verification preserves the focused editor through portrait/landscape/portrait, supports close/reopen and opens a second library window with the same scope. Exact complete library bytes remain unchanged. Phone verification also retains the correct editor through rotation and background/foreground, with exact original Unicode source and complete library bytes. Phone rotation still dismisses the keyboard and input focus, and landscape body content is partly clipped. The second-window Markdown creation action did not open a creation UI; pending-typing lifecycle acceptance remains separate. [Evidence and limits](qa-library-lifetime-20261012/README.md). Full R10 and R04 remain open.

## Build 1.0.0 (3), 12 October 2026

Quelle `c9f29e1` auf `fix/compact-writing-viewport`: Fokus-Wiederherstellung nach Drehen (`FocusRestoringTextView`), kompaktes Querformat-Layout und „Neue Markdown-Datei“ aus der Bibliothek. 668 Swift-Testing-Tests (vier optionale übersprungen), 58 XCTest, unsignierter Release-Build. Native Prüfung auf Phone und iPad über Xcode MCP: [Evidenz](qa-merged-ui-20261012/README.md). Fokus, Cursor und Tippen bleiben über Drehungen erhalten, der Editor ist im Querformat nicht mehr abgeschnitten, Dateierstellung funktioniert im Hauptfenster und im zweiten Bibliotheksfenster. Grenzen: Auf den Simulatoren erschien keine Software-Tastatur, daher sind der Fall mit eingeblendeter Tastatur im Querformat und das bewusste Schließen der Tastatur ungeprüft. Der Start-Button „Neue Markdown-Datei“ legte `Untitled.txt` an und wurde entfernt. Die Seitenlisten zweier Bibliotheksfenster laufen bis zur nächsten Aktion auseinander.

Signierung: Nach der Anmeldung im Xcode-Konto setzte `-allowProvisioningUpdates` iCloud/CloudKit, den Container `iCloud.com.mobilebox.Skriptum` und Push an der App-ID und erneuerte die Profile. Der App-Store-Export trägt aps-environment production, CloudKit und PCC ([Nachweis](releases/build3/signed-20261012/distribution-proof-c9f29e1.json)). Der Verifier meldet nur `iCloudRuntimeGate` als offen: Der iCloud-Sync bleibt zur Laufzeit abgeschaltet, bis Produktionsschema und echte Teilnehmer-Zusammenarbeit nachgewiesen sind. Der Upload meldete „Upload succeeded“. Danach verarbeitet, Exportcompliance „None of the algorithms mentioned above“ (wie Build 2) auf ausdrückliche Bestätigung des Nutzers gespeichert, Status Ready to Test, und der Build der internen Gruppe Mark–Intern zugewiesen: Die Gruppe zeigt 1.0.0 (3) und 1.0.0 (2) mit Status Testing ([Nachweis](releases/build3/signed-20261012/testflight-build3-internal.jpg)). Installation und Test von Build 3 auf einem Gerät stehen aus.

## Build 1.0.0 (4), 13. Oktober 2026

Quelle `9959ac2` auf `fix/compact-writing-viewport`: Ulysses-Welle als Antwort auf das TestFlight-Feedback zu Build 3 ([Feedback](qa-testflight-feedback-20261012/README.md), Produktfokus in [REQUIREMENTS.md](REQUIREMENTS.md)). Schreibfläche zuerst: leere Einfügevorlagen, Blockwerkzeuge nur auf Abruf (Kontextmenü, langes Drücken, natives Umsortieren), Tastatur-Zubehörleiste (Fett, Kursiv, Überschrift, Liste, Link, Rückgängig, Wiederholen, KI-Menü), Cursor bleibt sichtbar, Markdown-Zeichen abgedimmt ohne Änderung der Bytes, KI-Aktionen auf Auswahl, aktiven Block oder Seite mit Annehmen/Verwerfen, Assistent beantwortet die Aufgabe statt die Seite zu wiederholen, Seitenleisten bei sichtbarer Tastatur ausgeblendet. Native Prüfung mit Software-Tastatur: [Welle](qa-ulysses-wave-20261012/), [Korrekturen](qa-ulysses-fix-20261013/). Ungeprüft: iPad, echtes Gerät, Tippen mit sichtbarer Tastatur. Lange Rohquellen-Blöcke scrollen bei sichtbarer Tastatur intern (kosmetisch).

Signierung wie Build 3, Verifier meldet nur `iCloudRuntimeGate` ([Nachweis](releases/build4/)). Der Upload lief nach erneuter Xcode-Anmeldung durch. Danach verarbeitet, Exportcompliance „None of the algorithms mentioned above“ auf ausdrückliche Wahl des Nutzers gespeichert (Ready to Test) und der Build der Gruppe Mark–Intern zugewiesen: Die Gruppe zeigt 1.0.0 (4), (3) und (2) mit Status Testing ([Nachweis](releases/build4/testflight-build4-internal.jpg)). Installation auf einem Gerät steht aus.

## Build 1.0.0 (5), 13. Oktober 2026

Quelle `4749463` auf `fix/compact-writing-viewport`, Antwort auf das Feedback zu Build 4 ([Feedback](qa-testflight-feedback-20261012/build4-feedback.md)). Der Freigabedialog „KI-Anfrage freigeben“ entfällt, der Empfänger steht dauerhaft in der Kontextkarte. Ein Chat-Auftrag mit Änderungswunsch ersetzt Auswahl, aktiven Block oder Seite sofort; „Rückgängig“ stellt das Original wieder her. Kontextkarte und Auftragsfeld sind getrennt und hervorgehoben, im Querformat mit Tastatur bleiben Feld und Senden-Pfeil sichtbar. Native Prüfung im Simulator: [Evidenz](qa-assistant-build4-20261013/README.md). Ungeprüft: Ersetzen mit echter KI-Antwort (im Simulator ist kein Anbieter verfügbar), iPad, echtes Gerät. Bekannt: Das Lektorat startet beim Öffnen automatisch und schreibt den Auftragstext in den Chatverlauf der Seite.

Signierung wie Build 3 und 4, Verifier meldet nur `iCloudRuntimeGate` ([Nachweis](releases/build5/)). Upload erfolgreich, Exportcompliance „None of the algorithms mentioned above“ auf ausdrückliche Bestätigung des Nutzers gespeichert, Build der Gruppe Mark–Intern zugewiesen, Status Testing ([Nachweis](releases/build5/testflight-build5-internal.jpg)).

## Build 1.0.0 (6), 13. Oktober 2026

Quelle `2e8ec92` auf `fix/compact-writing-viewport`. Der Chat entscheidet selbst: Fragen beantwortet er, Änderungswünsche setzt er sofort im Bereich (Auswahl, aktiver Block, Seite) um. Der Umschalter Chat/Änderung entfällt. Die Antwort trägt den neuen Text zwischen Markern, die Erkennung hängt nicht mehr an einer Liste von Befehlswörtern. Native Prüfung mit lokalem Test-Anbieter (nur Debug-Builds, im Release-Binary nicht enthalten): [Evidenz](qa-chat-replace-20261013/README.md), alle sieben Punkte bestanden. Ungeprüft: echte KI-Antwort, iPad, echtes Gerät. Offen: Das Rückgängig im Panel verschwindet nach dem Schließen; das Editor-Menü „Textänderung rückgängig“ wurde danach nicht gezielt geprüft.

Signierung wie zuvor, Verifier meldet nur `iCloudRuntimeGate` ([Nachweis](releases/build6/)). Upload erfolgreich, Exportcompliance „None of the algorithms mentioned above“ auf ausdrückliche Bestätigung des Nutzers gespeichert, Build der Gruppe Mark–Intern zugewiesen, Status Testing ([Nachweis](releases/build6/testflight-build6-internal.jpg)).

## App-Store-Einreichung, 13. Oktober 2026

Version 1.0.0, Build 7 (Quelle `5c31a2b`, wie Build 6, aber ohne „nur internes TestFlight“; TestFlight-Builds 1 bis 6 waren dafür nicht wählbar). Auf Wunsch des Nutzers eingereicht: manuelle Veröffentlichung nach Freigabe, weltweit (175 Länder), Preis 0,99 € (Basisland Deutschland), Kategorie Produktivität, Altersfreigabe 4+ (alle Fragen mit Nein bzw. Keine), Content Rights „keine Inhalte Dritter“, Exportcompliance „None of the algorithms mentioned above“. Datenschutz-URL und Support-URL sind die Seiten von mobilebox-consulting.de; die Datenschutzseite füllt der Nutzer separat. App-Privacy-Angaben: „Sonstige Nutzerinhalte“ (an den vom Nutzer gewählten KI-Anbieter), Zweck App-Funktion, mit dem Nutzer verknüpft, kein Tracking. Das ist eine vorsichtige Einschätzung und mit der Datenschutzerklärung abzugleichen. Screenshots: sechs je iPhone (1206 x 2622) und iPad 13 Zoll (2064 x 2752), siehe [docs/app-store/screenshots](app-store/screenshots/README.md). Status in App Store Connect: Waiting for Review ([Beleg](releases/build7/app-store-submitted.jpg)).

## Remaining external status

Build 8 is waiting for Apple review. Automatic public release is configured for approval; approval/publication are not claimed yet. The owner confirmed the Xcode login renewal and Paid Applications Schedule handling, and the subsequent upload succeeded. No new agreement was accepted by the agent.

Jimdo remains a separate explicitly deferred task. The full professional scope retains its documented capability limits; see the current verification report and original requirements.

## Evidence map

- [Requirements](REQUIREMENTS.md), [professional writing scope](PROFESSIONAL_WRITING_PLAN.md)
- [Acceptance history](ACCEPTANCE_STATUS_20261010.md), [release preflight](releases/build3/PREFLIGHT.md)
- [WWDC improvements](WWDC_WRITING_IMPROVEMENTS_20261011.md), [project layout](PROJECT_LAYOUT.md)
- [German/English privacy text](legal/README.md), [licenses](licenses/README.md), [Apple submission material](app-store/README.md)
