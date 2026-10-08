# Local performance profile and future estimate binding

P1 defines local diagnostic recording. P2/P3 below specify a future separate estimate binding.
The initial schema is local diagnostic data, not a new public policy response.
No empirical estimate is automatically supplied to the product planner.

## P1 records and compatibility

`benchmarks/retained-results/local-performance-profile.mjs` defines three
separate objects: fixture data statistics, one execution observation, and a
condition-partitioned descriptive profile. `run-local-native-profile.mjs` records
existing Native Owner observations; `read-local-native-profile.mjs` reads and
verifies originals offline without launching a process or contacting a service.

An observation records a unique local trial ID, round, wall timestamp, typed
outcome, Owner acceptance, conditions, original-record digest, independent
quantity observations, capture availability and existing candidate/execution
mapping. The local trial ID is not a Run or attempt identity. Candidate snapshot
digest is a byte witness, not a new canonical candidate CID. Exact proposals,
selection positions/revisions/registrations and original explanations are kept.
The Owner checks each completed task against actual candidates and attempt,
reservation and holding deltas. Opaque attempt identity is explicitly unknown.
The selected native acquisition is distinct from Compute choice and explicit
Host configuration. Experiment controls are recorded independently: observing
these controlled candidates does not establish ordinary-plan superiority.

Compatibility partitions by Host/realization, revision/binary, bound input and
Program, scale/schema/limits, environment/library, concurrency, process/cache
condition, instrumentation revision, capture mode, measurement scope, controls
and authorized use scope. Provider-thread count and competing load are unknown
or uncontrolled. Exact-compatible observation does not imply universal
performance or complete environmental isolation.

A profile contains condition identity, all attempted observation IDs, typed
outcome counts, compatible complete-success counts, descriptive count/median/
minimum/maximum per measured quantity, freshness policy and unknown reasons.
An unmeasured quantity remains null/unknown. Population failure rate, precision,
calibration and planner estimate remain absent/not established. Three rounds are
the selected experiment's descriptive scope, not a universal sufficiency rule.
Freshness uses an explicit caller policy; the initial 24-hour analysis window is
not a scientifically calibrated validity lifetime. Querying a profile under a
different condition or stricter age returns unknown.

Successful execution and successful optional capture are distinct. Failed or
missing capture retains the execution outcome but excludes it from a complete
capture-mode profile. Failed/censored observations do not become fast success
samples. A process killed by timeout is interrupted, not Owner-confirmed
Cancelled. A between-task stop is not public Run cancellation. Unknown physical
responsibility stops the experiment rather than launching another task/process.

## Scope, budgets and local capture

The admitted local experiment owns a new output directory, 18 sequential slots
and three repetitions of each of six conditions. No automatic retries, slot
replacement, warmup discard, adaptive expansion or background profiling occurs.
Each Native invocation retains the existing 120-second fixture timeout and
1 MiB per-stream capture bound. Additional saved capture and an individual
observation record are each bounded at 2 MiB. Offline experiment readback is
bounded at 40 MiB; per-file readback at 2 MiB refuses final symlinks. This is a
finite diagnostic protocol, not a physical heap upper bound or a general
embedded-callback guarantee. Required Owner validation remains active in off
mode. Off means optional physical-phase/capture work is off, not an
uninstrumented product.

Metadata-only saves compact authorized synthetic execution metadata. Evidence
mode saves that metadata plus the actual admitted stdout/stderr to a local file
sink, with exclusive creation and byte/digest readback. The receiver rechecks
actual saved candidate/choice/holding/attempt/final-ledger correspondence. No
borrowed values or live handles cross this post-process boundary. This capture
contains execution-evidence streams, not row payloads, an evaluation dataset or
a general production Evidence API. Production content capture remains a
separate implementation under existing capture/resource ownership.

The original observation is written once before its own recording interval is
known. The enclosing experiment adds the measured recording/end-to-end duration
and original digest separately; the offline reader checks that exact projection.
Checkpoint writes, final checkpoint cost and offline readback/aggregation are
reported separately. No prior execution SHA is rewritten when documentation is
published later. Complete experiment time includes setup, provenance work,
execution and recording; the final cost-receipt write is explicitly excluded.

`coldMs` keeps the existing parent preparation through child exit minus cleanup
boundary; `warmMs` keeps the sequential same-Run task intervals. New process and
resident environment are explicit, OS cache uncontrolled. Operator intervals,
cleanup, process cycle and observed local end-to-end time are separate and
nested. A parent benchmark interval is not customer application or public Run
latency. Evidence copy/serialization/file persistence costs occur after physical
cleanup and are still charged to the observed local end-to-end interval. No
interval sum claims a whole-run p95 or excludes expensive first-use samples.

OTel export is absent. Local profiling consent, optional execution-log capture,
external telemetry destination and cross-tenant learning are independent
settings, not inherited permission. In this pilot only explicitly authorized
synthetic fixtures can be recorded. Future adapters must bind tenant/project,
disclosure revision and purpose before aggregation, and validate any extra
feature disclosure; removing metric dimensions does not remove scope.

## P2: local descriptive sidecar

The first implementation accepts duration references for the Native synthetic
1,000-row Text fixture. It does not provide calibrated ETA, p90, reranking or
execution authority. The original placement request/closed response and
candidate CID are unchanged.

The trusted caller selects the local profile directory; payloads cannot select
files or authenticate their issuer. `loadLocalOperationalProfile` invokes the
existing profile/record/capture validator, rereads and pins exact report bytes,
and freezes the admitted original. A configured local producer derives a
reference only from exact condition matches and observations attributable to
the same candidate snapshot, task and selected position. Neither digest nor
three matching samples proves a general performance bound.

The separate closed `actql-operational-estimate/0.1` envelope contains `version`,
`binding`, `profile_revision`, `candidate_snapshot_cid`, `conditions`,
`oldest_ms`, `newest_ms`, `max_age_ms`, `capture_ms`, `overhead`, `entries`.
`binding` echoes the existing request's version, request ID, Run identity,
authority, candidate-set CID, generation, revision and decimal-string deadline.
`profile_revision` is the immutable original report digest. There is no learned
model or optimization objective in this reference-only stage. Conditions are
the closed P1 fields, including input/runtime/artifact identities, authorized
local scope, instrumentation/capture/measurement revisions, concurrency and
uncontrolled OS cache. No feature reads, tenant learning or export are added.

Each entry contains `position`, `task`, `quantity`, `status`, `reason`,
`median_ms`, `minimum_ms`, `maximum_ms`, `sample_count`. Supported quantities are
`task-processing`, `task-release`, `resident-preparation`, `resident-import`.
The initial reference is the actual selected task's phase processing interval;
preparation/import are excluded from it, while release is separate. Missing
phase intervals are unknown, never fabricated zero. Unselected candidates have
no attributed samples. Observed extrema are descriptions, not prediction
intervals; quantities are not summed into whole-Run ETA. `capture_ms` is the
median per-execution capture expense, not a per-task additive charge.

Reference entries need at least three successful, accepted, complete and
attributed samples. Condition mismatch, insufficient samples or phase coverage,
and stale/future observations yield nullable values with fixed diagnostic
codes. An `off` mode cannot supply phase duration references. The 24-hour maximum
window is an operational analysis rule; callers may tighten it. `overhead` is
`unknown-no-off-comparison` for the six metadata-only samples. Direct record,
readback, aggregation and receive costs are reported separately.

Ceilings are 64 KiB encoded UTF-8, depth 8, 4,096 decoded nodes, at most 64
entries, and 128 UTF-8 bytes for IDs/revisions/condition strings. Nullable
quantities must be present. Duplicate (position, task, quantity), absent task
or candidate, unsupported diagnostic codes, non-finite/negative values and
unknown root fields are refused. The decoder reads the existing bounded
candidate projection (8 MiB/depth 24/one million nodes) solely for membership;
these decoder limits are not measured physical heap upper bounds. Existing
4,096-byte policy response bounds remain intact.

`admit_native_operational_estimate` validates the original dispatch Owner's
pending request before and after decoding using its existing durable Native
clock. It rechecks generation, revision, search/resources and deadline; expired
requests or changed pending bindings are refused. Freshness is checked again
at receive completion. Receipt admission never commits a candidate, reserves
capacity, retries or reads Source. Optional reference failure does not change
ordinary policy validity. The caller must authenticate the local producer and
pin its validated profile outside JSON; the fixture additionally pins each
producer template's exact bytes in caller configuration before binding it to
the actual held request. Passing an issuer string for arbitrary unvalidated
payloads would violate this adapter trust boundary.

The functional Native fixture admits references and reasoned unknowns, refuses
binding/position/profile/issuer mutations and rechecks refusal after ordinary
offline commit. It leaves candidate bytes, actual selection, acquisition,
physical attempts and final ledger cleanup unchanged. The six fixed samples
are separate from two functional receive runs; failures are recorded without
replacement. Neither local evidence nor this sidecar is an Actions original.

## P3: bounded reranking proposal

A private or third-party ranker receives only the already admitted bounded
snapshot and authorized features. It proposes a position/order among those
positions, with the frozen objective/model revision. It does not enumerate new
plans, recover candidates pruned by the common search, or certify optimality.
Record presented count and the existing `search_complete` value independently.
Test a single remaining candidate and a real multi-position choice; an
unchanged single candidate is not a ranking improvement.

The existing `admit_placement_policy_response_json` and
`commit_dispatch_policy_response_json` remain the decision and freshness/resource
revalidation boundary. Common commit retains feasibility, current registration,
rights, reservation and send permission. A ranking score is not an enforceable
capacity or a scheduling instruction. Keep absolute ETA evaluation separate
from ordering/objective comparison; future held-out time-split evaluation must
include observation, inference and consultation costs.

A transport failure preserves the same pending Native consultation. No new
request, silent offline substitute, task retry or resend grant is introduced.
Explicit offline selection is a pre-dispatch action through the existing Owner.
Predictor/sidecar absence means unknown estimates; policy outcomes still obey
that contract. Learners, remote private adapters, calibration, generic search
and runtime reallocation are not implemented in this unit.

OSS owns portable profile/estimate/admission interfaces, basic local analysis,
offline choice and third-party policy integration. Cloud may implement advanced
prediction, tenant-local continuous calibration and authorized service resource
information. No tenant-crossing data/model aggregation is included. There is no
new release dependency on Cloud, telemetry export or the deferred CI-original
qualification work.
