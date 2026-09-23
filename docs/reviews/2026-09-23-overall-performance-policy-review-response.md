# Performance and placement-policy review response

The external review was fixed at `e4029354d452732d6c205fd6132ca54d74019248`.
It distinguishes implementation defects, scale limits, and unfinished acceptance
evidence. This response tracks those findings against this branch; none of the
items below is declared complete merely because a diagnostic test passes.

| Review item | Current result | Required closure |
| --- | --- | --- |
| PERF-1: formal 27-case acceptance | Open. The registered experiment remains `preregistered-not-measured`. The 27-case smoke and seven small diagnostic pairs are not acceptance samples. | Fix one clean revision and its release build, run all four comparators with at least seven alternating pairs per eligible case, preserve every failed case, verify obligations, holdings and cleanup, then apply the preregistered confidence and timing gates. The nine capacity-infeasible baseline cases have no baseline ratio but still require retained and equivalent-comparator results. |
| PERF-2: candidate cross-product | The adaptive Host now uses a bounded frontier when the complete product exceeds `max_strategies`; explicit exhaustive search still fails closed. Partial-search provenance is bound into the candidate CID, selection history and explain. Three-target regressions cover 1/2/5 ceilings, one/two/five offers on a seven-task Carrier graph, a late fifth-offer feasible assignment, and all sampled assignments infeasible. The seven-task/five-offer case evaluates 64 complete assignments from 1,435 generated prefixes and peaks at 384 frontier states and 2,624 index cells. | Measure wall time and process memory against a fixed product SHA over larger task/offer profiles; the in-process counters are not RSS. Validate provider capability constraints in a full standard Host profile. Partial search must never be described as globally optimal. |
| PERF-3: remote policy contract | The portable standard DuckDB/Local Host exposes an exact pending decision before task dispatch. The native Host now uses its existing mTLS HTTPS client, a configured endpoint-to-policy identity mapping, a required metadata-disclosure callback, bounded request/response bodies and a durable monotonic clock. The same consultation survives a lost response; common admission rejects foreign identity, expiry and replay. Real mTLS fixture coverage includes disconnect, same-request retry, foreign identity and late response. | Complete final same-SHA gates and publish the supported Host configuration. Other environments need their own physical adapters; this native implementation does not imply a Cloud deployment. |

The common Host now records the same per-task elapsed interval for Local and
DuckDB. These measurements can inform an estimate model; they are neither
calibration evidence by themselves nor proof of the small-case timing gate.
Cost estimates, enforceable capacity and policy preferences remain separate.

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

Review regressions to add before closing PERF-1: missing pair, missing case,
changed Program or implementation hash, unconfirmed cleanup, and a baseline
capacity exception incorrectly converted into a finite speed ratio.
