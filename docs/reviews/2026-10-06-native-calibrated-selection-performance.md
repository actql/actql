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


### Fixed-source results and remaining qualification

Experiment source: `fe0b68242d9e240494e85ecb0438f74f55855c88` (clean).
Native release: 12,405,024 bytes,
`sha256:2152155cc13ae8003df3c8b46a13ae45edf4a567554d579a440332475dd18f80`.
Selected JS release modules:
`0d92ea84a7ce4fe4a03c1d87aa5e82b574893e84dc032efd28703a829765fe4a`.
Only SHA-256 implementation and its whitebox tests differ in `src/` from the
archived original. No Owner, work/capacity ceiling or semantic input changes.

All 42 Native executions passed full existing product/Owner admission. Every
actual plan selected three resident tasks, and both sides agreed on candidates,
assessments/explanations, task usage, holdings, acquisition evidence and final
ledger usage. Common source preparation was `200.595 ms`, reported separately.

| Boundary, after minus before | Mean | 95% paired interval | Observed result |
| --- | ---: | ---: | --- |
| Parent cycle including files, binary hash and admission | -10.418 ms | -28.959 to -0.667 ms | Reduction in this series |
| Native probe entry through final result identity | -1.225 ms | -2.259 to -0.378 ms | Reduction in this series |
| Application preparation | -0.578 ms | -1.449 to -0.048 ms | Reduction in this series |
| Within-Run task intervals | -0.362 ms | -0.908 to +0.101 ms | Indeterminate |
| Compute through result identity | -0.452 ms | -1.073 to +0.075 ms | Indeterminate |
| Physical cleanup | -0.025 ms | -0.065 to +0.016 ms | Indeterminate |

The first parent cycles were `601.712` and `411.192 ms`, while their Native
entry-to-result clocks were `35.164` and `31.222 ms`. That gap is observed;
whether Node first-use, OS/image initialization or scheduling caused it is not
established. A later original-binary application interval was also `14.601 ms`.
Neither sample is removed. The median parent-cycle difference was `-0.961 ms`;
this is descriptive, not a replacement primary statistic. The mean reduction
is not attributed exclusively to ASCII absorption and is not a universal or
first-request speedup. The original raw `improvement=true` reports its timing
criterion only; the controller now names that flag `observedCycleReduction`.
A matched comparison that resolves the first-use boundary remains required
before closing the runtime-performance task.

Separate acceptance at the same experiment source passed:

- New measured profile: 12 forced training/mixed executions and held-out
  ordinary selection. Local rates `[1,1,1]`, fresh `[5,5,6]`; resident task
  rates `[2,2,2]`, preparation 4 ms, cleanup 1 ms, known imports 1 ms.
  Unknown imports remain unknown. Ordinary held-out selection was three Local
  tasks; this is distinct from the fixed resident timing experiment.
- Existing calibrated release-pair entry succeeded. Seven independent-
  obligation pairs passed the original gates: warm overhead mean `-1.864 ms`,
  upper `-1.481 ms` against 10 ms; cold overhead mean `-80.298 ms`, upper
  `-76.388 ms` against 100 ms. No threshold changed.
- Node Native/Broad acquisition with equivalent residual output and existing
  process-request cancellation: 2/2. This cancellation includes real stop/exit
  and retained completion; it is not public Run `Cancelled` certification.
- Native 100-row resident/fresh/Local choices, cheaper attempt-cap refusal,
  retained holding and task-between close: 1/1 (five settings). The close case
  remains `stopped-between-tasks`, not formal cancellation.
- Before commit, implementation-matching SHA-256 tests passed 14/14 on JS and
  14/14 Native; hash/ASCII/fragment-integrity consumers passed 6/6; statistical
  checks passed 7/7. These receipts are working-diff checks, not new-SHA runs.

Commands, exact artifact/input digests and receipts are recorded in
`_build/repro/artifacts-fe0b68242.json`. The original comparison is
`_build/repro/ascii-word-comparison-fe0b68242.json`,
`sha256:227a843d8982834fe182f9f6f0ea788f7d288448461301aa2f8f69d66bf8b228`;
calibration is `calibration-fe0b68242.json`,
`sha256:54db092ae8c50efb32ea075ea1892a33290ec072833f8451440be6426782d1ee`;
original gate is `equivalent-series-fe0b68242.json`,
`sha256:a0a8e753d3158fa28fdf602872ac9dee8a4f2754e1615911882c7df971d7e4a4`.
Separate descriptive analysis does not rewrite these originals.

Successful bounded receipts: Native build `run-JGfPyu`, selected JS build
`run-MQhAsr`, comparison `run-QYvBmf`, calibration `run-qt3ahF`, existing
release/gate and Node checks `run-7tptrb`, Native owner `run-CskUP2`.
Initial test-helper visibility failure `run-bupelz` and a rejected nested-guard
invocation `run-vYknlI` are retained and excluded from success counts.
No full Core, Wasm, packed acceptance or performance matrix was run. #412's
isolated-image acceptance and unproved physical capacity remain separate.
The final report commit changes classification/documentation only; the actual
compiled and measured source remains the experiment revision above.

### Matched launch condition, fixed before measurement

Use the same archived and new binaries and existing 100-row input, actual
resident plan, admission and limits. Run exactly one full admitted prelaunch
per binary, then 21 alternating measured pairs. Preserve both prelaunches with
their full files/hash/process/admission costs separately from the pairs; do not
discard an observed measured pair or replace the original series. Both binary
images already have prior use. This condition addresses repeated launches, not
an OS-cache-cold or first-request claim and not an explanation of the original
external startup delay. The controller binds the new binary to its actual
compiled `fe0b68242` source and digest and checks current runtime bytes are
unchanged; a controller/report revision is recorded independently.

No new build or broad acceptance is required for the unchanged binary. Use the
existing bounded local guard for this one fixed case. Primary assessment remains
the complete parent cycle; probe preparation, entry-to-result, task and cleanup
clocks remain separate. Retain an indeterminate result rather than rerunning
until a favorable interval appears.

Matched-condition result, controller revision
`c619179b8b2297943574ce527e2d9524c121159d`, compiled source still `fe0b68242`:
all 44 product/Owner admissions succeeded. Common source preparation was
`236.924 ms`. Prelaunch complete parent cycles were `61.453 / 51.761 ms`, with
Native process intervals `45.962 / 41.840 ms` and entry-through-result clocks
`36.476 / 32.417 ms`; these costs remain separate from the measured series.

| Boundary, after minus before | Mean | 95% paired interval | Result |
| --- | ---: | ---: | --- |
| Complete parent cycle | -0.523 ms | -3.480 to +2.894 ms | Indeterminate |
| Native entry through result identity | -0.289 ms | -1.389 to +0.747 ms | Indeterminate |
| Application preparation | +0.013 ms | -0.364 to +0.324 ms | Indeterminate |
| Within-Run task intervals | -0.262 ms | -0.685 to +0.193 ms | Indeterminate |
| Compute through result identity | -0.465 ms | -1.124 to +0.254 ms | Indeterminate |
| Physical cleanup | -0.032 ms | -0.154 to +0.075 ms | Indeterminate |

This repeated-launch condition does not demonstrate the required runtime
improvement. It neither invalidates the original raw series nor explains its
external first-use gap. Do not rerun this condition until it becomes favorable,
report the first series alone as the algorithm's effect, or close #170 from
these observations. The next implementation needs a cause supported by the
actual Native application/Compute/identity boundaries; the portable JS CPU
profile alone is insufficient.

Bounded receipt: `run-GdRh6O`; command:

```sh
node benchmarks/retained-results/run-native-ascii-word-comparison.mjs \
  _build/repro/native-probe-f8c687638.exe \
  /private/tmp/g507-native-ascii-matched-c619179b8.json --matched-first-use
```

Run inside the existing `runLocalCheck` guard with a 120-second budget. Preserved
original: `_build/repro/ascii-matched-c619179b8.json`, 13,073,809 bytes,
`sha256:6bdf7fdc327f323d08fa61a7c53a66529e52ed1422e36636d1f27b8bea7f908c`.
No rebuild, full matrix, new broad verification or CI retry was performed for
this unchanged compiled binary.

### Actual Native preparation diagnosis and next candidate

At `6a12f318d05b26a62393fdb6f78c395b00820100`, temporarily instrument the
existing application builder and prelude, with no API, Owner, normalization,
limit or admission change. Five fixed 100-row Native products all passed the
existing full product/Owner admission. Program checking took `6.274 ms` on the
first launch and `1.977–2.087 ms` on the other four; the four generated stages
were another roughly `2–3 ms`. Prelude intervals are nested in application
intervals and are not added together. Timing buffers/prints perturb execution;
this diagnosis does not measure a speedup or certify capacity.

All four source files and the normal release binary were restored to their
original bytes. Protected reproduction directory:
`_build/repro/application-phase-6a12f318d/`, containing original/diagnostic
sources, patch, controller, manifest, binary and full observations. Diagnostic
binary digest: `6a236e13d0818b1cfb6898ebe4d4ebe7620b4c6dc8049f7291910f6d9382b65f`;
observation digest: `14c9a93a874fff8dc737eb17027d00c3f181a9e496ebf22debb4f22244c7ae8c`.
Incremental selected Native build: `run-twVHsd` (six tasks); bounded observation:
`run-kLS72x`. These are diagnostic working-diff artifacts, not clean HEAD builds.

The next candidate is `canonical_json.advance_emit`: keep a container's
existing continuation on the stack until it ends, rather than pop/recreate its
enum wrapper for every child. All child visits, key/node/container-end
scheduling, limits, output bytes and cancellation remain; no cached digest,
rendered text or new retained data is added. The existing nested cursor fixture
pins all 17 advances and still checks one-node maximum progress and cancel.
Working-diff checks: selected cursor/raw-string/value-budget/depth/integrity
JS files `19/19` (`run-PL1pPN`, `focused-test-I99YGy`), and selected Native
cursor/raw-string/fragment integrity `6/6` (`run-X4TLjE`, `focused-test-DSYYfD`).
These preserve contract evidence; performance is unmeasured at this point.

Before measurement, fix the same 21 alternating 100-row resident pairs and one
fully admitted prelaunch per binary. Compare the unchanged release compiled at
`fe0b68242` with the new clean-source release; only canonical emitter and its
cursor fixture may differ in `src/`. Extend the existing controller as
`run-native-preparation-comparison.mjs --retained-continuation`, keeping full
hash/files/process/admission costs, source and both prelaunch costs, actual
planner/Owner correspondence and all phase intervals. This isolates the emitter
candidate from the earlier ASCII change. Preserve indeterminate results and
the original separate gate thresholds; do not rerun to find a favorable result.

The continuation experiment completed at clean
`09b003893564cd01d4ff36ae4a6b2302839bd852`. Native binary: 12,405,216 bytes,
`sha256:c60bcc58aa831f91167fe06246ae3c13e7e5e538e05d21a34ada84165a4c2543`.
All 44 admissions succeeded, but the primary complete-parent difference was
`+1.754 ms`, 95% `[+0.300, +4.003]`: it failed the reduction criterion. Native
entry-through-result difference was `+0.083 ms`, `[-0.322, +0.593]`; application
preparation `-0.112 ms`, `[-0.306, +0.079]`; task, Compute/identity and cleanup
differences were also indeterminate. Do not infer an internal algorithm
regression from the external-time difference or advertise a preparation gain.

Common source preparation was `146.905 ms`. Full prelaunch parent cycles were
`561.977 / 427.592 ms`, Native process intervals `521.792 / 417.945 ms`, compared
with entry-through-result clocks `40.782 / 31.417 ms`. These large external
gaps recurred even for previously used binaries, so calling the cause simply
the first-ever image use would be unsupported. Costs and raw observations are
preserved, not folded into a favorable subset.

The candidate is **not adopted**: restore both canonical emitter/cursor files
to the `fe0b68242` bytes and restore the normal release binary with its verified
`2152155c…` digest. The experiment commit, full binary, measurements and controller
remain reproducible; no production value/emitter boundary change remains from
this candidate. Working-diff semantic checks are evidence for the tested
candidate, not a claim of current-HEAD execution. No extra calibration/full gate
was run for a rejected performance candidate.

Receipts: selected release `run-RDptSZ` (79 dependency tasks), statistical check
`7/7` (`run-XYpJNv`, `focused-test-Si6WUo`), paired comparison `run-JX5d0r`.
Original: `_build/repro/continuation-comparison-09b003893.json`, 13,074,279 bytes,
`sha256:7a85bd2bc2574b64915515e9dad2765261aced9ef89cdfb017840cdd2df3ff55`.
Source/binary/command manifest: `_build/repro/artifacts-09b003893.json`.
The runtime-performance objective remains unmet. Do not repeat the same test
until favorable; use these Native boundaries to choose the next cause or a
justified larger existing case, keeping the same comparison obligations.

## Retained-output scaling diagnostic and fixed comparison

At clean controller revision `638c89d4f56c4a6fe844234ba2512ad3a3484b08`,
reuse the already compiled `fe0b68242` release, not a retagged HEAD build.
The existing 1,000-row narrow training observations confirm that the selective
fixture still retains only two rows: its Local Compute/identity interval is
2.120--2.250 ms and fresh DuckDB 14.204--16.251 ms. Those forced training legs
cannot establish a runtime improvement. No training campaign was repeated.

One existing `retainedCase` at
`retained-large-output-downstream-reuse/text-1024/1000` exposes the larger
retention/identity workload while preserving every fixture limit. This size
belongs to the fixture domain, but is outside the registered 27-case acceptance
matrix. It is a selected diagnostic, not new matrix qualification.

The initial controller incorrectly supplied Local rates when the existing
cumulative text contract makes Local ineligible; Native refused before execution
(`incomplete task estimate profile`, `run-IotZZR`). Remove that invalid control
input without changing eligibility or budgets. The corrected single invocation
(`run-0EV8eL`) admits three 1,000-row holdings of 1,047,891 bytes each, five
physical attempts (three Computes, one environment, one import), and zero final
holding/reservations. Native entry-through-result is 162.199 ms, including
32.935 ms acquisition and 110.203 ms Compute/identity; the final output read and
identity interval occupies approximately 29.592 ms of that enclosing interval.
Resident setup is 3.641 ms and import 6.647 ms. These nested intervals must not
be added to their enclosing timers. Source preparation is 178.657 ms, complete
parent execution/admission 187.416 ms, and independent product admission 9.126 ms.
A single invocation is not a performance estimate or CPU attribution.

Preserve the failed input and corrected observation/controller in
`_build/repro/retained-text-638c89d4/`, including its byte/digest manifest.

Before measuring, fix one fully admitted prelaunch per binary and 21 alternating
pairs for this exact retained-text fixture. Use the existing comparison entry
with `--retained-text-1000`, archived `f8c687638` before and `fe0b68242` after
binaries, unchanged ASCII-runtime source difference, full binary hashes, one
immutable source, and actual planner/Owner/usage/holding correspondence. Local
receives no offer estimate in either leg because it is ineligible. Both fresh
and resident costs remain the same explicit controls, not calibrated estimates.
Retain source preparation, prelaunch costs, complete parent intervals, application,
Compute/identity, sequential task and cleanup intervals. Decide the primary
complete-parent reduction using the same paired arithmetic mean and 95% interval
with threshold zero. Keep every observation; do not extend the sample count or
retry the experiment to obtain a favorable result. The earlier 100-row ASCII
result remains indeterminate; this separate workload cannot replace that result
or authorize a general speedup claim.

The fixed experiment completed at
`ec69977dd2b92356283912fdda654ebe1137f625` (`run-XbXiAw`). Both prelaunches
and all 42 measured full product/Owner admissions succeeded. Binary builds
remain the archived `f8c687638` and `fe0b68242`; `ec69977dd` identifies only
the clean controller/source correspondence, not a newly compiled runtime.

| After minus before | Mean difference (ms) | 95% interval (ms) | Result |
| --- | ---: | ---: | --- |
| Complete parent cycle | +0.042 | [-7.607, +7.485] | Indeterminate |
| Native entry through result | +1.064 | [-6.090, +8.067] | Indeterminate |
| Application preparation | -0.036 | [-0.198, +0.135] | Indeterminate |
| Compute/identity | +1.247 | [-5.301, +7.524] | Indeterminate |
| Sequential task intervals | +2.001 | [-3.644, +7.715] | Indeterminate |
| Cleanup | -0.264 | [-0.586, -0.018] | Lower observed interval only |

The cleanup difference does not satisfy the primary performance criterion or
establish attribution to hashing. Runtime improvement remains **unmet** for
this workload too. Do not repeat or enlarge this fixed experiment. Retain all
observations and the two prelaunch costs in
`_build/repro/retained-text-comparison-ec69977dd.json`, with source/binary/timing
identities in the companion `-manifest.json`. This finite diagnostic also does
not prove a physical heap upper bound. The next causal boundary to separate is
the final output read versus identity construction inside the approximately
30 ms interval observed by the one-case diagnostic; no value/identity check is
removed on the basis of a timing.

## Actual output conversion attribution and preflight candidate

At base `fda2dd7efac22c7d30b8c666783b32f7d6df5f95`, temporarily add clocks
around the existing Native final read and subsequent ordered-row identity.
One full retained-text diagnostic admitted all three holdings and five attempts,
with zero final reservations (`run-yy67Bn`). Conversion took **23.935 ms**,
subsequent identity **4.629 ms**. These are operation intervals, not CPU samples
or a before/after speedup. Source preparation was 188.242 ms, complete parent
cycle 683.695 ms, Native entry-through-result 175.500 ms, and independent parent
admission 9.186 ms; the external gap is retained without an inferred cause.

The selected incremental Native build (`run-wh893L`, 79 dependency tasks)
created a temporary working-diff binary, 12,405,168 bytes,
`sha256:0f4824f03af37582f58f70e093b57accaa86c1ea976ca4d8c4822929143659ca`.
Original/diagnostic sources, patch, controller, binary and observation remain in
`_build/repro/output-phase-fda2dd7ef/`. The original CLI source was restored by
byte comparison and the usual release binary restored to `2152155c...`.
The observation is 175,985 bytes,
`sha256:37bf5b63abb1130053048cb1ff96c6c60e72aef593a550e550694c45b807664a`.
No diagnostic clock/API/Owner change is delivered.

Generated Native C shows that `preflight_retained_row` calls `Iter.next` per
Unicode scalar. This is a confirmed execution mechanism, not proof that the
whole conversion interval belongs to it. Replace that private shape predicate
with direct UTF-16-unit traversal. The only recognized delimiters are ASCII,
and UTF-8 validation still precedes it. The two units of a supplementary scalar
cannot introduce an ASCII delimiter; outside quoted strings they remain one
literal token, and inside strings they cannot alter shape/node counting. Keep
all depth/node ceilings, following JSON syntax and typed/value admission, hashing,
exact completion/occurrence binding, holding and cleanup. No normalization,
digest cache, expression work/quantum, public API or allocation owner changes.

Working-diff selected decoder and completed-import files passed **11/11 JS**
(`run-r3MHzt`, `focused-test-gMRVYs`) and **11/11 Native** (`run-KGF51E`,
`focused-test-B2KCNY`). New boundary expectations independently pin node counts
for supplementary strings/keys, quoted delimiters and nesting, and confirm that
non-JSON Unicode literals/escapes still reach JSON rejection. Existing raw-value,
exact owner/CID, shape/parse/value limits and closed conversion regressions remain.
These are semantic/consumer checks, not evidence of a performance improvement.

The fixed timing method for this candidate is one admitted prelaunch per binary
plus 21 alternating retained-text pairs, with archived `fe0b68242` as before
and the clean candidate release as after. Only the decoder and its fixture may
differ in runtime source. Use the same existing product/Owner checks, immutable
source, limits, fixed fresh/resident controls and primary complete-parent
zero-threshold criterion. Include all phases and prelaunch costs. Do not extend
the sample count or repeat the experiment until favorable. The earlier ASCII
and continuation results remain separately unchanged.

### Fixed preflight comparison: improvement not demonstrated

Candidate release source `9c74a5b6686ebb87fa7726ed763eeda447541846` built
with the pinned MoonBit toolchain (`run-9tM7wW`, 27 incremental tasks):
12,404,208 bytes,
`sha256:0bcb9cf3cb82a7d4ce1abde7c493c7bef02f7cedb8528bdbab1e43f04571b347`.
The before release remains `fe0b68242d9e240494e85ecb0438f74f55855c88`,
`sha256:2152155cc13ae8003df3c8b46a13ae45edf4a567554d579a440332475dd18f80`.
The clean controller revision is
`d8009c2bb1ae4365d5ca5b5b8b2ad7c70b4a8b1b`; it does not retag either build.

Reproduction at that recorded source, through the existing bounded guard:

```sh
node benchmarks/retained-results/run-native-preparation-comparison.mjs \
  _build/repro/native-probe-fe0b68242.exe \
  /private/tmp/g-retained-preflight-d8009c2bb.json --retained-preflight
```

Both prelaunches and all 42 measured product/Owner admissions succeeded. Every
leg selected the same three resident tasks, with identical before/after
planner/attempt/holding/work facts and final zero reservations. The outer
`run-IOyN3J` **failed afterward**: the statistics helper did not yet register
`retained-preflight-iterator`. This is not reported as a successful runner.
Register that label without changing statistics, thresholds, confidence, seed
or samples; the existing statistics regression passes **7/7** (`run-Pei4nL`).
Analyze the original saved 21 pairs only. No Native process is rerun.

| After minus before | Mean difference (ms) | 95% interval (ms) | Result |
| --- | ---: | ---: | --- |
| Complete parent cycle | -4.346 | [-22.173, +9.964] | Indeterminate |
| Native entry through result | +1.303 | [-7.659, +10.642] | Indeterminate |
| Application preparation | -0.007 | [-1.396, +1.142] | Indeterminate |
| Compute/identity | +0.223 | [-6.792, +6.416] | Indeterminate |
| Sequential task intervals | -0.300 | [-5.829, +4.583] | Indeterminate |
| Cleanup | -0.475 | [-1.334, +0.079] | Indeterminate |

Source preparation is 232.424 ms separately. Prelaunch complete cycles were
233.149 / 552.861 ms, versus Native entry-through-result 191.639 / 159.958 ms;
retain these costs without inferring the external delay's cause. All samples
remain, including slower later intervals. The primary criterion is unmet.
Withdraw the two candidate decoder files by restoring exact `fe0b68242` bytes.
Restore the usual release binary to its archived before digest. No new
production decoder/Owner/value/quantum behavior is delivered on this result.

Keep the failed original unchanged at
`_build/repro/retained-preflight-d8009c2bb.json`, 6,910,213 bytes,
`sha256:71438203712e30dfd2b1293c19e2aeca68bba1ad9c52dc9384f26d5948f5e86e`.
The separate `-analysis.json` binds that digest and marks analysis-only, not
repeated execution. Candidate/before source bytes, original controller, patch
and exact artifact manifest remain in
`_build/repro/retained-preflight-9c74a5b66/`; the candidate binary is
`_build/repro/native-probe-9c74a5b66.exe`. Later helper/report changes do not
become new runtime evidence. The strict archived-source mode is retained for
reproduction, not rerun to obtain a favorable result.

Next causal boundary: separate shape scanning, JSON parsing, typed value
admission and completion identity within the real retained-output conversion.
Do not bypass any of these obligations based on the aggregate read interval.
Actual source/Owner checks, limits and public value preservation remain;
D/H/A boundaries, physical heap bounds, #412 image acceptance and dynamic
Hybrid remain outside this experiment. No full Core, Wasm, packed or whole
performance matrix was run.


### Real retained-conversion subphases and bounded text discard candidate

Starting source `1c9bccc54d373f64c27ea1c5a48c74e7044c1b95` contains the
restored preflight implementation. Two explicitly selected, temporary Native
clock diagnostics subdivide the retained conversion; neither is a matched
performance comparison. Preserve their original sources, instrumented sources,
patches, controllers, binaries and observations under
`_build/repro/conversion-phases-1c9bccc54/`. The manifest binds every source
before/after digest. All six instrumented files were restored byte-for-byte
before implementing the candidate below. No diagnostic clock or public clock
API is delivered. The initial diagnostic build failed because a temporary local
result required an explicit type (`run-3cgIQ9`); no product execution failed.

| Actual boundary (ms) | Diagnostic v1 | Diagnostic v2 |
| --- | ---: | ---: |
| Completed-output conversion | 25.034 | 26.198 |
| Following ordered-row identity | 4.508 | 5.047 |
| UTF-8 validation | 0.352 | 0.398 |
| JSON shape preflight | 1.980 | 2.088 |
| JSON parsing | 1.529 | 1.667 |
| Raw cursor | 0.766 | 0.886 |
| Typed value admission | 1.567 | 1.654 |
| Retention budget validation | 0.500 | 0.520 |
| Completion encoding/hash | 7.079 | 7.473 |

Each row subphase was observed 1,000 times. V2 separately measures actual Native
reader boundaries: 17 `next` calls (including existing complete-content hash)
total 3.322 ms, 17 frame-feed calls total 2.278 ms, import preparation 0.005,
frame preparation 0.008, reader open 0.028, frame finish 0.001, reader finish/close
0.005, and import finish/binding 0.009. The remaining 5.855 ms is unassigned;
static availability calls do not establish CPU attribution. None is bypassed.
Empty 1,000 clock-pair controls total 13.044 / 12.505 microseconds. This is not
measurement of the full instrumentation overhead, and is not subtracted.

V1 release: 12,406,240 bytes,
`sha256:8135dbc4e2ea1bfe13d16a0acb01b5b3684ba9c56d95721f41e79cbef6819779`,
build `run-YJ4hYY`, execution `run-9ev83O`; observation 177,576 bytes,
`sha256:9533a16b325a7f78a1ca2d1649e6413a9fe475d27484f0acbb551d794b47307f`.
V2 release: 12,406,896 bytes,
`sha256:48e7a25224a92e5101d45da2a8d4088e85d39bf42d3d4e5e328ac7df6208fcea`,
build `run-zquCu5`, execution `run-QycxNn`; observation 178,948 bytes,
`sha256:a69bf6dc85d9d31de43bbbaa8592ef2c2542dc443cc2e28c67667a9870b5e01f`.
Both single-case executions use the existing immutable 1,000-row text fixture,
select three actual resident candidates, verify all five physical attempts and
three holdings, unchanged values/identity/work and final zero reservations.
Keep full parent/source preparation/entry costs: v1 590.754 / 180.191 / 166.967 ms;
v2 621.889 / 196.832 / 176.016 ms. These are separate launches, not improvement
measurements or OS-cache-cold results.

`CompletedOutputImport` ignores each provisional serialized batch returned by
`drain_hash_output`. The new candidate uses the **same buffered hash sink** with
optional text retention disabled. It still emits every canonical byte into SHA,
reserves the same per-batch encoded byte budget, requires each drain before
completion, preserves aggregate node/depth/byte ceilings and closes on failure.
It does not replace that sink with the existing unbounded hash-only writer.
The existing public default still retains text; generated `encode_core` interface
adds the optional keyword. Verified-document embedding obeys the same mode.
No value normalization, cached digest, owner, availability, expression quantum,
Ledger cleanup or cancellation decision changes. An encoded byte counter is
not a proof of physical heap usage; resource/retention bounds are not weakened.

Focused working-diff checks: **26/26 JS** (`run-NPLmlI`,
`focused-test-cibDXe`) and **26/26 Native** (`run-RpQfnK`,
`focused-test-kelJwL`). Select exactly:

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 180 -- --target js \
  src/encode_core/buffered_hash_wbtest.mbt src/encode_core/ascii_span_wbtest.mbt \
  src/encode_core/string_cursor_wbtest.mbt src/encode_core/cancel_writer_wbtest.mbt \
  src/execution_relation/completed_output_import_wbtest.mbt \
  src/execution_relation/admitted_output_stream_wbtest.mbt
```

Repeat that selection with `--target native`, using the pinned MoonBit toolchain.
Selected `moon info src/encode_core --target js` succeeded (`run-bdqE5b`, three
tasks). An earlier guard invocation omitted its step argument list and launched
no compiler (`run-fgUtb5`); the corrected invocation above is the interface evidence.
Prior candidate checks caught a missed buffered-document consumer and an
incorrect test expectation that confused authored `[s,n]` projection with canonical
internal `[n,s]` cells. Fix those expectations using the existing schema contract;
no product projection/order rule changed. Independent new fixtures preserve a
literal Unicode/CRLF/quote/backslash hash, exact encoded batch cap at 16/17/18,
aggregate overflow across drains, undrained completion rejection, repeated cancel,
and completed-import row boundaries at 18/19/20 with exact names/cells/occurrence.

The candidate's performance remains **unverified**. Predeclare one admitted
prelaunch per binary and 21 alternating pairs on the same existing 1,000-row text
case, before archived `fe0b68242` and after the clean candidate release. Pin actual
compiled SHA/digest and the complete source difference. Preserve full parent,
entry, preparation, compute/identity, sequential task and cleanup intervals and
all source/prelaunch costs. Primary improvement requires the complete-parent
95% interval strictly below zero. Do not reroll indeterminate earlier candidates
or increase samples to obtain a favorable result. Wasm, full Core, packed,
calibrated whole matrix and new CI acceptance remain unexecuted.
