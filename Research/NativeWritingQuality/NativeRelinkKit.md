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
it is not App Store signing. App reconstruction, library substitution, developer
signing, installation instructions, application terms and full corresponding
source completion remain open. No app is installed, launched or uploaded by
these commands. The existing production app is not modified.
