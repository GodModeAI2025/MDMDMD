# Experimental bounded loader source fork — not Internet-ready

This isolated wave preserves exact upstream sources, builds a real Rust/Swift XCFramework and tests the native wrapper against it. **Do not enable untrusted native ingress or replace the production dependency with this partial fork.** The production module manifest, replica source, native app and Xcode project remain unchanged.

## Exact inputs and reproducible builds

- Automerge Swift0.7.2: official commit `aa45d17ac92cef2b8ded63b47e65a28dc85e3418`, retained under `../../Vendor/automerge-swift-0.7.2`, including its upstream LICENSE and original Cargo.lock (`rust/Cargo.lock.upstream`). Its official binary checksum declaration is untouched. The source build uses upstream's explicit `LOCAL_BUILD=1` path; it does not forge a release checksum.
- Rust core0.7.2: official published crate SHA256 `b06c470ec20f3ccfbf9103e5539554d5b986852fcefaa9b44298dcca0daf1630`, retained under `../../Vendor/automerge-core-0.7.2`. The crate omits the license file, so LICENSE was retrieved from verified official core tag `rust/automerge@0.7.2`, commit `1a5b63747f5c081f5f4a1a165c250f614ff36304`.
- UniFFI0.28.2, flate2 1.0.30, hexane0.1.6 and remaining transitive inputs are pinned by the retained lockfiles. Only the automerge package is redirected to the local fork via an explicit Cargo patch.
- Compiler: `rustc 1.98.1 (48a229cea 2026-09-01)`. Build script verifies this exact string, uses `--locked`, leaves the user's default toolchain unchanged, and records archive SHA256 values. The initial unmodified official bridge source built successfully for arm64 macOS, iOS device and iOS simulator; all three experimental source slices also build successfully.
- Generated XCFramework lives inside the vendored Swift fork and is ignored by Git. Build caches remain in `/private/tmp`. A source build reproducible from these inputs is established; bit-identical builds across Xcode/linker/SDK hosts are not claimed.

Install the official Rust standard libraries for `aarch64-apple-darwin`, `aarch64-apple-ios`, `aarch64-apple-ios-sim`, then run `python3 build_source.py`. The script intentionally omits the upstream script's global toolchain update/default changes and unrelated Catalyst/visionOS targets. Set `SCRIPTUM_CARGO_CACHE` or `SCRIPTUM_RUST_BUILD` for alternate task caches. The vendored source licenses must accompany redistribution.

## Implemented, tested paths

A single thread-local RAII context is installed by the source-built FFI `Doc::load`. Nested contexts fail closed, preventing counter/deadline replenishment. Explicit Rust callers can use `load_budget::with_budget`. Limits accumulate across all chunks and columns in that call:

| Counter | Default | Enforcement added |
|---|---:|---|
| Inflated output |16MiB|8KiB streamed reads charged before reserve/append; outer type2 and both type0 column sets share it|
| Accounted allocation requests |64MiB|Checked addition/multiplication; inflate output, expanded change copy, metadata collections and bundle predecessor reserve|
| Collection items |100,000|Chunks and parsed actor/head/dependency/column collections; bundle metadata and predecessor count|
| Legacy RLE value visits |2,000,000|Checked signed/unsigned runs and per-visit charging|
| Operation visits |100,000|Core OpIter reconstruction and bundle OpBuilder visits|
| Cooperative deadline |500ms|Checked at charged boundaries and after the action; not a hard interrupt inside opaque calls|
| Cancellation |Optional AtomicBool|Checked at charged boundaries and on scope exit|

`Doc::load` also rejects more than24MiB raw input before calling the core. The generated UniFFI input Vec has already been allocated at this point; this is not an FFI allocation guard.

The 64MiB expansion fixture now rejects normally at approximately28MB kernel peak RSS instead of reaching212MB and being killed with the official artifact. Both64MiB internal-column fixtures and combined18MiB columns reject at about28MB. Metadata count-plus-one fixtures are built from the exact pinned type0/1/3 format and reject before collection growth. These measurements prove these paths, not a total process-memory bound.

## Evidence and commands

- Six Rust tests: exact inflation/item/operation boundaries, cumulative inflation, actual document operation reconstruction, cancellation, context cleanup, nested-scope rejection and valid Unicode document loading.
- Original nine replica Swift tests run against the real source-built XCFramework: actual two-peer encoded change exchange, Unicode/CRLF, save/reload, stable IDs, identity rejection, candidate rollback, malformed suffix, deletion/edit recovery, concurrent insert/move/cycle convergence.
- Thirteen final dedicated child probes (four outer and nine internal-column/count cases) reuse the CPU3s/wall5s/RSS192MiB monitor. Known compressed/change/internal-column/count paths reject without worker termination. The RSS watcher is sampled and does not impose a hard allocation limit.

```sh
cargo test --manifest-path Cargo.toml --locked
LOCAL_BUILD=1 swift test --package-path Swift --disable-sandbox --disable-keychain --disable-netrc --build-system native --scratch-path /private/tmp/skriptum-bounded-swift-build
python3 ../ParserProbe/run_probe.py /private/tmp/skriptum-bounded-swift-build/debug/ParserProbe
python3 column_probe.py /private/tmp/skriptum-bounded-swift-build/debug/ParserProbe
```

Swift verification contains explicit unchanged snapshots of the reviewed replica files/tests. It is separate from the production manifest. Evidence logs are in workspace `work/bounded-*.log` and `work/bounded-*.jsonl`; source/build input hashes accompany them.

## Open paths preventing Internet acceptance

1. **hexane packed-column scanning/allocation occurs before core operation charging.** `op_set2/columns.rs::load_column` calls `ColumnData::load_with`; row/run counts and scans in hexane0.1.6 need equivalent pre-allocation budgets. Instrumenting the legacy Automerge RLE decoder does not cover this newer path. Vendoring/instrumenting hexane with a shared budget crate, or complete validated column preflight, is the next concrete source work.
2. Accounted allocation bytes are not total heap bytes. Metadata Vec capacity growth, document column copies/reconstruction, change graph/index construction, strings/raw values, dependencies/successor collections and clone/merge buffers still need complete checked accounting/fallible reservation. Internal metadata Vec growth is count-bounded, not an allocator sandbox.
3. Only FFI `Doc::load` establishes this context. Its defaults are currently fixed; configurable limits and cancellation are Rust-only and are not yet exposed through the Swift/UniFFI API. `apply_encoded_changes`, its patches variant, sync message decode/receive and other public byte-decoding constructors must establish the same context and publish atomically after validation. Calling the core outside an explicit scope currently preserves upstream behavior. No claim of whole-public-API safety is made.
4. Aggregate decoded values and operation/successor counts require complete schema-independent coverage, including bundle value lengths and hexane raw/String cursor paths. Current bundle predecessor reservation is guarded, but bundle reconstruction is not fully resource-audited/fuzzed. Invalid value-length arithmetic and panic paths remain to examine.
5. Deadline/cancellation is cooperative; an opaque inflate/scanning/library call can exceed a deadline before yielding. No hard CPU bound is claimed. Keep bounded worker probes until every path is covered.
6. The full matrix of valid/budget-plus-one internal columns, RLE runs, bundles, nested groups, extremely large count/length fields, arithmetic overflow and malformed concatenations remains required. Current tests are permanent evidence for implemented paths, not complete format fuzz coverage.
7. iOS Rust slices are built; Swift app integration, iOS simulator execution, physical-device peak memory/cancellation, cross-device sync, signed payloads, backend authorization and durable pending changes remain unverified.

A server-side parser does not protect a native client that subsequently decodes the same pathological bytes. No server endpoint workaround or Internet-ready assertion is provided.
