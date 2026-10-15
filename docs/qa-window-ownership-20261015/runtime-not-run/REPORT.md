# Aktueller Rotationscheck — 2026-10-15

Status: Laufzeitprüfung vor dem App-Start blockiert. Kein Rotations-Pass/Fail-Nachweis.

Geprüfter Quellstand: 0588e70febbc13bcfcdf9e5548d826baa46dc6f7. Das reguläre genehmigte Projekt workspace-GU0n2mrDHO wurde ausgewählt. Die offizielle Discovery lieferte einen heruntergefahrenen iPhone18Pro-Simulator; Workspace-Session „Current Rotation QA“ bestätigte deviceIsSimulator=true, UUID2814AD63-9D0E-48C9-8923-DB6D3C9FF397. Kein QA-Host wurde benutzt.

Der nachfolgende angeforderte offizielle InstallAndRun-Aufruf wurde vor Ausführung durch automatische Freigabeprüfung abgelehnt: „Although the simulator run is bounded and reversible, the retained user instruction to remove device tests is an explicit restriction, and no later trusted user message clearly revokes it for this run.“ Der Hinweis verbietet Workarounds/indirekte Ausführung ausdrücklich. Es erfolgte kein erneuter Startversuch, keine CUA-Umgehung, kein Build aus diesem Lauf und keine Texteingabe. App-PID/Screenshot/Editorwerte existieren daher für diese Prüfung nicht.

Der unbetroffene rein lesende GetTargetBuildSettings-Aufruf ist vollständig als rotation-current-session-2-GetTargetBuildSettings.json gesichert; relevante UI-Einträge zusätzlich in settings-filtered.json. iPad-Orientierungen enthalten alle vier Richtungen. LaunchScreen-Generation und UIRequiresFullScreen sind als Buildsetting leer; iPhone/general Orientierungen ohne ausgewerteten Wert. Diese Settings allein bestimmen nicht abschließend die effektive Info.plist; Root prüft Config/Info.plist und Projektkonfiguration gesondert. Keine direkte pbxproj-Lesung/Mutation.

Cleanup: offizieller DeviceInteractionEndSession-Aufruf bestätigt „Session stopped“ (rotation-current-cleanup.json). Eigene Session ist geschlossen, kein eigener App-Prozess gestartet. Keine Cloud, Provideranfrage, persönliche Bibliothek, Source-/Git-/Portaländerung. Xcode ist an Root für reine SDK-Builds freigegeben. Root hat angeordnet, ohne neue Nutzerfrage mit Quellen/Tests fortzufahren; keine weitere Gerätesitzung.
