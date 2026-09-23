# Performance and placement-policy review response

The external review was fixed at `e4029354d452732d6c205fd6132ca54d74019248`.
It distinguishes implementation defects, scale limits, and unfinished acceptance
evidence. This response tracks those findings against this branch; none of the
items below is declared complete merely because a diagnostic test passes.
The reviewed `01-performance-policy.md` is incorporated here as a fixed-revision
review, not as a current-source audit. Its PERF-1 acceptance requirement is
adopted without reducing the registered matrix or thresholds. PERF-2 remains
an operational scale question after the bounded-frontier implementation, and
PERF-3 still needs final-revision Linux CI after the native policy adapter.

| Review item | Current result | Required closure |
| --- | --- | --- |
| PERF-1: formal 27-case acceptance | Open. The registered experiment remains `preregistered-not-measured`. The 27-case smoke and seven small diagnostic pairs are not acceptance samples. | Fix one clean revision and its release build, run all four comparators with at least seven alternating pairs per eligible case, preserve every failed case, verify obligations, holdings and cleanup, then apply the preregistered confidence and timing gates. The nine capacity-infeasible baseline cases have no baseline ratio but still require retained and equivalent-comparator results. |
| PERF-2: candidate cross-product | The adaptive Host now uses a bounded frontier when the complete product exceeds `max_strategies`; explicit exhaustive search still fails closed. Partial-search provenance is bound into the candidate CID, selection history and explain. Three-target regressions cover 1/2/5 ceilings, one/two/five offers on a seven-task Carrier graph, a late fifth-offer feasible assignment, and all sampled assignments infeasible. A 20-compute-task standard Host fixture with installed Local/DuckDB contributions and two offers per task now passes on JS, Wasm and native, selecting from a bounded 64 rather than the full 1,048,576 combinations. Three fixed-revision release JS process diagnostics record its full fixture interval and process RSS. | Profile an operational workload with calibrated provider estimates, attributed planner memory and a declared deployment budget. The current test-bundle process RSS and fixture interval are not planner-only measurements or operational acceptance. Partial search must never be described as globally optimal. |
| PERF-3: remote policy contract | The portable standard DuckDB/Local Host exposes an exact pending decision before task dispatch. The native Host now uses its existing mTLS HTTPS client, a configured endpoint-to-policy identity mapping, a required metadata-disclosure callback, bounded request/response bodies and a durable monotonic clock. The same consultation survives a lost response; common admission rejects foreign identity, expiry and replay. The supported native Host configuration is documented in `docs/design/placement-policy-wire.md`. At the current source revision the real native mTLS fixture passed (553/553 query-integration tests), along with docs, format and JS/Wasm/native checks. | The native adapter is locally verified; the final branch SHA still needs its Linux CI result. Other environments need their own physical adapters, and this native implementation does not imply a Cloud deployment. |

The common Host now records the same per-task elapsed interval for Local and
DuckDB. These measurements can inform an estimate model; they are neither
calibration evidence by themselves nor proof of the small-case timing gate.
Cost estimates, enforceable capacity and policy preferences remain separate.

The native policy check used `ACTQL_TEST_SCRATCH_ROOT` pointing to a writable
workspace scratch directory with `node scripts/test-native-http-client.mjs`.
The real mTLS fixture covered success, lost response, foreign policy identity,
expiry and denied disclosure; its query-integration run passed 553/553.

The registered equivalent-obligations case-level assessor now rejects missing
or mixed-revision pairs, changed registered fixture/Program/source provenance,
unconfirmed release and diagnostic-only product selection. It applies the
registered small or large timing limit only after those checks. The seven
existing small-case pairs are correctly incomplete at this boundary because
their retained leg uses the example's uncalibrated estimate. This does not
close PERF-1: qualified execution and the other comparator/matrix gates remain.
The 27-case equivalent-comparator aggregator now rejects missing, duplicate,
foreign and mixed-revision records and prints each case's paired interval and
gate result. It is still only one comparator; no raw formal samples have been
admitted from the current product path.

The registered narrow-100 Program also runs through a Node-free native Host
probe with real DuckDB acquisition and an independently checked final CID.
This isolates the JS process setup cost but still lacks independent holding,
a fresh consumer and a matched comparator; it supplies no PERF-1 sample.
When parameterized with registered larger cases, the native materialized path
rejects some cases before dispatch under the fixed 1 GiB retention ceiling.
This path needs managed bounded holding for native acceptance; raising the
registered ceiling is not a valid substitute.

A later full registered Node managed Host readiness run verified 27/27 case IDs
with real DuckDB, independent file holding, consumers and release. It took 306.5
seconds as a single diagnostic suite and is recorded in
`benchmarks/retained-results/diagnostic-2026-09-24.md`. This establishes matrix
readiness on that path, not the paired timing acceptance or Node-free native
equivalence.

At clean revision `a7dfa0b9c`, the independent equivalent-obligations
comparator also completed all 27 registered cases in separate fresh children.
Its raw summary and scope are recorded in
`benchmarks/retained-results/equivalent-readiness-2026-09-24.md`. This removes
an execution-readiness uncertainty for that comparator; it does not admit
cross-revision ratios or replace same-revision alternating pairs.

A separate candidate-training diagnostic now measures both installed Local and
DuckDB task realizations, confirms final identity and release, and feeds their
measured median task intervals into a distinct ordinary selection. For two
100-row cases the Host selected resident DuckDB throughout. The observations,
scope and remaining Local accounting gap are recorded in
`benchmarks/retained-results/calibration-diagnostic-2026-09-24.md`. Training
used the same case and database as the later choice, so it is not independent
held-out calibration and supplies no formal PERF-1 sample.
The runner now also supports a distinct registered row-count case and source
file for its ordinary choice. A 100-row training case followed by a 1,000-row
evaluation case completed with independent identity and release checks at
`fafb2517a`; see `benchmarks/retained-results/calibration-diagnostic-2026-09-24.md`.
This removes same-case reuse from that diagnostic, while the Local work
breakdown and formal sample qualification remain open.

Seven alternating pairs at clean revision `c93402ffb` confirmed a substantial
small-case timing gap on the current Node managed Host: median retained-minus-
equivalent warm and cold intervals were 31.700 ms and 729.792 ms. The retained
leg was still unqualified because its selection used an example estimate.
One later resident-placement diagnostic at `2a1f8a3a0` still measured 27.005 ms
warm and 703.239 ms fresh-process for the same registered narrow-100 case.
The example prepared the Program in both parent and child; resident input
identity reuse did not waive the new filter's consumer demand. The exact raw
record and phase breakdown are in
`benchmarks/retained-results/diagnostic-2026-09-24.md`. This remains diagnostic
and does not establish a confidence interval or a qualified selection.
The native materialized path separately rejected a registered 100,000-row
numeric-64 case before dispatch under its 1 GiB retention ceiling. The raw
records and exact scope are in the same diagnostic document. These failures
make startup/coordination and native bounded holding implementation work, not
mere missing measurement paperwork.

Review regressions to add before closing PERF-1: missing pair, missing case,
changed Program or implementation hash, unconfirmed cleanup, and a baseline
capacity exception incorrectly converted into a finite speed ratio.

At clean revision `4d8da8dec`, a distinct 100-row training case produced a
verified estimate profile for the registered 1,000-row evaluation case. One
fresh-child alternating retained/equivalent pair then completed with the real
DuckDB Store path. The independent assembly now records all three Compute
attempts while keeping one bounded shared database capacity; it matched the
product's seven total attempt admissions, logical guard and comparison charges,
acquisition metadata, final identity, and terminal release. The raw training
and pair records are in the workspace scratch directories
`actql-retained-calibration-pspM3F` and
`matched-calibrated-4d8da8dec.json`.

The pair's `acceptanceEligible: true` means its *equivalent-obligation
admission* succeeded. Both child legs still report `acceptanceEligible: false`,
and the registered series assessor rejects the retained leg as an unqualified
product timing sample. This run is one diagnostic pair, not seven alternating
pairs, and says nothing about the other 26 cases or the other comparators.
PERF-1 therefore remains open at the reviewed priority.
