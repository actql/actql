# One-pass ordinary-path recovery

The user accepted the completion boundary and authorized one performance
recovery pass, without changing thresholds, workloads, measurement conditions
or the evaluator architecture. No second optimization pass follows these results.

## Frozen comparisons

Use the existing diagnostic subset: numeric projection, conditional, ordered
and long-expression cases, 1,000 rows, native/JS, E2E/prepared, seven alternating
pairs per cell (224 successful processes per comparison). Keep raw evidence,
compiler/binary/fixture identities and the independent report audit.

1. Direct attribution: historical `f025ce4` versus `536fef9`.
2. Recovery: `536fef9` versus that exact revision plus the one local patch.
3. Residual: pre-frame baseline `bafdc88` versus the same patched revision.

All measured revisions use the historical `7b655eb` main base, avoiding the
new main compiler/contracts as a confounder. The same product patch is committed
on the current rebased branch for whole-repository correctness verification.
The old baseline receives only the existing audited test-view compatibility
shim and byte-identical shared profiling fixtures. No product overlay is used.

The first sandboxed attempt failed before collecting any sample because macOS
RSS timing requires sysctl permission. Its failed report is retained at
`_build/revision-measurements/1789264915491-68104/report.json`; it is not evidence.
The permitted run collected all 224 samples at
`_build/revision-measurements/1789265022619-68997/report.json`.

## Selected local change

The direct comparison did not identify a reproducible five-percent time
regression caused by completion changes. Several JS cells remain uncertain;
separate earlier reports must not be treated as causal attribution.

Source and generated release JS do show a concrete extra operation introduced
by the boundary: `reserve_table` unconditionally calls a stored reservation
closure, even for default row storage whose closure always returns true and
does no accounting. Generated JS retains that indirect call, so it is not
merely unused source abstraction. It occurs per table, not per cell; it does
not by itself explain the earlier multi-percent timing differences.

This single patch represents the absent hook as `None`, avoiding construction
and invocation of the no-op callback. Explicit typed-storage hooks remain
`Some` and execute before the same common row accounting. It does not remove
the physical reservation boundary, expression frames, events, success evidence
or shared driver. The corresponding private optional-argument plumbing and
one existing typed test call site are adjusted. A fixed test compares absent
and explicit no-op accounting and checks that a rejecting hook still prevents
table installation. Existing typed retained-capacity and failure tests remain.

The patch is justified by the confirmed unnecessary call, not a claim that it
causes the measured residual. Only the fixed post-patch comparisons can show
whether its removal has a measurable benefit. An inconclusive or unfavorable
result is reported rather than initiating another optimization or rollback.

## Results and stopping decision

Implementation commit: `c6c0608` on main base `974ae98`. Its exact historical
cherry-pick is `8b3a625`, measured on `536fef9`. Only the one local hook patch
was applied; neither main changes nor evaluator redesign enter that candidate.

All three comparisons completed 224 successful measured processes each
(672 total), and their independent raw-output auditors passed. No uncertainty
extension, threshold change, workload reselection or second tuning pass occurred.

| Comparison | Time within threshold | Time regression | Time uncertain | RSS within threshold |
| --- | ---: | ---: | ---: | ---: |
| f025ce4 → 536fef9 | 10 | 0 | 6 | 16 |
| 536fef9 → 8b3a625 | 6 | 0 | 10 | 16 |
| bafdc88 → 8b3a625 | 2 | 8 | 6 | 16 |

`within_tolerance` is the existing cell policy, not an overall performance
acceptance. `extend` in the tables means unresolved after the fixed seven pairs;
no extra samples were collected. Paired-ratio medians and differences between
separate marginal medians are distinct estimators and can have opposite signs.

The local patch removes the confirmed no-op closure path in generated JS.
The prepared JS conditional case improved by a paired median 12.0%
(marginal median difference -1.770 ms), but this alone does not establish a
broad or reproducible engine-wide speedup. Other cells are small or uncertain;
conditional E2E point estimates worsened (native +8.4%, JS +6.3%) but remain
uncertain under the unchanged policy. Nothing is hidden by an overall average.

Against the pre-frame baseline, prepared native residuals are +5.5% numeric
projection (+0.250 ms), +12.8% conditional (+0.367 ms), +10.5% ordered
(+0.890 ms), and +12.2% long expressions (+3.532 ms). Prepared JS residuals
are +10.2% numeric (+0.905 ms, uncertain), +12.9% conditional (+0.925 ms,
regression), +1.7% ordered (+0.140 ms, uncertain), and +2.8% long expressions
(+1.242 ms, uncertain). These are direct paired comparisons, not sums of
percentages from the other runs. Full details, including E2E and RSS, follow.

The evidence supports removal of an unnecessary operation, not a complete
performance recovery. Acceptance of this candidate remains the user's decision;
there is no automatic rollback, further optimization or next-feature expansion.
Ordinary rows stay default, typed storage retains its explicit reservation,
and success ownership, shared demand/charge/failure rules and expression-frame
independence of completion are unchanged. Performance of the newly rebased main
itself, typed-path performance, Wasm timing and the full matrix are not measured
by this subset. No tests/builds were intentionally run concurrently with samples.

## Audited evidence

Whole-repository checks/tests on the current main-based `c6c0608` passed on
JS, Wasm and native with warnings denied: 3,401 tests each. Public interfaces
match across targets and tracked files. Format, documentation, metadata and
the 14 revision-overlay/statistics/auditor tests passed. Existing typed
completion, producer ownership, Parameter, failure atomicity and exact-budget
regressions are included in those whole-repository runs. Expression/frame/event,
completion success and producer-binding implementation files were not edited;
the driver edit only carries the optional storage hook.

Linux CI was not run. No push/merge was performed. Measurement worktrees,
binaries and raw logs are ignored and were not committed. The required pass
ends here; adopting the candidate and selecting the next feature remain
separate decisions.

Raw reports remain under `_build/revision-measurements/` (ignored). Generated
artifacts, source/fixture/runner hashes, compiler and host metadata are in each
report; these and previous baselines are retained rather than overwritten.

- `1789265022619-68997/report.json`: `94626bbc726f71905d8a150a50cea7dedc702321d9b7a19b7d9ad83abec02e4e`.
- `1789265171451-75139/report.json`: `f4166aae645e9af7c1fb5ff62030ac9a317cb4196cb866dbb275b7d3d3c3806b`.
- `1789265313592-76805/report.json`: `caa7a67294c4073f6944e2174584304006bc757d103e54c2140e558573ad6772`.

### Direct boundary attribution

Baseline: f025ce480be6e93b29a8f4f01cc3f0ba6e25c520. Candidate: 536fef920f7590754c63b31b92271a340409a0b0.

Gate: **not_evaluated**. 224 measured processes; 16 case/mode/target cells.

Time is microseconds (E2E or prepared operation as labelled). RSS is whole-process peak bytes; build is excluded. Intervals are descriptive paired-bootstrap ratio intervals, not family-wise guarantees.

| Case / target / mode | Metric | Pairs | Before median | After median | Absolute difference | Paired ratio | 95% ratio interval | Decision |
| --- | --- | ---: | ---: | ---: | ---: | ---: | --- | --- |
| native/additional/0/e2e | time | 7 | 73182.916 | 70985.625 | -2197.291 | 0.9737 | 0.9444–0.9781 | within_tolerance |
| native/additional/0/e2e | rss | 7 | 38617088.000 | 38699008.000 | 81920.000 | 1.0021 | 1.0021–1.0025 | within_tolerance |
| native/additional/0/prepared | time | 7 | 4533.375 | 4308.584 | -224.791 | 0.9390 | 0.9222–0.9911 | within_tolerance |
| native/additional/0/prepared | rss | 7 | 25346048.000 | 25411584.000 | 65536.000 | 1.0026 | 1.0026–1.0032 | within_tolerance |
| js/additional/0/e2e | time | 7 | 115070.875 | 118994.291 | 3923.416 | 0.9993 | 0.9817–1.0911 | extend |
| js/additional/0/e2e | rss | 7 | 199393280.000 | 200540160.000 | 1146880.000 | 1.0044 | 1.0005–1.0094 | within_tolerance |
| js/additional/0/prepared | time | 7 | 11604.750 | 11409.334 | -195.416 | 0.9474 | 0.9264–1.1671 | extend |
| js/additional/0/prepared | rss | 7 | 171212800.000 | 172392448.000 | 1179648.000 | 1.0068 | 1.0047–1.0092 | within_tolerance |
| native/supplemental/conditional-frames/e2e | time | 7 | 9846.709 | 9598.792 | -247.917 | 0.9803 | 0.9664–0.9957 | within_tolerance |
| native/supplemental/conditional-frames/e2e | rss | 7 | 7520256.000 | 7913472.000 | 393216.000 | 1.0523 | 1.0523–1.0546 | within_tolerance |
| native/supplemental/conditional-frames/prepared | time | 7 | 4381.667 | 4239.791 | -141.876 | 0.9709 | 0.9457–0.9875 | within_tolerance |
| native/supplemental/conditional-frames/prepared | rss | 7 | 7356416.000 | 7438336.000 | 81920.000 | 1.0111 | 1.0067–1.0111 | within_tolerance |
| native/supplemental/ordered-frames/e2e | time | 7 | 17411.917 | 17122.541 | -289.376 | 0.9775 | 0.9683–0.9851 | within_tolerance |
| native/supplemental/ordered-frames/e2e | rss | 7 | 8290304.000 | 8421376.000 | 131072.000 | 1.0178 | 1.0158–1.0178 | within_tolerance |
| native/supplemental/ordered-frames/prepared | time | 7 | 9299.500 | 8990.083 | -309.417 | 0.9690 | 0.9500–0.9753 | within_tolerance |
| native/supplemental/ordered-frames/prepared | rss | 7 | 8257536.000 | 8355840.000 | 98304.000 | 1.0099 | 1.0079–1.0139 | within_tolerance |
| native/supplemental/long-frames/e2e | time | 7 | 44284.583 | 42785.584 | -1498.999 | 0.9661 | 0.9488–0.9874 | within_tolerance |
| native/supplemental/long-frames/e2e | rss | 7 | 10584064.000 | 10485760.000 | -98304.000 | 0.9953 | 0.9814–1.0139 | within_tolerance |
| native/supplemental/long-frames/prepared | time | 7 | 31950.417 | 31119.916 | -830.501 | 0.9785 | 0.9568–1.0164 | within_tolerance |
| native/supplemental/long-frames/prepared | rss | 7 | 9682944.000 | 9797632.000 | 114688.000 | 1.0118 | 1.0084–1.0119 | within_tolerance |
| js/supplemental/conditional-frames/e2e | time | 7 | 29175.125 | 29842.958 | 667.833 | 1.0324 | 1.0042–1.0778 | extend |
| js/supplemental/conditional-frames/e2e | rss | 7 | 122437632.000 | 123879424.000 | 1441792.000 | 1.0118 | 1.0098–1.0123 | within_tolerance |
| js/supplemental/conditional-frames/prepared | time | 7 | 8793.333 | 9351.916 | 558.583 | 1.0409 | 1.0247–1.1077 | extend |
| js/supplemental/conditional-frames/prepared | rss | 7 | 119701504.000 | 121225216.000 | 1523712.000 | 1.0125 | 1.0117–1.0137 | within_tolerance |
| js/supplemental/ordered-frames/e2e | time | 7 | 43616.708 | 43040.667 | -576.041 | 0.9974 | 0.9606–1.0330 | within_tolerance |
| js/supplemental/ordered-frames/e2e | rss | 7 | 141017088.000 | 142491648.000 | 1474560.000 | 1.0099 | 1.0076–1.0117 | within_tolerance |
| js/supplemental/ordered-frames/prepared | time | 7 | 16620.250 | 15470.791 | -1149.459 | 0.9443 | 0.8746–0.9968 | within_tolerance |
| js/supplemental/ordered-frames/prepared | rss | 7 | 121470976.000 | 123011072.000 | 1540096.000 | 1.0125 | 1.0115–1.0140 | within_tolerance |
| js/supplemental/long-frames/e2e | time | 7 | 84227.792 | 88288.125 | 4060.333 | 1.0346 | 0.9375–1.1043 | extend |
| js/supplemental/long-frames/e2e | rss | 7 | 145440768.000 | 146735104.000 | 1294336.000 | 1.0127 | 0.9975–1.0291 | within_tolerance |
| js/supplemental/long-frames/prepared | time | 7 | 40279.458 | 41542.125 | 1262.667 | 1.0217 | 1.0053–1.0858 | extend |
| js/supplemental/long-frames/prepared | rss | 7 | 138559488.000 | 139902976.000 | 1343488.000 | 1.0107 | 1.0095–1.0116 | within_tolerance |

Seven-pair screening results remain in the raw report. A regression seen then is not erased by a later extension for another metric. No column-adoption or completion-boundary conformance claim follows from timing evidence.

### One-patch comparison

Baseline: 536fef920f7590754c63b31b92271a340409a0b0. Candidate: 8b3a625939815dd152f9ff97f49edd99c6a25223.

Gate: **not_evaluated**. 224 measured processes; 16 case/mode/target cells.

Time is microseconds (E2E or prepared operation as labelled). RSS is whole-process peak bytes; build is excluded. Intervals are descriptive paired-bootstrap ratio intervals, not family-wise guarantees.

| Case / target / mode | Metric | Pairs | Before median | After median | Absolute difference | Paired ratio | 95% ratio interval | Decision |
| --- | --- | ---: | ---: | ---: | ---: | ---: | --- | --- |
| native/additional/0/e2e | time | 7 | 71672.292 | 71127.500 | -544.792 | 0.9946 | 0.9764–0.9985 | within_tolerance |
| native/additional/0/e2e | rss | 7 | 38715392.000 | 38715392.000 | 0.000 | 1.0000 | 1.0000–1.0004 | within_tolerance |
| native/additional/0/prepared | time | 7 | 4381.833 | 4417.709 | 35.876 | 0.9825 | 0.9724–1.0280 | within_tolerance |
| native/additional/0/prepared | rss | 7 | 25411584.000 | 25444352.000 | 32768.000 | 1.0013 | 1.0013–1.0013 | within_tolerance |
| js/additional/0/e2e | time | 7 | 134115.750 | 134935.875 | 820.125 | 1.0219 | 0.9299–1.0601 | extend |
| js/additional/0/e2e | rss | 7 | 200704000.000 | 200146944.000 | -557056.000 | 0.9999 | 0.9962–1.0016 | within_tolerance |
| js/additional/0/prepared | time | 7 | 14491.333 | 14393.125 | -98.208 | 0.9885 | 0.8855–1.2607 | extend |
| js/additional/0/prepared | rss | 7 | 172343296.000 | 172376064.000 | 32768.000 | 1.0010 | 0.9944–1.0037 | within_tolerance |
| native/supplemental/conditional-frames/e2e | time | 7 | 10864.083 | 11427.042 | 562.959 | 1.0842 | 0.9681–1.0927 | extend |
| native/supplemental/conditional-frames/e2e | rss | 7 | 7913472.000 | 7684096.000 | -229376.000 | 0.9710 | 0.9689–0.9710 | within_tolerance |
| native/supplemental/conditional-frames/prepared | time | 7 | 4507.833 | 4502.125 | -5.708 | 0.9698 | 0.8988–1.0770 | extend |
| native/supplemental/conditional-frames/prepared | rss | 7 | 7421952.000 | 7503872.000 | 81920.000 | 1.0110 | 1.0088–1.0110 | within_tolerance |
| native/supplemental/ordered-frames/e2e | time | 7 | 18588.666 | 19111.041 | 522.375 | 1.0004 | 0.9337–1.0798 | extend |
| native/supplemental/ordered-frames/e2e | rss | 7 | 8421376.000 | 8486912.000 | 65536.000 | 1.0078 | 1.0078–1.0078 | within_tolerance |
| native/supplemental/ordered-frames/prepared | time | 7 | 10218.708 | 9881.375 | -337.333 | 0.9746 | 0.8798–1.0586 | extend |
| native/supplemental/ordered-frames/prepared | rss | 7 | 8355840.000 | 8437760.000 | 81920.000 | 1.0098 | 1.0078–1.0118 | within_tolerance |
| native/supplemental/long-frames/e2e | time | 7 | 48233.000 | 48827.833 | 594.833 | 1.0316 | 1.0050–1.0406 | within_tolerance |
| native/supplemental/long-frames/e2e | rss | 7 | 10469376.000 | 10846208.000 | 376832.000 | 1.0314 | 1.0153–1.0392 | within_tolerance |
| native/supplemental/long-frames/prepared | time | 7 | 35204.917 | 35166.541 | -38.376 | 1.0064 | 0.9686–1.0390 | within_tolerance |
| native/supplemental/long-frames/prepared | rss | 7 | 9797632.000 | 9912320.000 | 114688.000 | 1.0083 | 1.0067–1.0134 | within_tolerance |
| js/supplemental/conditional-frames/e2e | time | 7 | 35494.667 | 36783.917 | 1289.250 | 1.0631 | 0.9418–1.2124 | extend |
| js/supplemental/conditional-frames/e2e | rss | 7 | 123748352.000 | 124043264.000 | 294912.000 | 1.0011 | 0.9996–1.0048 | within_tolerance |
| js/supplemental/conditional-frames/prepared | time | 7 | 12508.833 | 10738.375 | -1770.458 | 0.8801 | 0.6636–0.9141 | within_tolerance |
| js/supplemental/conditional-frames/prepared | rss | 7 | 121225216.000 | 121094144.000 | -131072.000 | 0.9986 | 0.9982–1.0000 | within_tolerance |
| js/supplemental/ordered-frames/e2e | time | 7 | 49806.666 | 50896.583 | 1089.917 | 1.0325 | 0.9755–1.0501 | extend |
| js/supplemental/ordered-frames/e2e | rss | 7 | 142540800.000 | 142557184.000 | 16384.000 | 1.0001 | 0.9966–1.0029 | within_tolerance |
| js/supplemental/ordered-frames/prepared | time | 7 | 17303.709 | 18261.959 | 958.250 | 1.0149 | 0.9421–1.4975 | extend |
| js/supplemental/ordered-frames/prepared | rss | 7 | 122961920.000 | 123027456.000 | 65536.000 | 0.9995 | 0.9984–1.0024 | within_tolerance |
| js/supplemental/long-frames/e2e | time | 7 | 84789.000 | 85228.792 | 439.792 | 1.0374 | 0.9858–1.0533 | extend |
| js/supplemental/long-frames/e2e | rss | 7 | 146112512.000 | 145752064.000 | -360448.000 | 0.9980 | 0.9939–1.0016 | within_tolerance |
| js/supplemental/long-frames/prepared | time | 7 | 38815.667 | 37973.416 | -842.251 | 0.9880 | 0.9603–1.0005 | within_tolerance |
| js/supplemental/long-frames/prepared | rss | 7 | 139870208.000 | 139771904.000 | -98304.000 | 1.0000 | 0.9992–1.0014 | within_tolerance |

Seven-pair screening results remain in the raw report. A regression seen then is not erased by a later extension for another metric. No column-adoption or completion-boundary conformance claim follows from timing evidence.

### Remaining cost against old baseline

Baseline: bafdc88da64a5cccdce541a57e57b4b05e5fa7da. Candidate: 8b3a625939815dd152f9ff97f49edd99c6a25223.

Gate: **not_evaluated**. 224 measured processes; 16 case/mode/target cells.

Time is microseconds (E2E or prepared operation as labelled). RSS is whole-process peak bytes; build is excluded. Intervals are descriptive paired-bootstrap ratio intervals, not family-wise guarantees.

| Case / target / mode | Metric | Pairs | Before median | After median | Absolute difference | Paired ratio | 95% ratio interval | Decision |
| --- | --- | ---: | ---: | ---: | ---: | ---: | --- | --- |
| native/additional/0/e2e | time | 7 | 71113.208 | 71042.584 | -70.624 | 1.0049 | 0.9923–1.0087 | within_tolerance |
| native/additional/0/e2e | rss | 7 | 38502400.000 | 38715392.000 | 212992.000 | 1.0055 | 1.0055–1.0055 | within_tolerance |
| native/additional/0/prepared | time | 7 | 4070.375 | 4320.291 | 249.916 | 1.0549 | 1.0456–1.0683 | regression |
| native/additional/0/prepared | rss | 7 | 25247744.000 | 25444352.000 | 196608.000 | 1.0078 | 1.0078–1.0078 | within_tolerance |
| js/additional/0/e2e | time | 7 | 112966.792 | 114592.792 | 1626.000 | 1.0077 | 0.9935–1.0376 | within_tolerance |
| js/additional/0/e2e | rss | 7 | 197083136.000 | 199917568.000 | 2834432.000 | 1.0130 | 1.0118–1.0147 | within_tolerance |
| js/additional/0/prepared | time | 7 | 10171.458 | 11076.167 | 904.709 | 1.1022 | 0.9398–1.1642 | extend |
| js/additional/0/prepared | rss | 7 | 169672704.000 | 172277760.000 | 2605056.000 | 1.0155 | 1.0146–1.0175 | within_tolerance |
| native/supplemental/conditional-frames/e2e | time | 7 | 9566.250 | 9830.208 | 263.958 | 1.0407 | 0.9995–1.0723 | extend |
| native/supplemental/conditional-frames/e2e | rss | 7 | 7798784.000 | 7684096.000 | -114688.000 | 0.9853 | 0.9811–0.9853 | within_tolerance |
| native/supplemental/conditional-frames/prepared | time | 7 | 3938.708 | 4305.416 | 366.708 | 1.1284 | 1.0337–1.1398 | regression |
| native/supplemental/conditional-frames/prepared | rss | 7 | 7356416.000 | 7503872.000 | 147456.000 | 1.0200 | 1.0178–1.0200 | within_tolerance |
| native/supplemental/ordered-frames/e2e | time | 7 | 16481.750 | 17590.125 | 1108.375 | 1.0608 | 1.0479–1.0773 | regression |
| native/supplemental/ordered-frames/e2e | rss | 7 | 8290304.000 | 8486912.000 | 196608.000 | 1.0237 | 1.0237–1.0257 | within_tolerance |
| native/supplemental/ordered-frames/prepared | time | 7 | 8318.000 | 9207.792 | 889.792 | 1.1054 | 1.0979–1.1408 | regression |
| native/supplemental/ordered-frames/prepared | rss | 7 | 8273920.000 | 8437760.000 | 163840.000 | 1.0198 | 1.0178–1.0218 | within_tolerance |
| native/supplemental/long-frames/e2e | time | 7 | 40702.792 | 43801.375 | 3098.583 | 1.0835 | 1.0651–1.1037 | regression |
| native/supplemental/long-frames/e2e | rss | 7 | 10534912.000 | 10813440.000 | 278528.000 | 1.0264 | 1.0217–1.0279 | within_tolerance |
| native/supplemental/long-frames/prepared | time | 7 | 27688.000 | 31220.292 | 3532.292 | 1.1224 | 1.1171–1.1390 | regression |
| native/supplemental/long-frames/prepared | rss | 7 | 9715712.000 | 9945088.000 | 229376.000 | 1.0236 | 1.0169–1.0288 | within_tolerance |
| js/supplemental/conditional-frames/e2e | time | 7 | 29311.459 | 29806.834 | 495.375 | 1.0389 | 0.9537–1.0807 | extend |
| js/supplemental/conditional-frames/e2e | rss | 7 | 120635392.000 | 124059648.000 | 3424256.000 | 1.0277 | 1.0259–1.0298 | within_tolerance |
| js/supplemental/conditional-frames/prepared | time | 7 | 8381.209 | 9306.542 | 925.333 | 1.1294 | 1.0820–1.1709 | regression |
| js/supplemental/conditional-frames/prepared | rss | 7 | 118095872.000 | 121110528.000 | 3014656.000 | 1.0255 | 1.0244–1.0295 | within_tolerance |
| js/supplemental/ordered-frames/e2e | time | 7 | 43766.083 | 44051.125 | 285.042 | 1.0109 | 0.9895–1.0557 | extend |
| js/supplemental/ordered-frames/e2e | rss | 7 | 139771904.000 | 142409728.000 | 2637824.000 | 1.0201 | 1.0172–1.0216 | within_tolerance |
| js/supplemental/ordered-frames/prepared | time | 7 | 13962.750 | 14102.459 | 139.709 | 1.0171 | 0.9819–1.0519 | extend |
| js/supplemental/ordered-frames/prepared | rss | 7 | 120061952.000 | 123043840.000 | 2981888.000 | 1.0247 | 1.0229–1.0250 | within_tolerance |
| js/supplemental/long-frames/e2e | time | 7 | 70110.208 | 75137.083 | 5026.875 | 1.0728 | 1.0539–1.0985 | regression |
| js/supplemental/long-frames/e2e | rss | 7 | 139984896.000 | 146735104.000 | 6750208.000 | 1.0454 | 1.0375–1.0495 | within_tolerance |
| js/supplemental/long-frames/prepared | time | 7 | 35283.875 | 36526.333 | 1242.458 | 1.0279 | 1.0225–1.1058 | extend |
| js/supplemental/long-frames/prepared | rss | 7 | 136773632.000 | 139837440.000 | 3063808.000 | 1.0224 | 1.0216–1.0233 | within_tolerance |

Seven-pair screening results remain in the raw report. A regression seen then is not erased by a later extension for another metric. No column-adoption or completion-boundary conformance claim follows from timing evidence.
