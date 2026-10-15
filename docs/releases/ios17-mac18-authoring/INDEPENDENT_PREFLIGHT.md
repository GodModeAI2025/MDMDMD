# Unabhängiger Release-Preflight

Read-only-Teilreview für Quellstand `05841db91be6b9f1e02e117e96788e39cc077b4e` am 15. Oktober 2026, vor Abschluss der Uploads. Keine konkreten Blocker oder Inkonsistenzen gefunden.

- 11/11 Quellhashes stimmen mit Commit und Arbeitsbaum überein.
- Größe und SHA-256 der lokalen IPA/PKG stimmen mit ARTIFACTS.json überein.
- Archive und exportierte Apps tragen 1.0.1 (17) für iOS und 1.0.1 (18) für den nativen Mac.
- Die Privacy-Manifeste in beiden Archiven und Payloads sind bytegleich zur korrigierten Quelle; CA92.1, C617.1 und 3B52.1 sind enthalten.
- Distributionsbelege bestehen mit 25/25 iOS- und 28/28 Mac-Prüfungen. Die separate native Grammatik-Payload bleibt ausgeschlossen.
- Alle 23 IPA-Dateien stimmen bytegenau mit der geprüften entpackten App überein.
- 46/46 gebundene QA-Dateien sowie beide vollständigen SDK-Logs sind unverändert. Seit der Integration änderten sich nur Version-/Projektmetadaten und das Privacy-Manifest; die geprüften Implementierungen sind identisch.
- Export und Upload sind auf Production-CloudKit und dasselbe Entwicklerteam eingestellt.

Die Artefakthashes binden lokale Exporte, keine Empfangshashes bei Apple. Dieser Review ändert keine Dateien, startet keine App, führt keine neuen Tests aus und bestätigt keine Live-iCloud-Synchronisation.
