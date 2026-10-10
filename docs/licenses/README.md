# iOS Settings licenses

Path: Settings → Apps → Scriptum → Licenses (German: Einstellungen → Apps → Scriptum → Lizenzen). Root.plist links Acknowledgements.plist using PSChildPaneSpecifier. Each component links a read-only pane; PSGroupSpecifier FooterText carries the complete original license text, not a shortened translation. Navigation is localized in German and English. No preference keys or writable settings are added.

Sources are the exact resolved Xcode checkouts recorded in settings-license-manifest.json. Houdini, GitHub buffers and utf8proc MIT notices are preserved individually from swift-cmark COPYING sections 1–3. The complete COPYING is also included to preserve its BSD and bundled notices. Its normalization script / test / specification notices are retained as part of the unabridged upstream document, not a claim that those tools ship in Scriptum. Swift Markdown includes its full NOTICE and Apache license with Runtime Library Exception. Foundation Models Utilities includes its complete Apache license. Original license text is not localized or modified.

Only the application target's actual third-party runtime dependencies are included. Untracked Automerge investigation/vendor files are not linked by project.yml or the application Package dependencies, so they are not represented as shipped components. Swift Argument Parser is mentioned by the original upstream NOTICE; it belongs to upstream tools and is not an app-target dependency. Apple's SDK frameworks are not third-party MIT packages.

The Settings bundle is an app resource through XcodeGen's Sources/SkriptumApp resource discovery. When dependencies change, review resolved revisions and upstream notices, update panes/manifest, and validate both the copied bundle and Settings navigation.

Apple schema: https://developer.apple.com/documentation/foundation/building-a-settings-bundle-for-your-app and https://developer.apple.com/library/archive/documentation/PreferenceSettings/Conceptual/SettingsApplicationSchemaReference/Articles/PSGroupSpecifier.html

## Verification (2026-10-10)

plutil validates all8 property lists and2 localization tables. All six text hashes and child-pane links match the exact upstream sources above. The built app contains a copied Settings.bundle whose8 plists and2 strings tables match source semantically (plutil JSON conversion). Xcode MCP Build238 passes, no errors. Native Settings UI QA verifies all six panes, complete MIT texts and long notice scrolling;311 source hashes match before/after observations, session ended268. See qa/REPORT.md. No paid inference, document edits, preferences changes or new TestFlight distribution.
