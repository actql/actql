# Contiguous selection: local metadata diagnostic

Product revision: `4979d9cf`. The accompanying opt-in whitebox test is the
measurement harness. Toolchain: MoonBit `0.10.12+1634b282e`, debug `moon test`,
JS and Native on the working machine. No production code was changed for these
measurements.

Reproduce with the pinned toolchain on PATH:

```sh
ACTQL_MANAGED_SLICE_DIAGNOSTIC=1 moon test src/execution_relation --target js --filter '*managed slice metadata paired diagnostic*' --deny-warn
ACTQL_MANAGED_SLICE_DIAGNOSTIC=1 moon test src/execution_relation --target native --filter '*managed slice metadata paired diagnostic*' --deny-warn
```

The harness constructs a synthetic sealed-index scale model, not a proven
execution of a large Program. Each row has two nonuniform cell measurements.
Source preparation is outside timing. Both legs aggregate and copy the same
index, validate result size/last occurrence and consume the same fixed checksum.
The array leg also creates and defensively copies explicit occurrence indices;
the slice leg uses the exact interval. Provisional copied index references are
discarded inside both timed legs. Runtime allocator/GC scheduling is not forced.
There is no content decoding, canonicalization, hashing or DuckDB execution in
this experiment, and no native storage/worker reclamation claim.

One alternating warmup pair is discarded, followed by seven alternating pairs.
Every sample contains ten preparations. Full samples are in
[managed-slice-diagnostic.json](managed-slice-diagnostic.json).

| Target | Rows | Array median, ms / 10 | Slice median, ms / 10 | Median paired slice/array ratio |
| --- | ---: | ---: | ---: | ---: |
| JS | 1,000 | 0.357 | 0.298 | 0.844 |
| JS | 100,000 | 40.523 | 35.613 | 0.888 |
| Native | 1,000 | 0.847 | 0.563 | 0.821 |
| Native | 100,000 | 62.871 | 50.953 | 0.813 |

The 100,000-row result is consistent with reduced row-map work. It is not a
universal speedup claim: JS's per-pair ratios range from 0.840 to 1.290 at that
size, and its small case is considerably noisier (0.290 to 2.566). Native's
100,000-row ratios range from 0.802 to 0.822. Medians of individual leg times
and medians of paired ratios are different statistics.

The old array leg already includes the preceding ordered-selection duplicate
map optimization. Thus this experiment isolates the subsequent contiguous-map
change, not the entire branch's performance gain. No RSS/heap peak or physical
reservation was measured. No formal acceptance bootstrap is claimed. The
original 27 registered cases, 1 GiB constraint, same-obligation baselines and
new-profile end-to-end gates remain separate and unfinished.

Verification of this harness increment: the opt-in diagnostic passed on JS and
Native; the full execution-relation suite passed 453/453 on JS, Wasm and Native
(diagnostic disabled by default). Strict JS, format and diff checks passed.
