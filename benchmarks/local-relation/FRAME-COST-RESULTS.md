# Frame/event cost: one-pass results

## Outcome

One bounded improvement pass is complete; full performance acceptance is **not** claimed. Keep the current candidate available for review, without automatically moving into completion/producer changes or another tuning pass.

Frame extraction and event extraction both contributed measurable cost in the representative paths. Draining the shared transition loop and removing two temporary arrays shortened native prepared execution about 5–8% against the unoptimized extracted evaluator. JS was not consistently improved. These two local edits were tested together: their individual contributions have not been separately measured.

Against the pre-extraction baseline, native prepared paired medians still increased about 4–12% (median-time differences 0.17–3.81 ms per 1,000 rows). JS numeric projection remained about 14% higher (1.72 ms). Several other JS cases remained uncertain rather than demonstrated regressions or absence of regressions. Absolute costs below are specific to these bounded fixtures, not predictions for arbitrary row counts or API latency.

## Measurement and audit

All comparisons use the same rebased main base `7b655eb`, pinned release compiler, identical profiling overlays, native/JS, four 1,000-row workloads and E2E/prepared separately. Exactly seven alternating pairs per cell: 16 cells and 224 measured processes per comparison, 896 total. No uncertainty-driven repeat or second optimization cycle was performed. Every report's raw success assertions, RSS, pair order and computed statistics passed `auditDiagnosticReport`; the full-matrix auditor does not accept these reports as a gate.

- Frame extraction: `bafdc88 → fdf2723`; raw directory `_build/revision-measurements/1789257917782-76935/`; report SHA-256 `87c6c1dd70947afcb8f9b616f182a34a4201504dc80b99f83d4c3253cf23ee84`.
- Event/row handoff extraction: `fdf2723 → 1f2b981`; raw directory `_build/revision-measurements/1789258052379-76926/`; report SHA-256 `986a2fd2f364bcd2751bfdc1f0066dc9c0618dd057d34f8668a66d6e792aa675`.
- One improvement pass: `1f2b981 → d5ccc5d`; raw directory `_build/revision-measurements/1789258604542-3591/`; report SHA-256 `fe0a73dffe434267f70c730ea5420b0fbc3702e00da025dbd87e72187cad9526`.
- Residual against pre-extraction: `bafdc88 → d5ccc5d`; raw directory `_build/revision-measurements/1789258686228-3582/`; report SHA-256 `2d6d729e8fc32172514daf2c5aac3773f2c3c98750065647380756251c94c422`.

Builds were excluded. No tests/builds were intentionally run alongside measurement samples. RSS includes process startup, warmup, observation and cleanup; it is not a measure of logical roots or owned buffer capacity. Bootstrap intervals are descriptive paired-ratio intervals, not family-wise guarantees. Separate comparisons cannot be added to obtain an exact causal decomposition. Generated-code changes, allocation and host variation remain confounders; this is a controlled revision comparison, not instruction-level profiling.

## Attribution and improvement

Percentages are median paired time ratios minus one. Positive means slower. This table retains every case/mode/target in the fixed diagnostic subset.

| Target / case / mode | Frame extraction | Event extraction | Improvement vs extracted | Residual vs original |
| --- | ---: | ---: | ---: | ---: |
| native/additional/0/e2e | 0.3% | -0.3% | -1.0% | 0.8% |
| native/additional/0/prepared | 7.1% | 0.4% | -5.4% | 3.6% |
| js/additional/0/e2e | 1.7% | -2.5% | -1.3% | 1.8% |
| js/additional/0/prepared | 9.4% | 2.9% | 5.4% | 14.4% |
| native/supplemental/conditional-frames/e2e | 1.2% | 3.0% | -4.0% | 3.8% |
| native/supplemental/conditional-frames/prepared | 9.0% | 9.2% | -5.2% | 9.5% |
| native/supplemental/ordered-frames/e2e | 3.5% | 5.8% | -3.1% | 4.9% |
| native/supplemental/ordered-frames/prepared | 9.4% | 8.0% | -4.9% | 11.3% |
| native/supplemental/long-frames/e2e | 4.7% | 9.7% | -7.4% | 6.8% |
| native/supplemental/long-frames/prepared | 9.2% | 13.4% | -8.3% | 11.6% |
| js/supplemental/conditional-frames/e2e | 2.2% | 3.7% | 1.2% | 1.5% |
| js/supplemental/conditional-frames/prepared | 8.1% | 7.3% | -1.2% | 4.7% |
| js/supplemental/ordered-frames/e2e | -4.5% | -2.9% | 4.7% | 1.7% |
| js/supplemental/ordered-frames/prepared | 8.0% | -0.1% | 5.1% | 2.6% |
| js/supplemental/long-frames/e2e | 5.2% | 1.3% | -2.0% | -0.4% |
| js/supplemental/long-frames/prepared | 9.7% | 0.9% | -0.6% | 0.4% |

## Residual absolute cost and uncertainty

Times are milliseconds for the entire 1,000-row case. E2E includes preparation/import/observation/disposal; prepared includes the operation clock with reused admitted input and fresh budgets. Difference is after-median minus before-median; it can have a different sign from the median of paired ratios when samples vary. Do not substitute one statistic for the other. `uncertain` is the original seven-pair `extend` outcome, retained without extending under this bounded diagnostic authorization.

| Target / case / mode | Before ms | After ms | Difference ms | 95% paired ratio | Time observation | RSS change |
| --- | ---: | ---: | ---: | --- | --- | ---: |
| native/additional/0/e2e | 70.367 | 70.965 | 0.598 | 1.0027–1.0159 | within_tolerance | 0.3% |
| native/additional/0/prepared | 4.191 | 4.362 | 0.172 | 0.9848–1.1058 | uncertain | 0.4% |
| js/additional/0/e2e | 114.059 | 114.964 | 0.905 | 0.9961–1.0285 | within_tolerance | 0.9% |
| js/additional/0/prepared | 10.526 | 12.246 | 1.720 | 1.0732–1.2130 | regression | 0.8% |
| native/supplemental/conditional-frames/e2e | 9.440 | 9.751 | 0.311 | 1.0144–1.0679 | uncertain | -3.8% |
| native/supplemental/conditional-frames/prepared | 3.887 | 4.379 | 0.492 | 1.0654–1.1594 | regression | -0.2% |
| native/supplemental/ordered-frames/e2e | 16.477 | 17.290 | 0.813 | 1.0377–1.0546 | uncertain | -0.2% |
| native/supplemental/ordered-frames/prepared | 8.336 | 9.240 | 0.905 | 1.0938–1.1257 | regression | -0.2% |
| native/supplemental/long-frames/e2e | 40.481 | 43.785 | 3.305 | 1.0439–1.1383 | regression | -0.2% |
| native/supplemental/long-frames/prepared | 29.374 | 33.182 | 3.808 | 1.1070–1.1296 | regression | 0.3% |
| js/supplemental/conditional-frames/e2e | 31.073 | 32.654 | 1.581 | 0.9931–1.1262 | uncertain | 1.4% |
| js/supplemental/conditional-frames/prepared | 9.267 | 9.581 | 0.314 | 0.9817–1.0842 | uncertain | 1.5% |
| js/supplemental/ordered-frames/e2e | 49.294 | 49.742 | 0.447 | 0.9892–1.0194 | within_tolerance | 1.1% |
| js/supplemental/ordered-frames/prepared | 21.314 | 20.907 | -0.407 | 0.8118–1.0560 | uncertain | 1.2% |
| js/supplemental/long-frames/e2e | 102.154 | 105.788 | 3.634 | 0.9557–1.0527 | uncertain | 1.8% |
| js/supplemental/long-frames/prepared | 50.244 | 51.042 | 0.798 | 0.9932–1.0159 | within_tolerance | 1.2% |

No representative RSS comparison against the original exceeded the agreed 10% practical boundary. This does not prove all workloads or Wasm performance acceptable. Wasm performance, wide/nested cases outside this subset, and final full-matrix acceptance remain unmeasured in this pass.

## Preserved boundaries and checks

Product commit `d5ccc5d` changes only the shared expression transition implementation and binary-event iteration. The single-step private frame entry remains available. Synchronous draining does not create a second evaluator, change demand, defer charges or change terminal cleanup. Entry/operand/result/choice events and the row-root handoff remain shared with the restricted typed-kernel experiment. Fixed independent lazy/eager/failure/budget vectors still pass.

Added tests compare stepped/drained success and exact failure kind/expression range across 320 combinations of logical/control ceilings, including zero and exact boundaries. They compare consumed work, peak/live roots and failure status, and test draining after suspension, one-time result detachment, terminal reuse rejection and preservation of borrowed roots. Existing Relation ordering, ownership, input immutability and failure-atomicity tests run through the changed synchronous path.

Whole-repository JS/Wasm/native checks and tests passed with warnings denied: **3,366 tests each**. Public interfaces match all targets and tracked files; format, full documentation, metadata and 21 runner/statistics/auditor tests passed. Linux CI was not run. The private product output/producer Table boundary was not changed; Program/Run/Host/Effect remains out of scope.

## Decision to make

The retained frame/event boundary buys shared demand, error and root-accounting rules, controlled suspension/cleanup and a tested insertion point for restricted alternative kernels. It does **not** prove general vectorization or storage-independent production completion. Reverting the extraction wholesale would lose that demonstrated seam and reintroduce the earlier risk of duplicated semantics.

The remaining native expression-heavy cost and JS projection cost mean this candidate should not be described as free abstraction. Three choices remain with the user: accept the measured residual for the retained boundary; authorize a separate pass focused on the ordinary synchronous path while keeping shared semantics; or selectively revert part of the extraction. My recommendation is to retain the boundary and consider a separately bounded ordinary-path improvement before accepting broad performance regression. This pass provides no evidence that the whole boundary must be reverted. No further tuning, fallback or acceptance-policy change is made automatically.
