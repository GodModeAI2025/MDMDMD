# Collaboration decoder budget — remaining evidence

The standalone collaboration module is not linked to native untrusted ingress. Its experimental source fork and verification remain separate, partial work; R08 sharing/roles/transport/native simultaneous-editing acceptance is not closed.

On 2026-10-09, a bounded local diagnostic of the fork's hexane 0.1.6 ColumnData API confirmed that its packed row accounting and raw-copy allocation are outside the custom Automerge budget counters. A small packed column reported 100001 logical values with a zero row/item/operation allowance; a 4 MiB raw column copied its input with a zero allocation allowance. The owned diagnostic exited 0 after 1.473 seconds, with kernel peak RSS 23019520 bytes. These are scoped ColumnData observations, not proof of complete top-level loader behavior or a native exploit.

The existing experimental README already names this gap: op_set2/columns.rs::load_column calls ColumnData::load_with before complete core operation charging. The next implementation needs shared pre-allocation/count accounting in hexane or a complete validated column preflight. Full heap budgets, incremental/sync entrances, cooperative cancellation, broader validation and native iOS behavior still require evidence.

The delegated audit stopped with an automatic possible-cybersecurity-risk rejection before a completed source review/patch. No production manifest, decoder or App ingress was changed. The owned diagnostic is terminal and no matching probe/monitor process remained in a subsequent process read. The safe editor work continued independently. Keep the experimental module outside native untrusted transport until a complete review and acceptance run is available.
