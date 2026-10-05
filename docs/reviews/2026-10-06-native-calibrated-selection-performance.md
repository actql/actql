# Native calibrated selection performance

Current conclusion: actual planner/Owner and independent acceptance are
connected; Native execution-performance improvement remains unestablished.
The source-open experiment below retains its inconclusive result. #507 stays
Draft and #170 is not complete.

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

Changes stay in the Native benchmark probe, profile, calibration, pair/admission
and timing scripts and their tests/documentation. The source-open experiment
changes the probe's acquisition configuration, not the production Owner. Native
Owner, Ledger, cancellation, Model/Effect values, expression work and CI job
selection are unchanged. Relevant benchmark overlap should be reconciled at the
specific function, not by a second selector or Owner.

The worktree borrows main's root and DuckDB adapter `node_modules` and pinned
`.toolchains`. Earlier experiments used an owned copy of #493's verified
release artifact, digest
`sha256:eb6ba72cab3d04a337bfa8573de9ba3bb702223e3931d392e86591a6ed7dde5f`.
Those experiments required unchanged Native compile inputs. The source-open
experiment below instead builds the selected Native probe and required JS
comparator modules at its own fixed source. The old Native binary remains at
`_build/repro/native-probe-7b48ed314.exe`.
No full Core, packed or performance matrix is needed for this one-case unit.

The larger Native/Broad public acceptance, physical-memory bounds and #412's
actual isolated-image mutations/restoration/final-consumer acceptance remain
separate. Observation or profile admission alone does not complete #170.

## Current-main source-open experiment: no improvement

Normal main integration `bbcb79e88fe3a356a61db2b0ce256e785f9fe777` retains
main parent `64046e37a1cadb2148edeab7cbf85b96d125b518` and all existing
declarations. Actual retained-history validation passed (`run-ibocV1`).
D/H/A's cancellation, values, Ledger and bounded-execution changes are not
duplicated.

Clean experiment source: `f8c6876389430490cdfd09c3e576d77c6d227d06`.
The selected Native release build (`run-ZiLwqt`) produced 12,405,152 bytes,
`sha256:18c389007dcdd78638895b9b3d6a88c36783a342c8a1667ffe8a8c849a5a9830`.
Seven required JS modules were rebuilt (`run-qNI2kG`), combined digest
`e779e2a5c747cc3f7d821adcf2bce9c38c15b0732ba6c9171c51f4d3725b4b88`.
The earlier Native build failed at the added mode-print expression; failed
`run-jdiE5v` is retained separately from the corrected successful build.

The immutable acquisition database previously opened read-write. The existing
`open_native_read_only_source_acquisition` establishes its read-only contract.
The probe now defaults to read-only and exposes the prior mode as an explicit
bounded comparison control. Capture still precedes source-connection close;
fresh/resident Compute databases and Owner/cleanup are unchanged. This aligns
the acquisition access mode, **not a demonstrated speedup** or public API change.

Calibration (`run-fq6iYK`): three training rounds plus held-out selection;
Local `[1,1,1]`, fresh `[6,5,5]`, resident `[2,1,2]` ms, preparation/cleanup
`4/1` ms, imports `[1,1,Unknown,Unknown]`. Ordinary selection was all Local.
Initial acquisition-open preparation is outside these matched Compute rates.

Seven fixed alternating pairs (`run-IxVmLs`) used one binary, qualified profile,
immutable source and unchanged limits. All fourteen legs passed independent
equivalent-obligation admission. Exact holdings, work, usage, attempt mapping,
intermediate reservations and actual candidate/choice/explanation observations
matched across controls. Both original applicable warm/cold comparator gates
passed. Source SHA-256:
`6f7a6da0ec42ac80a2aae1d086f953a8d378702e75985487ad56153e77e61ff1`.

| Read-only minus prior read-write | Mean | 95% paired interval |
| --- | ---: | ---: |
| Complete Native cycle plus qualification | +2.600 ms | -4.472 to +12.183 ms |
| Database-start to acquisition-start | +0.929 ms | -0.359 to +3.063 ms |
| Native execution through completion | +2.659 ms | -2.876 to +10.774 ms |
| Within-Run warm interval | +0.163 ms | -0.011 to +0.382 ms |
| Physical cleanup | -0.035 ms | -0.131 to +0.030 ms |
| Entire benchmark pair | -1.785 ms | -22.736 to +17.349 ms |

Every verdict is indeterminate. Source preparation: 173.181 ms; offline
calibration: 3,490.533 ms. Qualification/full-byte hashes/observation remain
charged. All samples, including the slower final after leg, remain included;
its cause is unestablished. Each process is new; OS-cache coldness is uncontrolled.

The existing calibrated release pair passed (`run-gw5Lkx`). Bounded Node-host
Native/Broad acceptance passed **1/1** via the official nonzero wrapper
(`run-S5WCtG`, `focused-test-PUslqC`). The earlier direct `test-execution.mjs`
helper invocation executed no tests and is excluded from acceptance. Changed
observation/statistical checks passed **27/27** on the precommit working diff
(`run-J34Rvf`); those blobs match the experiment source. No full Core, packed,
all-target or performance matrix was run.

Protected local originals:

- `_build/repro/calibration-f8c687638.json`: 2,483,571 bytes,
  `sha256:9731ea6fe95d9d434184e52058f7d866ae560d452a23e8e80daaf62b55b88a1f`.
- `_build/repro/source-open-comparison-f8c687638.json`: 2,933,344 bytes,
  `sha256:23a6c1e5c358fd8108b57cff6517dab298876125212719a1f1d586cd0f4b335a`.
- `_build/repro/artifacts-f8c687638.json` binds toolchain, commands, receipts,
  main/source/binary identities and preserved `native-probe-f8c687638.exe`.

Controllers: `native-resident-estimate-calibration.mjs <profile-output>` then
`run-native-source-open-comparison.mjs <profile> <comparison-output>`, through
the bounded local guard, from the fixed source. A different candidate needs
its own calibration; never retag the original profile. Documentation-only
integration does not justify a new campaign.

Next: separate actual file-read/UTF-8 assembly from portable contract admission
within application construction. The growing per-byte array in the existing
bounded reader is a candidate, not yet a measured Native root cause. Preserve
generation checks, reader finish/close, value bytes, work/quantum and limits.

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

## Follow-up: reduce evidence-processing cost without weakening identity

The CPU diagnostic re-admitted the unchanged recorded profile ten times; full
profile checks took about 7 ms initially and about 2 ms thereafter. This does not
establish current Native timing. The pair's qualification also hashes the 12 MB
Native binary. Seven fixed alternating hash-only diagnostics checked every byte
with 64 KiB and 1 MiB reads, retaining the same digest. The larger read size
reduced this diagnostic cost. The implementation now shares `sha256File` across
release modules and Native/source checks; it reads every byte on every call,
never caches a digest or accepts a caller-supplied hash. Only these two bounded
read sizes are available as experiment controls. Read size is not a parent or
child heap bound and does not change any ledger reservation.

At clean `a3b9680f290d19c03c3d116f1bdb87f1edfee795`, a new three-round
calibration and one seven-pair selection comparison again passed the unchanged
equivalent-obligation gate. The qualified Native-cycle difference was
`-1.659 ms`, 95% interval `[-7.932, +6.359]`: indeterminate. This is a selection
comparison, not an isolated before/after measurement of the read-size change.
It is retained rather than presented as successful Native improvement.

The causal control experiment at clean
`21b245869ce1844ae240e770441094a67735dd9b` therefore uses the same calibration,
binary, source, fixture, limits and actual planner selection on both sides.
Both sides select three Local tasks, re-admit actual Owner/holding observations,
and independently execute the equivalent-obligations comparator. The only
changed input is full-byte read size: 64 KiB before, 1 MiB after. Seven alternating
pairs were fixed before execution; no failed or unfavorable pair is omitted.
The original comparator order also alternates inside each before/after series.

| Boundary (after minus before) | Mean | 95% paired interval | Result |
| --- | ---: | ---: | --- |
| Entire benchmark pair, including evidence checks and independent execution | -32.281 ms | -57.525 to -13.343 ms | Evidence-processing improvement |
| Native prepare/execute/cleanup plus profile qualification | -2.481 ms | -6.832 to +0.741 ms | Indeterminate |
| Native probe entry through final result identity | -0.305 ms | -2.316 to +1.610 ms | Indeterminate |
| Within-Run warm interval | +0.415 ms | +0.074 to +0.757 ms | Slower in this sample |
| Native physical cleanup | +0.041 ms | -0.023 to +0.101 ms | Indeterminate |

Both seven-pair series passed independent obligation/Owner admission and their
unchanged applicable warm/cold gates. This is a measured reduction in benchmark
evidence-processing cost, not a Native query algorithm speedup or completion of
the performance task. Source preparation was `173.535 ms` shared by both series;
offline calibration was `3,013.768 ms`. Every leg starts fresh Native and Node
processes; OS cache coldness is uncontrolled. Nothing amortizes calibration into
a first-request claim. The earlier SHA's observations are not used as matched
timing samples for this SHA.

The next Native-runtime investigation is the observed startup/preparation
boundary. These labels mark starts, not completed operations: one actual after
leg spent about 6.2 ms between application-start and library-start (application
construction), 3.0 ms between library-start and database-start (library loading),
and 5.0 ms between database-start and acquisition-start (database initialization),
versus 2.2 ms from strategy-execute through completion. These are one leg's
boundary observations, not a demonstrated root cause or universal cost.
Inspect that existing preparation path before proposing a runtime change. Keep
D/H/A's correctness boundaries and the retained input/identity obligations.

Evidence remains local, with the unchanged Native binary compiled at #493's
fixed source and the same seven-module release digest recorded above:

- CPU/hash-only diagnostics: `run-6piWkN` / `run-IPS4bN`.
- At `a3b9680f2`: calibration `run-uOnMVA`; selection `run-JDmYRU`.
- At `21b245869`: calibration `run-tgZD0Z`; controlled comparison `run-hIVjpj`.
- Focused artifact/statistical/series checks: 10/10 on the precommit working
  diff, `run-aPWiE7`, focused `focused-test-kS8c7x`. The first added statistic
  assertion failed only from binary floating-point rounding and was corrected
  to the existing tests' `1e-12` precision; real thresholds were unchanged.
- `_build/repro/artifacts-21b245869.json` records commands and exact digests.
  Controlled calibration: `calibration-21b245869.json`,
  `sha256:b9737afdfae7d7b4694c3aa8273a86a884d0f18686370619f5c7bcc4b3dfb7f2`.
  Controlled comparison: `artifact-read-comparison-21b245869.json`,
  `sha256:2faef3ce2cd0dcd30fe15ff7a6eb9d84dcb1a7636c97599160080323b5afdb47`.

The subsequent documentation commit does not rerun or retag these observations.
Full Core, packed, other targets and a full matrix remain unexecuted. Draft and
unverified GitHub CI status remain separate from these bounded local results.


## Bounded ASCII-word experiment

The first two macOS `sample` attempts produced empty call graphs, including a
100-load diagnostic lasting about 647 ms inside application preparation. Their
successful sampler exit status is not CPU evidence. The original raw receipt is
preserved; a separate analysis corrects its initial `sampled` classification.
The temporary repeated-load probe source was restored byte-for-byte, and its
binary is kept separately from the original release artifact.

A 100-call JS profile of the same portable application builder recorded 1,386
samples at the unchanged `f8c687638` compiled source. Inclusive counts were 580
under Program checking and 416 under runtime-fragment preparation; these overlap
and are not additive. SHA-256 ASCII absorption and compression were observed as
self-time hotspots. This ranks an investigation, not a Native CPU attribution.
Raw profile: `_build/repro/portable-preparation-f8c687638.cpuprofile`,
`sha256:de536a501647e3b3581b527114839e107873e9f7c7b7a002c235a5a678eee59d`.

The implementation experiment changes only `sha256.update_ascii_range`: build a
word from four checked UTF-16 units without its four-iteration inner loop. A
combined high-bit check closes the state if any unit is non-ASCII. Every input
unit is still read, the same 64-byte block/schedule is retained, and length,
partial-block, finalization and invalid-range handling are unchanged. No digest
cache, new allocation, normalization rule, Owner or admission bypass is added.
Fragment regeneration and all value/CID integrity checks remain intact.

Before measurement, fix 21 alternating pairs of the existing 100-row/narrow
Native resident case. Compare the archived original release binary at
`f8c6876389430490cdfd09c3e576d77c6d227d06` with the new fixed-source release.
Use identical explicit control estimates (Local/fresh 1000 ms, resident default
1 ms) on both sides, not a relabeled measured cost profile. Require actual
resident selection, identical actual planner/Owner facts and holdings, the
independent fixture's expected identities, unchanged source bytes and confirmed
cleanup on every leg. Report application preparation, library/database,
acquisition, capture, Compute/result identity, task reuse, cleanup and complete
parent cycle separately; charge per-leg full-binary hashing and admission.
Source creation is common preparation and is reported separately. No phase-only
improvement establishes whole-cycle improvement. The existing calibrated
release/equivalent-obligation gate remains a separate current-source acceptance.

The `execution_us` clock starts at probe entry and includes application and
acquisition preparation through final identity. Earlier table labels calling it
physical execution were inaccurate; the raw observations are preserved and the
labels above are corrected. Actual enclosing/nested phases remain separate.
