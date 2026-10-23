# iPhone Duo redesign notes
Journey: Dokument-Startansicht → Bibliothek → Editor
Stack: SwiftUI, iOS27; Xcode27.2 (27B48), iOS27.2 SDK.
Stage: 5  Next: Apples Prüfung/Veröffentlichung abwarten; tatsächlichen Duo-Foldtest nachholen, wenn DeviceHub steuerbar.

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
- Breite iPad-Ansicht834×1210/1210×834: Starttitel/CTA lesbar; echter Tap öffnet dreispaltige Bibliothek.
- Dokumenttyp-Tests und git diff --check bestanden; Releasearchiv/Export und25 Distributionsprüfungen bestanden.
- Unveränderte vollständige Suite, Cloud/AI und physische Geräte nicht erneut getestet.
