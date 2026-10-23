# iPhone Duo redesign notes
Journey: Dokument-Startansicht → Bibliothek → Editor
Stack: SwiftUI, iOS27; Xcode27.2 (27B48), iOS27.2 SDK.
Stage: 5  Next: Breite Ansicht ergänzend prüfen; signierten Build37 exportieren und hochladen.

## Findings
- Absolute Logo-Position über Gesamtfenster wurde neben Systembrowser abgeschnitten. [HIG]
- Bibliothek verwendet NavigationSplitView für kompakte/regelmäßige Darstellung. [HIG]
- LaunchScreen vorhanden; alle vier iPad-Ausrichtungen deklariert; kein UIRequiresFullScreen.
- Keine UIScreen.main-, userInterfaceIdiom- oder interfaceOrientation-Treffer im Produktionsquelltext.
- Kamera, hinge effects, poseabhängige Sonderfunktionen: N/A.

## Decisions
- Systemtitel statt absolutem Logo-Overlay; Papierhintergrund bleibt (Agent,2026-10-23; autonome Entscheidung autorisiert).
- Keine Änderungen an Dokumentformat, Speicherung, Cloud oder KI.
- iOS1.0.3 (37); unveränderte Mac1.0.2 (36) bleibt in laufender Prüfung.

## Done / verified
- DocumentGroupLaunchScene verwendet nativen Titel Scriptum; ungenutzter Overlay-Code entfernt.
- XcodeMCP Duo-Build/Start bestanden; Titel/Button lesbar, echter Tap öffnet Bibliothek.
- Synthetische Testseite und Text bleiben nach Geräte-Rotation erhalten.
- Rotation änderte die Appfläche nicht (466×678); innerer Bildschirm/Falten dadurch nicht bewiesen.
- DeviceHub über CUA nicht erreichbar; keine Behauptung vollständiger Fold-/Hinge-Tests.
- Dokumenttyp-Tests und git diff --check bestanden; Releasearchive läuft.
- Unveränderte vollständige Suite, Cloud/AI und physische Geräte nicht erneut getestet.
