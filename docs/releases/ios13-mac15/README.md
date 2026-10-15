# Scriptum 1.0.1 — iOS13 und nativer Mac15

Quellstand b770ec0ef9b59772a2830051db15713eeabbc695, am Archivierungsstart sauber. Separate Release-Archive mit Swift-Warnungen als Fehler und unveränderten Warnungsanzeigen bauen erfolgreich. Beide App-Store-Connect-Exporte sind erfolgreich. Die tatsächlichen exportierten Apps bestehen 25 iOS- beziehungsweise 28 native Mac-Distributionsprüfungen, einschließlich Signatur/Profil, CloudKit-Production, Push, PCC und Mac-Sandbox. Der Installer-Check endet mit Exit0 und der Apple-Zertifikatskette für das bestehende Team. Die 13 Verifier-Regressionen bestehen.

Der erste Installer-Vertrauenscheck im eingeschränkten Sandbox-Prozess konnte die vollständige Apple-Kette nicht auswerten; er bleibt getrennt erhalten. Der genehmigte read-only Check mit normalem Zugriff auf den Vertrauensspeicher besteht. Es wurde weder ein Zertifikat installiert noch Vertrauen überschrieben oder eine Sicherheitsprüfung abgeschaltet. Die generische pkgutil-Statuszeile nennt „developer certificate issued by Apple (Development)“; die tatsächliche Installer-Identität ist „3rd Party Mac Developer Installer“ des Teams, und die exportierte App selbst besteht die Distributionsprofil-/Distributionszertifikatsprüfung.

## Enthaltener Stand

- iCloud-Systempfadkorrektur aus iOS12; im vorigen Mac14 noch nicht enthalten.
- Wahrheitsgemäße Aufgabenfortschrittsanzeige aus c9128ef: zulässiger nächster Termin, laufende/ausstehende/beendete Planung und separates letztes Ergebnis.
- Fensterlokaler Bibliotheksstart, weak-Host-Ownership, explizite Szenenaktionen und native Aktionsleisten aus c6a63f8.

Die separate native Grammatikbibliothek und ihr Datenpaket sind in diesen Exporten ausdrücklich nicht enthalten; dies wurde am tatsächlichen App-Inhalt kontrolliert. Es gibt keine neue 20+-Sprachen-, Rotations- oder Geräteerfolgszusage. [Fensterkorrektur und Grenzen](../../qa-window-ownership-20261015/REPORT.md); [811 tatsächlich ausgeführte Root-Tests, vier optionale Skips](../../qa-window-ownership-20261015/STATE.json).

## Auslieferungsgrenzen

SOURCE.json bindet den tatsächlichen sauberen Archivierungsstand. ARTIFACTS.json hasht die separat geprüften lokalen Exportdateien. Der Upload verwendet dieselben Release-Archive mit Upload-Destination; da Xcode für den Upload erneut paketiert/signiert, werden die lokalen IPA-/PKG-Hashes nicht als unabhängig nachgewiesene Hashes von Apples empfangenem Upload ausgegeben. Annahme, serverseitige Verarbeitung, Exportcompliance und interne Gruppe werden gesondert in STATE.json erfasst, sobald tatsächlich beobachtet.

Die bestehende iOS11-Store-Einreichung 4625ac11-3d3e-455a-9db9-395d8766bc2d bleibt auf ausdrücklichen Eigentümerwunsch bestehen. Auch Mac14/64c9f5f0-8444-491d-96b6-0e88590a1e10 wird hier weder zurückgezogen noch ersetzt. Die neue interne TestFlight-Auslieferung ist keine neue Store-Einreichung, Genehmigung oder Veröffentlichung. Das vollständige R01–R15-Ziel bleibt offen.

Große Archive, exportierte IPA/PKG, entpackte Apps und vollständige Build-/Export-/Uploadlogs bleiben ausschließlich unter work/release-ios13-mac15 erhalten. Git bewahrt Quellbindung, relevante Logs, Prüfergebnisse, Notizen und Portalbelege.

## Nach neuem Eigentümerfeedback zurückgehalten

Nach erfolgreichem Upload meldete der Eigentümer für iOS12 den neuen Fehler Connection.superseded. Der gleiche lokale Verbindungsschlüssel ist auch in diesem Archivierungsstand enthalten. Eine feste Regression reproduziert ihn. Deshalb wurden iOS13/Mac15 keiner internen Gruppe zugeordnet; die weitere Auslieferung wird mit korrigierten neueren Buildnummern fortgesetzt. Es wurde kein vorhandener TestFlight-Build gelöscht und keine Store-Einreichung verändert.
