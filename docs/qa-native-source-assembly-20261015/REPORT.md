# Native source assembly candidate — 15 October 2026

Implemented only `Research/NativeWritingQuality/assemble_native_source_candidate.py` and `tests/test_source_assembly.py`. No project configuration, production route, app, simulator, portal, commit or push was changed by this task.

The final retained package is `final-candidate/SourceMaterials.zip`: **840,683,522 bytes**, **2,041 ZIP entries** (2,040 materials plus manifest), SHA256 `91f674509e63c5fbb83081079f49eb50a6b893126fa91134a59ab2859bf56d5f`. Its manifest SHA256 is `2a77da47bdfa670c4e0ac47a6c2743a99323db7d13becd25574ec2732621f629`.

It combines the unchanged V3 mirror (including its nested V2), unchanged later Portuguese source mirror, directly accessible original Portuguese sources/notices/dependencies, complete tagger+synthesis proof, current verification tools and complete portable relink kit. All 1,926 relink files are retained, not just a recipe. The Portuguese chain binds 16,679,668 complete rows and 1,386 tags. Historical scope texts/logs remain byte-for-byte intact; ASSEMBLY.json records the later evidence separately.

## Actual checks

- 22 targeted tests pass: seven new source-assembly regressions, eight existing material-mirror tests and seven existing relink tests. See `final-full-tool-tests.log`.
- Both source ZIPs and every declared member were checked against retained outer/inner SHA256 receipts before packaging; complete later evidence directories were checked against their SHA256SUMS, and current retained tool/source bindings were checked.
- The final archive was extracted to a directory with spaces and checked from an independent third working directory. Both the candidate verifier and the embedded relink verifier succeeded. No compiler was invoked.
- The extracted candidate then reassembled itself with only its own retained files, without the original source checkout. Resulting ZIP and manifest are byte-identical. Exact commands, paths and terminal success are in `FINAL_REPRODUCTION.json`.
- All terminal handles are complete with exit code 0: initial 8106/56848/45997, final assembly 61957, final reproduction 29269, cleanup 74324. The final 22-test command completed directly with exit code 0 (result chunk 96d76d). See STATE.json; no handles remain running.

## Reproduce from the final extracted candidate

```sh
python3 -B tools/assemble_native_source_candidate.py --verify-directory .
python3 -B relink/relink_native_kit.py --verify-only
python3 -B tools/assemble_native_source_candidate.py --repo . \
  --v3-package previous/SourceMaterialsV3.zip \
  --portuguese-package portuguese/SourceMaterials.zip \
  --relink-kit relink --output ../reassembled-candidate
```

The new output must not already exist. No network or compiler is needed for assembly. The embedded `relink/README.md` separately documents actual framework relinking; the earlier successful relinking/runtime evidence is retained but was not repeated here.

## Cleanup and remaining work

`CLEANUP.json` records exact paths, per-file/per-tree checks, before/after sizes and preserved reconstruction archives. Only this task's byte-identical second ZIPs and fully verified extraction copies were removed: **4,115,862,866 bytes** freed. The final ZIP, initial intermediate ZIP, small receipts/manifests and all proof logs remain. Original V3/PT packages and the original complete relink kit were reverified after cleanup and remain untouched. Extracted copies can be reconstructed from the retained ZIPs.

This closes the fragmented local material-assembly gap, not R14 or source/distribution approval. Irish FST/Gaelspell source correspondence and resource-specific terms remain open. Ukrainian root dictionary CC BY-NC-SA 4.0, software GPL 3+ and derivative LGPL 2.1+ notices remain distinct; source/binary correspondence and redistribution rights remain unresolved. Portuguese spelling and byte-identical FSA serialization, other language-resource bindings, modified host-JDK/native-SDK correspondence, complete preferred-source rebuild, app reconstruction/library substitution, signing/installation and application terms remain open. No customer-ready, legal-approval or production claim is made.

For small Git evidence, select this report, STATE.json, FINAL_REPRODUCTION.json, CLEANUP.json, final tool/verification logs and final-candidate/{PACKAGE,MANIFEST,ASSEMBLY}.json. Keep ZIPs, binary inputs and extracted trees outside Git.
