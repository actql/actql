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

Implementation, exact-source local results and overhead will be appended after
execution. Existing performance gates and independent fixture expectations are
unchanged. No full performance matrix, Hosted CI or cross-Host comparison is
claimed. Stop after the completed Draft PR handoff.
