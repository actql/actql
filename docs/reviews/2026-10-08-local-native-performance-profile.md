# Local Native performance profiles: bounded first unit

Owner: G. Adopted main: `db1bcddd793ad9a1e2e1d9fe452a984dc35254ac`.
This implements P1 local recording/basic aggregation and designs P2/P3 bindings.
Learned product selection remains post-0.1. No new execution Owner or remote
dependency is introduced. CI remains stopped.

## Editing and mapping boundary

G adds files under `benchmarks/retained-results/` for local profile validation,
bounded recording, a fixed Native experiment and focused tests. G does not edit
the common Owner, Native probe, existing gates, policy response or OTel adapter.
A owns common observation mapping, identity correspondence and disclosure.

The initial adapter consumes existing actual Native candidate projections,
choices, explanations, task/holding observations, physical phase events and
confirmed cleanup. Host is an explicit experiment condition, acquisition is a
separate actual choice, and Compute is the common planner's choice. The existing
Owner validator checks candidate position/revision/registration against the
execution and its exact reservation/holding/attempt deltas. Its attempt counters
are not opaque attempt IDs: unavailable identity stays unknown. Do not fabricate
a semantic attempt identifier from a span or ordinal.

A's mapping can later project these facts through a shared observation contract.
The required correspondence is the immutable candidate projection and selected
task/revision/position/registration, the actual measuring Host, distinct physical
attempts and their existing Owner boundary. A projection must preserve missing
identity and measurement scope. This unit depends on the existing facts, not on
OTel export completion. Metadata includes only the explicitly authorized local
synthetic fixture; it is not an admission to disclose arbitrary customer data.

## Finite experiment

Use the existing 1,000-row Text retained-reuse fixture and all unchanged limits.
Local is ineligible under the existing cumulative Text limit and its structural
reason is recorded; do not relax the limit to make it a measurement candidate.
Run fresh DuckDB and resident in three modes (off, metadata-only,
Evidence-enabled), three predeclared alternating rounds, concurrency one: 18
executions. The controls deliberately isolate a realization but still pass
through actual planner feasibility/selection. Record the controls separately
from the actual presented candidates, estimates, assessment and choices.

Every execution starts a fresh Native process and resident environment where
selected. OS cache state is uncontrolled. Keep process cycle, the existing
`coldMs` (parent preparation/start through child exit minus cleanup), the existing
`warmMs` (same-Run sequential task intervals), cleanup, operator boundaries and
local recording/basic aggregation separate. Intervals nest and must not be
summed into another elapsed time. These labels do not mean independent warmed
Runs or an OS-cache-cold measurement.

The modes concern this explicitly scoped diagnostic capture. Required canonical
Owner acceptance remains on in all modes. Off disables additional recording and
physical phase events; metadata-only enables phase observations and a compact
local record; Evidence-enabled additionally saves the actual admitted stdout
and stderr through a bounded local file sink and verifies their bytes/digests.
This is execution-evidence stream capture, not row-content capture, evaluation
Evidence integration, general user telemetry or a physical allocation bound.
No OTel package, exporter, network destination or customer data is required.

Never replace a failed/missing/censored observation with a successful rerun.
Report per-condition count, median and range only; three observations establish
no precision, quantile, ordinary failure rate or causal attribution. Preserve
first-use observations. Related result/resource/capture interference is a
failure to close, not an acceptable observation-overhead regression.

## P2/P3 connection design

The first estimate is a bounded sidecar to the common Owner's immutable
candidate snapshot and exact pending request, with candidate position,
authorized feature snapshot reference, profile/model revision, objective-policy
revision, units, measurement inclusion, capture/instrumentation revision,
freshness and uncertainty/unknown reasons. G's local data and profile digests
are provenance, never replacements for a candidate CID or permission.

The sidecar has its own authenticated issuer/admission and disclosure boundary.
Absent/stale/mismatched/oversized sidecars make estimates unavailable; they do
not repair or invalidate an independently valid closed policy response. No new
field is added to that response; no JSON protocol is hidden in `explanation`.
Feature gaps stay unknown. Planning must not fetch Source/Model/Effect content
or expand disclosure to fill them. Model revisions are frozen per consultation.

P3 initially reranks only the common planner's bounded presented eligible
candidate set. Record count, search completeness and comparison scope; test one
candidate and a meaningful multi-candidate choice when P3 is implemented. A
private predictor/ranker proposes estimates/order, while the existing Owner
retains feasibility, authorization, quotas, reservation and dispatch rechecks.
Transport/rejection does not mint a new request or grant silent offline fallback.
This unit does not implement empirical ranking or mutate current estimate inputs.

OSS owns useful local records/basic analysis, offline choice and portable
third-party contracts. Cloud may add private prediction, tenant-only continuous
calibration and authorized operational-resource features behind those contracts.
OTel export, tenant profiling and cross-tenant learning are separate opt-ins;
this unit sends nothing and adds no cross-tenant learning. Profile compatibility
and sidecar validation are separate: a matching local profile is not a valid
pending-request binding or an execution authority.

## CI evidence handoff

Previous CI evidence work is retained in #962 and its original local validation.
Actions original authentication, compatible later-main comparison, actual PR
`mutations-js` reuse, related-input fresh execution and net runner savings remain
unverified. Do not poll for originals or make this unit depend on them. Resume
only when an actual successful full-main Actions original is available; retain
its HEAD/run/attempt/artifact and qualify against a policy-compatible later main,
never the same SHA twice. Local records are not Actions originals.

## Acceptance

The fixed implementation source below passed local acceptance. Existing performance gates and independent fixture expectations are
unchanged. No full performance matrix, Hosted CI or cross-Host comparison is
claimed. Stop after the completed Draft PR handoff.


## Fixed-source acceptance and original custody

Executed source: `fa1d9c73ea435d272bdbcb2af5eb9de199e2610e`, clean throughout.
Subsequent publication adds documentation and preserved evidence only, without
rewriting this execution revision. Binary digest:
`sha256:e5eb40c2f4d9a2e4b247fdb699503f92a2090cef04df668010507730a1df6a04`.
Node 22.23.2, pinned MoonBit 0.10.12+1634b282e; actual environment, toolchain,
library and input identities are in the [summary](evidence/2026-10-08-local-native-profile-fa1d9c73e.json).
The [original archive](evidence/2026-10-08-local-native-profile-fa1d9c73e.tar.gz) contains the experiment, source
database, all 18 original observations, prepared invocation inputs, 12 metadata
captures, six actual stdout/stderr pairs, build witness and guarded logs/receipts.
Archive: 654,659 bytes, 250 regular files,
4,703,984 uncompressed bytes;
`sha256:376d478f7bf438f0e38cb94217463c34074c56ed02ed6c173f9f1e2b6d62f106`. Every archived member was read back and compared
byte-for-byte against its original. The compiled binary remains in the local
worktree's selected release `_build`; it is not republished as a product package.

Exact executed commands (the Node tests use the existing nonzero focused
reporter, release/campaign use the cooperative guarded local-check runner):

```sh
node scripts/local-checks.mjs test node --timeout-seconds 120 -- \
  benchmarks/retained-results/local-performance-profile.test.mjs \
  benchmarks/retained-results/native-owner-observations.test.mjs \
  benchmarks/retained-results/native-resident-estimate-profile.test.mjs
moon build --target native --release src/cmd/native_retained_case_probe --deny-warn
node --test --test-concurrency=1 benchmarks/retained-results/native-owner-acceptance.mjs
node benchmarks/retained-results/run-local-native-profile.mjs /private/tmp/g-native-profile-fa1d9c73e-20261008
node benchmarks/retained-results/read-local-native-profile.mjs /private/tmp/g-native-profile-fa1d9c73e-20261008
```

* Focused Node: **49/49**, zero skipped, `focused-test-Az4AnO` / `run-7mzwfw`.
  This includes 19 profile/capture checks, 16 existing Owner checks and 14
  existing resident-estimate profile checks.
* Selected release build: **168 tasks succeeded**, 348.668 seconds elapsed,
  first step of `run-yM3iAq`.
  Its following private witness script had a syntax error before acceptance;
  the whole guarded attempt failed, and that failure/log is retained. Fixing
  only that private wrapper did not rebuild or change submitted sources.
* Continued same-binary `run-pB4tew`: actual Native Owner **1/1 parameterized
  case** (`focused-test-NVOiUq`, ten selection/refusal/stop settings), **18/18**
  predeclared observations, and real offline capture/Owner readback all passed.
  No experiment sample was retried, replaced, discarded or added.
* Six condition groups each contain exactly three complete successes. Source,
  library, binary and clean source revision readback were unchanged. Across
  modes within each realization, independent result holdings, measured work,
  physical attempt deltas and final Ledger usage matched exactly; held and
  reserved resources were zero after cleanup. Resident environment/import
  attempts remain accounted through the existing Owner validator.
* Local refused: minimum cumulative Text 2,066,000 bytes exceeds the unchanged
  2,048,000-byte ceiling for two mandatory materialized outputs. It was not
  timed as an admissible candidate.

## Recorded observation costs

All times below are milliseconds, median [minimum, maximum], three samples per
cell. Off still includes required Owner diagnostics and observation recording.
Optional capture cost is its actual encoding/persistence/readback interval;
recording is original observation persistence/readback. Process cycle excludes
subsequent local capture/admission; local end-to-end includes them and recording.

| Realization | Mode | Count | Capture | Recording | Process cycle | Local end-to-end |
| --- | --- | ---: | --- | --- | --- | --- |
| fresh | off | 3 | 0.000 [0.000, 0.000] | 1.188 [1.127, 1.204] | 717.074 [604.619, 1133.245] | 742.743 [636.641, 1161.284] |
| resident | off | 3 | 0.000 [0.000, 0.000] | 1.645 [1.231, 22.517] | 605.370 [482.935, 1069.579] | 640.014 [508.484, 1156.685] |
| fresh | metadata-only | 3 | 1.896 [1.300, 3.985] | 2.139 [1.109, 10.518] | 1053.967 [814.074, 1876.204] | 1083.268 [841.911, 1962.547] |
| resident | metadata-only | 3 | 1.750 [1.355, 15.106] | 1.270 [1.256, 9.775] | 894.420 [558.570, 2609.050] | 924.097 [587.161, 2671.493] |
| fresh | evidence-enabled | 3 | 3.434 [2.561, 12.397] | 1.202 [0.733, 44.256] | 1519.100 [885.303, 3158.275] | 1547.005 [915.631, 3253.510] |
| resident | evidence-enabled | 3 | 5.154 [4.425, 8.118] | 2.070 [1.463, 3.117] | 748.984 [554.104, 1775.608] | 790.358 [591.188, 1808.908] |

Fixed-round paired deltas relative to off, retaining all negative and positive
values without selecting a favorable repetition:

| Realization | Mode | Pairs | Process-cycle delta | Local end-to-end delta |
| --- | --- | ---: | --- | --- |
| fresh | metadata-only | 3 | 336.893 [-319.171, 1271.585] | 340.525 [-319.373, 1325.906] |
| fresh | evidence-enabled | 3 | 802.026 [-247.943, 2553.656] | 804.262 [-245.653, 2616.870] |
| resident | metadata-only | 3 | 411.484 [-46.800, 1539.472] | 415.613 [-52.853, 1514.807] |
| resident | evidence-enabled | 3 | 266.049 [-51.266, 706.029] | 281.874 [-48.827, 652.223] |

Order/environment variation is not causally separated. These mode deltas do
**not** establish a telemetry overhead upper bound, regression percentage or
performance improvement; no blanket 5% threshold is introduced. First-use
samples remain present. Off is not an uninstrumented production baseline.

Common source preparation: 278.584 ms. Initial basic
aggregation: 1.953 ms. All 20 checkpoint writes including
the final experiment: 452.708 ms. Entire local experiment
through final checkpoint: 23244.388 ms,
excluding only the final small cost-receipt write. Separate offline original
readback/aggregation: 271.962125 ms. Compilation is outside this experiment.
Nested cold/warm, operator, cleanup and recording intervals are never added to
manufacture a second whole-run duration. Full per-sample and condition summaries
are retained in the JSON/original archive; OS cache and competing load remain
uncontrolled, provider thread count unknown, experiment concurrency one.

## Completed boundary and remaining scope

P1 local recording, condition-specific descriptive aggregation, capture failure
handling, actual execution-evidence capture and overhead disclosure are ready
for review. [The P2/P3 design](../design/local-performance-profiles.md) specifies
the held candidate/request binding, proposed bounded separate sidecar decoder,
negative admission cases and common-Owner commit path; it is not implemented
reranking, an accepted public schema or automatic profile-to-estimate input.

Opaque physical attempt identities remain unavailable (counter correspondence
only). The Native setting's between-task stop is not formal public Run
Cancelled. Production row-content Evidence, customer end-to-end latency, OTel
export, remote learning, held-out ranking/ETA calibration, Node/Host comparison,
existing full release/calibrated performance matrix and Hosted CI were not run
or newly established. Existing gates and independent expectations are untouched.
CI-original qualification and net Actions savings remain separately unverified
as described above. After this Draft PR handoff, stop this finite work unit.
