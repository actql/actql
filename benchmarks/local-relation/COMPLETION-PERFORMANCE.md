# Post-boundary diagnostic

One authorized diagnostic is complete: `bafdc88` versus `2e913f2`, four
1,000-row workloads, native/JS, E2E/prepared, seven alternating pairs per cell.
All 224 measured processes passed their output assertions; the independent
diagnostic auditor recomputed all 16 cells from raw output and RSS. There was
no extension, remeasurement or frame/event optimization.

This is **not a performance gate pass** and does **not establish that the
accepted regression stayed unchanged**. Nine time cells report regression,
four are within the practical threshold and three remain uncertain. The
historical full-matrix gate remains unpassed. All RSS cells are within the
10% threshold, with paired changes ranging approximately -2.1% to +3.1%.

## Comparison with the recorded one-pass residuals

Percentages below are paired time ratios against the respective run's
pre-extraction baseline. These are separate measurements, not a paired
before/after estimate of the completion boundary alone.

| Prepared case | Prior residual | Current residual | Current median difference |
| --- | ---: | ---: | ---: |
| native numeric projection | +3.6% | +8.1% | +0.290 ms |
| native conditional | +9.5% | +11.8% | +0.451 ms |
| native ordered | +11.3% | +12.7% | +0.912 ms |
| native long expression | +11.6% | +11.1% | +3.155 ms |
| JS numeric projection | +14.4% | +20.0% | +2.179 ms |
| JS conditional | +4.7% | +5.5% | +0.476 ms |
| JS ordered | +2.6% | +5.4% | +0.846 ms |
| JS long expression | +0.4% | +3.3% | +1.066 ms |

Possible growth is especially visible in numeric projection, while other
cells moved in both directions. The current long-expression JS result remains
uncertain under the fixed policy. Some historical cells were uncertain too.
Host metadata matches (Apple M4, macOS 25.2.0, Node 22.23.2), but machine load,
runtime optimization and generated-code differences remain confounders.
Do not subtract ratios or absolute medians across runs to claim exact causal
cost. No further diagnosis or acceptance decision is implicit.

## Evidence and profiling compatibility

Raw directory: `_build/revision-measurements/1789262577023-7322/`.
Report SHA-256:
`500ebb0c652cedf323a07317277f6ff16e8c7f4882b9f9b8db3ea10091911141`.

The report records both source commits/trees, overlay hashes, runner/helper
hashes, binaries, compiler, execution order, raw successful output and RSS.
The earlier residual report and its raw files remain unchanged; see
[the one-pass report](FRAME-COST-RESULTS.md).

Shared profiling fixtures, clocks and assertions are byte-identical between
the two worktrees. The old completion representation additionally uses an
exact baseline-only whitebox shim returning its existing row store/table.
The candidate's existing helper unwraps its row representation. Neither
changes product execution, budgets, success construction or measurement
scope. The overlay checker rejects product edits, arbitrary new files,
modified shims and applying the legacy shim to the new layout. Nine shared
fixture overlays and that shim are recorded on the baseline; its product
source is untouched.

Builds are excluded and no other tests/builds were intentionally run during
samples. Whole-process RSS is not logical value bytes or owned buffer capacity.
Wasm performance, the full historical matrix and typed-path performance are
not measured by this diagnostic. `extend` below means uncertainty retained
at seven pairs, not permission to collect more samples.

## Independently audited cells

# Row execution revision comparison

Baseline: bafdc88da64a5cccdce541a57e57b4b05e5fa7da. Candidate: 2e913f293ae1f190d74a262f71d549bc3f7e98a6.

Gate: **not_evaluated**. 224 measured processes; 16 case/mode/target cells.

Time is microseconds (E2E or prepared operation as labelled). RSS is whole-process peak bytes; build is excluded. Intervals are descriptive paired-bootstrap ratio intervals, not family-wise guarantees.

| Case / target / mode | Metric | Pairs | Before median | After median | Absolute difference | Paired ratio | 95% ratio interval | Decision |
| --- | --- | ---: | ---: | ---: | ---: | ---: | --- | --- |
| native/additional/0/e2e | time | 7 | 70510.375 | 70815.625 | 305.250 | 1.0076 | 1.0006–1.0129 | within_tolerance |
| native/additional/0/e2e | rss | 7 | 38502400.000 | 38715392.000 | 212992.000 | 1.0055 | 1.0055–1.0055 | within_tolerance |
| native/additional/0/prepared | time | 7 | 4084.583 | 4374.666 | 290.083 | 1.0807 | 1.0477–1.0896 | regression |
| native/additional/0/prepared | rss | 7 | 25247744.000 | 25427968.000 | 180224.000 | 1.0071 | 1.0065–1.0078 | within_tolerance |
| js/additional/0/e2e | time | 7 | 110645.833 | 111849.875 | 1204.042 | 1.0018 | 0.9964–1.0340 | within_tolerance |
| js/additional/0/e2e | rss | 7 | 197165056.000 | 200507392.000 | 3342336.000 | 1.0153 | 1.0095–1.0190 | within_tolerance |
| js/additional/0/prepared | time | 7 | 9635.292 | 11814.750 | 2179.458 | 1.1999 | 1.0955–1.2684 | regression |
| js/additional/0/prepared | rss | 7 | 169574400.000 | 172163072.000 | 2588672.000 | 1.0164 | 1.0131–1.0206 | within_tolerance |
| native/supplemental/conditional-frames/e2e | time | 7 | 9379.459 | 9615.542 | 236.083 | 1.0230 | 1.0112–1.0285 | within_tolerance |
| native/supplemental/conditional-frames/e2e | rss | 7 | 7798784.000 | 7634944.000 | -163840.000 | 0.9790 | 0.9790–0.9790 | within_tolerance |
| native/supplemental/conditional-frames/prepared | time | 7 | 3765.625 | 4216.250 | 450.625 | 1.1180 | 1.0918–1.1687 | regression |
| native/supplemental/conditional-frames/prepared | rss | 7 | 7372800.000 | 7454720.000 | 81920.000 | 1.0111 | 1.0089–1.0111 | within_tolerance |
| native/supplemental/ordered-frames/e2e | time | 7 | 16065.292 | 17120.791 | 1055.499 | 1.0761 | 1.0638–1.0834 | regression |
| native/supplemental/ordered-frames/e2e | rss | 7 | 8290304.000 | 8437760.000 | 147456.000 | 1.0178 | 1.0158–1.0198 | within_tolerance |
| native/supplemental/ordered-frames/prepared | time | 7 | 8077.167 | 8989.666 | 912.499 | 1.1269 | 1.0916–1.1416 | regression |
| native/supplemental/ordered-frames/prepared | rss | 7 | 8273920.000 | 8372224.000 | 98304.000 | 1.0119 | 1.0119–1.0159 | within_tolerance |
| native/supplemental/long-frames/e2e | time | 7 | 40297.292 | 43004.250 | 2706.958 | 1.0765 | 1.0539–1.0784 | regression |
| native/supplemental/long-frames/e2e | rss | 7 | 10518528.000 | 10780672.000 | 262144.000 | 1.0233 | 1.0156–1.0265 | within_tolerance |
| native/supplemental/long-frames/prepared | time | 7 | 27786.084 | 30941.209 | 3155.125 | 1.1107 | 1.0917–1.1405 | regression |
| native/supplemental/long-frames/prepared | rss | 7 | 9682944.000 | 9846784.000 | 163840.000 | 1.0152 | 1.0101–1.0186 | within_tolerance |
| js/supplemental/conditional-frames/e2e | time | 7 | 28714.292 | 28589.875 | -124.417 | 1.0093 | 0.9912–1.0689 | extend |
| js/supplemental/conditional-frames/e2e | rss | 7 | 120651776.000 | 123748352.000 | 3096576.000 | 1.0250 | 1.0240–1.0264 | within_tolerance |
| js/supplemental/conditional-frames/prepared | time | 7 | 8356.750 | 8832.917 | 476.167 | 1.0548 | 1.0295–1.1361 | regression |
| js/supplemental/conditional-frames/prepared | rss | 7 | 117882880.000 | 120848384.000 | 2965504.000 | 1.0252 | 1.0223–1.0285 | within_tolerance |
| js/supplemental/ordered-frames/e2e | time | 7 | 42135.042 | 42744.333 | 609.291 | 1.0270 | 0.9942–1.0477 | within_tolerance |
| js/supplemental/ordered-frames/e2e | rss | 7 | 139771904.000 | 142262272.000 | 2490368.000 | 1.0173 | 1.0147–1.0202 | within_tolerance |
| js/supplemental/ordered-frames/prepared | time | 7 | 13169.250 | 14015.042 | 845.792 | 1.0536 | 1.0106–1.0818 | regression |
| js/supplemental/ordered-frames/prepared | rss | 7 | 119832576.000 | 122847232.000 | 3014656.000 | 1.0251 | 1.0230–1.0274 | within_tolerance |
| js/supplemental/long-frames/e2e | time | 7 | 70646.792 | 71878.916 | 1232.124 | 1.0305 | 0.9959–1.0620 | extend |
| js/supplemental/long-frames/e2e | rss | 7 | 142311424.000 | 146489344.000 | 4177920.000 | 1.0307 | 1.0180–1.0444 | within_tolerance |
| js/supplemental/long-frames/prepared | time | 7 | 33991.542 | 35057.917 | 1066.375 | 1.0326 | 1.0124–1.0500 | extend |
| js/supplemental/long-frames/prepared | rss | 7 | 136708096.000 | 139837440.000 | 3129344.000 | 1.0220 | 1.0196–1.0237 | within_tolerance |

Seven-pair screening results remain in the raw report. A regression seen then is not erased by a later extension for another metric. No column-adoption or completion-boundary conformance claim follows from timing evidence.
