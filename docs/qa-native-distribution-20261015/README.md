# Native framework distribution checkpoint · 15 October 2026

This R14 checkpoint turns the native research objects into separate Apple framework candidates and prepares source/license materials. It does not enable the engine in the app, upload a new build or complete R14. Delivered iOS build 9 / Mac build 10 are not replaced by this work.

## Full iOS link and runtime boundary

The first complete iOS link exposed a missing download at the previously hardcoded `24-2` SDK coordinate (HTTP 403). The actually installed Substrate 0.0.69 artifact declares `18-ea+prep18-9` as its default for this Graal generation. That official archive downloads successfully and the complete iOS link succeeds. The research POM now pins this version through an overridable `scriptum.javaStaticSdkVersion` property. Compile-only evidence from the earlier checkpoints remains historical; the new link logs are retained separately.

The generated Gluon static archive also contains an application delegate and bootstrap object. The framework builder links the native object and generated Graal JVM fallbacks directly, excluding both `AppDelegate.o` and `dummy.o`. The independent `IOSRuntimeCompatibility.c` uses the pinned Graal CPU-feature header, zeroes its complete 17-byte ABI structure and advertises the mandatory AArch64 baseline only. Its legacy JNI availability functions return typed `JNI_FALSE`; unexpected datagram initialization throws a managed unsupported-operation exception. It does not introduce an application delegate or make a network request. Four host C/JNI mock checks validate baseline flags/bounds, typed availability, explicit failure and preservation of an existing exception; these are not iOS execution tests.

The native JDK libraries require CFNetwork for proxy-selector symbols, so that public system framework is linked explicitly. No AppKit or UIKit dependency is needed by the packaged grammar frameworks. The linked-object receipts confirm the bootstrap objects are absent. Other recorded native/JDK fallback behavior is unchanged; broad failure-path and linguistic acceptance are not claimed.

## Framework and resource layout

The builder produces a versioned macOS framework, an iOS framework and `ScriptumGrammar.xcframework` containing arm64 slices for both platforms. Each exports exactly the seven Graal isolate operations, three Scriptum operations and required VM locator helper. No executable `main` or application-delegate entry is exported. Module maps/public C headers support direct Swift `import ScriptumGrammar`. Local candidates are ad-hoc signed and pass strict code-signature verification; that is not App Store distribution signing.

The framework binary sizes are recorded in `framework-package/STATE.json`. A separate codeless resource bundle contains the 1,888 byte-verified raw LanguageTool resource files (337,383,291 bytes). It contains no transfer ZIP or extracted runtime cache. Development output retains intermediate framework copies for evidence; the intended app layout includes one platform framework and one resource bundle. App Store download size is not measured here. The own iOS compatibility MIT notice is included in the iOS framework.

Scriptum already targets macOS 27. Apple's [current compatibility specification](https://support.apple.com/en-us/127455) lists Apple-silicon Macs for that OS. The native Mac app's Debug/Release architecture is now explicitly arm64 to match the supported production hardware and framework slice; the source project is regenerated from XcodeGen. The actual Mac app builds successfully through Xcode MCP. No iOS Simulator slice is produced in this checkpoint; simulator build integration remains a separate implementation concern and does not reintroduce a physical-device release gate.

## Fresh execution and target evidence

- All five native groups pass through the packaged Mac framework's actual C module, with network denied: 29 exact language/range witnesses, 29 correction controls, five long chunks, 23 boundary checks and a separate nine-check heap-exhaustion path.
- The real Swift quality worker/decoder/correction probe imports the framework module directly and passes all 29 extended Markdown witnesses, producing 30 findings and 28 admitted safe corrections. The packaged resource bundle is checked against all original resource hashes before execution.
- The final Mac framework binary is byte-identical to that runtime-tested candidate. Both final native object hashes match the tested build. Resource bytes and public exports are reverified in the final package, providing an explicit equality link between the retained execution receipts and final packaging.
- Swift consumers import/link both final XCFramework slices. The host consumer creates an isolate, sets the heap budget and tears down successfully with network denied. The iOS consumer links with an explicit iOS SDK environment; its Mach-O load command reports `IOS` and minimum OS `27.0`. It is compile/link evidence, not iOS execution. An initial inherited macOS SDK-root warning and its corrected invocation are retained outside the Git evidence set.
- Ten Python tests cover existing resource packaging plus source archive bounds/paths, classifier coordinates, restricted source URLs, resource mutation/traversal/symlink refusal and exclusion of compiled code from license candidates. No unrelated package-wide test rerun is inferred; the unchanged Swift quality module's earlier 53-function receipt remains in the prior checkpoint.

## Source and license preparation

The [corrected material set](../licenses/native-engine-distribution-20261015/README.md) binds all 146 input JAR hashes, 132 published sources archives and 99 original legal/documentation texts. Sources are checked against published checksums, validated as bounded non-traversing archives and stored in a deterministic-timestamp ZIP outside Git. The first snapshot is preserved; the corrected notice classification was repackaged offline using the unchanged verified source archives. Two metadata-only and 12 linguistic-data artifacts lack a standard Maven sources artifact; their precise contents and upstream declarations are retained in `SOURCE_GAPS.json`.

The exact OpenRegex release source/license resolves an unversioned LGPL label, but resource/data obligations, matching iOS runtime SDK sources/notices, final relinking/installation material and application terms remain open. The SDK archive contains no accompanying source/license text. No distribution approval is inferred from a successful link or a source download.

Large frameworks, resources, SDKs, source archives and probe binaries stay under `work/native-quality-distribution-20261015`, outside Git. `STATE.json` binds the current sources, retained evidence and final artifact equality. Complete source/license packaging, broader linguistic cases, production language catalog, availability/error UI and final app integration remain necessary before a new TestFlight build. The complete R01–R15 objective is unchanged.

## Reproduction

`build_frameworks.py` takes explicit native objects, iOS JVM fallbacks, pinned Graal/SDK library paths, headers and the verified resource root/manifest, and requires a fresh output directory. Its recorded commands link/sign/inspect both frameworks, validate exact exports/resources and create the XCFramework. `verify_native.py --framework …` and then `verify_reviewer.py --framework … --native-receipt …` exercise the actual module rather than a bridging-header dylib substitute. Source collection uses `collect_source_materials.py` with the pinned classpath/inventory. Receipt files retain exact local arguments and scope; these helpers never edit app availability or publish a build.
