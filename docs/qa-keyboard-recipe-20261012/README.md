# Software-Tastatur im Simulator: getestetes Rezept (2026-10-12)

## Befund

Die Software-Tastatur fehlt nicht wegen Simulator-Einstellungen. Sie verschwindet, sobald über Xcode DeviceInteractionSynthesize ein `sender keyboard kbd <text>` gesendet wurde. Das Kommando simuliert eine Hardware-Tastatur, iOS blendet die Software-Tastatur aus, der Fokus bleibt ("Keyboard Focused" bleibt im TextView). Der nächste Touch (`t x y`) bringt die Tastatur zurück. Belegt in `ev/`:

| Schritt | Datei | Keyboard-Element | Keyboard Focused |
|---|---|---|---|
| Tap in Block "Hier beginnt Ihr nächster Text" | `ev/02-focus-*` | ja, `{{0,653},{440,245}}` | ja |
| danach `sender keyboard kbd Hallo` | `ev/03-after-kbd-*` | nein | ja |
| Tap auf anderen Block | `ev/04-retap-*` | ja | ja |
| Tap auf Textblock, Tastatur sichtbar | `ev/05-retap-block-*` = `keyboard-up.png` | ja | ja |

Der frühere Lauf `qa-library-lifetime-20261012` hatte die Tastatur, weil dort vor der Aufnahme nichts per kbd getippt wurde. In `qa-merged-ui-20261012` wurde fast jeder Schritt mit kbd-Eingabe oder nach einer solchen gemessen.

Simulator.app existiert in diesem Xcode nicht (`/Applications/Xcode.app/Contents/Developer/Applications` fehlt, kein Simulator*.app im System), `ConnectHardwareKeyboard` ist in `com.apple.iphonesimulator` nicht gesetzt. Das Umschalten über Cmd+K ist also nicht möglich und nicht nötig. Eine Pref-Änderung (`HardwareKeyboardLastSeen` in `com.apple.keyboard.preferences.plist`) wurde nicht gebraucht.

## Rezept

1. Frisches Gerät (hier geht auch das QA-Gerät, nur mit der Reihenfolge unten): `xcrun simctl create "Scriptum Keyboard Recipe 20261012" com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro-Max com.apple.CoreSimulator.SimRuntime.iOS-27-0` (UDID 7C64E426-46D0-4635-87C6-EE41CC6BFAC3, nach dem Test heruntergefahren, nicht gelöscht).
2. Simulator-Build: `xcodebuild -project Skriptum.xcodeproj -scheme Skriptum -destination "generic/platform=iOS Simulator" -derivedDataPath <dir> CODE_SIGNING_ALLOWED=NO build`, dann `xcrun simctl boot <UDID>`, `xcrun simctl install <UDID> <dir>/Build/Products/Debug-iphonesimulator/Skriptum.app`, `xcrun simctl launch <UDID> com.mobilebox.Skriptum`.
3. Xcode-MCP: `DeviceInteractionStartWorkspaceSession` (workspaceIdentifier aus XcodeListWorkspaces, deviceIdentifier = UDID, sessionIdentifier frei).
4. Block fokussieren mit `DeviceInteractionSynthesize` und `t <x> <y>` auf den Block-Button. Danach muss die Hierarchie `Keyboard, {{0.0, 653.0}, {440.0, 245.0}}` enthalten, Screenshot zeigt die Tastatur.
5. Tastatur-Messungen (Layout, Viewport) in dieser Phase machen. Kein `sender keyboard kbd` davor. Wenn Text nötig ist: kbd senden, danach genau einen `t` auf den Textblock senden, dann ist die Tastatur wieder da (Text bleibt erhalten, siehe `keyboard-up.png`, "Hallo" im Block).
6. `DeviceInteractionEndSession`.

Hinweise: Bei Rotation auf dem Telefon geht der Fokus laut früheren Läufen verloren, danach erneut tippen. `simctl io screenshot` und XcodeBuildMCP `snapshot_ui` funktionieren auf dem neuen Gerät ebenfalls, XcodeBuildMCP hatte hier aber kein tap-Werkzeug geladen. `synthesize-helper.sh` ist der Hilfsaufruf (benötigt den Proxy aus `docs/qa-xcode-transport-and-license-bundle/REPAIRED_PROXY.py` unter /tmp/qpx/mcp.sock).

Nicht getestet: das QA-Gerät DD4D1567 selbst (gleicher Mechanismus erwartet), physisches Gerät "iPhone von M" (nichts installiert; dort ist die Software-Tastatur Standard, solange keine Hardware-Tastatur gekoppelt ist).
