# Native Mac iCloud-Freigabe: isolierte Laufzeitprüfung

Am 15.10.2026 auf macOS 27.2 mit dem über Xcode MCP gebauten nativen Debug-Kandidaten geprüft. Die tatsächlich signierten Entitlements wurden außerhalb der Sandbox validiert: CloudKit Development. Die Sandbox hatte zuvor Codesign-Ausgaben verfälscht; die nachfolgende echte Prüfung war erfolgreich.

Die App wurde mit dem bestehenden Debug-QA-Einstieg auf eine neue eigene synthetische Bibliothek begrenzt. Prozessargumente, Quellhashes, Buildreceipt und signierte Entitlements sind hier abgelegt. Es wurde keine normale Nutzerbibliothek verwendet.

Die neue Bibliothek wurde aktiviert und erfolgreich synchronisiert. Für die synthetische Seite „Schreiben auf dem Mac“ öffnete Seiteninfo → iCloud-Freigabe den tatsächlichen nativen Apple-Freigabedialog. Er zeigte nur den aktuellen Eigentümer, „Add Participants“, private Personenauswahl, Bearbeiten-Recht und „Done“. Es wurde niemand gewählt oder eingeladen, keine Freigabeberechtigung geändert. Nach „Done“ wurde dieselbe bestehende Freigabe nochmals erfolgreich im nativen Dialog geöffnet.

Nach dem ersten Schließen blieb ein rotes Synchronisationsfehlerbanner in der App stehen. Die anschließend aufgeklappte iCloud-Diagnose war bereits `ready`, Ausstehend 0, Empfangen 0, Konflikte 0, Fehler `none`. Root erhielt diesen zusätzlichen Befund zur Behebung; die ganze Freigabe→Synchronisationskette wird deshalb nicht uneingeschränkt grün genannt.

Die native UI wurde als CUA-Screenshots und Accessibility-Bäume im Chat geprüft. Eine bereinigte AX-Zusammenfassung liegt hier; Freigabe-URLs und private Accountkennungen werden nicht ins Git kopiert. Die eigene QA-Bibliothek und die Development-Freigabe bleiben als Nachweis bestehen. App anschließend via Befehl-Q beendet und Prozessende geprüft. Kein Nachweis für Einladungsannahme oder Bearbeitung durch ein zweites Konto.
