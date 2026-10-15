# Native grammar framework relink kit

This local engineering kit contains pinned native objects, selected runtime
archives, headers, unchanged resource bytes, the generated iOS fallback source
and the framework builder. It can be moved to a different directory without
access to the original development checkout, Maven cache or Gluon cache.

Requirements: Apple-silicon macOS with Xcode 27 and its macOS/iOS SDKs selected
through `xcode-select`, and Python 3.9 or later. No network is needed by these
commands. Apple SDKs and signing credentials are not part of the kit.

From the kit directory:

```sh
python3 -B relink_native_kit.py --verify-only
python3 -B relink_native_kit.py --output ../relinked-frameworks
```

The output must be a new directory outside this kit. All input hashes are checked
before invoking the builder. The builder compiles the included iOS compatibility
source, links both arm64 frameworks, verifies their exact public symbols and
ad-hoc signatures, validates resource bytes and assembles the XCFramework. The
output receipts describe the actual new build; they are not included in this
immutable input manifest. The original kit remains untouched.

The platform frameworks are `macos/ScriptumGrammar.framework` and
`ios/ScriptumGrammar.framework`; `ScriptumGrammarResources.bundle` accompanies
either. The module is named `ScriptumGrammar`. `ScriptumGrammar.xcframework`
contains those two slices. There is no iOS Simulator slice.

This recipe relinks retained binary objects. It does not recompile LanguageTool,
Graal, the JDK or linguistic data from preferred source; those source packages
and their outstanding correspondence reviews remain separate. The generated
fallback implementation includes unsupported-operation failure paths retained
from the current candidate; relinking does not expand supported runtime calls.

This is an internal preparation kit, not a source/license redistribution approval
or an installation package. Ad-hoc signing permits local artifact inspection;
it is not App Store signing. The separate app reconstruction, substitution and
development-signing recipe follows below. A customer installation package,
application terms and full corresponding source completion remain open. No app
is installed, launched or uploaded by these two kit commands. The existing
production app is not modified.

## Rebuilding the isolated app with a replacement framework package

`prepare_app_candidate.py` accepts the completed framework builder output,
including `STATE.json` and `ScriptumGrammarResources.bundle`. From the Scriptum
checkout, pass that package, a fresh candidate output directory and a dedicated
new QA-library path beneath Scriptum's sandbox `Data/tmp` directory. The helper
prints the generated Xcode project. It preserves the ordinary project and adds
the framework as an embedded, code-signed dynamic dependency for each platform.
The generated Mac scheme supplies the isolated library argument.

Replace the two package/output paths and choose a fresh QA directory name:

```sh
python3 Research/NativeWritingQuality/prepare_app_candidate.py \
  --framework-package /absolute/path/to/relinked-frameworks \
  --qa-root "$HOME/Library/Containers/com.mobilebox.Skriptum/Data/tmp/ReplacementQA-New" \
  --output /absolute/path/to/new-candidate
```

Open the generated project in Xcode, select the development team and build
`SkriptumMac / My Mac` or `Skriptum / Any iOS Device (arm64)`. Xcode embeds and
signs the replacement with the application. On the Mac, use the generated run
scheme so the replacement check opens its dedicated QA library. An iOS generic
build is compilation/signing evidence; it does not install or execute the app.
Provisioning and signing identities belong to the person performing the build
and are excluded from the input kit.

The [15 October replacement checkpoint](../../docs/qa-native-app-replacement-20261015/README.md)
records the actual package substitution, app build, development signatures and
resource/code comparison. It uses the previously relocated kit's newly linked
framework. Its computational code is unchanged; no modified grammar behavior or
full recompilation from preferred source is established by this substitution.
Apple re-signing changes the signature and `__LINKEDIT` virtual-size metadata;
the receipt keeps those differences explicit rather than claiming whole-binary
equality. The ordinary TestFlight builds retain their existing dependency set.

This technical app recipe does not complete preferred-source correspondence,
resource-specific distribution terms, application distribution terms or a
customer-ready replacement/installation package.
