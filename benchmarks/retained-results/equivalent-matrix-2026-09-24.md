# Equivalent-obligations retained-result comparison

This is the first complete-denominator execution of this comparator on clean
revision `03e3daa42479824dd2c23ea4f11bf293ffa05141`. It does not satisfy
the performance review's PERF-1 acceptance condition. The generated release
modules had one digest across all admitted pairs. Raw records remain in the
workspace scratch directory `equivalent-matrix-full-03e3`; the SHA-256 digests
of `progress.json` and `assessment.json` are
`50cf6bcf8fcb277e13ebc53ea70fd3be137fbff1b843b0f9d45d5ef5e9c73730`
and `4a67166f62863593d544d12356b29946823c84ceb9591a1858f06d98efaad8a7`.

The four small-case failures below contain seven admitted alternating pairs
each and fail both registered warm and cold limits. Six incomplete cases have
seven attempted pairs but ordinary product selection chose Local, while the
product comparator reads DuckDB-only accounting fields. The other 17 cases
stopped in calibration: 16 could not force the Local candidate under the
training fixture and one asserted that an already released intermediate
completion remained present after close. These are measurement-path gaps; they
do not remove cases from the denominator or turn any failure into a pass.

Next, fix the post-close assertion, represent unavailable training candidates
explicitly, and expose real Local obligation diagnostics when Local is the
ordinary choice. Repeat a fixed-revision matrix after those changes. Keep the
four observed gate failures and optimize the product path against the unchanged
limits. The baseline and raw-DuckDB comparators, plus operational PERF-2
profiling and final-SHA PERF-3 Linux CI, still require independent closure.

Status: **incomplete**. Scope: one comparator; this is not whole-experiment acceptance.

Expected revision: `03e3daa42479824dd2c23ea4f11bf293ffa05141`. Registered cases: 27. Received records: 27.
Generated release build: `ddb1cae0e6a816fb881777915d2ff053d16a5718e504c38a14137b218627f415`.

| Case | Status | Pairs | Gate 95% intervals | Reason |
| --- | --- | ---: | --- | --- |
| native-acquisition-full-validation-low-selectivity/narrow/100 | fail | 7 | warmMs: 23.048–24.037 (limit 10, fail); coldMs: 717.858–734.561 (limit 100, fail) |  |
| native-acquisition-full-validation-low-selectivity/narrow/1000 | fail | 7 | warmMs: 25.122–26.401 (limit 10, fail); coldMs: 723.890–732.036 (limit 100, fail) |  |
| native-acquisition-full-validation-low-selectivity/narrow/10000 | incomplete |  |  | unadmitted-pair:0 |
| native-acquisition-full-validation-low-selectivity/narrow/100000 | incomplete |  |  | unadmitted-pair:0 |
| native-acquisition-full-validation-low-selectivity/narrow/1000000 | incomplete |  |  | missing-or-invalid-pairs |
| native-acquisition-full-validation-low-selectivity/numeric-64/10000 | incomplete |  |  | missing-or-invalid-pairs |
| native-acquisition-full-validation-low-selectivity/numeric-64/100000 | incomplete |  |  | missing-or-invalid-pairs |
| native-acquisition-full-validation-low-selectivity/text-1024/10000 | incomplete |  |  | missing-or-invalid-pairs |
| native-acquisition-full-validation-low-selectivity/text-1024/100000 | incomplete |  |  | missing-or-invalid-pairs |
| fixed-join-count-shrinking-intermediate/narrow/100 | incomplete |  |  | unadmitted-pair:0 |
| fixed-join-count-shrinking-intermediate/narrow/1000 | incomplete |  |  | unadmitted-pair:0 |
| fixed-join-count-shrinking-intermediate/narrow/10000 | incomplete |  |  | unadmitted-pair:0 |
| fixed-join-count-shrinking-intermediate/narrow/100000 | incomplete |  |  | missing-or-invalid-pairs |
| fixed-join-count-shrinking-intermediate/narrow/1000000 | incomplete |  |  | missing-or-invalid-pairs |
| fixed-join-count-shrinking-intermediate/numeric-64/10000 | incomplete |  |  | missing-or-invalid-pairs |
| fixed-join-count-shrinking-intermediate/numeric-64/100000 | incomplete |  |  | missing-or-invalid-pairs |
| fixed-join-count-shrinking-intermediate/text-1024/10000 | incomplete |  |  | missing-or-invalid-pairs |
| fixed-join-count-shrinking-intermediate/text-1024/100000 | incomplete |  |  | missing-or-invalid-pairs |
| retained-large-output-downstream-reuse/narrow/100 | fail | 7 | warmMs: 52.236–71.667 (limit 10, fail); coldMs: 1100.762–1530.623 (limit 100, fail) |  |
| retained-large-output-downstream-reuse/narrow/1000 | fail | 7 | warmMs: 111.587–121.502 (limit 10, fail); coldMs: 1136.357–1209.703 (limit 100, fail) |  |
| retained-large-output-downstream-reuse/narrow/10000 | incomplete |  |  | unadmitted-pair:0 |
| retained-large-output-downstream-reuse/narrow/100000 | incomplete |  |  | missing-or-invalid-pairs |
| retained-large-output-downstream-reuse/narrow/1000000 | incomplete |  |  | missing-or-invalid-pairs |
| retained-large-output-downstream-reuse/numeric-64/10000 | incomplete |  |  | missing-or-invalid-pairs |
| retained-large-output-downstream-reuse/numeric-64/100000 | incomplete |  |  | missing-or-invalid-pairs |
| retained-large-output-downstream-reuse/text-1024/10000 | incomplete |  |  | missing-or-invalid-pairs |
| retained-large-output-downstream-reuse/text-1024/100000 | incomplete |  |  | missing-or-invalid-pairs |
