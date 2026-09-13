---
spec_id: actql.execution
status: adopted
version: actql/0.1
normative_dependencies: [actql.language]
---

# ActQL execution

[Specification index](README.md)

<!-- normative-import: actql.language actql/0.1 -->

This document owns capture, admission, run-identity-model, checkpoint-invariants, replay, effect-outcomes, reconciliation. It does not define other owners' wire protocols or a particular Host implementation. Cross-owner links outside the declared dependencies are informative navigation to protocol bindings or conformance evidence; they do not import those documents' requirements. Narrow machine contracts remain authoritative for their explicitly referenced values and envelopes.

<!-- page-contents:start -->
## On this page

- [Terms](#execution-terms)
- [Run execution](#effects-and-execution)
- [Capture, execution, and replay](#capture-and-replay)
- [Program and stage execution](#stage-execution)
- [Numeric observation capture](#numeric-observation)
- [Run admission and identity](#run-admission)
- [Run states and transitions](#run-states)
- [Checkpoints and Resolutions](#checkpoints)
- [Effect preview, approval, and application](#effect-application)
- [Semantic risk routing](#policy-routing)
- [Logical request and item recovery](#logical-request)
- [Preview renewal and template authorization](#approval-renewal)
- [Outcomes and reconciliation](#reconciliation)
- [Source-state advancement](#source-state)
- [Row rejection and runtime failure](#runtime-failure)
- [Boundary with later work](#later-work)
<!-- page-contents:end -->

<a id="execution-terms"></a>

## Terms

- **ObservationSet** — the exact captured input and acquisition evidence used by
  one stage computation, including local/remote numeric observations, receipt
  imports, model responses and relevant
  Artifact identities. Capture and replay are specified in [Capture, execution, and replay](#capture-and-replay).
- **Invocation** — the content-addressed semantic input to replayable
  computation: the local Unit Definition, used bound values, local contract closure, and
  exact captured ObservationSet. It is distinct from an approval unit or Host
  lifecycle; its establishment is specified in [Capture, execution, and replay](#capture-and-replay).
- **Run** — the Host-managed lifecycle of executing one local computation unit, including
  admission, runtime units, Checkpoints, Effect application, receipts, and
  reconciliation. Its relationship to an Invocation is specified in [Run admission and identity](#run-admission).
- **Run Definition** — the immutable record identifying one Run's scope and
  Run ID, checked Plan, Invocation Template, authorization context, initial
  captured input artifact set, and creation and expiration times. It is
  identified by `run_definition_cid` and remains distinct from admission
  evidence and changing continuation state ([Run admission and identity](#run-admission)).
- **Host** — the execution environment owning authentication, current policy,
  Run state, Checkpoints, and provider scheduling.
- **Prepared Invocation** — the admission artifact binding a bound Invocation
  Template and Compiled Plan to an authenticated execution context, policy
  decision, and expiration. It precedes capture of the complete ObservationSet
  and is not a concrete Invocation ([Run admission and identity](#run-admission)).
- **Run Authorization** — the Host-verified allow or approved decision for one
  exact Prepared Invocation ([Run admission and identity](#run-admission)).
- **Checkpoint** — a sealed pause at a protected execution boundary requiring
  a decision, including preparation before Plan execution starts ([Checkpoints and Resolutions](#checkpoints)).
- **Resolution** — the Host-verified approval or rejection of one exact
  Checkpoint ([Checkpoints and Resolutions](#checkpoints)).
- **Captured Run** — the private evidence artifact containing a Run Receipt,
  Result Manifest, Result Artifacts, Effect context, and captured observations.
  It provides the captured computation evidence for Effect preview ([Capture, execution, and replay](#capture-and-replay)).

<a id="effects-and-execution"></a>

## Run execution

An execution request supplies a Program, invocation values, input bindings,
execution context/constraints, and zero or more Result deliveries. Delivery
selection is not Program semantics ([Result delivery](protocols/artifacts.md#result-delivery)), but may inform end-to-end schedule
estimates. CLI, SDK, and scheduled invocation adapters map to this same model;
a scheduled invocation binds that occurrence's values before bound planning.

Public workflow separates checking, explanation, and execution. Checking is
optional before execution and performs no observation. Explanation describes
known contracts, estimates, their evidence, and unresolved choices; it neither
authorizes execution nor serves as its saved executable input. New observations
require explicit authorization and budget, not merely an explanation request.
Execution performs its own checks; cached artifacts require validated reuse
conditions. Missing initial input bindings prevent execution admission.

A request to stop before commit stops after the complete Effect Preview is
persisted and before the first Effect application. Reads, inference, egress,
and costs may already have occurred, with earlier Checkpoints where required.
Stopping grants no authority and promises no atomic transaction across Effects.
Continuation uses the same Run and its captured outputs, with the existing
Resolution and dispatch-time revalidation rules ([Checkpoints and Resolutions](#checkpoints)). Delivery failure does
not undo a successful Run or authorize replay of its Effects; retry delivery
against the materialized Results instead.

<a id="capture-and-replay"></a>

### Capture, execution, and replay

Ranked candidate acquisition captures one logical response per input query,
including zero hits, with the request, ordered prefix, completion scope,
exactness, pagination termination and accounting evidence. Candidates and
coverage are two output ports of one acquisition, not independent captures.
Their publication is atomic at the operation boundary. A failed request
produces neither a successful empty response nor a successful coverage row.
Replay uses the captured prefix and coverage; a fresh search is a fresh
observation even when the provider, query and k are unchanged. Transport
batching does not change logical query identity or reset consumed budgets.

Pure graph Delta application, lexical ranking and calendar calculation are
computations, not external observations or Effects. Their admitted semantic
dependencies include the relevant graph, numerical, Unicode and timezone
artifacts. Loading those dependencies is explicit preparation; executing an
expression does not discover a profile or acquire new provider data.

<!-- requirement-block: capture-and-replay.consumer-capacity -->
Predicate consumers MUST bind and enforce `actql-consumer-capacity/0.1` and its
exact canonical `capacity_contract_cid` in their sealed body. The artifact is
registered in Contracts' Machine contracts and the conformance contract index.
`max_rows` caps each admitted input collection separately:
raw graph node declarations, raw edge declarations, Relation occurrences and
event records; it separately caps published output rows. It is not a predicate
callback count, a graph-normalization dedupe allowance, or a traversal-work
limit. `max_value_bytes` caps each top-level value in each admitted record and
published row by UTF-8 canonical JSON bytes (graph props is one such value),
each value of a demanded predicate context, and each evaluated root result.
Check a demanded root's result contract and canonical byte ceiling once, before
strict-true consumption; do not evaluate an undemanded root to check its size.
Root byte failures use the shared fragment `ACTQL_E_BOUND_EXCEEDED` diagnostic.
Check inputs before computation
and outputs before any publication/consumer, even when no predicate exists.
Validate supplied context field contracts even without predicates; admit all
known input fields, types and nullability, including unvisited graph elements,
before predicate evaluation. Contexts remain open to additional fields.
Input admission inspects values without evaluating expressions. Traversal work
and sequence-match ceilings remain separate operation limits. Serialization,
composition and replay preserve the law and scope; a changed law changes the
sealed identity; admission preserves the exact law bound by that identity.

<!-- requirement-block: capture-and-replay.execution-must-use-only-validated-aoa-ir-and-when-present capture-and-replay.the-runtime-must-not-execute-actql-source-directly-or-reinterpret -->
Execution MUST use only validated AoA IR and, when present, validated typed
acquisition, numeric-observation and Artifact barriers. The runtime MUST NOT execute ActQL source
directly or reinterpret it after lowering.

<!-- requirement-block: capture-and-replay.the-host-must-not-issue-a-completed-invocation-identity-while -->
An Invocation is established only after the exact input and external
observations needed by its checked computation have been captured. The
ObservationSet includes the source evidence, model responses, keyed-acquisition
responses, imported receipt views, captured local/remote floating aggregate
values, and Artifact content identities on which that computation depends.
Concrete opaque bindings are bound by that observation evidence; scalar
parameter values and the Check Environment are bound as specified in [Canonical identities](language.md#canonical-identities).
The Host MUST NOT issue a completed Invocation identity while required
observations remain uncaptured.

<!-- requirement-block: capture-and-replay.each-observation-must-be-captured-before-its-downstream-consumers-execute capture-and-replay.once-established-its-observationset-must-not-change -->
Capture may be staged: a data-dependent acquisition can require pure
computation over earlier captured observations. Each observation MUST be
captured before its downstream consumers execute. Intermediate unit outputs
do not imply that the complete Invocation has already been established.
Once established, its ObservationSet MUST NOT change. A fresh acquisition
creates a new Invocation rather than changing the inputs of a replay.

<!-- requirement-block: capture-and-replay.effect-preview-must-use-that-artifact-as-its-source-of -->
The Captured Run records the computation's Run Receipt, Result Manifest, exact
Result Artifacts, Effect context, and captured observations as private evidence.
Effect preview MUST use that artifact as its source of computation evidence.
For local semantic identity, it uses the verified projections defined in
[Result Artifacts](protocols/artifacts.md#result-artifacts), not the full Captured
Run/audit Manifest CID. Projection attestation and current membership are
mandatory admission evidence outside the Preview semantic preimage; neither
discarding the source audit nor accepting an unauthenticated projection is legal.
Current target observations, authorization, and freshness checks still occur
at their boundaries in [Checkpoints and Resolutions](#checkpoints) and [Effect preview, approval, and application](#effect-application); they bind Preview/apply evidence rather
than replacing the computation's ObservationSet.

Receipt dependencies are acyclic:

```text
computation receipt → Captured Run → Effect Preview
  → approval/apply/reconciliation receipts → final Run receipt
```

<!-- requirement-block: capture-and-replay.an-artifact-must-not-require-a-future-artifact-s-cid-in -->
The computation receipt embedded in Captured Run contains no later Preview or
apply CID. A final Run receipt is a new artifact referencing the earlier
evidence, not a mutation of that captured receipt. The receipt schema may be
shared, but its pre-effect and final instances have distinct CIDs. An artifact
MUST NOT require a future artifact's CID in its own hash preimage.

<!-- requirement-block: capture-and-replay.given-the-same-canonical-plan-captured-observations-and-semantic-contracts capture-and-replay.delivery-bytes-must-also-be-stable-when-the-result-artifact -->
Given the same canonical Plan, captured observations, and semantic contracts,
executions MUST produce the same logical Result CID for every named Result,
independently of compiler or runtime implementation.
Delivery bytes MUST also be stable when the Result Artifact and serialization
contract are the same. A fresh model call is a new external observation and is
not required to reproduce an earlier response.

<!-- requirement-block: capture-and-replay.on-type-conversion-bound-identity-completeness-serialization-or-operation-failure -->
Every AoA operation is logically atomic. Its output artifact is published only
after successful completion and validation. On type conversion, bound,
identity, completeness, serialization, or operation failure, that operation's
output artifact does not exist; a partial semantic result MUST NOT be exposed.
Already content-addressed upstream artifacts MAY remain.

<!-- requirement-block: capture-and-replay.the-run-receipt-must-identify -->
The Run Receipt MUST identify:

- ActQL version and compiler version;
- AoA IR version and logical CID;
- connector/input logical identities and completeness;
- the exact Result Manifest CID and every referenced Result Artifact CID;
- effect preview identity, if present;
- normalization journal identity or embedded journal;
- task contract, acquisition evidence, raw-response Artifact, and
  capture-bundle identities for every acquisition or Artifact barrier.

<!-- requirement-block: capture-and-replay.they-must-not-embed-result-row-payloads -->
The Result Manifest and its Result Artifacts carry each Result's exact logical
CID, schema, non-negative row count, completeness, effective policy, and
provenance. They MUST NOT embed Result row payloads. Serialization-contract and
byte identities are bound only by the delivery receipt in [Result delivery](protocols/artifacts.md#result-delivery).

<!-- requirement-block: capture-and-replay.it-must-not-substitute-a-fresh-acquisition-during-same-observation-replay -->
Raw network access remains Connector- or admitted task-host-only. Model and
other typed external acquisition may incur cost and data egress, but neither grants
business-state mutation authority. The runtime captures each response before
downstream computation. It MUST NOT substitute a fresh acquisition during
same-Observation replay or Effect apply.

<a id="query-acquisition"></a>

### Query-shaped acquisition

The initial query-acquisition profile covers an exclusive finite Relation scan,
one checked filter and one checked select, with no intervening semantic barrier.
Its input is the selected SourceView request; its single completed output port is
the select result. A source or filter output with another consumer is outside
this profile. Other shapes, changes feeds and checkpoints have no derivation
rule in this profile. Finite snapshot read mode does not imply snapshot isolation
or require a provider snapshot token.

<!-- requirement-block: query-acquisition.derivation -->
The compiler MUST derive this boundary from the checked graph, selected source
contracts and effective Parameter bindings, independently of backend registration,
price or placement; retain the exact filter and select occurrences and their
obligations; and place capture after both operations and before consumers.

<!-- requirement-block: query-acquisition.admission -->
Every realization MUST validate all known fields and their declared types and
nullability throughout the selected scan before applying its filter, including
fields not used by the query and rows excluded by the filter; preserve the checked
expression demand and every demanded failure without evaluating undemanded
expressions; and reject a native realization unable to implement these checks.
The selected scan means the extent of the bound source request, not all data in
the connector. This profile makes full admission explicit across pushdown. A
provider may perform it internally with verifiable execution evidence; reducing
Host receipt to projected rows is not evidence that it happened. Residual work
cannot restore failures or rows already suppressed by an incompatible provider.

<!-- requirement-block: query-acquisition.limits -->
Execution MUST enforce the requirement's logical output-row guard on the complete
select result, its value-byte guard on admitted records and demanded expression
roots, and all separately selected consumer-capacity limits at their own scopes;
enforce physical receipt and retention budgets against actual usage, not result
size; and publish no successful capture on any admission, evaluation, limit,
coverage, capture or cancellation failure.
Input admission precedes predicate evaluation; capture follows complete logical
evaluation and validation. Physical budget exhaustion can stop receipt earlier.
There is no requirement to continue an exhausted physical attempt to discover a
later semantic error or to choose the same diagnostic across physical candidates.
Successful retained upstream observations survive a downstream failure; failure
does not authorize a replacement read.

The closed machine contract is
<!-- machine-import: ../../spec/contracts/actql-query-acquisition.json# sha256:4bb69dfaade0a15952fe23a8202a9475ff450c9f0fab93f9dd5cef1b82045ab1 -->
<!-- machine-import: ../../spec/contracts/actql-query-acquisition.json#/schemas/requirement sha256:b6506c5d7b23c83c1ddc311b3c7d6766a6f3f5e2de92747e1d03f949e5df1dc1 -->
<!-- machine-import: ../../spec/contracts/actql-query-acquisition.json#/schemas/completed_observation sha256:ec44c31bc821c4e1a1f3eafa7e519cd1d4fc9ba9458149aaa3577b6053934715 -->
[`actql-query-acquisition.json`](../../spec/contracts/actql-query-acquisition.json):
`/schemas/requirement` and `/schemas/completed_observation`. Its root CID is
`sha256:4bb69dfaade0a15952fe23a8202a9475ff450c9f0fab93f9dd5cef1b82045ab1`.
All listed properties are required, unknown properties are rejected, and explicit
null is used only where the schema permits it. JSON Schema checks shape, not
graph ownership, actual execution, admission, budget use or evidence authenticity.

<!-- requirement-block: query-acquisition.program-owner-definition -->
`owner.program_source_cid` MUST be the authority-bearing Program Definition CID
defined in [Canonical identities](language.md#canonical-identities), not the
Program semantics CID or a source-text hash. Its exact preimage is
`{version: "actql-program-definition/0.1", id, program_semantics_cid}`:
`id` is the normalized authored root Program ID, and `program_semantics_cid`
hashes that same Program's canonical unbound `actql-program-semantics/0.1`
envelope. Hash the whole definition object as canonical JSON UTF-8 with SHA-256;
there is no self-CID member. The semantic envelope excludes the root ID while
retaining the ordered stage descriptors and exports prescribed by that section.
Thus changing the root ID without changing semantics changes this owner.
Bound values, Check Environment, observations and physical attempt identifiers
do not enter the Definition preimage; their separate acquisition bindings remain
required. The owner in the completed observation must match the requirement.

The requirement's exact preimage is its entire schema-conforming object, with no
self-CID field. `owner` contains the Program Definition CID and authored stage and
input names. Occurrences are stage-relative RFC 6901 pointers into the actual
`steps` array. `filter.expression_cid` hashes the normalized structured expression,
without evaluating it; `select.fields` retains authored projection order and
input/output names. Input/output contract CIDs hash the complete checked field
maps. `source_contract_cid` is the selected SourceView contract CID, not the whole
Catalog CID. `request` contains resolved typed wire request values: only authored
Parameter slots are substituted; business `$param` and `literal` members are
never reinterpreted. `parameter_values_cid` uses the existing typed parameter-value
projection for exactly the union of request and filter Parameter names, including
defaulted values once, excluding unused declarations and origin metadata.
`source_validation.fields` lists every known input field once in UTF-16 order.
`source_order_cid` names applicable source order evidence, or is null; a physical
enumeration order is not automatically logical order evidence.

<!-- requirement-block: query-acquisition.binding -->
Completion admission MUST match the exact requirement CID, source reference,
source contract, owner and Parameter identity; recompute `resolved_request_cid`
from the requirement's request object; verify the actual access and complete
coverage evidence against that request and its snapshot conditions; and verify
that output rows conform to the required output contract and query semantics.
`snapshot` is null when no snapshot evidence applies; otherwise its contract and
token are verified according to the selected source contract. Changing a required
snapshot, owner or binding is not justified by an equal result. The access scope
is the CID of exactly `{version:"actql-query-access-scope/0.1", requirement_cid,
received_rows_cid, received_fields}`. Its rows CID hashes the complete ordered
array of received typed wire rows, before residual operations; its field names
are unique and UTF-16 sorted. Optional provider scope is source-contract-defined,
separate from receipt, and is null when no such evidence is available. Coverage
scope is the CID of exactly `{version:"actql-query-scan-scope/0.1", source_ref,
source_contract_cid, resolved_request_cid}`. It identifies the selected scan,
which can differ from Host receipt. Evidence CIDs reference verified execution
records for source validation, filter and select, each bound to the exact
requirement and actual acquisition attempt under the admitted Host/source
evidence contract; a proposal, boolean claim or
valid self-hash alone is insufficient. A weak prefilter leaves the checked filter
as residual work before capture.

The completed-observation preimage is its entire schema-conforming object, also
without a self-CID. Its CID is the capture identity for this process-retention
profile. `output.rows_cid` hashes the ordered array of typed wire row objects;
object key order is canonicalized, row order and repeated rows are retained.
`output.contract_cid` equals the requirement's output contract CID. Decimal uses
the canonical fixed-scale string under that contract, not a JSON number. Every
CID here uses SHA-256 of canonical JSON UTF-8. No future observation or Invocation
CID occurs in the static requirement. Equal rows do not imply equal observations:
actual access, coverage and snapshot evidence remain in the completed preimage.
This is not a new Invocation preimage; existing Invocation rules retain the exact
completed observations rather than substituting result CIDs.

<!-- requirement-block: query-acquisition.retention -->
A process-retained observation MUST be complete and immutable before a fixed-input
consumer receives it; bind that consumer to the retained output of the exact
observation rather than a source selector; reject a fresh read as a substitute;
and never claim that process retention satisfies durable Run, recovery, checkpoint
or numeric-observation capture requirements.
Losing the process loses this retention guarantee. Runtime evidence verification
and backend execution support are separate from static derivation and registration.

<a id="query-process-evidence"></a>

#### Process-retained query evidence

<!-- machine-import: ../../spec/contracts/actql-query-process-evidence.json# sha256:f407203d3799dc51c2bc8cee460111ee6ebe44fb55c1c515d8d94190813b62a4 -->
<!-- machine-import: ../../spec/contracts/actql-query-process-evidence.json#/schemas/record sha256:758c9c4f1942890e73462776f3230400e7076c146af8eb3f7e39602715c7427e -->
The initial process-evidence profile specializes the acquisition contract without
changing its requirement or observation shapes. Its closed record schema is
[`actql-query-process-evidence.json`](../../spec/contracts/actql-query-process-evidence.json)
at `/schemas/record`. This is a Host-private execution trust boundary, not a
portable proof system, backend registration or durable Run capability.

<!-- requirement-block: query-process-evidence.order -->
This initial profile MUST require `source_order_cid: null`; preserve the relative
order of admitted rows through filter and select; and never infer total order or
justify an order-dependent consumer from physical enumeration alone.
This does not erase independently selected source guarantees. A non-null source
order requirement needs its own admitted source-order evidence contract and is
unsupported by this profile. The earlier `fixture_order` hash is test input only,
not such a contract. Snapshot tokens neither establish nor replace order evidence.

<!-- requirement-block: query-process-evidence.issuer -->
The selected Host MUST authorize the execution-record issuer outside candidate
proposals; allocate a process-unique issuer identifier and a never-reused attempt
identifier within it; and allow issuance only after successful full selected-scan
admission, demanded filter evaluation, select, applicable logical and physical
limits, and immutable output retention have completed.
An attempt is allocated before execution, not supplied by a candidate or caller.
The Host's selected verifier pins this process-evidence contract and its acquisition
dependency; a matching version string alone does not select or authorize a verifier.
The issuer is trusted execution code with access to the completed task and its
actual source scope. It can be Host-private; no shared MoonBit issuer constructor
or generic evidence reader is required. All three role records are issued at this
completion point, including the earlier source-validation phase. Failure or
cancellation before completion issues none and admits no consumer. A later consumer
failure does not revoke an already completed retained observation.

The exact record preimage is the entire `/schemas/record` object, without a
self-CID: `{version:"actql-query-process-evidence/0.1", issuer, attempt,
requirement_cid, role, snapshot, scan_scope_cid, actual_access, output}`.
`role` is `source_validation`, `filter` or `select`. `snapshot`, `actual_access`
and `output` have exactly the acquisition observation meanings and shapes.
`scan_scope_cid` equals its coverage scope. Each of the three coverage evidence
CIDs hashes the corresponding record with SHA-256 over canonical JSON UTF-8.
No record includes the observation CID or another role's CID, avoiding a cycle.
The requirement CID binds owner, source, resolved request, Parameters, operations
and contracts; issuer/attempt distinguish executions even with identical output.

<!-- requirement-block: query-process-evidence.admission -->
The Host capture verifier MUST resolve all three evidence CIDs to live immutable
opaque records issued by an authorized issuer; match their roles, exact requirement,
same issuer and attempt, applicable snapshot, scan scope, actual access and output
to the expected execution and observation; verify the retained rows and their
output CID, count and contract; and reject missing, foreign, unissued, substituted
or deserialized records even when their self-hashes match.
The expected attempt comes from the Host's owned task, not from the submitted
observation. A CID-indexed lookup alone does not confer authority: live provenance
and task ownership are additional checks. Losing the issuer's process or retained
records ends this profile; serialized JSON cannot restore that authority. JSON
Schema validates only the closed shape, not these semantic or provenance checks.

<!-- requirement-block: query-process-evidence.native -->
For native pushdown, the issuer MUST possess verified execution provenance covering
all mandatory fields and rows of the selected source scan before filtering,
including those not received by the Host; otherwise completion is rejected or a
broad acquisition is executed instead. Successful admission of projected received
rows alone is insufficient.
A mock source owning the complete finite scan can perform these checks itself
and keep private completion handles. An external provider needs an independently
admitted source attestation path; this profile does not invent one. Neither a
coverage boolean nor a native candidate's promise supplies the missing provenance.
Snapshot applicability still follows the source contract, and null remains valid
when no snapshot evidence applies. No universal snapshot facility is introduced.

<a id="stage-execution"></a>

### Program and stage execution

A checked unit waiting for control milestones or import availability reports
`pending_predecessor` under the [public planning contract](protocols/contracts.md#planning-wire).
It cannot dispatch or establish an Invocation until those prerequisites and
ordinary current admission succeed.

A single Run executes one local unit: capture, pure computation, independent
Effect Set and receipts. A stage list is compiled into common Run Graph units,
not a separate ProgramRun/StageExecution state machine. Graph activation,
shared context, commit scopes and recovery ownership use the pinned narrow
graph law; this owner retains single-Run admission and execution.

<!-- requirement-block: stage-execution.product-2e6789533bf2 stage-execution.product-ae166d3d086d -->
Each activated unit MUST verify its concrete local parameter/import projection,
contract closure, producer authority, policy, limits and current authorization.
Graph-wide static checking does not waive this admission. Preflight failure
causes zero local mutations. Effect members remain attempt_all and rows default
halt. Typed empty Results/receipt views preserve successful zero-item meaning.
No unit reads its own newly produced Effects as part of the same computation.

Local ObservationSet and Invocation remain immutable. Completion evidence binds
the original OperationRef and finite contract separately; accepted success is
not provider completion. Normal successors need the graph's control milestone
AND binding readiness, including completion-only values after accepted edges.
The same contracts apply to extracted Programs and direct graph authoring.

Recovery MUST preserve original observations and durable item keys; successful
items are not resent and unknown reconciles before any eligible retry.
Cancelled checkpoints do not become pending. Immutable attempts link their
history. New graph revisions require explicit admission/recovery links;
resume retains its starting semantic/engine pins. Captured source checkpoints
are pending until common commit-scope eligibility is verified, not merely until
the capture unit succeeds. The separately authorized exceptional path below is
not implicit success, automatic compensation or unrestricted cursor movement.

<a id="numeric-observation"></a>

### Numeric observation capture

<!-- requirement-block: numeric-observation.product-1821bc23c5d0 -->
The closed binary64 sum/avg boundary in Language applies equally to local and
remote placement. Its adopted values MUST be durably captured before consumers
or Effect Preview. Replay reads the exact observation and issues no aggregate
provider call or local recomputation. Empty aggregates retain their typed NULL
law; exact count/decimal/proved integer lanes remain deterministic computations.
The captured slot includes input/contributor identity, group/window, count,
numeric law, adopted value, policy and accounting. Slot preimages contain no
future Stage Invocation identity. Host-selected placement cannot weaken
authorization, structural aggregate semantics, demand or finite bounds.

<a id="run-admission"></a>

### Run admission and identity

Connector and Effect access occurs only after capability admission by the Host;
checking is not admission ([Validation](language.md#validation)).

<!-- requirement-block: run-admission.denial-must-occur-before-execution-or-effect-application-and-must run-admission.denial-must-occur-before-execution-or-effect-application-and-must.second -->
A capability profile MAY deny any connector, source, algebra, operation,
effect kind, target, permission, row-count limit, or region policy. Denial MUST
occur before execution or effect application and MUST identify the rejected
capability.

ActQL validation does not grant authority. A valid program may still be denied
by host policy.

<!-- requirement-block: run-admission.program-source-must-not-contain-allow-review-approve-checkpoint-or -->
A Host executes one checked Plan as a durable Run. Approval is not an ActQL
operation, SourceView mode, Effect kind, or author-selected policy. Program
source MUST NOT contain `allow`, `review`, `approve`, `checkpoint`, or recovery
control that changes Host admission.

<!-- requirement-block: run-admission.the-host-must-record-an-admitted-allow-or-approved-decision run-admission.plan-execution-must-not-start-without-valid-run-authorization -->
Run-start admission uses `actql-run-policy/0.1` to evaluate the bound
Invocation Template and Compiled Plan in the authenticated execution context.
The `actql-prepared-invocation/0.1` artifact binds that template, Plan, policy
decision, context, and expiration; it is not the concrete Invocation whose
observations are captured later ([Capture, execution, and replay](#capture-and-replay)). The Host MUST record an admitted
`allow` or `approved` decision as `actql-run-authorization/0.1` bound to that
exact Prepared Invocation. An `approved` decision requires verified
Checkpoint Resolution evidence. Plan execution MUST NOT start without valid
Run Authorization. Preparation and its Checkpoints may precede that
authorization; they do not authorize execution. Run Authorization does not
waive per-unit, provider-access, or Effect-commit checks.

<!-- requirement-block: run-admission.the-run-definition-must-refer-to-the-plan-invocation-template run-admission.it-must-remain-unchanged-across-checkpoint-pause-resume-retry-and-reconciliation -->
One immutable `actql-run-definition/0.1` anchors each admitted durable Run. It
binds `scope_id`, `run_id`, `compiled_plan_cid`, `invocation_template_cid`,
`authorization_context_cid`, `input_artifact_set_cid`, `created_at`, and
`valid_until`, and is identified by `run_definition_cid`. The Run Definition
MUST refer to the Plan, Invocation Template, and authorization context admitted
by the Run Authorization. It MUST remain unchanged across Checkpoint
pause/resume, retry, and reconciliation; changing continuation state is recorded
separately.

<!-- requirement-block: run-admission.a-host-must-not-add-later-captures-to-that-initial -->
Prepared Invocation records the preparation submitted for admission, whereas
Run Definition fixes the identity and captured starting inputs of one durable
execution. Neither artifact substitutes for the other or grants authority by
itself. The Run Definition's `input_artifact_set_cid` identifies the initial
captured inputs, not the complete ObservationSet: subsequent acquisition
evidence belongs to the Run's captured unit outputs and receipts ([Capture, execution, and replay](#capture-and-replay)).
Preparation acquires any protected starting inputs only after the corresponding
preparation Checkpoint is resolved. The initial input set is sealed before Run
Definition creation; it may be empty when all observations are later Plan
acquisitions. A Host MUST NOT add later captures to that initial set.
Persisted continuations also bind the Host's versioned continuation-format and
execution-implementation identity. Resumption requires those bindings or an
explicitly admitted state migration; semantic Contract pinning alone does not
establish continuation compatibility.

<!-- requirement-block: run-admission.a-checkpoint-pause-or-same-run-retry-must-reuse-captured-observations -->
A captured stage attempt contains at most one established Invocation. An attempt that ends before all
required observations have been captured has none. A Checkpoint pause or
same-Run retry MUST reuse captured observations and unit outputs, rather than
establish a different Invocation for that captured attempt. An explicitly
authorized fresh-observation revision creates a new stage attempt/Invocation;
it is not same-observation replay and cannot resend already applied items.

<a id="run-states"></a>

### Run states and transitions

The public Run state is exactly one of the following. These are portable
lifecycle states, not a Host's worker, scheduler, or storage implementation
states.

<!-- requirement-block: run-states.state-meaning-terminal-preparing -->
| State | Meaning | Terminal |
| --- | --- | --- |
| `preparing` | Initial preparation is in progress; execution still requires admission. | no |
| `running` | Admitted initial execution is in progress. | no |
| `waiting_checkpoint` | A sealed Checkpoint prevents the protected continuation from executing. | no |
| `resuming` | An approved Resolution has authorized continuation of the same Run. | no |
| `needs_reconciliation` | One or more Effect outcomes remain unknown. | no |
| `succeeded` | Required computation and Effect receipt aggregation completed successfully. | yes |
| `failed` | The Run ended unsuccessfully, with no unresolved Effect outcome. | yes |
| `cancelled` | Preparation or a paused continuation ended without further dispatch. | yes |

<!-- requirement-block: run-states.public-state-changes-must-follow-this-table-and-the-referenced -->
A Host MAY create the initial public record as `preparing`, or as `running`
when initial admission has completed. Public state changes MUST follow this
table and the referenced conditions. Internal progress that does not change
the public state does not require a new state name.

<!-- requirement-block: run-states.from-to-required-condition-preparing -->
| From | To | Required condition |
| --- | --- | --- |
| `preparing` | `running` | Initial admission completed; execution may begin. |
| `preparing`, `running`, `resuming` | `waiting_checkpoint` | The exact continuation and Checkpoint were persisted before protected dispatch ([Checkpoints and Resolutions](#checkpoints)). |
| `waiting_checkpoint` | `resuming` | A Host-verified approved Resolution and unique resume intent were stored atomically ([Checkpoints and Resolutions](#checkpoints)). |
| `waiting_checkpoint` | `cancelled` | The Checkpoint was rejected or expired without dispatching its continuation. |
| `preparing`, `waiting_checkpoint`, `resuming` | `cancelled` | Cancellation was admitted with no dispatch in flight or unresolved Effect outcome. |
| `preparing`, `running`, `resuming` | `succeeded`, `failed`, `needs_reconciliation` | The continuation completed or failed; admission, publication, and Effect aggregation conditions determine the destination ([Capture, execution, and replay](#capture-and-replay), [Outcomes and reconciliation](#reconciliation)). |
| `needs_reconciliation` | `needs_reconciliation`, `succeeded`, `failed` | A valid reconciliation receipt extended the sealed member history and all member outcomes were aggregated ([Outcomes and reconciliation](#reconciliation)). |

<!-- requirement-block: run-states.a-transition-must-not-dispatch-a-continuation-across-an-unresolved run-states.a-terminal-state-must-not-transition-to-another-state -->
A transition MUST NOT dispatch a continuation across an unresolved Checkpoint.
A terminal state MUST NOT
transition to another state. Exact redelivery of already committed evidence
is idempotent; conflicting terminal evidence is rejected. Cancellation does
not roll back previously applied Effects. An `accepted` asynchronous Effect
can complete its Run while its provider operation remains pending ([Outcomes and reconciliation](#reconciliation)).

<!-- requirement-block: run-states.run-creation-and-lifecycle-operations-must-expose-the-closed-actql-run-state-0-2 -->
Run creation and lifecycle operations MUST expose the closed
`actql-run-state/0.1` projection: Run identity, current state, update time,
optional Checkpoint identity, result availability, and one state-consistent
next action. Result Manifests, Result payloads, and restricted Review
Projections are retrieved separately under their respective authority and
policy checks.

<a id="checkpoints"></a>

### Checkpoints and Resolutions

<!-- requirement-block: checkpoints.the-human-review-view-for-a-waiting-checkpoint-must-render checkpoints.machine-run-state-must-remain-separate checkpoints.it-must-not-embed-restricted-projection-contents -->
The human review view for a waiting Checkpoint MUST render the exact stored
review projection bound by that Checkpoint. Machine Run state MUST remain
separate. It MUST NOT embed restricted projection contents.

<!-- requirement-block: checkpoints.external-work-must-not-cross-an-unresolved-checkpoint -->
The Host divides the Plan into runtime units at external boundaries. A runtime
unit is the smallest physical fragment that can execute under one closed
capability, policy, and resource envelope without pausing. It is not an authored
ActQL step. Physical grouping and optimization follow the preservation
requirements in [Scope and conventions](language.md#scope). External work MUST NOT cross an unresolved Checkpoint.

Immediately before a unit may access a provider or commit an Effect, runtime
preflight returns exactly one result:

```text
allow       execute the unit
deny        terminate the Run without dispatching the unit
checkpoint  persist a sealed Checkpoint and stop before dispatch
```

Checkpoint message variants and authenticated decisions use the Run protocol binding.

<!-- requirement-block: checkpoints.the-host-must-reuse-already-captured-unit-outputs checkpoints.the-host-must-not-silently-regenerate-a-new-review-artifact checkpoints.before-dispatch-after-a-delayed-resolution-it-must-revalidate-the -->
An approved preparation Resolution continues the same preparation attempt;
an approved Run-unit Resolution resumes the same Run and continuation. The Host
MUST reuse already captured unit outputs. The Host MUST NOT silently regenerate
a new review artifact under the old approval. Before dispatch after a delayed
Resolution, it MUST revalidate the bound authorization-context and
environment-binding CIDs. Artifact availability and exact target freshness are
then revalidated at their existing provider-access and Effect-commit boundaries.
If those facts changed, the Checkpoint is invalidated or the Run fails; the Host
does not weaken or reinterpret the old approval.

<!-- requirement-block: checkpoints.every-path-backed-run-input-and-model-replay-bundle-must-be-captured -->
Every path-backed Run input and model-replay bundle MUST be captured as an
immutable private content-addressed artifact before a Run-scope Checkpoint can
be issued. The Prepared Invocation binds those captured locators; the admitted
Run Definition subsequently binds the same initial `input_artifact_set_cid`.
Execution reads only those captured locators, not their mutable source paths.

<!-- requirement-block: checkpoints.a-host-policy-denial-must-be-decided-before-reading-or -->
A Host policy denial MUST be decided before reading or capturing path-backed
Run inputs, creating private invocation artifacts, or creating durable Run
state. Denial evidence belongs to Host audit rather than to a Run that has not
started.

<!-- requirement-block: checkpoints.current-effect-policy-identity-must-bind-both-the-policy-contract-cid -->
Current Effect policy identity MUST bind both the policy-contract CID and the
evaluated `allow`, `review`, or `deny` decision, and that complete identity is
revalidated before resumed Effect dispatch.

<!-- requirement-block: checkpoints.an-expired-or-superseded-resume-claimant-must-not-release-fail checkpoints.a-resumed-run-transition-and-resume-intent-completion-must-occur-in -->
An expired or superseded resume claimant MUST NOT release, fail, complete, or
otherwise alter a resume intent or its Run. A resumed Run transition and
resume-intent completion MUST occur in the same transaction; the portable store
does not expose intent-only successful completion.

The Effect Set proposal and commit boundary follow [Effect declarations](language.md#effects) and [Effect preview, approval, and application](#effect-application). When review
is required, the complete Effect Set Preview is the sealed artifact of the
Effect Commit Checkpoint; its Resolution resumes the same Run's Effect application.

<!-- requirement-block: checkpoints.a-multi-effect-set-must-enter-that-effect-commit-checkpoint-even -->
A multi-Effect Set MUST retain authenticated `partial_application_accepted`
evidence from a human or policy issuer. Resolved `allow` does not add a human
Checkpoint merely because there are multiple members. `require_review` uses
one Checkpoint for the complete stage Preview. Run-level allow is insufficient
unless the current concrete scope is proved inside its admitted envelope.

<!-- requirement-block: checkpoints.actual-requests-must-remain-a-subset-of-that-envelope-and -->
For data-dependent acquisition, a Checkpoint review projection MAY display the
bounded envelope rather than identifiers unavailable before the read: source,
request fields, maximum item and byte scope, destination, classification, and
other policy facts. Actual requests MUST remain a subset of that envelope and
are bound by the Run Receipt. When policy requires a person to inspect exact
identifiers produced by an earlier unit in the same Run, it MAY pause after
those identifiers are durably materialized and before the next provider
dispatch. This remains a same-Run Checkpoint, not the later-work boundary in
[Boundary with later work](#later-work).

<a id="effect-application"></a>

### Effect preview, approval, and application

<!-- requirement-block: effect-application.when-approval-is-required-its-attestation-must-sign-the-effect effect-application.when-approval-is-required-its-attestation-must-sign-the-effect.second -->
Approval requirements come from Host and Contract policy; source validation
does not approve a concrete Effect.
Parameter declarations, authored Mapping or Command Contract references, and
Effect semantics belong to Program identity. Resolved permission sets and
Contract evidence belong to checked Plan and Effect Preview identity, not to
author-declared Program fields. Concrete bindings and typed parameter values
belong to Invocation and Effect Preview identity as specified in [Canonical identities](language.md#canonical-identities).
The exact target set and before/after rows belong to the Effect
Preview CID. When approval is required, its attestation MUST sign the Effect
Preview CID, and the apply receipt MUST bind both the preview identity and
approval evidence. When current Host policy and the Contract minimum both
allow direct commit, the receipt instead records that no approval attestation
was required.

Resolved approval is the monotone maximum of the Mapping or Command Contract
minimum and the current Host minimum. Host policy MAY strengthen an internally
resolved no-minimum policy to `required`, but it cannot weaken a contract
minimum. The absence of approval syntax does not grant permission to bypass
approval.

<!-- requirement-block: effect-application.they-must-not-make-structural-or-authority-choices-such-as -->
ActQL 0.1 parameters follow [Parameters and binding](language.md#parameters). They MUST NOT make structural or authority
choices such as effect kind, mapping, target, or failure policy
invocation-variable. `max_items` is a numeric author guard, not an authority
choice, and MAY be parameterized under [Parameters and binding](language.md#parameters).
Literal selector IDs MAY be typed parameters. Changing them changes Invocation
and Effect Preview CIDs and invalidates approval of the previous preview.

<!-- requirement-block: effect-application.create-must-not-combine-from-result-name-with-a-payload -->
Effect authority uses only the keys defined by this specification. `create`
MUST NOT combine `from: {result: name}` with a payload. Command has no payload or
mapping form.

<!-- requirement-block: effect-application.it-must-not-rerun-the-program-sourceviews-or-modeltasks effect-application.preview-must -->
During one durable Run, the Effect Set proposal unit consumes the Captured Run
defined in [Capture, execution, and replay](#capture-and-replay). It MUST NOT rerun the Program, SourceViews, or ModelTasks.
Preview MUST:

- resolve every member's exact scope and enforce its resolved item limit;
- emit before/after evidence when the Connector's admitted preview capability
  supplies that evidence ([Preview strength, scope, and freshness](#preview-strength));
- derive a stable row-level idempotency key for each change;
- bind each applicable AoA effect-plan CID and resolved Mapping or Command
  Contract CID;
- emit the complete `effect_preview_cid`; and
- report `executed: false`.

<!-- requirement-block: effect-application.when-review-is-required-the-runtime-must-pause-at-one effect-application.the-host-must-preflight-every-member-before-the-first-mutation effect-application.before-the-first-mutation-dispatch-a-data-connector-must-advertise -->
Application remains a separate host-authorized phase inside that Run.
When review is required, the runtime MUST pause at one Effect Commit
Checkpoint bound to the complete previewed Effect Set. Resolving that
Checkpoint resumes the same Run; no interface may
release a subset. The host MUST preflight every member before the first
mutation dispatch. A multi-Effect set additionally
requires authenticated human or policy acceptance of partial-application risk
bound to its exact Preview and review projection. Before the first mutation
dispatch, a data Connector MUST advertise exact
mutation atomicity, row-error identity, idempotency, request-order behavior,
and unknown-outcome reconciliation. `store` remains relation materialization
and is not generalized into binary upload.

> **Note (informative):** `partial_application_accepted` records a reviewer's
> acceptance of business risk, not a compiler proof of atomicity.

`present` is the observed before row or proposed complete after row.
`absent` means no row exists (create-before or delete-after), not an unknown
value. `unavailable` means a complete state is not known: targeted preview
uses it for before and, unless deleting, after, and records its exact intended
changes and target guard separately. Commands and non-row artifacts use
`not_applicable` where no row state is defined. Both members are required;
null, omission, and an empty object are not alternative encodings of these
states. A present empty row is `{state: "present", value: {}}`.
Redaction belongs to the public projection, not to private state evidence.
The normative row idempotency key is then:

<!-- requirement-block: effect-application.actql-row-idempotency-key -->
<!-- normative-code: envelope -->
```text
CID({
  version: "actql-row-idempotency-key/0.1",
  logical_request_scope_cid,
  effect_preview_cid,
  row_or_item_key
})
```

For `update`, `upsert`, and `delete`, `target_row_identity` is the validated
target primary-key value. For `command` the item key binds Command semantics,
target ResourceRef identity and canonical payload CID, not the target alone.
For `create` and relation-valued
`store`, preview rows are first ordered by `content_cid`; their identity is
`{content_cid, occurrence}`, where `content_cid` is the CID
of `{version: "actql-effect-content-row/0.1", value: after}` and `occurrence`
is the zero-based count among canonical-content-identical rows. This makes batch
order and idempotency independent of provider enumeration without collapsing
intentional duplicate rows.

<!-- requirement-block: effect-application.two-conforming-implementations-must-produce-the-same-row-key-for policy-routing.product-e8810b68bee2 policy-routing.product-f9a159648240 logical-request.product-2af972f63b66 logical-request.product-5fbdd5fa2eb2 logical-request.product-c3acfb1394ec logical-request.product-a93ff1904dcb -->
`effect_identity_cid` binds the local Unit Definition CID and local Invocation,
Effect ID, canonical Effect semantics, the exact Result Artifact
CID when a Result is consumed, and the resolved Mapping or Command Contract
CID. Physical Run identity is excluded. Recovery across workers or physical
attempts reuses logical request scope and the original ledger Preview/key.
Create/store rows use only `{content_cid, occurrence}` as row identity;
there is no second ordinal identity. Two conforming
implementations MUST produce the same row key for the same canonical preview.

The Effect apply key is
`CID({version: "actql-effect-apply-idempotency-key/0.1",
logical_request_scope_cid, effect_preview_cid, effect_id, effect_member_preview_cid})`. Thus an exact
Effect Preview redispatch reuses the same key, while a changed Effect,
Contract, target row, intended change, or new logical request produces a different
identity. A new physical recovery Run does not by itself create a new business
request. Ledger lookup precedes refreshing any Preview of possibly dispatched work.

<a id="policy-routing"></a>

### Semantic risk routing

Approval routing MUST NOT consume Effect/stage counts, multiple/later flags,
array lengths, source AST, arbitrary metadata or equivalent proxies. Moving a
count rule into a Connector minimum is still prohibited. Current semantic risk
may include operation, target scope, permissions, classification/egress, actual
logical item/record count, amount/cost/write bytes, irreversibility, partial
application and reconciliation capability, actor and current allowances.
One 1000-item Effect is not presumed safer than two one-item Effects.

Packaging independent work without changing action semantics, failure guarantees
or authority MUST NOT change review routing. Provider atomicity or real ordering
changes are not such a packaging equivalence. Cumulative risk/spend uses logical
request or explicit operational-period scope, not a reset per stage. Unknown
future values use finite reservations and concrete admission, not forced review
based on stage count. Node-count capacity is separate, not review-overridable.
Record the exact semantic facts and rule identity: allow records policy acceptance,
require_review creates the local Checkpoint, deny dispatches nothing. A legitimate
Contract minimum still applies. Graph launch allowlists remain separate admission.

<a id="logical-request"></a>

### Logical request and item recovery

Target identity reuses scoped ResourceRef/Mapping identity; item identity reuses
the row key, Command namespace/target/payload tuple or create occurrence. Only
the stable ledger locator and exact dispatch key are new runtime key roles;
four roles do not require four artifact families. Locator uses the typed unit
namespace and stable Effect site/correlation, never enclosing revision CID or
provider return order. Ledger records retain the admitted local definition,
intent fingerprint and original revision membership to detect changed payload.
Same request id with a different revision/values/input intent is a conflict.
An authorized recovery link explicitly binds old/new graph, retained successes,
reusable observations/Previews and changed work. New requests intentionally do
not inherit earlier success; D6 is not cross-request event deduplication.

The authenticated tenant/workspace plus caller request ID identifies one logical
request. A CLI without a caller ID creates, persists and returns one; a new
business request gets a new ID, while resume/recovery carries the original.
The request fingerprint binds Program Definition, effective parameters and
caller input intent, not physical workers, attempts, secrets or wall clocks.
The same scoped ID with a different fingerprint MUST fail as a conflict.
Separate scoped IDs permit intentional repeated business requests.

The following CID preimages are closed. CID fields identify canonical envelopes
without self-CIDs; schema/law IDs are pinned by the checked contract.

```text
LogicalRequestScope = CID({version: "actql-logical-request/0.1",
  authority_scope_cid, caller_request_id})
LogicalItemLocator = CID({version: "actql-logical-item/0.1",
  logical_request_scope_cid, unit_namespace, effect_id,
  item_correlation})
DispatchKey = CID({version: "actql-row-idempotency-key/0.1",
  logical_request_scope_cid, effect_preview_cid, row_or_item_key})
```

The locator finds durable recovery state; the dispatch key binds the exact
Preview. Recovery MUST reuse the ledger's original Preview, key and canonical
request. Physical Run/attempt/worker IDs are audit provenance, never direct or
transitive inputs to these keys. Preview meaning excludes the derived key,
authorization timestamps and physical Run identity. The Effect-level apply key
binds logical request scope, exact set Preview and member identity, not a new
physical attempt. The same key with a different request is invalid.

Before dispatch the Host MUST durably reserve the item and canonical request
under states `prepared|dispatching|applied|accepted|failed|unknown`, with fencing
against concurrent or superseded workers. Lost response after possible dispatch
is unknown. Applied/accepted results are replayed without dispatch; accepted
retains its OperationRef. A store ledger alone does not prove provider exactly-once.
Renewing an undispatched Preview requires proof of no dispatch, retiring its
reservation and linking the new key. After possible dispatch, reconcile first.

The recovery contract is `native`, `stamped`, `natural_key` or `unavailable`.
Native binds provider idempotency and exact-request reconciliation. Stamped
requires business mutation and stamp in the same provider commit unit; separate
stamp writes are unsafe. Natural-key reconciliation requires scoped uniqueness
and exact-request matching, not merely a matching row. Unavailable permits the
first authorized dispatch but prohibits automatic resend after uncertainty.
`not_applied` evidence excludes delayed indexing, an in-flight original request,
late commits and incomplete read scope. Unknown is not ordinary failed.

Stamp writes MUST be included in permission and footprint evidence. Preview
binds a stamp derivation recipe, not a value hashed from that Preview; after key
derivation the adapter inserts and validates the stamp. Both business-payload
CID and final transport digest are retained. Retention/recovery horizon and
attempt/cost/deadline bounds persist across recovery. Missing/expired records
are not proof of a first request; expiry never clears unknown uncertainty.

<a id="preview-strength"></a>

#### Preview strength, scope, and freshness

Every preview declares one of:

- `full_diff`: exact target identities, before/after, and target versions;
- `targeted`: exact target identities and intended after/change with before
  unavailable, guarded by a connector target version; or
- `blind`: exact target scope cannot be resolved.

<!-- requirement-block: preview-strength.a-blind-preview-may-be-displayed-but-must-not-be -->
`update`, `delete`, and update-side `upsert` are apply-admissible only as
`full_diff` or version-guarded `targeted`. `create`, `command`, and `store` do
not require before state; command admissibility also depends on its declared
preview strength. A `blind` preview may be displayed but MUST NOT be
applied.

The resolved item limit counts created rows for create, unique target identities for
update/delete, unique upsert keys for upsert, logical target-plus-payload items for command,
and output relation rows for store. ActQL 0.1 has no scalar/file store effect,
so a relation is not counted as one artifact. Duplicate mutation identities
are invalid rather than collapsed. Mapping/type failures abort preview before a
scope is approved and cannot be omitted from the count.

Row order is canonical target identity order for update/upsert/delete,
target identity then canonical payload CID for command,
and `(content_cid, occurrence)` order for create/store. `halt` and
`continue` operate on that order. Their dispatch rules are:

<!-- requirement-block: preview-strength.current-row-outcome-halt-continue -->
| Current row outcome | `halt` | `continue` |
| --- | --- | --- |
| `applied` or valid `accepted` | Dispatch next row | Dispatch next row |
| `failed` | Later rows unattempted | Dispatch next row |
| `unknown` | Later rows unattempted; reconcile current row | Dispatch other rows only; reconcile current row without resending it |

Admission/preflight failure dispatches no rows under either policy. Per-item
continuation does not override whole-set preflight or the Effect Set's separate
`attempt_all` member policy. Receipt partitions retain all five outcomes;
`accepted` does not assert provider completion ([Outcomes and reconciliation](#reconciliation)).

<!-- requirement-block: preview-strength.the-host-must-not-silently-regenerate-a-new-preview-and -->
Apply admission revalidates the exact source binding, resolved mapping
contract CID, capability evidence CID, authority-scope CID, and every target
version/content guard from the preview. Any difference is `stale_preview`; all
preview rows remain unattempted. The host MUST NOT silently regenerate a new
preview and reuse the old approval.
The apply admission map `current_target_versions` is keyed by
`row_preview_cid`; its value is the connector's current target version/content
CID for that exact preview row. Missing evidence is a mismatch, not a waiver.

<!-- requirement-block: preview-strength.before-the-first-mutation-dispatch-apply-admission-must-also-prove approval-renewal.product-47a0b238db29 approval-renewal.product-b51e19af3303 -->
Before the first mutation dispatch, apply admission MUST also prove that connector
capability evidence can realize the authored failure policy exactly. The
capability contract records mutation atomicity (`per_item`,
`provider_batch_atomic`, or `unknown`), failure granularity, request-order
preservation, row-error identity, native/emulated/unavailable idempotency, and
unknown-outcome reconciliation. `continue` requires exact per-item outcomes;
`halt` additionally requires preserved canonical request order. If these
conditions are unavailable, apply is rejected as unsupported rather than
approximated with provider batch behavior.

<a id="approval-renewal"></a>

### Preview renewal and template authorization

Stale detection remains exact. Host policy may authorize a new Preview after
evaluating the exact difference, but MUST issue fresh renewal and authorization
evidence rather than reuse an old approval silently. Evidence binds old/new
Preview CIDs, original approval, diff, current guard and permissions, payload
and scope comparison, policy rule, issuer and expiry. Read dependencies,
selection and model/numeric observations matter even if writable fields do not
change. New business observations require a new Stage Invocation. A bounded
refresh loop shares attempt/cost/deadline limits. Schema/lock compatibility
renewal is deferred and is not target-state drift tolerance.

A template approval binds the local Unit Definition and used effective parameters,
known input artifacts, producer/effect and receipt contract, item correlation,
fixed Connector/Resource/operation/write fields/payload, scope ceilings, allowed
typed ID/Ref substitution slots and uses, issuer, policy, expiry, review context
and risk claims. Static eligibility proves no fresh business-observation
dependency. Concrete instantiation separately proves only the permitted
producer's IDs/Refs occupied those slots without changing amount, operation,
destination kind, writable fields or authority scope.

Template approval MUST NOT authorize arbitrary receipt strings or computations
as ID substitution. A fresh business read, infer or numeric observation affecting
a write disqualifies this narrow template path; ordinary concrete policy allow
can still authorize the stage. Current rights and target-guard checks are not
themselves new business inputs. A valid template and instantiation produce new
exact-Preview authorization evidence, not a copied signature. Changed metadata
requires a new review projection and attestation, even with unchanged computation.

<a id="reconciliation"></a>

### Outcomes and reconciliation

A typed command returns exactly one `EffectOutcome`:

```text
applied  final result is known
accepted provider returned operation_ref<operation>; final result is pending
failed   final structured failure is known
unknown  transport ended without a provable provider outcome
```

<!-- requirement-block: reconciliation.a-completed-operation-must-not-be-cancelled reconciliation.an-expired-operation-must-not-be-applied-or-cancelled reconciliation.a-runtime-must-not-turn-transport-timeout-into-failed-or -->
`accepted` binds the OperationRef, poll contract, cancellation capability,
result schema, optional expiration, and reconciliation contract. `unknown`
binds command identity, reconciliation contract, reason, and a required
idempotency key.
Runtime reconciliation uses only the Connector contract that owns the
OperationRef; cancellation is admitted only when that command contract declares
cancellation. Provider-operation cancellation is terminal and idempotent.
A completed operation MUST NOT be cancelled. An expired operation MUST NOT be
applied or cancelled. A runtime MUST NOT turn transport timeout into `failed`
or retry an unknown outcome without its reconciliation and idempotency contracts.

<!-- requirement-block: reconciliation.before-the-first-mutation-dispatch-a-command-runtime-must-prove reconciliation.it-must-durably-bind-the-derived-idempotency-key-to-the reconciliation.an-identical-retry-must-replay-that-outcome-without-re-execution reconciliation.reuse-of-the-key-with-a-different-request-must-fail reconciliation.a-retry-must-not-erase-the-original-uncertainty-or-create -->
Before the first mutation dispatch, a command runtime MUST resolve its recovery
capability as native, stamped, natural_key or unavailable. Unavailable permits
an authorized initial dispatch but no automatic resend after response loss.
It MUST durably bind the derived idempotency key to the
canonical command request and its exact outcome. An identical retry MUST
replay that outcome without re-execution. Reuse of the key with a different
request MUST fail. These rules apply equally to final,
accepted, failed, and outcome-unknown command results. A retry MUST NOT erase
the original uncertainty or create a second operation.

A provider-native atomic batch is one typed command whose contract declares
`provider_batch_atomic`; it is not represented as several Effect Set members.
Effect Set ordering, atomicity boundaries, and the fixed `attempt_all` policy
are defined in [Effect declarations](language.md#effects). The receipt records actual dispatch sequence and partial
outcomes as evidence rather than an authored execution order.

<!-- requirement-block: reconciliation.run-linked-reconciliation-must-use-the-connector-environment-and-authority-binding -->
Run-linked reconciliation MUST use the Connector environment and authority
binding captured by that Run; an invocation-time Connector override is invalid.
Each `actql-effect-reconciliation-receipt/0.1` has these closed fields:

<!-- requirement-block: reconciliation.field-meaning-version-exactly-actql-effect-reconciliation-receipt-0-1 -->
| Field | Meaning |
| --- | --- |
| `version` | Exactly `actql-effect-reconciliation-receipt/0.1`. |
| `effect_id` | Member of the original Effect Set. |
| `effect_set_receipt_cid` | Exact pending Effect Set receipt. |
| `prior_receipt_cid` | Original member apply receipt, unchanged across attempts. |
| `attempt_sequence` | Positive attempt number, beginning at 1. |
| `previous_reconciliation_receipt_cid` | Immediately preceding attempt; absent on attempt 1 and required thereafter. |
| `terminal` | `false` exactly when `outcome.state` is `unknown`. |
| `operation_ref` | Operation correlation; mutually exclusive with command correlation. |
| `command_id`, `idempotency_key` | Command correlation; both required when `operation_ref` is absent. |
| `outcome` | One fully validated closed `EffectOutcome`, not just a state name. |
| `reconciliation_receipt_cid` | Self-CID of the receipt. |

<!-- requirement-block: reconciliation.the-host-must-validate-the-original-member-and-effect-set reconciliation.subsequent-receipts-must-extend-the-latest-receipt-for-the-same -->
The Host MUST validate the original member and Effect Set bindings before
accepting a receipt. Exactly one correlation form is required. Subsequent
receipts MUST extend the latest receipt for the same member, with
`attempt_sequence` incremented by one and its exact CID as
`previous_reconciliation_receipt_cid`.

<!-- requirement-block: reconciliation.exact-receipt-redelivery-is-idempotent-a-different-receipt-after-a -->
Only a nonterminal `unknown` outcome permits a further attempt. `applied`,
`accepted`, and `failed` close the chain. Exact receipt redelivery is
idempotent; a different receipt after a terminal attempt MUST fail as a
conflict. Thus `unknown → unknown → applied` is valid, but a terminal result
cannot be replaced by a later attempt.

<!-- requirement-block: reconciliation.initial-application-and-each-reconciliation-must-determine-the-run-outcome -->
Initial application and each reconciliation MUST determine the Run outcome
from every member of the original Effect Set, using its latest validated
outcome. The following table is evaluated from top to bottom:

<!-- requirement-block: reconciliation.effective-member-outcomes-run-state-any -->
| Effective member outcomes | Run state |
| --- | --- |
| Any `unknown` | `needs_reconciliation` |
| No `unknown`, but any `failed` or `unattempted` | `failed` |
| Every member `applied` or validly `accepted` | `succeeded` |

<!-- requirement-block: reconciliation.an-unknown-outcome-must-not-be-converted-to-cancellation-or -->
An unknown outcome MUST NOT be converted to cancellation or ordinary apply
retry. An `accepted` outcome counts as terminal success for the Run only with
its valid OperationRef and admitted status/cancellation contract. Its provider
operation may still be pending; observing its later result is separate work
([Boundary with later work](#later-work)).

<a id="source-state"></a>

### Source-state advancement

<!-- requirement-block: source-state.the-host-must-capture-each-connector-observation-before-computation-consumes source-state.the-host-must-retain-the-connector-s-next-checkpoint-as-pending source-state.failed-cancelled-or-unresolved-effect-outcomes-must-not-advance-it -->
The Host MUST capture each Connector observation before computation consumes
it ([Capture, execution, and replay](#capture-and-replay)). The Host MUST retain the Connector's next checkpoint as pending
state. The exact pending list is staged
under the durable Run, bound to the Captured Run's ObservationSet CID and each
checkpoint Contract CID, and the terminal transition API does not accept a
replacement list from its caller. The Store may commit that staged checkpoint
only after verified common commit-scope eligibility, including required
downstream milestones, using compare-and-swap on the previous generation.
Failed, cancelled, or unresolved Effect outcomes MUST NOT cause normal
advancement. The explicit operator path below is separate. A same-Run retry reuses the captured
ObservationSet instead of acquiring the SourceView again. Stale generations
and concurrent schedulers fail closed.

<!-- requirement-block: source-state.importing-a-private-content-addressed-source-state-artifact-must-match-the-program source-state.a-mismatched-or-conflicting-seed-must-fail-before-run-execution cursor-recovery.product-be2f85421b3a -->
Importing a private, content-addressed source-state artifact MUST match the
stable source ownership namespace, source-state requirement, checkpoint Contract,
authenticated revision membership, and current
authorization context. A mismatched or conflicting seed MUST fail before Run
execution. Import and migration command syntax is outside this specification.

<a id="cursor-recovery"></a>

#### Exceptional source-state advancement

The claim `source_state_advance_authorized` requires independent operator
authority; source read, Effect allow and partial_application_accepted do not
grant it. It is not Program syntax, metadata or a hidden force flag. Execution
MUST verify the common eligibility contract, authenticated issuer/tenant/scope,
policy revision, expiry/nonce, exact graph run and fenced state revision, captured
batch, pending checkpoint list, partitions and prior generations, and the exact
unmet obligations and outcome evidence.

Each obligation has a disposition. Known failed or unattempted work may be
`abandon_known_failure`; unknown or incomplete accepted work requires durable
`handoff`, retaining original intent, keys, OperationRef, ownership, retention
and resume/reconciliation rules. No disposition relabels an unknown as failed,
applied or not_applied. Missing handoff leaves the cursor pending. The operator's
reason and displayed loss/delay risk are signed review evidence. Exceptional
commit does not satisfy success edges or create a successful business receipt.

Unmet obligations are an explicit tagged union: kind node_milestone or
effect_item, bound by obligation_cid to the sealed scope/gate and exact producer
or item. State preserves original failed, unattempted, unknown, accepted_pending,
cancelled, timed_out, budget_exhausted or rejected evidence. Node cancellation,
timeout, budget exhaustion or rejection does not assert that its items were
unattempted. Every node-level entry includes the complete item-outcome evidence
set; applied results remain applied. If any descendant is unknown or accepted
without completion, durable handoff is mandatory for that outstanding subset;
abandonment of the enclosing cancelled node cannot bypass it. Proven no-dispatch
cancelled/expired-review work may be explicitly abandoned. Missing item/dispatch
evidence leaves uncertainty and cannot prove no application.

The common outcome mapping is total: completed/approved/effect.applied satisfy
only their declared computation/approval/item facts; effect.accepted contributes
accepted, effect.pending contributes accepted_pending when a verified acceptance
exists, effect.unknown maps unknown, effect.failed maps failed. Node failed,
cancelled, timed_out, budget_exhausted and rejected retain those exact states;
never-started work is unattempted. Unknown provenance remains unknown. Success
of a different fact is not success of an unmet node milestone. No source failure
handler is introduced and no terminal receipt is rewritten by exceptional commit.

The common graph protocol atomically establishes claim/disposition/ownership
and eligibility; Execution commits only the exact captured checkpoint under
generation CAS, with idempotent identical claim redelivery. Stale claims, changed
outcomes, foreign scope, expired authority and arbitrary caller checkpoints
fail before ack. Outbox/reconciliation records each partition ack; no distributed
transaction is implied. Original receipts remain immutable, including late
provider results. Pending batches retain their original logical request rather
than being refetched under a new request id.

<a id="runtime-failure"></a>

### Row rejection and runtime failure

<!-- requirement-block: runtime-failure.axis-meaning-value-validity-observed -->
| Axis | Meaning |
| --- | --- |
| Value validity | observed null or domain-level invalidity |
| Observation completeness | coverage of the declared acquisition scope |
| Execution outcome | the Run's success, failure, cancellation, or unresolved outcome |
| Delivery outcome | publication of retained Result bytes |

<!-- requirement-block: runtime-failure.acquisition-failure-must-not-satisfy-the-completeness-evidence-required-by -->
A nullable contract does not authorize conversion of acquisition failure into
null or an empty Relation. Proven absence, observed null, incomplete observation,
and acquisition unavailability are distinct. Acquisition failure MUST NOT
satisfy the completeness evidence required by an ordinary join, including an
anti join. Result completeness does not summarize execution or delivery failure.

Expected row-level invalidity is ordinary Relation data, not an ActQL runtime
error. A Program represents expected invalidity by:

1. converting an expected partial operation to an admitted total form when one
   exists, such as `try_number`;
2. deriving one or more explicit classification fields; and
3. constructing named Relation branches with ordinary predicates.

Accepted and rejected branches are ordinary named results. A Program SHOULD
retain a stable row identity and a stable rejection code so that no input row
is silently lost or admitted to both branches.

<!-- requirement-block: runtime-failure.these-spellings-must-not-catch-downgrade-or-datafy-a-runtime -->
ActQL 0.1 does not define `try`, `catch`, `recover`, `ignore_errors`,
`on_error: continue`, `on_error: nullify`, `errors_as`, `rejects_as`, an Error Carrier, or a general
Result/Either value type. It also does not add `validate` or `partition` as
special error-control operations. These spellings MUST NOT catch, downgrade,
or datafy a runtime failure.

Except for the explicitly admitted infer slot-level provider outcomes,
Connector authentication failure, provider timeout or refusal, schema
mismatch, bound exhaustion, unavailable Artifact data, and engine failure
remain Invocation or acquisition-barrier failures. Infer output schema_invalid,
refusal and exhausted finite provider retries may become typed outcomes under
its default publication law. Wrong input schema, authorization/egress denial,
invalid or unavailable Artifact, global capacity exhaustion, engine failure and
cancel remain barrier failures, never failure rows. No acquisition failure
becomes ordinary NULL or external absence. Strict infer publishes no Relation.
Effect outcomes remain
Effect Receipts. The same-Run and later-work boundaries are specified in
[Checkpoints and Resolutions](#checkpoints), [Source-state advancement](#source-state), and [Boundary with later work](#later-work).

Failure classification names the boundary where the failure originates. A
Lookup or Inference Barrier failure therefore remains an acquisition-barrier
failure even though atomic barrier failure also causes the enclosing Invocation
to fail. An engine failure originates at the Invocation boundary. This
classification does not permit partial output from either failure.

<!-- requirement-block: runtime-failure.event-required-treatment-business-required-value-is -->
| Event | Required treatment |
| --- | --- |
| Business-required value is null in a nullable field | classify with `derive`, then branch with `filter` |
| Expected number parse fails | use `try_number`, then classify its null result |
| Known business status is invalid | classify with an ordinary predicate |
| External keyed acquisition finds no row | follow the pinned SourceView cardinality contract and authored join kind |
| External keyed acquisition times out, is rate-limited, or cannot authenticate | preserve the Lookup Barrier failure |
| `infer` refuses or returns a schema mismatch | capture its typed failure outcome; strict opt-in fails publication; do not retry those classes |
| Artifact bytes are unavailable | fail before provider access |
| Effect fails or has unknown outcome | preserve the Effect Receipt; reconcile the durable Run or use a later Run Graph continuation |
| Engine failure | fail the Invocation |

<!-- requirement-block: runtime-failure.it-must-offer-guidance-rather-than-an-automatic-replacement-because -->
A checker SHOULD report
`ACTQL_E_ERROR_CONTROL_UNSUPPORTED` when error-control vocabulary is authored
where an operation, expression, or operation parameter is expected. It MUST
offer guidance rather than an automatic replacement because choosing which
invalidity is expected is a semantic decision.

<a id="later-work"></a>

### Boundary with later work

Checkpoint pause/resume and the Run Graph are distinct. A Checkpoint continues
the same captured stage without changing its meaning. Later stages within the
Program may consume completion and Effect receipts under the fixed activation
rules. General later work outside that finite sequence uses separate Runs and
the companion Run Graph. A Run Graph approval gate MAY lower to the same Host Checkpoint substrate;
it does not require a second approval engine.

Optional read collection ([Read collection protocol](protocols/collection.md#collection)) aggregates independent Run outcomes
and coverage evidence without changing ordinary join or inference failures.

<!-- stage-contract-pins:start -->
```text
../../spec/contracts/actql-stage-contracts.json#/laws sha256:540d06456c7ddf166f5192dd1379b853e48791ca869a54abcc428b2210097325
../../spec/contracts/actql-stage-contracts.json#/schemas/ledger_entry sha256:742fc9a5260f71181d27758aa842b1d674660c88b51c1bf8073370c7a9c5e57a
../../spec/contracts/actql-stage-contracts.json#/schemas/numeric_observation sha256:a6339065c171308f9c4fa637ce2110b75b5cbaa0a4d6d0e708ca52cef0d69688
../../spec/contracts/actql-stage-contracts.json#/schemas/commit_eligibility sha256:9d90efc4c81d15691e3c26d4a10a7252ff04c781a88afc387a69cdd22869d967
```
<!-- stage-contract-pins:end -->
