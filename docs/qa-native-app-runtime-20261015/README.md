# Native grammar app-runtime integration · 15 October 2026

This checkpoint connects the R14 native engine to the shared app review flow and creates local Mac/iOS application candidates. It is not a new TestFlight upload or completed R14 acceptance. The regular project still excludes the native framework and data, pending the separately recorded source/distribution work.

## Application behavior

`BundledGrammarRuntime` is now shared application code. It reports whether the framework is linked, then verifies the pinned LanguageTool 6.6 manifest and every declared resource before constructing its private native driver. Missing, changed, aliased, duplicate and escaping resource paths fail explicitly; symlinks are refused. The reader checks sizes and hashes, streams bounded chunks, supports cancellation and never downloads or extracts files. No native driver is created for unverified data.

The installed driver uses the established serialized worker, owns each isolate's creation/heap/resource setup/check/teardown on one background thread and reports failures without partial findings. All text still goes through the actual Markdown projection, response decoder and exact source/revision admission.

When the framework is linked, Textprüfung defaults to on-device grammar/style. Its advanced settings retain the explicit Apple-only and own-server alternatives. The text-language selector uses the 29 codes already exercised through the pinned native engine; it does not reuse Apple's spelling catalog as a grammar-support claim. Apple contributes spelling only when a matching dictionary exists; the exact selected dictionary is visible. This avoids duplicate Apple grammar/basic-style findings and unrelated dictionary fallback. Missing or invalid native resources report an error instead of silently switching services. The existing ordinary app builds keep their existing Apple/server flow because the native framework is not linked there.

## Actual verification

- All **59** writing-quality test functions pass. Six new functions cover exact resource/manifest bytes, unsafe and duplicate paths, aliases, symlinks, engine identity/count/size mismatch, unavailable-runtime behavior and spelling-only behavior. Existing source, Unicode, cancellation and remote-review checks remain intact.
- The actual application runtime factory verifies the complete **1,888-file** resource bundle, then passes all **29** unchanged synthetic language witnesses through the real Mac framework, worker, projection and decoder, with network denied. The result has 30 findings and 28 safe correction admissions. A failed-resource-root attempt precedes the successful checks. These are bounded synthetic witnesses, not comprehensive proofreading quality certification.
- The first run's measured peak was **759,137,480 bytes**. `FileHandle`'s autoreleased read buffers accumulated while hashing the complete 337-MB data set. A pool around each read lowers the repeated same-corpus peak to **418,153,384 bytes**, preserving every expected finding/correction. Initial and final output/metrics are retained separately. This is host-process measurement, not an iOS jetsam or device-performance claim.
- The final regular iOS-arm64 and native Mac projects build through Xcode MCP. Separate actual **Mac and iOS-arm64 apps** also compile/link with the native driver, embedded platform framework and raw resource bundle. Their final app binaries contain `InstalledGrammarEngine` and the framework load command. Every copied resource matches its original hash. Both completed app bundles pass deep/strict development-signature verification. These are local Debug candidates, not App Store distribution packages.

No new physical-device test is required by the owner's scope. No iOS native execution is claimed. The new candidate's actual dialog, correction/undo interaction and appearance remain unverified: Xcode MCP records an owner-approval requirement when opening this new project. The requested menu-bar confirmation is pending. No app was launched from that request and no personal library was used.

## Candidate preparation and failures retained

`Research/NativeWritingQuality/prepare_app_candidate.py` takes an explicit verified framework package, a fresh output directory and a fresh QA-library directory inside Scriptum's sandbox temporary directory. It generates a separate XcodeGen project, embeds both platform frameworks/resources and gives the Mac run scheme the dedicated QA-library arguments. It does not edit the normal dependency list, install, launch or upload an app. `candidate-spec.json` and `CANDIDATE.json` retain the actual regenerated input.

The first candidate build failed because copied relative entitlement settings were interpreted under the new project directory. The next exposed relative resource/framework paths based on a different project root. The helper now uses absolute entitlement/Info paths and makes its project-root equal its output directory. The successful Mac/iOS builds and exact final bundle proofs follow those failures. Earlier failure logs remain preserved.

The actual Mac candidate built under `work/native-quality-app-runtime-20261015/candidate`; the reproduced helper output and iOS candidate use `candidate-final`. Signed app binaries, SDKs, framework/resource copies, harness build caches and generated projects stay outside Git. Final incremental logs and full earlier candidate logs are retained here. Existing Swift Sendable warnings and the App Intents metadata warning are recorded; no zero-warning claim is made.

## Remaining delivery work

Complete the source/resource-specific distribution and relinking materials, broader linguistic acceptance and the pending real dialog check before enabling these native dependencies in a distributable project. The normal TestFlight builds are unchanged. Mac 11's prior upload still lacks a fresh processing/internal-group receipt because App Store Connect is logged out. The complete R01–R15 objective remains active.
