# Pinned parser resource assessment — 2026-10-09

**Internet acceptance remains open.** The reviewed production replica sources were not modified. Their input-byte, schema, text and saved-byte limits apply too late to bound upstream decompression and operation reconstruction.

## Sources actually inspected

Official automerge-swift 0.7.2, revision `aa45d17ac92cef2b8ded63b47e65a28dc85e3418`. Its Rust lockfile pins automerge 0.7.2, crate checksum `b06c470ec20f3ccfbf9103e5539554d5b986852fcefaa9b44298dcca0daf1630`; independently verified against the downloaded official crate. The verified Swift binary artifact checksum is unchanged.

- Rust `storage/chunk.rs:80–95`: compressed-change type2 uses raw DEFLATE `read_to_end` into an initially empty Vec without an output budget, then allocates/copies the expanded payload into an inner change chunk.
- `storage/columns/raw_column.rs:76–88`: compressed document columns likewise use `read_to_end` into a shared output Vec without a per-column or aggregate expansion budget.
- `storage/document/compression.rs:245–255`: metadata copy and output buffers are allocated before document reconstruction.
- `storage/load.rs:88–99`: `Chunk::parse` precedes checksum verification. Invalid checksum or invalid change content therefore cannot prevent the initial expansion allocation.
- `storage/load.rs:108`: operations are collected into a Vec during reconstruction. Parsing/reconstruction does not expose a caller-provided maximum operation count, allocation budget or CPU deadline through the pinned Swift API. Format validation is not a resource budget.

This is an inspection of these paths, not a claim that every possible allocation in the entire upstream crate has been enumerated.

## Decompression and count-field inventory

A source-wide search for `DeflateDecoder`, `read_to_end`, `inflate` and `decompress` found two binary decompression mechanisms in this pinned core:

1. Outer type2 compressed change: `storage/chunk.rs:80–95`; raw DEFLATE expands the whole inner type1 change.
2. Internal type0 document columns: both **change metadata columns and operation columns** flow through `storage/document.rs:119–157` → `document/compression.rs` → `columns/raw_column.rs:76–88,142–155`. Each deflate-marked column appends into a shared Vec; both per-column and aggregate expansion need limits.

Type1 changes do **not** allow compressed operation columns: `storage/change.rs:127–130` explicitly rejects them (`CompressedChangeCols`). Type3 bundles reject compressed change columns and compressed operation columns in `storage/bundle/storage.rs:58–72`. These rejection paths still require complete header/column/count parsing; a bounded loader must preserve these rules rather than assuming all formats share the document decompressor. Other `read_to_end` occurrences in `storage/change/compressed.rs` and raw-column compression write DEFLATE output, not decode it.

Count/length-driven work and allocation fields to cover:

- Outer chunk byte length (u64 LEB128), actor-ID byte lengths and message lengths; bounds-checked input slices do not establish an allocation budget for later copies.
- Type0 document actor count, head count, change-column count and op-column count; head-index suffix iterates head count (`document.rs:119–141`).
- Type1 change dependency count, other-actor count, message length and op-column count (`change.rs:104–123`).
- Type3 bundle dependency and actor counts plus both change/op column counts (`bundle/storage.rs:50–76`).
- Column metadata `num_columns` and each column byte length (`columns/raw_column.rs:209–235`); cumulative offsets use saturating addition, then later slice validation. `parse::apply_n`/`length_prefixed` grow vectors as elements parse; they do not reserve the entire attacker-declared count immediately, but successful metadata can still amplify memory and parser work.
- RLE repeat/null/literal row counts (`columnar/encoding/rle.rs:179–204`) expand logical iteration independently of DEFLATE. Tiny encodings can request extensive reconstruction work; count and operation budgets remain necessary even when compression is rejected.
- Dependency/op-id group counts have limited **initial** capacity (`columnar/column_range/deps.rs:56` and `opid_list.rs:197` use min(count,100)), but vectors can continue growing. This is not an aggregate resource cap.
- Bundle predecessor count is directly used by `Vec::with_capacity(pred_count)` (`storage/bundle/builder.rs:793–801`) before reading each predecessor. Operation collection and document reconstruction need their own bounded allocations.

Only the outer compressed-change path was dynamically stress-probed in this wave. Internal-column and count-field paths were inspected, **not** claimed dynamically bounded. Complete future regression coverage must include all of them.

Pinned primary source links: [chunk](https://docs.rs/crate/automerge/0.7.2/source/src/storage/chunk.rs), [document](https://docs.rs/crate/automerge/0.7.2/source/src/storage/document.rs), [raw columns](https://docs.rs/crate/automerge/0.7.2/source/src/storage/columns/raw_column.rs), [change](https://docs.rs/crate/automerge/0.7.2/source/src/storage/change.rs), [bundle storage](https://docs.rs/crate/automerge/0.7.2/source/src/storage/bundle/storage.rs), [bundle builder](https://docs.rs/crate/automerge/0.7.2/source/src/storage/bundle/builder.rs), [load](https://docs.rs/crate/automerge/0.7.2/source/src/storage/load.rs), [RLE](https://docs.rs/crate/automerge/0.7.2/source/src/columnar/encoding/rle.rs). These links identify the exact-version source; local downloaded crate bytes were the inspected evidence.

## Real binary measurements

The dedicated Swift executable calls the actual official `Document(Data)` decoder. Fixtures use the actual type2 header (magic `85 6f 4a 83`, checksum, chunk type, unsigned LEB128 compressed length, raw DEFLATE). Zero-filled expanded content deliberately fails semantic parsing; dependency artifact checksums are never bypassed.

| Inflated fixture | Input bytes | Kernel peak RSS bytes | Outcome |
|---|---:|---:|---|
| 0 MiB | 12 | 8,749,056 | Decoder rejected |
| 1 MiB | 1,044 | 12,107,776 | Decoder rejected |
| 16 MiB | 16,321 | 61,538,304 | Decoder rejected after expansion; 0.039 CPU seconds |
| 64 MiB | 65,244 | 212,090,880 | Exact child killed by RSS monitor; 0.093 CPU seconds |

The 16KB case already exceeds the replica's 16MiB saved-byte limit in process memory before schema validation. A 65KB input reached about 202MiB RSS, despite being far below the 8MiB incoming-byte limit. These are synthetic malformed payloads and process memory includes runtime/buffer overhead; measurements do not imply these exact RSS values for valid documents.

Child safeguards: CPU limit3 seconds, wall deadline5 seconds, observed RSS threshold192MiB, fixture expansion ceiling64MiB, no core dumps, monitored process group restricted to the exact child. RSS polling is not a hard allocation cap: the kernel peak overshot the threshold by about10MiB. A dedicated constrained service/container is required for a hard production memory boundary. Parent fixture generation is streamed. Monitoring denied by the shell sandbox was rerun with authorization for reading only the spawned child PIDs. Results are in workspace `work/parser-resource-probe.jsonl`; build evidence in `work/parser-probe-build.log`.

## Required boundary and why no partial guard ships

Checking only compressed-change type2 is insufficient: type0 documents contain individually compressed columns, and type3 bundles and operation reconstruction add other allocation paths. Compression ratio heuristics cannot guarantee resource bounds. A raw payload signature or post-load schema check cannot protect the preceding allocation. No incomplete preflight guard was added to production.

For Internet-facing use, implement and review a source-built upstream loader with checked lengths and aggregate expansion/allocation/operation budgets **before** allocating, including all document columns, changes and bundles. Require checked arithmetic, bounded streamed inflate, bounded reconstruction, chunk/column/actor/change/operation counts, and deadline/cancellation support; test budget-plus-one and malformed metadata in isolated processes. A full format preflight would duplicate these parsing semantics and needs equivalent complete coverage, not only a type2 scanner.

Until a bounded loader is validated, decode untrusted bytes only in an isolated service process with hard OS/container memory and CPU limits, authenticate and authorize before forwarding, persist raw pending input before acknowledgment, and treat worker termination as rejection without mutation. The current Swift actor is concurrency isolation, not process or memory isolation. iOS cannot safely substitute arbitrary child-process spawning for this; native incoming data must not reach this pinned unbounded loader merely because a server parsed it first. Signed/authenticated data can still contain pathological content. Do not enable native Internet acceptance until a bounded client decoding path is proven.

No backend, deployment, native integration or device test is claimed by this probe.

## Reproduce

From this directory, build `swift build --disable-sandbox --disable-keychain --disable-netrc --build-system native --scratch-path /private/tmp/skriptum-parser-probe-build`, then run `python3 run_probe.py /private/tmp/skriptum-parser-probe-build/debug/ParserProbe`. Run only on a host where reading the spawned PIDs is permitted. The Python monitor is Darwin-only and intentionally accepts no fixture size or external input arguments.
