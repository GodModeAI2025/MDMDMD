# Shared-scene routing regression

Xcode MCP installed and launched the current Scriptum source on an iOS 27.0 Simulator. A device-interaction subagent exclusively captured hierarchy/screenshots and operated observed hitPoints. App version was 1.0.0 (1); this is a simulator build, not TestFlight.

Source manifest SHA-256: `0bfef68eb82b2181474c5a99a12a4d73068134c974b7055c54025a40480f5591`. Source remained unchanged throughout verification.

Passed: normal launch; Spaces und Bibliothek öffnen; preserved welcome editor; Alle Seiten; Bibliothek root with favorites, trash, recovery and spaces. No crash, navigation failure, overlap or clipped content was observed in this focused portrait flow.

Screenshots: [launch](launch.png), [editor](library.png), [page list](all-pages.png), [library](spaces.png). Full native receipts/hierarchies remain in local work evidence; device identifiers are excluded from this report.

Actual invitation acceptance, cold/background invitation delivery, shared editor interaction, other window sizes and two-device CloudKit collaboration remain unverified. Provisioning is still disabled. The device session was ended after QA.

The routing follows Apple's [scene/application delegate integration](https://developer.apple.com/documentation/coredata/accepting-share-invitations-in-a-swiftui-app), including both connection metadata and callbacks on existing scenes.
