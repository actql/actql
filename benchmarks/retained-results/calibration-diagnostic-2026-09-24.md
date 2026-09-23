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

At clean revision `fafb2517a`, a separate-source check trained on the registered
low-selectivity narrow 100-row case and made an ordinary choice for the
registered 1,000-row case. The training medians rounded up to Local
`16 / 3 / 4` ms and DuckDB `20 / 10 / 9` ms. The held-out run selected resident
DuckDB for all three tasks, verified independent Result CID
`sha256:712ca1b9660ec74b203730a533cf188419ce28f8f6b0c8bae59080b7f75e8ac6`,
confirmed release, and recorded 32.145 ms warm task time and 563.450 ms full
Host cycle. The training and held-out sources were distinct DuckDB files;
the latter file hash was
`d8ebb89f597525d736ebbc5ade9451c899f68ce294cf7129d1094a2de1c47153`.
The raw records are in the workspace scratch directory
`actql-retained-calibration-d4KDNt`. This closes the same-case calibration
defect in this diagnostic only. It does not prove that the estimate transfers
to every workload, supply the missing Local work breakdown, or pass the formal
paired timing gate.
