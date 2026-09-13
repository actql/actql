# Historical row execution comparison: stopped

> Historical snapshot, not current status or authorization. Start with the
> [integrated report](../REPORT.md). Past stops and pending approvals below
> describe only the stage at which this document was written.

The performance gate did **not** pass. No completion/producer product edits
were made. This is an incomplete historical comparison, not full-matrix or
final implementation verification.

## Evidence and stopping condition

Baseline `f9ac87b` and candidate `820a971`, row A, used identical test-only
overlays from `ec352ed`, the pinned release compiler and alternating pairs.
Raw outputs, binaries, hashes, host details and screening/final statistics are
retained in ignored `_build/revision-measurements/1789256481121-46828/`.

The first native E2E cell remained inconclusive after 21 pairs: median paired
ratio 1.0439, descriptive 95% interval 1.0337–1.0550. This crosses the agreed
1.05 practical boundary; it is not evidence of absence of regression.
Native prepared cases also showed reproducible regressions, including
numeric projection and nullable workloads at approximately 14–17%.

The initial runner incorrectly continued collecting later cells after an
inconclusive 21-pair result. It was manually terminated (exit 143), retaining
812 successful raw samples and 37 completed cell decisions. Of these decisions,
time had 27 regressions, six inconclusive cases and four within tolerance;
RSS was within the agreed 10% tolerance for all 37. No conclusion is drawn
for unmeasured JS/Wasm cells or supplemental expression profiles. Their earlier
48-invocation smoke proves correctness of the fixture path, not performance.

The checkpoint still says `running` because termination bypassed finalization;
this report records its actual stopped state without rewriting raw evidence.
All 812 stored samples were revalidated against raw output assertions and RSS,
and the 37 saved screening/final decisions were independently recomputed.
Trailing samples without a saved decision are not included in decision counts.
Decided cells account for 798 samples; 14 trailing samples remain unclassified.
Checkpoint SHA-256:
`7f02dec886e46f08a873f73c581edf81d0cda8f9313154fd34f4fbed3e8ab12c`.
The full-matrix auditor correctly refuses this incomplete checkpoint.

The runner now automatically stops collection on the first inconclusive final
decision, writes `status: stopped` and `matrix_gate: not_evaluated`, and does not
proceed to another cell. Unit coverage fixes this protocol error. The historical
measurement is not retried to obtain a pass or silently reclassified.
The stop/auditor/statistics tests passed 19 cases after this correction;
script syntax, diff whitespace, document links and metadata also passed.

## Completed native cells

Times are microseconds. Ratio is the median of paired ratios, not the ratio of
the two medians. IDs refer to the fixed inventory in `columnar-experiment.json`.
RSS ratio is whole-process peak memory, not logical or explicitly owned memory.

| Cell | Pairs | Before | After | Time ratio | 95% ratio interval | Time decision | RSS ratio |
| --- | ---: | ---: | ---: | ---: | --- | --- | ---: |
| legacy/0/e2e | 21 | 777.708 | 813.083 | 1.0439 | 1.0337–1.0550 | inconclusive | 1.0147 |
| legacy/0/prepared | 7 | 62.542 | 73.042 | 1.1446 | 1.0828–1.2007 | regression | 1.0147 |
| legacy/1/e2e | 21 | 1032.250 | 1069.375 | 1.0291 | 1.0194–1.0650 | inconclusive | 1.0175 |
| legacy/1/prepared | 7 | 291.792 | 304.833 | 1.0716 | 1.0143–1.1747 | regression | 1.0147 |
| legacy/2/e2e | 21 | 7501.834 | 7760.667 | 1.0374 | 1.0211–1.0516 | inconclusive | 1.0086 |
| legacy/2/prepared | 7 | 451.542 | 502.125 | 1.1163 | 1.0898–1.1410 | regression | 1.0087 |
| legacy/3/e2e | 7 | 7821.166 | 8286.000 | 1.0672 | 1.0239–1.0730 | regression | 1.0108 |
| legacy/3/prepared | 7 | 873.084 | 949.875 | 1.0879 | 1.0719–1.1062 | regression | 1.0086 |
| legacy/4/e2e | 7 | 3581.834 | 3682.167 | 1.0254 | 1.0166–1.0486 | within_tolerance | 1.0126 |
| legacy/4/prepared | 21 | 700.833 | 742.917 | 1.0508 | 1.0347–1.0692 | regression | 1.0101 |
| legacy/5/e2e | 21 | 6417.417 | 6674.708 | 1.0393 | 1.0330–1.0590 | inconclusive | 1.0101 |
| legacy/5/prepared | 21 | 3485.000 | 3652.791 | 1.0421 | 1.0334–1.0595 | inconclusive | 1.0100 |
| legacy/6/e2e | 7 | 68815.542 | 72727.875 | 1.0569 | 1.0333–1.0743 | regression | 1.0022 |
| legacy/6/prepared | 7 | 4227.125 | 4585.917 | 1.0933 | 1.0397–1.1154 | regression | 1.0027 |
| legacy/7/e2e | 7 | 73531.375 | 77377.792 | 1.0502 | 1.0418–1.0656 | regression | 1.0013 |
| legacy/7/prepared | 7 | 8899.875 | 9808.417 | 1.0972 | 1.0905–1.1023 | regression | 1.0027 |
| legacy/8/e2e | 7 | 31889.250 | 33441.542 | 1.0526 | 1.0330–1.0613 | regression | 1.0040 |
| legacy/8/prepared | 7 | 8120.459 | 8678.166 | 1.0650 | 1.0505–1.1150 | regression | 1.0041 |
| legacy/9/e2e | 7 | 66859.750 | 69753.709 | 1.0433 | 1.0314–1.0487 | within_tolerance | 1.0050 |
| legacy/9/prepared | 7 | 41627.917 | 43783.708 | 1.0564 | 1.0454–1.0578 | regression | 1.0040 |
| legacy/10/e2e | 21 | 684880.125 | 714525.958 | 1.0456 | 1.0363–1.0508 | inconclusive | 1.0004 |
| legacy/10/prepared | 21 | 46363.333 | 50137.000 | 1.0815 | 1.0713–1.0943 | regression | 1.0002 |
| legacy/11/e2e | 7 | 748895.458 | 775697.125 | 1.0366 | 1.0170–1.0421 | within_tolerance | 1.0004 |
| legacy/11/prepared | 7 | 101984.125 | 109960.958 | 1.0760 | 1.0683–1.0819 | regression | 1.0003 |
| additional/0/e2e | 21 | 70300.083 | 73550.375 | 1.0501 | 1.0446–1.0552 | regression | 1.0034 |
| additional/0/prepared | 7 | 3929.375 | 4495.541 | 1.1576 | 1.0880–1.1812 | regression | 1.0045 |
| additional/1/e2e | 7 | 675530.875 | 710338.084 | 1.0515 | 1.0360–1.0574 | regression | 1.0006 |
| additional/1/prepared | 7 | 41876.584 | 47745.333 | 1.1448 | 1.1253–1.1621 | regression | 1.0006 |
| additional/2/e2e | 7 | 69239.666 | 72501.666 | 1.0509 | 1.0418–1.0542 | regression | 1.0034 |
| additional/2/prepared | 7 | 4551.291 | 5236.958 | 1.1653 | 1.1157–1.1747 | regression | 1.0053 |
| additional/3/e2e | 7 | 637272.041 | 664389.000 | 1.0408 | 1.0344–1.0486 | within_tolerance | 1.0006 |
| additional/3/prepared | 7 | 47067.000 | 54958.708 | 1.1677 | 1.1590–1.1752 | regression | 1.0006 |
| additional/4/e2e | 7 | 906443.875 | 953463.916 | 1.0515 | 1.0452–1.0554 | regression | 1.0006 |
| additional/4/prepared | 7 | 270885.292 | 287333.875 | 1.0539 | 1.0446–1.0726 | regression | 1.0006 |
| additional/5/e2e | 7 | 1016994.041 | 1068036.500 | 1.0529 | 1.0489–1.0584 | regression | 1.0006 |
| additional/5/prepared | 7 | 388865.333 | 420224.416 | 1.0801 | 1.0688–1.1017 | regression | 1.0006 |
| additional/6/e2e | 21 | 1144835.583 | 1211450.542 | 1.0538 | 1.0409–1.0716 | regression | 1.0006 |

## Interpretation and next decision

The cause is not yet isolated. Frame allocation, per-transition resumable
dispatch and extracted event operations are investigation candidates, not
measured causal findings. No logical budget, demand or failure rule should be
relaxed to recover speed. Completion-boundary work remains unstarted; the
agreed uncertainty stop requires a decision before renewed measurement or
product changes. Linux CI and final whole-repository verification remain undone.
