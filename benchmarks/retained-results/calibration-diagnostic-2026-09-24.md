# Retained candidate training diagnostic (2026-09-24)

At clean revision `0806f3e5b`, the calibration runner exercised three
alternating forced-choice rounds per case for both installed Local and DuckDB
providers. Every training Run checked the independent final CID and confirmed
physical release. It then used the median measured task intervals, rounded up
to integer milliseconds, in one separate ordinary standard Host selection.
The forced training runs are not timing acceptance samples. The ordinary
selection is a separate execution, but it uses the same registered workload
and source database, so it is not a held-out workload validation.

| Registered case | Local task estimates (ms) | DuckDB task estimates (ms) | Ordinary task choices | Ordinary warm task sum (ms) | Ordinary Host cycle (ms) |
| --- | --- | --- | --- | ---: | ---: |
| Low-selectivity, narrow, 100 | 15 / 4 / 3 | 17 / 9 / 9 | resident DuckDB x3 | 27.890 | 491.238 |
| Join/count, narrow, 100 | 24 / 11 / 12 / 6 | 18 / 10 / 27 / 9 | resident DuckDB x4 | 46.251 | 531.054 |

The first case's Host cycle includes 18.158 ms of parent preparation, 80.815
ms of child start, 216.635 ms of child preparation and 168.079 ms of child
execution. Its first task took 20.824 ms, while its recorded native work
interval was 4.507 ms. The remaining interval includes common admission,
completion, retention and Host coordination and must not be deleted by moving
required obligations outside the clock. The ordinary choice is cost-grounded
by this diagnostic training, but its estimate source is not yet an admitted
formal calibration profile.

Raw records are under
`workspace/.codex-scratch/actql-retained-calibration-6T1hhu/` and
`workspace/.codex-scratch/actql-retained-calibration-cEPlzF/`. The respective
training SHA-256 values are
`4536faadab48fac43ba33c7b6fb340e9b407976562bb1b6c1c61aabfc3952e90`
and `455f867352e875b3c0edfd0cb02eec04dff14af6ec9ba5e3530e2a995eea0319`.
The ordinary-choice record hashes are
`74274672b854257d9ad30a93b8679b246f48e753fccf36f7aace4b4e9e84e1e2`
and `b1f347d00f2eb59dd92cc4a8b9e2400a53270117f7e3961ef629baa1d5d25383`.

The Local training path exposed a separate formal-comparison gap. Its standard
Host task report contains task elapsed time, imported/exported rows and bytes,
but not the measured guard and comparison-work breakdown required by the
equivalent-obligations pair admission. The independent comparator cannot fill
those product-observation fields on Local's behalf. Formal acceptance needs a
common observation from the Local implementation, plus training on separate
workloads and the registered alternating pairs. The current fixed diagnostic
estimate must not be relabeled as calibrated selection.
