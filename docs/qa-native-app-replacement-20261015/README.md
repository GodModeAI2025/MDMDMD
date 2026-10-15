# Native grammar: replacement framework in the actual app

15 October 2026, source `e5cf522`. This advances the technical application
replacement step for R14. The ordinary project and TestFlight dependencies are
unchanged. Source/data correspondence and distribution completion remain open.

## Actual inputs and reconstruction

The relocated, previously verified 1,926-file relink kit produced the framework
package under `work/native-quality-relink-20261015/relinked-frameworks`.
`INPUT_VERIFICATION.json` rechecks both platform framework fingerprints and all
1,888 raw resource files before candidate preparation. The existing helper
generates an isolated candidate from that package. All seven files of the
previous candidate project/spec/receipt were copied and byte-checked before the
already approved project path was regenerated. The backups stay under
`work/native-quality-app-replacement-20261015/previous-candidate`;
`PROJECT_BACKUP.json` binds their original bytes.

`ACTIVATED_CANDIDATE.json` records the actual new package, generated project and
fresh dedicated `ScriptumGrammarReplacementQA-20261015` library argument. The
source binding in `CURRENT_SOURCE.json` includes the shared quality module.
This is a development candidate, not a new distribution archive or installation
in the user's Applications folder.

## Mac payload and signing

The official Xcode MCP first listed the existing workspace, then built
`SkriptumMac / My Mac` successfully in 9.896 seconds with no build errors.
The actual built app and embedded framework both have the existing Apple
Development identity and team. `codesign --verify --deep --strict` succeeds
using the ordinary macOS trust store. The initial sandboxed verification failed
with `CSSMERR_TP_NOT_TRUSTED`; its original log remains here. No trust settings
or certificates were changed.

`MAC_APP_PROOF.json` binds the actual executable, Debug library and embedded
framework. The Debug library loads the versioned macOS framework at
`@rpath/ScriptumGrammar.framework/Versions/A/ScriptumGrammar`. All 1,888 embedded
resource files and the original manifest match their pinned bytes.

The source and Apple-signed embedded framework are not whole-binary identical.
On disposable copies only, removal of both signatures reveals exactly one
remaining difference: the eight-byte `__LINKEDIT.vmsize` field at offset 1560
changes from 4,947,968 to 4,964,352. That segment has no allocated sections.
Every byte outside that field is equal. This records unchanged computational
code/data without erasing the actual signing metadata differences.

The first comparison incorrectly expected complete equality after signature
removal; the second expected the flat iOS load path on the Mac. Both original
assertion-based verifier versions are retained. The final verifier explicitly
checks the observed metadata field and actual versioned load path. These were
verification-assumption failures, not source fixes or evidence of a runtime
grammar defect. The actual signature and resource checks remained in place.

## iOS SDK candidate

The same activated project builds for `Skriptum / Any iOS Device (arm64)`
through the official Xcode MCP in 17.814 seconds with no build errors.
`IOS_APP_PROOF.json` records successful deep/strict development-signature
verification and all 1,888 embedded resource hashes. The actual Debug library
loads the flat iOS framework path; its Mach-O build command reports `IOS` and
minimum OS `27.0`. Its signature-stripped comparison also differs only in
`__LINKEDIT.vmsize`; all other bytes are identical. This is an actual iOS SDK
build and payload check, without installation or execution on iOS.

## Actual Mac correction and preservation

The actual local Mac dialog ran with the newly embedded framework, its own
server disabled and German explicitly selected. It found one grammar issue in
the ordinary paragraph “Es ist schöne Wetter.”, offered “schönes Wetter” and
reported zero findings after acceptance. “Korrektur rückgängig” restored the
original text and the finding. The source view retained the inline-code copy,
URL and combining-accent/emoji witness. The UI does not expose a rule ID, so
`SCHOENE_WETTER` remains an expected mapping rather than an observed identity.
The bounded runtime files and source comparisons are recorded separately under
`runtime/`; this one German correction does not establish 20-language quality.
The ordinary Markdown export after undo equals the complete 87-byte input,
including code, URL, combining accent and emoji. The QA process was regularly
closed and its exit verified. Xcode is restored to the ordinary
`Skriptum / Any iOS Device (arm64)` workspace configuration.

Six own disposable signature-stripped comparison files were removed after the
successful comparison, recovering 889,029,360 bytes. `CLEANUP.json` binds their
hashes and confirms that the original relinked framework and signed app binaries
were unchanged. The original source package, relink kit, candidate backup,
signed app, logs and small receipts remain.

Two further iOS comparison copies were removed after their successful check,
recovering 296,309,648 bytes. `IOS_CLEANUP.json` confirms the retained original
framework and signed iOS app hashes before and after that removal. No original
source or app artifact was removed.

This does not establish new grammar semantics, full source recompilation,
linguistic quality in 20 languages, iOS execution, Store distribution or complete
license/source obligations. The engine remains excluded from the ordinary app.
