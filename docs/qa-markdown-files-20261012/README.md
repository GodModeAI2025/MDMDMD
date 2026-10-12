# Regular Markdown export and Files roundtrip attempt

At committed source de22994, official Xcode MCP installs the actual app without QA launch flags. Regular library navigation opens the existing synthetic page, selects MD in the real export dialog and opens system sharing. Independent readback of the app-generated temporary file matches all 43 original UTF-8 bytes and SHA256 0d46996a6d1f74a666ca1d97e806cbdd19020708d03fa56346eaf881c247443b. The complete original stored page record is identical before/after; source hashes are unchanged.

The local Save-to-Files sheet visibly shows “Auf meinem iPhone”, the Scriptum folder and “Sichern”. Two stable official DeviceInteraction accessibility captures expose only generic Window/Other nodes, without target controls/hitPoints or a remote placeholder. The device-interaction skill requires hierarchy-grounded targets; no screenshot positions were guessed and no import was injected. Actual Files save, regular import and imported-document reopening are unverified.

An alternative native macOS Simulator accessibility inventory was attempted once. It reports the Mac is locked and cannot automatically unlock. No window was selected, no host unlock attempted and no new session created. The initial owned Xcode session is stopped and the original destination restored. Simulator/test data are preserved; no accounts, inference, external recipients or other devices were touched.

This is proof of current-source native MD export, not a complete R04 roundtrip pass. Real Files save/import remains an acceptance gate; the full R01–R15 and signed TestFlight requirements remain unchanged.
