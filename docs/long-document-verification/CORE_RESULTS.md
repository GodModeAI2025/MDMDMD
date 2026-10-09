# R11 Core long-document benchmark

Read-only copied production Core source with exact SHA256 manifest; provenance.json confirms all copied Core files still match the root checkout. Root HEAD at measurement: 2c6733d8ed6e08d096acb834f2c32b4aaa56ad9f. SwiftPM release build, macOS27.2 (26B5091g), Apple Silicon local Mac. Harness/build/logs remain under work; no repository source/tests/manifests changed.

Normal author fixtures: 1,000 paragraphs (128,890 UTF8 bytes, 20,000 whitespace-token words) and 5,000 (648,890 bytes, 100,000 whitespace-token words), emoji/combining Unicode/CJK/CRLF. Every iteration changes one word in the middle paragraph. Three iterations each, ContinuousClock medians. Assertions verify every persisted block UUID (including edited paragraph) survives, complete Markdown bytes survive reconcile+disk reload, and exactly one baseline revision is retained. Fixture cap2MiB, process30s, sampled RSS budget256MiB; neither limit reached. 50ms process RSS sampling gives observed peak, not a rigorous allocator high-water mark.

| Core operation median (ms) | 1,000 paragraphs | 5,000 paragraphs |
| --- | ---: | ---: |
| Segmentation | 0.336 | 1.699 |
| Reconcile middle edit | 1.751 | 8.892 |
| beginEditing | 3.313 | 15.367 |
| updateEditing | 5.426 | 26.229 |
| finishEditing | 3.775 | 18.052 |
| Reload exact source | 3.436 | 16.654 |

1k journal386,390 bytes/library386,559 bytes; 5k journal1,938,389–1,938,390 bytes/library1,938,558–1,938,559 bytes, one history revision. Baseline+current source in durable edit journal approximately triples raw UTF8 byte size after block/JSON metadata. Observed process RSS13.65MB/34.37MB; complete process0.128s/0.664s. Raw iteration JSON and operational-monitor.json provide exact measurements.

Measured largest Core operation is updateEditing: about26.2ms at5k, while standalone reconciliation is8.9ms. Actual LibraryStore.updateEditing(markdown:) calls reconcile, then block validation/exact comparison and JSONEncoder of complete baseline/current journal with atomic write. This supports investigating journal encoding/write and full-page work next; the benchmark does not independently time encoding vs disk or prove which dominates. Segmentation and reconcile roughly scale5× for5× paragraphs on these fixtures; no quadratic slowdown observed here.

LibraryStore is @MainActor and synchronous, so this Core work occupies its caller actor, but these timings are NOT keyboard/UI latency measurements. No UIKit layout/physical-device responsiveness claim. Next R11 gate: actual simulator/device typing/layout measurement with same normal fixtures, more retained revisions/multiple pages, then scoped optimization only if measured. Preserve durable save/UUID/source contracts; no debouncing/data-loss shortcut is implemented by this benchmark.

Word-count clarification: the exported normal fixtures contain exactly20 and100 thousand whitespace-separated tokens (1k/5k). Earlier work draft used a rough estimate23/115k; byte counts, paragraph counts and timings are unchanged. The native App counter agrees at100000. This is the current whitespace-token metric, not a language-aware prose count.
