# Retained result performance experiment

`experiment.json` preregisters comparators, sample sizes and acceptance criteria.
Its pinned `fixtures.mjs` defines 27 deterministic workload/layout/size cases,
ActQL Program text, source construction SQL, cardinalities, independent expected
result identities and explicit resource/timeout ceilings. This is not a record
of passing performance measurements.

`direct-path-registration.json` fixes the 21 large case IDs before direct-path
implementation. All remain mandatory, with normal cost-grounded selection and
admission; forced selection is conformance evidence only. Preparation costs are
included and preexisting resident state is a separate condition. The original
27-case functional and performance gates remain unchanged. The
[identity contract review](identity-contract-review.md) records the approved
separate tracks: preserve the existing contract and make logical CID conditional
in a new profile. The profile contract and a finite managed product path are now
registered; full profile conformance remains unfinished. The
[fixed-revision 27-case measurement](managed-profile-fixed-d14d5825.md) reports
that path separately. It does not authorize omission of an existing mandatory
CID or substitution of new-profile timings for this experiment's acceptance
evidence.

The approved [capacity comparison addendum](acceptance-addendum-2026-09-16.md)
preserves that registration and the 1 GiB ceiling. Nine capacity-impossible
baseline cases have no speed ratio; they do not exempt the new implementation
or the equivalent-obligations comparator from any of the 27 cases.
`comparison-eligibility.mjs` verifies the original registration and archived
capacity evidence before classifying a case. Its output is eligibility only,
never formal performance acceptance. Reported completions still require
semantic/resource verification and the registered paired timing assessment.

The equivalent-obligations comparator has a 27-case raw-pair aggregator. The
input is a JSON array of `{caseId, pairs}` records, where each `pairs` array is
the unmodified output of the matched-pair runner for that case. For a fixed
clean implementation revision, generate a readable per-case table with:

```sh
node benchmarks/retained-results/equivalent-matrix-report.mjs \
  /path/to/raw-equivalent-pairs.json FULL_40_CHARACTER_REVISION --markdown
```

The command exits nonzero for a missing, duplicate, foreign, mixed-revision,
unqualified, unreleased, failed or indeterminate case. It shows the registered
95% confidence interval and threshold for each admitted case. This checks one
mandatory comparator across all 27 cases; it does not measure the cases, attest
the build/toolchain, or certify the baseline and raw-direct comparisons. A
synthetic test of this aggregator is not a performance result.

```sh
node --test benchmarks/retained-results/comparison-eligibility.test.mjs benchmarks/retained-results/paired-assessment.test.mjs benchmarks/retained-results/baseline-feasibility.test.mjs
```

Development observations are recorded separately in
[2026-09-16 diagnostic observations](observations-2026-09-16.md). They include
failures and exclude unperformed comparisons; they are not acceptance results.
The later [2026-09-23 small-case diagnostic](diagnostic-2026-09-23.md) records
seven matched pairs and preparation-phase timings. It also does not satisfy the
registered performance gate.

The native case diagnostic loads the selected registered Program and data
profile, acquires from real DuckDB, executes through the native standard Host,
and checks the final CID against the independent fixture oracle:

```sh
moon build --target native --release src/cmd/native_retained_case_probe
node benchmarks/retained-results/native-case-probe.mjs \
  native-acquisition-full-validation-low-selectivity/narrow/100
```

Node prepares the fixture and launches the native binary; it is not used by the
running Host. The reported process interval is diagnostic. This path currently
lacks independent file holding, a fresh reader and equivalent comparator
obligations, so it cannot supply formal acceptance samples.

The correctness smoke checks run without importing the ActQL evaluator:

```sh
node --test benchmarks/retained-results/fixtures.test.mjs
node --test adapters/connectors/duckdb/node/test/benchmark-fixtures.test.mjs
node --test adapters/connectors/duckdb/node/test/benchmark-profile.test.mjs
node --test adapters/connectors/duckdb/node/test/benchmark-execution.test.mjs
```

The second command requires the pinned DuckDB Node dependency. It compares all
nine workload/layout shapes at 100 rows to real DuckDB. It verifies source
generation and expected values/cardinalities, not ActQL eligibility or speed.
The expectation encoder covers only these finite exact integers and ASCII
strings/keys; it is not a replacement for the common typed canonical encoder.

The profile test prepares every registered size through the public checker without
opening a source. The execution smoke uses the installed managed Host and real
DuckDB at 100, 1000 and 10000 rows across all nine shapes, checking independent logical
CIDs, process exit, surviving file holdings and explicit cleanup. These require
the pinned MoonBit toolchain; they are correctness tests, not timing samples.
Wide retained reuse also re-admits the same output in a fresh installed process
and binds its exact downstream port without reading the source again. It then
reads the retained bytes through shared Store access, with both admission and
consumer reads charged. This is input readmission and physical access, not
another Compute execution or Program continuation.
The smoke's cumulative transfer allowance covers acquisition plus the configured
per-task import/return envelopes; it is not a per-file byte ceiling.

Run the full preregistered size matrix explicitly (including one million narrow
rows and 100000-row wide layouts):

```sh
ACTQL_RETAINED_CASES=registered node --test adapters/connectors/duckdb/node/test/benchmark-execution.test.mjs
```

Both modes fail on an incomplete case and emit each attempted/verified/failed
case ID. Diagnostic elapsed time includes setup, optional readmission and
cleanup; it is not a performance sample or a substitute for the four comparators.
Successful case reports include per-task transport counters and nested phase
timings. INSERT time is part of each input interval; preparation and receiving
callbacks are parts of command time. Do not sum overlapping intervals. Counters
distinguish actual statement executions from SQL preparations, so preparation
reuse cannot be mistaken for fewer imported rows or shared transfer.
Each completed Host task also reports `taskElapsedMilliseconds`, measured from
the selected implementation's run call through its admitted completion. It
uses the same boundary for Local and DuckDB. The sum is a warm task interval;
it excludes candidate preparation and process startup and is not a cost-model
calibration by itself.
`controlTransport` separately reports the process channel's submitted and received
wire bytes as decimal strings. These include envelopes, configuration, accounting,
Store requests and completion metadata, not only result descriptors. Submitted
bytes count writes handed to the stream, not acknowledged delivery; received
bytes include invalid frames. Neither counter grants logical transfer budget or
proves that a payload contains no rows. Keep these separate from connector data
transport and from memory measurements. Failed requests rejected before encoding
do not count as submitted bytes.
`controlMemory` samples the controller's RSS, V8 heap, external and ArrayBuffer
usage every 20 ms around `host.run`, including its preparation, process startup,
execution and child exit. It excludes fixture source construction, independent
expected-value hashing, optional fresh-reader checks and final output release.
Only baseline, last and per-field observed maxima are retained, so the sampler's
own storage does not grow with runtime. These categories overlap and must not be
summed. Peaks between samples may be missed, and allocator retention is not a live
allocation count. Sampling failure yields `incomplete`, never a zero-memory pass.
There is no implicit memory acceptance threshold in this diagnostic. For scale
comparisons, run each exact case in a fresh controller and record its baseline;
the full-matrix process also includes prior-case module/allocator state. Source
fixture creation runs in a separate, awaited process before sampling so its
native allocation does not contaminate the controller baseline.
The registered run is a readiness gate, not performance sampling; the default
smoke does not prove the larger cases executable.
The [2026-09-24 full-matrix readiness diagnostic](diagnostic-2026-09-24.md)
records one successful 27/27 managed Host run. It remains outside formal paired
performance acceptance.
The [independent equivalent-comparator readiness run](equivalent-readiness-2026-09-24.md)
also completed 27/27 cases at a clean later revision. These separate runs do
not form paired measurements or prove obligation parity with the retained leg.

To compare ordinary and reused INSERTs through the actual bounded transport:

```sh
node adapters/connectors/duckdb/node/bench/session-import-probe.mjs
```

This separately reports setup-through-cleanup elapsed time, verifies identical
payloads and cumulative transport counters, and checks preparation counts. It
does not include MoonBit admission, logical guards, CID generation or independent
retention, and is not a replacement for the four-comparator experiment.

For diagnosis only, add `ACTQL_RETAINED_CASE` with one exact case ID from the
selected matrix (for example `fixed-join-count-shrinking-intermediate/numeric-64/100000`).
Unknown, empty and ambiguous IDs fail rather than running zero cases. The log
labels this scope `single-case-diagnostic`; its success is not full-matrix
readiness or performance acceptance. Omit this variable for the complete gate.

## Work and boundaries

- Low selectivity validates all N source rows and declared fields, although
  capture and each downstream result contain only the final two ids.
- Join/count captures N rows with each id occurring twice. A and B share that
  observation; the inner join produces 2N rows before a single global count.
  The intermediate join limit must allow 2N, not just the final one-row output.
- Large reuse preserves all N rows and all fields through capture, independent
  A/B consumers and the A-to-C edge. Wide layouts cannot silently project the
  payload away to make transfer or memory measurements smaller.

Source generation is outside measured execution. Required source validation,
identity generation, independent holding and consumer completion are inside;
final cleanup is recorded separately. Pure task boundaries and logical output
identities remain identical across comparators. No cross-task fusion or
unfinished-input streaming is permitted.

## Execution readiness

The shipped application's default remains the 100-row, 10-column and
100000-byte profile. Its explicit `dataProfile` entrance has 1000-row and
10000-row retained process integration cases, not acceptance of this matrix. Before timing,
connect all generated cases to the parameterized, owned application profile and
check that its query capacities, logical guards, intermediate bounds, transport,
hashing, retention and physical reservations agree with every explicit case
ceiling. Unsupported profiles and timeouts remain failures/incomplete cases;
do not drop them or derive a smaller workload from successful execution.

All four comparators must use the same immutable database contents and logical
contracts. Keep raw DuckDB distinct from the equivalent-obligations comparator.
Record tested revisions, runtime versions, dataset/Program/configuration hashes,
actual transfer, hash bytes/passes, materializations, memory and ledger usage.
Do not use a synthetic sleep or a configured cost estimate as measured work.

Changing the fixture pin after samples exist requires a new experiment record
and fresh samples, not overwriting inconvenient measurements. The current record
has no timing samples or performance acceptance result.

## Paired timing assessment

First check whether the unchanged baseline's reservation policy can admit the
registered dataset under the comparison's one-GiB retention ceiling:

```sh
node benchmarks/retained-results/baseline-feasibility.mjs
```

This command intentionally exits nonzero: nine cases already exceed the ceiling
using only a lower bound on mandatory reservation. It verifies exact archived
receiver/capacity source hashes and reports every case. It excludes positive
node, wire and metadata terms, so `not-ruled-out` is not execution readiness.
The declared reservation is not measured RSS. In particular, numeric-64/100000
needs at least 3328000000 bytes before those omitted terms. Numeric fixture values
require no text payload; text-1024 includes the two mandated string allowances.

No capacity-only adaptation can make those cases fit without changing the old
runtime's accounting policy or the experiment ceiling. The benchmark cannot
provide a finite baseline timing ratio for them as currently specified. Treating
capacity refusal as a reported comparison outcome, or registering a separate
larger-capacity experiment for both paths, requires an explicit acceptance
decision. Neither is silently adopted here; failed cases and thresholds stay
unchanged. This audit is not a performance pass and does not implement the
equivalent-obligations comparator.

To diagnose the unchanged baseline's capacity before attempting timings, first
independently extract and release-build `experiment.baselineRevision` with the
pinned toolchain and DuckDB dependency, then run:

```sh
ACTQL_RETAINED_BASELINE_ROOT=/path/to/verified-baseline node adapters/connectors/duckdb/node/bench/baseline-retained-probe.mjs
```

The probe executes all registered cases (or one exact `ACTQL_RETAINED_CASE`) and
reports every incomplete case with nonzero exit status. It never raises baseline
caps, rewrites its source, omits rejected cases, or treats its output as a timing
sample. It verifies successful final identities and attempts explicit cleanup;
unconfirmed cleanup preserves the temporary directory and reports it. The path
alone does not attest revision/build provenance: the caller must verify that
separately. The unchanged baseline is currently unable to run this matrix through
its default example limits; see observations before interpreting its exit code.

`ACTQL_BASELINE_PROFILE=received-row-envelope` instead assembles the same old
public APIs and supplies only a larger transport received-row allowance. This
separate diagnostic includes metadata rows, full validation and projected output
in that allowance; all other old limits remain fixed. It does not patch archived
source or replace the baseline algorithm. It is intentionally not the final
capacity-matched benchmark: old MoonBit acquisition, fragment, guard, retention
and column bounds still need explicit capacity-only assembly configuration.

`baseline-receipt-104.patch` records the smallest verified assembly adaptation
for the 100-row narrow low-selectivity case: only the physical receiver and
receipt row ceilings change from 100 to 104 (metadata + validation + selected
rows). Apply it only to an isolated baseline, rebuild its example, and use
`received-row-envelope` with that exact case. The original `host_limits.mbt`
SHA-256 is `905a1ac2bbd1fa702b4da3a07b1ebd1a39c0b4141cc0875f00f60858dca4dc9a`.
This is explicitly an adapted baseline assembly, not the unchanged example and
not a capacity profile for the entire matrix. It changes no execution algorithm,
identity, fixture or semantic validation rule.

`managed-configuration.mjs` is shared by the readiness gate and the retained
comparison leg so their Program, envelopes, estimates, child limits and retention
settings do not drift. It preserves the existing fixture ceilings; estimates are
still supplied selection inputs rather than measured costs.

`adapters/connectors/duckdb/node/bench/retained-comparator.mjs` runs that configuration through
the installed managed Host. Its `executionMs` starts before Host construction and
ends after completed independent holdings and confirmed child exit. Independent
expected identity is calculated beforehand, checked afterwards, and final result
release has a separate `cleanupMs`. A failed identity check or failed cleanup
throws instead of returning a completed sample. Reports include Program/parameter/
source-definition hashes, environment CID, ledger, task phases, controller memory
and wire traffic. The source-definition hash is not a verification of database
contents; paired data provenance still belongs to the experiment runner.

This is `managed-host-cycle-diagnostic`, not a warm-task timer or full experiment.
It is not directly comparable to the raw engine's CTAS-only interval. The baseline
and identical-obligations legs, common timing boundaries, immutable data/runtime
provenance, alternating schedule and acceptance report still require integration.
Managed input phases in this diagnostic require `identityReused: true` and
`logicalCidPasses: 0`; the separate independent-obligation assembly still
computes and checks the old logical CID and must not be replaced by that managed
expectation.
The real test covers all three 100-row narrow workloads and verifies that a wrong
oracle rejects the sample while still removing completed files:

```sh
node --test adapters/connectors/duckdb/node/test/retained-comparator.test.mjs
```

The retained comparison function also accepts an explicit fifth argument such as
`{resident: true, nativeMilliseconds: '20'}`. Defaults remain fresh selection
with a supplied native estimate of `'1'`. Reports snapshot and hash these
selection inputs, and retain the actual per-task realizations and import counts.
For a task-specific cost experiment, pass both `localTaskMilliseconds` and
`nativeTaskMilliseconds` arrays with one decimal-string duration per Compute
task, plus an `estimateSource` SHA-256 reference. The example Host then compares
those supplied costs through the ordinary planner instead of its fixed Local
`1 + 2 * rows` and native fixed estimates. The reference records provenance;
the comparator does not prove that the figures came from measurement. A formal
runner must verify independent calibration evidence and held-out workload
selection before treating such a sample as cost-grounded.
Enabling resident candidates does not force them past eligibility or resource
checks. The estimate is not elapsed time, and changing it is a different selection
configuration, not an optimization speedup by itself.

Both selections use the same managed-cycle timing and cleanup boundaries. The
real integration test checks all three narrow 100-row workloads through both
selections, identical independent final CIDs, resident initial import followed by
zero reimports, process completion and file release. This permits diagnosis of
reuse without silently changing the fresh comparison leg. It does not complete
the equivalent-obligations comparator or the preregistered paired experiment.

The benchmark-only raw DuckDB leg can now be exercised against all 27 registered
cases (or one exact `ACTQL_RETAINED_CASE`):

```sh
node adapters/connectors/duckdb/node/bench/raw-retained-probe.mjs
node --test adapters/connectors/duckdb/node/test/raw-retained-comparator.test.mjs
```

It uses one thread and the case's memory ceiling, creates the deterministic source
outside execution timing, and materializes every capture/Compute stage separately.
It preserves A/B sharing and A-to-C consumption without cross-task fusion. It
checks every intermediate cardinality and reads final values in native chunks
against independent fixture expectations. Verification and transaction rollback
have separate timers; a verification, cancellation or rollback failure cannot
yield a completed report. The caller closes the dedicated connection/database.

This is `raw-engine-diagnostic`, not an equivalent-obligations implementation or
paired acceptance sample. It omits ActQL validation, logical identity generation,
independent retention, admission and logical budgets. Its source is in memory and
its result lifetime ends at rollback. Process startup and connection shutdown are
not measured by its execution timer. Do not compare its execution time directly
with the managed smoke's setup-through-cleanup diagnostic total as a gate ratio.
The formal runner still needs paired source/configuration provenance and all four
comparator implementations. In particular, the pinned baseline's default public
example fixes small row/column/transport limits: large-case compatibility needs
an explicit benchmark harness, not silent baseline edits or omitted cases.

`paired-assessment.mjs` provides the timing-only statistic for the future sample
runner. It checks contiguous pair indices, a single case, completed samples,
finite durations, and alternating retained/reference order. Missing, timed-out
or unsupported samples remain `incomplete`; they cannot be dropped from a pair.
At least seven pairs and 10000 bootstrap resamples are required.

`equivalent-series-assessment.mjs` adds the first case-level admission boundary
for the independent-obligations comparator. It requires one registered fixture,
the unchanged experiment pin, seven admitted pairs on the same implementation
revision, Program, source definition, source contents and runtime, confirmed
release, and a product leg qualified for normal cost-grounded selection. It
then applies the registered warm/cold or large-case equivalent timing limits.
The current matched-pair diagnostic uses explicit example estimates and marks
its product leg unqualified, so those samples correctly remain `incomplete`
under this boundary. A passing one-comparator series still cannot certify the
27-case matrix, baseline and raw comparators, or the whole experiment.

The statistic is the ratio of paired arithmetic means for ratios, or their
difference for absolute overhead. A reproducible seeded bootstrap resamples whole
pairs and reports a two-sided percentile interval. Its upper endpoint must meet
the threshold to pass; an interval crossing the threshold is `indeterminate`,
not success. The seed, interval, pair count and configuration are included in the
report. Cleanup is a separate field and must not be added to an overlapping timer.

This helper deliberately reports `paired-timing-only`. It does not validate
source/configuration identity, comparator obligation equivalence, correctness,
memory/copy counters or matrix completeness. The eventual experiment runner must
bind those checks and the registered thresholds to its actual samples; passing
helper tests is not a performance result. Test it without DuckDB using:

```sh
node --test benchmarks/retained-results/*.test.mjs
```

`adapters/connectors/duckdb/node/bench/matched-equivalent-pair.mjs` provides the next
lower-level runner boundary: one alternating retained/equivalent pair against
one hashed immutable database and one clean revision, with a fresh child for
each leg. It records matched parent-cycle, child execution and cleanup timing
plus the downstream-consumer warm interval without declaring the independent
comparator equivalent. The executable
`matched-equivalent-pair-case.mjs` wrapper takes the explicit fixture and pair
index after source setup. Its output remains diagnostic while the equivalent
leg reports missing obligations; it cannot be passed directly to the timing
assessment as an accepted sample.

The independent-obligation report also exposes separate accounting domains for
native-to-semantic JSON transport, JavaScript cell materialization, retained
canonical bytes, identity preimages, measured and reused logical guards, and
comparison measurement. These are observed quantities, not configured cost
estimates. The pair runner now requires exact product-side logical guard and
comparison parity. The independent leg also admits its database plus bounded
scratch under the unchanged 4 GiB execution limit and settles actual retained
completion-metadata bytes under the unchanged 1 GiB limit. Transfer/work parity
and final pair admission are still required.

`equivalent-failure-parity.test.mjs` exercises five cross-leg negative cases:
an invalid source value excluded by the later predicate, a deferred record
guard, a later invalid value that takes precedence over that guard, excess
source cardinality before filtering, and legal source cardinality whose
duplicate join keys exceed the intermediate-row guard. Both legs must reject at
the required earlier boundary and reclaim their holdings. The remaining
expression-demand and native-close failure matrix stays explicit in the
comparator-boundary inventory. A separate real-filesystem fixture replaces an
active retained pathname and requires an unconfirmed cleanup result with its
exact path-identity failure preserved.

### Selective baseline receiver profile

`baseline-acquisition-capacity.mjs` now provides pure transformations for the
pinned baseline's `host_limits.mbt` and application ledger. Both reject unknown
source hashes. The `.mbt.txt` snapshots are exact test fixtures from the pinned
revision, not production source or semantic authorities. The receiver transform
returns adapted source, a numeric-change inventory and the resulting hash;
the ledger transform supplies one acquisition plus three unchanged Compute
transfer reservations and the benchmark's 1 GiB retention / 4 GiB execution
Run ceilings. Runtime algorithms and per-Compute envelopes are unchanged.

Use these transformations only in a separate baseline archive, then rebuild its
three JS entries. Acquisition gets scaled copies of the original pure capacity
helpers so the shared Compute defaults do not change. The adapter deliberately
rejects join and large-output profiles; it is not the full-matrix baseline.
It has executed selective/narrow/10000 and /100000 successfully, not merely
generated text. Flat-row value allowances scale with the scan; completion-record
and two-row capture metadata retain their original limits. Giving every metadata
object the cumulative multi-task value allowance would distort the comparison.

Selective wide inputs additionally scale source column mapping,
receiver columns and metadata matching work. Pass the fixture's field count as
the third argument to the application transformation; Compute stays id-only with
its original column bound. Numeric-64/10000 has completed through this assembly.
The full wide matrix has not. Logical wire uses the registered representation
bound, not the larger framing allowance. Physical string-value storage is zero
for numeric fixtures (subject to original minimum limits), while serialized
transport still needs text capacity. The two-row output's retention allowance
remains unchanged. These distinctions avoid artificial baseline overreservation
without modifying its runtime capacity policy or the experiment's Run ceilings.

For the selective narrow 1000-row baseline diagnostic, apply
`baseline-receipt-1004.patch` to a separate clean archive of the pinned baseline
(instead of the 104 patch), rebuild the three baseline JS entries, and select
`ACTQL_BASELINE_PROFILE=received-transport-envelope` with
`ACTQL_RETAINED_CASE=native-acquisition-full-validation-low-selectivity/narrow/1000`.
This mode derives acquisition receiver row/cell/byte ceilings from the fixture;
Compute transport and import bounds remain those of the original example.
The patch changes six numeric receiver literals only. It is not a general
capacity-matched baseline for wide, large-output or join cases.

### Small baseline join profile

`baseline-small-join.mjs` adapts only the exact pinned `host_limits.mbt` and
`limits_and_generation.mbt` assembly sources for narrow join/count at 100 source
rows. The `.mbt.txt` generation snapshot is pinned archival evidence. The pure
transformation changes numeric allowances only: combined acquisition receiving,
the 200-row intermediate result and downstream fragment input. Source topology,
operators, join obligation derivation and algorithms stay unchanged. Apply it to
a separate baseline archive and rebuild all three JS entries.

Run that archive using `ACTQL_BASELINE_PROFILE=small-join-envelope` with exact
`ACTQL_RETAINED_CASE=fixed-join-count-shrinking-intermediate/narrow/100`. The
profile rejects every other case, including an unfiltered matrix. Its Node
Compute receiver allows 600 protocol response rows (two 200-row imports plus
200 output rows), but the logical input/output limit stays 200. The independent
cell ceiling remains 1000 and the byte/engine ceilings stay at their old defaults.
No selected offer or reservation check is bypassed. This profile has completed
all four Compute tasks, verified the expected final CID and cleaned up; it is
not a general join-scale adapter or a formal timing comparison.

### Resident phase diagnostics

The [fixed-checkout identity-reuse diagnostic](resident-identity-diagnostic.md)
records three alternating pairs for a small resident case and three registered
large cases. It shows the small-case improvement and the large cases' continued
fresh selection; it is not formal acceptance.

The [equivalent-comparator boundary](equivalent-comparator-boundary.md) lists
the semantic components that may be shared and the execution assembly that
must remain independent. It does not mark that comparator implemented.

Resident Compute reports sequential wall-clock intervals in each task's `phases`:
input verification, view preparation, result materialization, receiving the
result, finalization (including awaited independent holding), and temporary SQL
cleanup. Their sum is `workMilliseconds`. Reusing a DB copy reports zero imported
rows/cells, but does not omit input verification or its cost.

`reusedInputIdentities` counts exact resident input leases whose existing
canonical identity replaced re-encoding/hashing. `directInputScans` still counts
their bounded typed scans: value admission, demand, guard and join work remain.
These counts are structural diagnostics, not a performance acceptance result;
no fresh file input gains this authority merely by matching a path or CID.

These intervals cover the callback inside the resident transaction, not BEGIN,
COMMIT/ROLLBACK, environment provisioning, first-copy imports or final environment
close. Those operations remain in the surrounding session/Host measurements.
Receiving includes the receiver's validation/encoding/write callbacks; it is not
pure DB execution time. Session command and callback timings overlap these
phases and must not be added to them. Diagnostics accompany successful execution;
a failed or cancelled finalization still rejects and rolls back, without yielding
a successful phase report. These are attribution measurements, not new resource
budgets or proof of a performance threshold.

The baseline capability probe also emits `baseline-public-entry-diagnostic`
execution and cleanup intervals, but only after correctness and cleanup succeed.
The independent expected CID is calculated before timing. Source construction,
builds and fixture removal are excluded. This baseline holds results in memory;
the retained leg owns a process and independent files, so these single samples
are not equivalent-obligation or paired acceptance ratios. Failed cases emit no
successful timing sample and keep the probe's nonzero exit status.
