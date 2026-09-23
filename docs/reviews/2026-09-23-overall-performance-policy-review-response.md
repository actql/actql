# Performance and placement-policy review response

The external review was fixed at `e4029354d452732d6c205fd6132ca54d74019248`.
It distinguishes implementation defects, scale limits, and unfinished acceptance
evidence. This response tracks those findings against this branch; none of the
items below is declared complete merely because a diagnostic test passes.

| Review item | Current result | Required closure |
| --- | --- | --- |
| PERF-1: formal 27-case acceptance | Open. The registered experiment remains `preregistered-not-measured`. The 27-case smoke and seven small diagnostic pairs are not acceptance samples. | Fix one clean revision and its release build, run all four comparators with at least seven alternating pairs per eligible case, preserve every failed case, verify obligations, holdings and cleanup, then apply the preregistered confidence and timing gates. The nine capacity-infeasible baseline cases have no baseline ratio but still require retained and equivalent-comparator results. |
| PERF-2: candidate cross-product | The adaptive Host now uses a bounded frontier when the complete product exceeds `max_strategies`; explicit exhaustive search still fails closed. Partial-search provenance is bound into the candidate CID, selection history and explain. Unit regressions cover 1/2/5 ceilings, a late assignment and all sampled assignments infeasible. | Measure larger task/offer profiles and peak metadata/work against a fixed product SHA. Validate a feasible candidate outside the cheap frontier in a product-shaped case. Partial search must never be described as globally optimal. |
| PERF-3: remote policy contract | A closed, bounded versioned JSON response is decoded against the exact pending request and the Host-authenticated policy identity, then committed through common admission. The candidate bytes are available to the Host. The contract is recorded in `docs/design/placement-policy-wire.md`. | Wire this contract to an authenticated external Host adapter, enforce metadata-disclosure policy, and test real disconnect/replay/timeout behavior. The local `PolicyDecisionRef` alone is not a remote authentication protocol. |

The common Host now records the same per-task elapsed interval for Local and
DuckDB. These measurements can inform an estimate model; they are neither
calibration evidence by themselves nor proof of the small-case timing gate.
Cost estimates, enforceable capacity and policy preferences remain separate.

The registered equivalent-obligations case-level assessor now rejects missing
or mixed-revision pairs, changed Program/source/configuration provenance,
unconfirmed release and diagnostic-only product selection. It applies the
registered small or large timing limit only after those checks. The seven
existing small-case pairs are correctly incomplete at this boundary because
their retained leg uses the example's uncalibrated estimate. This does not
close PERF-1: qualified execution and the other comparator/matrix gates remain.

The registered narrow-100 Program also runs through a Node-free native Host
probe with real DuckDB acquisition and an independently checked final CID.
This isolates the JS process setup cost but still lacks independent holding,
a fresh consumer and a matched comparator; it supplies no PERF-1 sample.
When parameterized with registered larger cases, the native materialized path
rejects some cases before dispatch under the fixed 1 GiB retention ceiling.
This path needs managed bounded holding for native acceptance; raising the
registered ceiling is not a valid substitute.

Review regressions to add before closing PERF-1: missing pair, missing case,
changed Program or implementation hash, unconfirmed cleanup, and a baseline
capacity exception incorrectly converted into a finite speed ratio.
