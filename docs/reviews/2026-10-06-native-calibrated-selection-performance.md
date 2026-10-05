# Native calibrated selection performance

G owns this second performance unit. The dependency #493, fixed at
`7b48ed3140b05c906c6c5f875712bc4bd81f3dfd`, was merged into main as
`5d52b3a970984f3cdad554b9030a0c25fa8ac887`. The final target and PR base are main.

## Connection contract

`native-resident-estimate-profile.mjs` admits a complete measured profile for the
existing low-selectivity/narrow 1,000-row training and 100-row held-out case.
It binds revision, Native binary digest, independent Program/source definitions,
three alternating training rounds, actual Owner/phase observations, derived
task/shared/import rates and held-out offers. Local, fresh and resident are
separate realizations even when both DuckDB forms share a registration name.
Missing training, raw events, unknown producer measurements, another revision
or binary and changed rates/actual offers are rejected. The original training
observations are not rewritten for another checkout.

The existing `native-direct-pair.mjs` accepts this explicit profile as an
alternative to its fresh-only profile. It preflights the measured profile before
either execution leg, verifies its exact binary again at Native dispatch, and
compares the actual realization choices and offers. Existing equivalent-
obligation admission and registered timing thresholds remain applicable.
Profile qualification time is reported separately, not disguised as task time.

The calibration CLI uses this shared derivation/admission contract. Synthetic
admission fixtures establish refusal/wiring only; actual timing and retained
Owner evidence still require real Native execution.

## Next measured comparison

Use one immutable 100-row source, the same Native binary, Host, logical Program,
output expectations and physical/work/retention limits. Before is the previous
explicit resident experiment with Local/fresh estimates of 1,000 ms and fixed
1 ms resident estimates. After supplies the measured profile to ordinary planner
selection. This compares cost-grounded selection with the old experiment's
unmeasured configuration; it is not an engine algorithm speedup or a comparison
with the experiment's pinned historical ActQL baseline.

Predeclare seven alternating pairs. Preserve every failed/incomplete pair; do
not rerun until favorable. Reuse the existing paired bootstrap statistic with
10,000 resamples and 95% confidence, labeled as this Native selection comparison.
Measure complete preparation-through-process-exit cycles as well as physical
task, acquisition/identity/holding, cleanup and within-Run reuse intervals. Every
leg starts a new Native process and resident environment; OS-cache coldness is
not asserted. Also run the existing independent equivalent-obligations pair on
the calibrated path. The registered gate and its applicability are reported
separately from a before/after improvement.

Training/profile qualification are experiment preparation costs. Record them
and amortization explicitly; do not claim the first request is faster by hiding
offline calibration. No favorable subinterval can substitute for whole-cycle
improvement. If the comparison is inconclusive or worse, record that result and
identify a next change rather than accepting another timing-only observation.

## Files and ownership

Changes stay in the Native benchmark profile, calibration, pair/admission and
timing scripts and their tests/documentation. Planned additional files are a
bounded one-case Native selection comparison runner and its assessment. Native
Owner, Ledger, cancellation, Model/Effect values, expression work and CI job
selection are unchanged. Relevant benchmark overlap should be reconciled at the
specific function, not by a second selector or Owner.

The new worktree borrows main's root and DuckDB adapter `node_modules` and pinned
`.toolchains`. Its Native probe is an owned byte-for-byte copy of #493's verified
release artifact, digest
`sha256:eb6ba72cab3d04a337bfa8573de9ba3bb702223e3931d392e86591a6ed7dde5f`.
Native compile inputs must remain unchanged from that source revision. Required
JS comparator modules will be built only for the selected consumer boundary.
No full Core, packed or performance matrix is needed for this one-case unit.

The larger Native/Broad public acceptance, physical-memory bounds and #412's
actual isolated-image mutations/restoration/final-consumer acceptance remain
separate. Observation or profile admission alone does not complete #170.

## First measured result: improvement not established

The clean experiment revision was
`957fa714d8d4f571621bf83b61b36a5c7ebd46ba`. Its Native compilation inputs were
unchanged from #493's fixed source above; the owned copied binary retains that
compiled-source identity and digest, rather than claiming a new Native build.
Seven imported JS release modules were built at the experiment revision. The
combined release artifact digest was
`497ee70fd6b88a04977fa6e01340a19315a46c4c3747e08b232848461a483fb5`.

Three training rounds and the held-out choice completed. Actual measured rates
were Local `[2,2,2]`, fresh DuckDB `[17,55,16]`, and resident `[4,3,7]` ms;
resident preparation/cleanup were `10/2` ms and measured producer imports
`[2,2,Unknown,Unknown]` ms. The ordinary planner chose Local for all three tasks.
The existing calibrated direct-pair smoke passed. All seven measured pairs
passed independent equivalent-obligation admission and the unchanged applicable
small-case warm/cold comparator gates. Before/after observed physical attempts
were five/three; the retained Owner admission still checks the environment/import
correspondence, holding and exact release. No final attempt-equality assertion
was simply removed.

| Boundary (after minus before) | Mean difference | 95% paired interval | Result |
| --- | ---: | ---: | --- |
| Preparation through child exit | +0.209 ms | -20.784 to +34.946 ms | Indeterminate |
| Cycle including profile qualification | +20.033 ms | -3.931 to +56.222 ms | Indeterminate |
| Physical execution | -14.060 ms | -23.859 to +1.213 ms | Indeterminate |
| Within-Run warm interval | -14.400 ms | -16.310 to -12.289 ms | Pass for this interval only |
| Physical cleanup | -2.077 ms | -2.760 to -1.450 ms | Pass for this interval only |

Profile qualification averaged `19.824` ms per calibrated pair. Offline
calibration plus initial qualification took `16,332.922` ms; no break-even count
is reported because whole-cycle improvement was not established. One after leg
took `193.715` ms versus `78.401–108.281` ms in the other six. That sample remains
included; these observations do not establish its cause or justify dropping it.
The seven-pair campaign is not repeated to obtain a favorable interval.

The next investigation is the repeated full-profile qualification and the
preparation/process interval outside task execution. Any change must preserve
the original observations and exact revision/binary/fixture binding. An admitted
input must not become a caller-declared success or permit changed bytes to reuse
an earlier admission. A matched comparison after a concrete change remains
required. Faster warm execution alone does not complete the performance task.

Local evidence (not GitHub CI):

- Selected JS build: `_build/local-checks/attempts/run-oSWnn0`.
- Calibration: `run-avFwsZ`; raw `_build/repro/calibration-957fa714d.json`,
  `sha256:77551a1775d3b2d34d135eb1c36dd23f2c3fa044da495708662e58e3d8aa119c`.
- Calibrated smoke: `run-qLnM0j`.
- Seven-pair comparison: `run-weaYID`; raw
  `_build/repro/comparison-957fa714d.json`,
  `sha256:52d5c4a5517591dd3ea20c47f3c6e8953395b226f5f72d687b4e414f977758cc`.
- `_build/repro/artifacts-957fa714d.json` binds commands, receipts, compiled
  source, experiment revision and artifact digests. These remain evidence for
  the experiment revision, including after this documentation is committed.

No full Core, packed, cross-target or performance matrix was run. The earlier
Draft push's automatic CI stopped before its selector could execute because of
GitHub payments/spending-limit failure; it is neither runtime acceptance nor a
product failure. The PR remains Draft and performance improvement remains open.
