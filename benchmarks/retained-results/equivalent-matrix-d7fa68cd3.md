# Equivalent-obligations retained-result comparison

This complete-denominator run uses clean revision
`d7fa68cd3745b3f32fdc844ca575fd8877ff07f4` and one unchanged generated
release build. The 27 registered cases remain in the denominator, including
the nine cases whose baseline capacity is infeasible. Every admitted case has
seven alternating pairs and the preregistered 10,000-resample confidence
assessment. This is one of four required comparators, not the full PERF-1
experiment.

The result is 13 failed gates, ten incomplete cases, four indeterminate cases,
and no passes. Six incomplete cases selected Local in the ordinary product
path, while the comparator still requires DuckDB-only per-task accounting.
Four other cases could not complete independent calibration: the nearest
training sizes either could not force the candidate under the fixed capacity,
or the product failed after partial progress. These outcomes are preserved as
incomplete rather than assigned a favorable time or removed from the matrix.

Raw records are in workspace scratch directory `equivalent-matrix-full-d7fa`.
The SHA-256 digests of `progress.json` and `assessment.json` are
`d34db8104f9afe67182b27b327d70fd7f067e3e22de5747c9a3fe30578ccf07a`
and `3cf40467d39ddd1d1392f92a87e6adc30e3a8c6212fd3846fd8f7087e33f176b`.

Status: **incomplete**. Scope: one comparator; this is not whole-experiment acceptance.

Expected revision: `d7fa68cd3745b3f32fdc844ca575fd8877ff07f4`. Registered cases: 27. Received records: 27.
Generated release build: `ddb1cae0e6a816fb881777915d2ff053d16a5718e504c38a14137b218627f415`.

| Case | Status | Pairs | Gate 95% intervals | Reason |
| --- | --- | ---: | --- | --- |
| native-acquisition-full-validation-low-selectivity/narrow/100 | fail | 7 | warmMs: 23.840–32.813 (limit 10, fail); coldMs: 728.964–923.626 (limit 100, fail) |  |
| native-acquisition-full-validation-low-selectivity/narrow/1000 | fail | 7 | warmMs: 33.317–35.152 (limit 10, fail); coldMs: 1001.620–1030.208 (limit 100, fail) |  |
| native-acquisition-full-validation-low-selectivity/narrow/10000 | incomplete |  |  | unadmitted-pair:0 |
| native-acquisition-full-validation-low-selectivity/narrow/100000 | fail | 7 | executionMs: 3.276–3.475 (limit 1.25, fail) |  |
| native-acquisition-full-validation-low-selectivity/narrow/1000000 | indeterminate | 7 | executionMs: 1.218–1.353 (limit 1.25, indeterminate) |  |
| native-acquisition-full-validation-low-selectivity/numeric-64/10000 | incomplete |  |  | unadmitted-pair:0 |
| native-acquisition-full-validation-low-selectivity/numeric-64/100000 | incomplete |  |  | unadmitted-pair:0 |
| native-acquisition-full-validation-low-selectivity/text-1024/10000 | fail | 7 | executionMs: 2.264–2.388 (limit 1.25, fail) |  |
| native-acquisition-full-validation-low-selectivity/text-1024/100000 | indeterminate | 7 | executionMs: 1.162–2.323 (limit 1.25, indeterminate) |  |
| fixed-join-count-shrinking-intermediate/narrow/100 | fail | 7 | warmMs: 61.945–82.545 (limit 10, fail); coldMs: 1450.939–1607.090 (limit 100, fail) |  |
| fixed-join-count-shrinking-intermediate/narrow/1000 | fail | 7 | warmMs: 111.575–123.958 (limit 10, fail); coldMs: 1220.425–1389.376 (limit 100, fail) |  |
| fixed-join-count-shrinking-intermediate/narrow/10000 | incomplete |  |  | unadmitted-pair:0 |
| fixed-join-count-shrinking-intermediate/narrow/100000 | fail | 7 | executionMs: 2.703–8.802 (limit 1.25, fail) |  |
| fixed-join-count-shrinking-intermediate/narrow/1000000 | fail | 7 | executionMs: 3.080–4.177 (limit 1.25, fail) |  |
| fixed-join-count-shrinking-intermediate/numeric-64/10000 | incomplete |  |  | unadmitted-pair:0 |
| fixed-join-count-shrinking-intermediate/numeric-64/100000 | incomplete |  |  | unadmitted-pair:0 |
| fixed-join-count-shrinking-intermediate/text-1024/10000 | fail | 7 | executionMs: 2.105–3.073 (limit 1.25, fail) |  |
| fixed-join-count-shrinking-intermediate/text-1024/100000 | indeterminate | 7 | executionMs: 1.136–1.674 (limit 1.25, indeterminate) |  |
| retained-large-output-downstream-reuse/narrow/100 | fail | 7 | warmMs: 48.044–50.074 (limit 10, fail); coldMs: 1088.416–1109.039 (limit 100, fail) |  |
| retained-large-output-downstream-reuse/narrow/1000 | fail | 7 | warmMs: 84.949–118.116 (limit 10, fail); coldMs: 935.209–1164.560 (limit 100, fail) |  |
| retained-large-output-downstream-reuse/narrow/10000 | fail | 7 | executionMs: 2.107–4.256 (limit 1.25, fail) |  |
| retained-large-output-downstream-reuse/narrow/100000 | fail | 7 | executionMs: 1.563–2.137 (limit 1.25, fail) |  |
| retained-large-output-downstream-reuse/narrow/1000000 | indeterminate | 7 | executionMs: 0.797–1.948 (limit 1.25, indeterminate) |  |
| retained-large-output-downstream-reuse/numeric-64/10000 | incomplete |  |  | missing-or-invalid-pairs |
| retained-large-output-downstream-reuse/numeric-64/100000 | incomplete |  |  | missing-or-invalid-pairs |
| retained-large-output-downstream-reuse/text-1024/10000 | incomplete |  |  | missing-or-invalid-pairs |
| retained-large-output-downstream-reuse/text-1024/100000 | incomplete |  |  | missing-or-invalid-pairs |
