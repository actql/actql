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

## P2: separate sidecar proposal

Implement separately after this design is reviewed. Keep the existing request
and closed response in `physical_strategy/policy_wire.mbt` unchanged. The common
Owner mints the request and canonical projection through
`prepare_dispatch_policy_choice`, `prepare_dispatch_policy_request` and
`dispatch_policy_candidates`. `strategy_policy_candidates` exposes only a
minted pending consultation. Its exact canonical UTF-8 bytes, including version,
are the source of the existing candidate-set CID.

Proposed separate admission inputs:

| Group | Fields and validation |
| --- | --- |
| Envelope | New sidecar contract version, bounded length, issuer identity from configured authentication; no issuer authority inferred from JSON |
| Pending binding | Exact request ID, Run identity, authority, candidate-set CID, generation, revision and deadline from the held common request |
| Candidate binding | Existing projected candidate position; must occur in that exact snapshot; no synthesized offers or modified estimates inside the original projection |
| Feature binding | Immutable authorized feature-snapshot reference/digest, disclosure revision and tenant/project/purpose scope; feature source/coverage/missing values |
| Model binding | Frozen profile/model revision, objective-policy revision and model scope; never replace these on a pending consultation |
| Quantity | Name/unit and known/unknown/conditional/statistical status, measurement inclusion, capture/instrumentation revision, sample/coverage/freshness and calibration status |

Do not add raw rows, file paths, credentials or opaque live handles. Unknown
NDV/selectivity or operational resources remain unknown; `plan` must not execute
reads or external calls to improve its feature snapshot. Proposed initial sidecar ceilings are 64 KiB encoded UTF-8, depth 8, 4,096
decoded nodes, at most 64 candidate entries and 16 authorized feature references.
Each candidate position must be unique and present in the held projection; a
larger presented set yields an explicitly partial/unavailable estimate, never
silent truncation interpreted as full coverage. IDs/revisions are nonempty and
bounded to 128 UTF-8 bytes; diagnostics use a bounded enum, not arbitrary text.
These are proposed decoding/resource ceilings for P2 review, not measured heap
bounds. Keep the existing 4,096-byte closed policy response ceiling unchanged.

Proposed closed sidecar envelope: `version`, `binding`, `feature_snapshot`,
`model_revision`, `profile_revision`, `objective_revision`, `scope`, `entries`.
`binding` contains the exact existing request echoes, not a newly minted request.
An entry contains `position`, `quantities` and `conditions`; quantity contains
`name`, `unit`, `status`, `value`, `sample_count`, `coverage`, `freshness` and
`calibration`. Initially support duration milliseconds only; unknown has null
value and a typed reason. Finite nonnegative values must remain bounded under
the chosen decoder representation, and unsupported money/work units stay
unknown rather than being converted into a score. This is a proposed separate
0.1 contract shape, not an addition to current canonical preimages or an
implemented/accepted wire schema. An issuer is supplied by the authenticated
adapter alongside the envelope, not self-authenticated by a payload field.

The decoder receives the held snapshot/request and authenticated issuer, checks
closed shape/domains/size and exact bindings, then returns an optional immutable
estimate record or an unavailable reason. It cannot return a dispatch ticket or
change candidate CID, Approved binding or reservation. A valid existing policy
response can proceed without an optional sidecar. An invalid response remains
invalid regardless of the sidecar. Keep issuer/model identity distinct from the
authenticated `policy_id` passed to the existing response admission.

Acceptance before P2 availability: wrong request/Run/generation/revision/deadline,
position, projection bytes, feature/disclosure/model scope, stale profile,
unknown required quantities, oversized sidecar, wrong issuer and a model update
while the request is pending. Confirm unchanged original candidate bytes/CID,
closed response refusal of unknown fields and no hidden JSON in `explanation`.
Compare local-profile availability separately from sidecar admission; no P1
match test qualifies a pending request.

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
