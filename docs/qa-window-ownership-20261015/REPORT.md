# Fensterlokaler Bibliotheksstart und native Aktionsleisten

15. Oktober 2026 · Ausgangsstand 0588e70 · R10/R11. Quelländerung im regulären Projekt, keine Aktivierung der separaten nativen Grammatik-Abhängigkeit. Kein Upload oder Eingriff in bestehende Store-Einreichungen durch diese Welle.

## Konkrete Änderung

Bisher hielt die App einen einzigen LibraryLaunchCoordinator samt starkem UIHostingController für alle Dokumentbrowserfenster. Ein bereits belegter Controller blockierte weitere Präsentationen; nur der ausdrücklich aufgerufene Schließen-Callback löschte ihn. Das war ein im Quellcode belegbarer gemeinsam gehaltener Präsentationszustand, kein neuer Nachweis eines Rotationsfehlers.

Jede LaunchLibraryAccess besitzt jetzt ihren eigenen Coordinator. Dessen Anchor hängt an der tatsächlich angeklickten Schaltfläche und verwendet ausschließlich deren eigenes UIWindow und lokale Präsentationskette. Der Papierhintergrund ist wieder rein dekorativ. DocumentGroup-Reihenfolge, Dokument-I/O, Speicherung, ausgewählte Seiten und Registry-Handoffs werden nicht geändert.

UIKit hält den präsentierten Host. Der Host hält über seinen Schließen-Callback den Coordinator stark; der Coordinator hält den Host schwach. Der sichtbare Editor kann den SwiftUI-Neuaufbau seines Startbereichs überleben, ohne dass der Coordinator einen später abgetrennten Host dauerhaft festhält. Ein Marker für den Bibliothekshost verhindert Doppelpräsentationen auch bei einem neuen Buttonzustand; bereits vorhandene Hosts konsumieren neue Anfragen. Noch nicht angeheftete Anchors behalten ihre Anforderung bis zum viewDidAppear. Ein frisches Request-Token erlaubt spätere explizite Klicks, ohne dass eine alte Bool-Zuweisung unverändert bleibt.

Die echte openWindow-Aktion und supportsMultipleWindows-Auskunft werden vor dem Übergang in den manuellen Hosting-Root aus der Launch-View gelesen und über LibraryWindowActions ausdrücklich weitergegeben. Normale WritingWorkspace-Views in WindowGroup verwenden weiter ihre eigenen Environment-Aktionen. Navigation-Guard, genaue Bibliotheks-/Seitenidentität und der bisherige beschränkte Registry-Handoff bleiben erhalten.

Drei echte Aktionsleisten verwenden jetzt safeAreaBar: Vorschlagsübernahme, Aufgabenaktivierung und Mac-Tabellenaktionen. Der installierte SDK erklärt diese API für iOS/macOS26+, beide App-Ziele sind auf27. Der Inhalt, die Buttons und die Plattformzweige wurden nicht verändert. Informations-/Fehler-/Manuskript-Inset-Inhalte und Papierhintergründe bleiben unverändert.

## Quellprüfung und vollständige Dateiabdeckung

Die unabhängige Skill-Prüfung erfasste 236 produktive Swift/UIKit-Dateien. Es gibt keine UIScreen.main-, UIDevice.current-, Layout-Orientierungs-/Idiom-Abfragen oder veraltete Layout-Guides zu ersetzen. Der ApplicationDelegate bleibt für einmalige Registrierung/APNs erforderlich; ein echter SceneDelegate ist vorhanden. Keyboard-/Caret-Konvertierung verwendet das jeweilige lokale Fenster, keine globale Fenstersuche. Diese Stellen wurden ausdrücklich als nicht anwendbare Migrationsziele eingeordnet, nicht stillschweigend ausgelassen.

Der abschließende unabhängige Review aller drei geänderten Dateien findet keinen blockierenden Quellfehler. Er bestätigt Ownership, beide Request-Verbrauchspfade, den schwachen Anchor, das unveränderte DEBUG-QA-Gate, die weitergereichten Szenenaktionen sowie genau drei Bar-Substitutionen. [Vollständige Dateiliste](PLAN.md). Der Review bestätigt weder eine tatsächlich erfolgreiche UIKit-Präsentation noch Rotation.

## Frische Verifikation

- Offizielles Xcode MCP: Skriptum / Any iOS Device (arm64) und SkriptumMac / My Mac bauen erfolgreich, jeweils ohne Compilerfehler. Dies sind Debug-SDK-Builds und keine neuen Release-Archive. Die vorhandene App-Intents-Metadatenwarnung bleibt erhalten; kein Null-Warnungen-Versprechen.
- Gesamte Root-Suite: 757 gemeldete Swift-Testing-Fälle einschließlich vier ausdrücklich optionaler Skips, dazu 58 ausgeführte XCTest-Fälle. **811 tatsächlich ausgeführte Tests, null Fehler.** Die vorhandenen Fenster-/Navigation-/Speicherregressionen laufen mit. Dies sind keine UI-Laufzeittests des neuen Präsentationspfads; es wurden keine spiegelnden Quelltext-Tests erfunden.
- Reine Settings-/Info-Prüfung: Config/Info.plist und evaluierte Xcode-Einstellungen sowie die tatsächlich frisch gebaute iOS-Info.plist bestätigen LaunchScreen, alle vier iPad-Ausrichtungen und keinen UIRequiresFullScreen-Schlüssel. Keine xcconfig vorhanden. Keine Buildsetting- oder plist-Mutation und keine direkte pbxproj-Lesung.
- Der erste lokale Compileraufruf scheiterte vor Teststart am geschützten Compiler-Cache; der Xcode-Bridge-Prozess endete vor Initialisierung. Mit genehmigtem Cache-/MCP-Zugriff liefen anschließend ausschließlich Modelltests und Builds erfolgreich. Keine App wurde als Ersatz gestartet.

## Nicht ausgeführte Laufzeitprüfung

Die unabhängige aktuelle Simulatorprüfung wurde **vor InstallAndRun** von der automatischen Freigabeprüfung ausdrücklich abgelehnt. Begründung: Die frühere Nutzeranweisung „Gerätetests raus“ sei eine weiterhin geltende Restriktion. Es gab keinen App-Start, keine Rotation und keinen Editorwert. Der Simulator-Sessionstart und die anschließende erfolgreiche Schließung bleiben unter runtime-not-run erhalten. Kein Retry, keine CUA-Ausweichroute und keine Umgehung. Dem Nutzer wurde der genaue Block mitgeteilt; daraus entsteht kein neues verpflichtendes Gerätetest-Gate.

Der ältere Rotationsfehler aus qa-resizability-20261012 betrifft eine inzwischen geänderte Präsentationsarchitektur. Er ist weder durch diese reine Quellkorrektur als behoben bewiesen noch erneut im aktuellen Stand reproduziert. Launch, Rotation, Software-Tastatur, mehrere sichtbare Fenster und das aktuelle Aussehen bleiben für diesen geänderten Pfad unbestätigt. R10 und das gesamte R01–R15-Ziel bleiben offen. iOS12 bleibt die zuvor nachgewiesene interne TestFlight-Auslieferung; die vom Eigentümer beibehaltene iOS11-Einreichung wird hier nicht ersetzt.
