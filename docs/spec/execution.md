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
- [Managed retained execution profile](#managed-retained-execution)
- [Capture, execution, and replay](#capture-and-replay)
- [Program and stage execution](#stage-execution)
- [Numeric observation capture](#numeric-observation)
- [Run admission and identity](#run-admission)
- [Run states and transitions](#run-states)
- [Checkpoints and Resolutions](#checkpoints)
- [Effect preview, approval, and application](#effect-application)
- [Account authorization routing](#policy-routing)
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

<a id="managed-retained-execution"></a>

### Managed retained execution profile

<!-- machine-import: ../../spec/contracts/actql-managed-retained-execution.json# sha256:161b405aa85064521a44076212bb266d93f166fa1b383ca8948a87923d797527 -->
<!-- machine-import: ../../spec/contracts/actql-managed-retained-execution.json#/schemas/identity_status sha256:6e7214696a897447a4e6210f97dfc60530ba98353fc7915082fb3a02c1a23352 -->
<!-- machine-import: ../../spec/contracts/actql-managed-retained-execution.json#/schemas/physical_manifest sha256:335f62ce6abd4d68cc79130d3e2ca3af800d03ffc40d359f5af1d856e34fd850 -->

The [managed retained execution contract](../../spec/contracts/actql-managed-retained-execution.json)
defines `actql-managed-retained-execution/0.1`. It separates a completed,
retained logical value from establishment of its content identity. It applies
equally to one, two or many rows. This is an explicit alternative completion
contract, not an interpretation that removes required fields from existing
acquisition observations, process-evidence records, captured Invocations,
Result Artifacts, Manifests or Run Receipts. Those content-addressed contracts
and their preimages remain unchanged.

<!-- requirement-block: managed-retained.selection -->
A Host MUST select this profile explicitly through an admitted execution API,
derive obligations from checked semantics, adopted laws/proof assumptions,
consumers, publication contracts, policy and requested capabilities before
candidate comparison, and preserve those obligations across physical choices.
The scope is one managed Run including accepted local execution-process
delegation; arbitrary remote workers, cross-Run evidence reuse and restart
restoration are outside this profile. No new authored Program syntax selects
an issuer or asserts successful verification.

<!-- requirement-block: managed-retained.completion -->
Managed completion MUST establish the exact producer, attempt, input bindings,
output port, immutable material generation and logical view, together with
required semantic execution, validation, guards, authorization, holding,
publication conditions and admitted capabilities. Unrequested future replay or
conversion is not promised. A managed read handle is not an old Result Artifact
or content-addressed Invocation, even when their represented values are equal.

<!-- requirement-block: managed-retained.identity -->
Implementations MUST establish each required logical identity in its unchanged
adopted preimage domain by the obligation's deadline, preserve logical meaning
independently of physical format, and leave unrequired identity unestablished
without automatic background generation. An identity may remain unestablished
throughout the result's lifetime. CID-dependent tie breaks, selectors and
publication are deadlines; an implementation hash or physical manifest does
not substitute for that CID. Equal content never merges separate occurrences,
attempts, authorization or access evidence.

<!-- requirement-block: managed-retained.identity-state -->
Identity state MUST distinguish establishment from availability of its exact
source, separately for each subject and domain, including discarded validation
receipts versus retained selected output. The pinned `identity_status` schema
is a closed diagnostic representation, not transportable authority. A retained
source does not promise sufficient future authorization, resources or decoder
support; an established CID does not promise that the data remains readable.

<!-- requirement-block: managed-retained.physical-manifest -->
File/chunk representations MUST bind the pinned closed physical-manifest shape
to accepted conversion/execution evidence, verify exact stored-byte digests
and lengths at the storage/transfer boundary or reuse valid immutable-generation
evidence, and verify that codec-decoded row counts sum without overflow to the
manifest count. The manifest CID hashes its complete canonical JSON UTF-8 with
no self-CID; chunk CIDs hash exact bytes. Codec, schema and logical-view contract
pins define decoding and interpretation, and the chunk array defines ordered
concatenation, including repeated chunk occurrences. Empty output can have no
chunks. Metadata integrity alone establishes neither logical correctness nor
authorization. A managed resident table or memory result needs no forced
export solely to obtain a physical hash.

<!-- requirement-block: managed-retained.capabilities -->
Known requirements MUST be resolved before irreversible discard by establishing
the required identities/evidence or retaining their exact sources, whereas an
unknown later request receives additional admission against current source,
authority, holding, implementation and remaining budget. Ordinary failure of
that added request leaves prior valid completion intact. Detected corruption
instead revokes the affected representation. Conversion to a legacy contract
checks its complete required dependency evidence, not only the final Result
CID; Effect eligibility follows its particular contract, not a profile-wide ban.

<!-- requirement-block: managed-retained.evidence -->
Evidence reuse MUST match the exact material generation, ordered view, scope,
value interpretation, measurement unit, contract and authorized issuance
binding, using the registered finite inclusion and view rules with bounded
composition along actual checked transformations. Initial rules include
identical contracts, nullability, registered numeric intervals, same-unit
count/size bounds, projection/rename/copy, checked row selection/permutation
and unchanged derive columns. New values receive their necessary validation
and measurement, including reusable validated join/group output. Predicate
evaluation and required ordering are not discharged by input value evidence.

<!-- requirement-block: managed-retained.failure -->
Reuse MUST preserve specified demand, phase, failure precedence, logical
location and operation atomicity, adding inspection when a summary proves a
violation but cannot select the required diagnostic. Insufficient evidence is
neither success nor violation. Universal success transfers to an exact subset;
violation somewhere in a larger scope does not. Physical discovery order and
the old implementation's unnecessary costs are not semantic requirements.
Input admission scope is not narrowed by the consumer's own later filter.

<!-- requirement-block: managed-retained.fallback -->
Concrete reuse admission MUST occur before its consumer starts, with allowed
ordinary validation fallback using remaining resources when rules or evidence
are insufficient or reuse exploration reaches its own sublimit. Exhausted
global budgets, confirmed violations, corruption and authority loss are not
optimization misses; they cannot be hidden by resetting budgets or silently
retrying a failed consumer on another backend.

<!-- requirement-block: managed-retained.quantities -->
Implementations MUST preserve selected logical value-size and per-consumer
charge obligations while accounting separately for actual physical work,
memory, storage and transfer, permitting compatible exact measurements or
registered safe bounds to avoid repeated measurement. Canonical top-level
value bytes are not compressed file bytes and do not require whole row-array
JSON materialization. A skipped physical operation is not reported as executed.

<!-- requirement-block: managed-retained.use -->
Dispatch MUST acquire a pin on the exact generation, current use authority and
required resources with a defined outcome against concurrent reclamation.
Each consumer releases its own hold; completion of computation does not end a
promised Result retention period. Availability, use-authority expiry and
retention-prohibition deadlines remain distinct. Ordinary timeout stops new
use/publication and requests cancellation; strict stop/deletion deadlines
require a capable candidate rather than reinterpretation as ordinary timeout.

<!-- requirement-block: managed-retained.release -->
Cancellation and revocation MUST prevent stale session/delegate/attempt
responses from restoring completion or publication and retain resource
responsibility until access termination and physical reclamation are confirmed.
Finite renewable leases are permitted but a renewable-lease service is not
required. A valid independent protected copy has its own policy and holding
conditions, not an unconditional dependency on the source's continued lease.

<!-- requirement-block: managed-retained.relocation -->
Physical relocation MUST preserve logical values, order, multiplicity and
admitted capabilities through an adopted conversion rule that issues new
generation-bound evidence, retaining the source until the destination is
committed and charging overlap plus workspace. It does not relabel old evidence
or redo the logical computation. Required provenance need not retain unused
ancestor buffers. Failure preserves the original valid result and provisional
cleanup responsibility.

<!-- requirement-block: managed-retained.issuance -->
Host adoption MUST restrict issuance to registered implementation revision,
contract, evidence kinds/rules, representations and conditions, then grant
task/attempt/subject-limited capabilities; Core checks these bindings and
required completion conditions while the adopted implementation remains
responsible for actual content operations and resource reports. Fixed
registration and managed delegation suffice; this is not native sandboxing,
PKI or proof of issuer truth. Third-party implementations of existing rules
use Host adoption without backend-name branches in common Core.

<!-- requirement-block: managed-retained.conformance -->
Conformance claims MUST distinguish contract registration, limited formal
models and their assumptions, machine-checked bridges where existing theorem
coverage is claimed, independent implementation tests, and performance results.
Initial runtime acceptance covers ordinary supported transformation chains and
multiple consumers, repeated validated join/group output, and managed delegation
through use/cancellation/reclamation, including positive reuse without repeated
full conversion. Existing same-obligation benchmarks and new-profile benchmarks
are separate; neither a schema test nor a lower hash count establishes runtime
or performance conformance.

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

<!-- requirement-block: capture-and-replay.effect-source-artifacts-have-an-independent-exact-inventory capture-and-replay.effect-source-holding-is-independent capture-and-replay.effect-source-current-authority-is-checked-at-use capture-and-replay.public-result-is-not-a-substitute-for-effect-source -->
An Effectful Captured Run MUST retain an exact private inventory of the Stage
Result Artifacts consumed by Effect members, separate from the Program Result
Manifest inventory. Each entry binds the checked source Result occurrence,
source binding, Invocation, logical Relation, schema, policies, and Store
authority to the Preview member. Its holding is independent of publication
holding even when both share one immutable physical allocation. The holding
identity alone is not current availability or apply authority: durable Store
custody and current authorization MUST be checked at their respective use
boundaries. A differently named Program Result MUST NOT stand in for the
Effect source, and a missing source MUST NOT be inferred from a public Result.

Receipt dependencies are acyclic:

```text
Effect-free Run: final Run receipt → Captured Run → durable publication index
Effectful Run: computation receipt → Captured Run → Effect Preview
  → approval/apply/reconciliation receipts → final Run receipt
```

<!-- requirement-block: capture-and-replay.an-artifact-must-not-require-a-future-artifact-s-cid-in capture-and-replay.effectful-final-run-receipt-binds-complete-prior-chain -->
The computation receipt embedded in Captured Run contains no later Preview or
apply CID. A final Run receipt is a new artifact referencing the earlier
evidence, not a mutation of that captured receipt. The receipt schema may be
shared, but its pre-effect and final instances have distinct CIDs. An artifact
MUST NOT require a future artifact's CID in its own hash preimage.
In 0.1, an Effectful final Run Receipt carries `effect_preview_cid`,
`effect_set_apply_receipt_cid`, and `captured_run_cid` together. An Effect-free
Receipt and an Effectful computation Receipt omit all three. Final admission
MUST verify the exact checked Program kind and referenced Run chain; well-formed
CID strings alone do not establish those bindings.

<!-- requirement-block: capture-and-replay.an-effect-free-run-must-use-its-single-run-receipt-as-the-final-receipt -->
An Effect-free Run MUST use its single Run Receipt as the final receipt; it does
not create a second content-equivalent final copy. That Receipt references its
Manifest and Result Artifacts, the Captured Run references the Receipt, and the
durable publication index references the admitted complete chain. Creating or
storing the Receipt alone is not publication commit and does not establish the
public `succeeded` outcome.

<!-- requirement-block: capture-and-replay.given-the-same-canonical-plan-captured-observations-and-semantic-contracts capture-and-replay.delivery-bytes-must-also-be-stable-when-the-result-artifact -->
For the content-addressed capture/replay contract, given the same canonical
Plan, captured observations, and semantic contracts,
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

<!-- requirement-block: capture-and-replay.compiler-and-aoa-ir-versions-must-match-admitted-plan-provenance capture-and-replay.a-later-publisher-must-not-replace-admitted-version-provenance -->
The mandatory `compiler_version` and `aoa_ir_version` values use the bounded
version-token syntax registered by the Run Receipt machine schema. They come
from the provenance of the admitted compiled plan and AoA IR and MUST match the
referenced plan and IR evidence. A later publisher MUST NOT replace them with
the version of the currently running binary.

The admitted provenance is the exact `actql-compiled-plan/0.1` envelope named
by the Prepared Invocation's `compiled_plan_cid`. Run admission also checks its
`program_definition_cid` against the Bound Invocation Template. Receipt
issuance reads `compiler_version`, `aoa_ir_version`, `program_semantics_cid`,
and `aoa_logical_cid` from that retained admission; those fields are not
publisher inputs.

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

<a id="query-resource-scopes"></a>

### Acquisition and realization resource scopes

The distinction between logical measurement and physical measurement is not a
distinction between universal and implementation-selected limits. A logical
limit can belong to a selected fragment rather than to the acquisition itself.

<!-- requirement-block: query-resource-scopes.selection -->
Every candidate MUST enforce the same canonical acquisition guards and selected
source, expression-profile and consumer contracts. Selecting a Local fragment
adds that fragment's enforcement bounds to the Local realization; it does not
add them to the backend-independent acquisition requirement. A native candidate
that implements that same fragment contract remains subject to all its limits.
Neither placement nor a different evaluator permits waiving an explicitly
selected common contract. The initial scan/filter/select profile has no ordered
derive step: `request.row_kernel_limits` is absent, not an invented set of
filter/select limits or a zero-valued exemption.

<!-- machine-import: ../../spec/contracts/actql-query-resource-scopes.json# sha256:02442e1e38627268539cad1953144f3f136791344d1d4279768cdb45eb6bf471 -->
The [pinned resource-scope contract](../../spec/contracts/actql-query-resource-scopes.json)
distinguishes measurement, subject and binding at `/limits`. Acquisition `max_rows`
counts complete select-output occurrences, not scanned or received rows.
Acquisition `max_value_bytes` measures canonical typed-wire UTF-8 for each
admitted record and demanded expression root, not a sum or heap allocation.
The selected fragment's `request.max_rows` bounds logical rows at its input and
operation boundaries; its `max_value_bytes` bounds input, evaluated-root and
published values. Equal numbers do not make these scopes interchangeable.
Ordered step `max_input_rows`, `max_value_bytes`, `max_live_value_bytes` and
`max_work` retain the exact [ordered resource measures](language.md#derive).
In particular live roots and work are logical fragment-specific measures, not
DuckDB memory or instruction counts. The exact step limit body is bound through
the fragment request and evidence `limits_cid`; it is not a query-output guard.

<!-- requirement-block: query-resource-scopes.native -->
A native candidate MUST enforce the exact complete output count and per-value
typed-wire byte guards, with full source admission and checked expression demand,
without replacing these measurements by SQL storage sizes, estimates, receipt
sizes or counts after filtering when the subject is an input record. Exact
streaming counters and typed-wire measurement, or admitted provider evidence
for the same checks, suffice; executing the Local fragment again is not required.
Demanded intermediate roots still need evidence even when SQL does not return
them. Algebraically derived measurements are admissible only when exact for the
checked types, values and demand, not merely an estimated upper limit claimed
as an observation. A candidate without enforceable measurements and admissible
evidence is unsupported. This profile does not introduce native ordered-derive
support or a substitute work/live-root accounting rule.

<!-- requirement-block: query-resource-scopes.evidence -->
The authorized process issuer MUST bind successful guard enforcement to the exact
requirement, guard values, owner, Parameter bindings, task, attempt, consistent
read-view, applicable snapshot, checked demand and retained output. Source
validation covers input records, filter evidence covers demanded filter roots,
and select evidence covers projection and final row count. Existing opaque
execution records retain this ownership; SQL success, a bool or a self-hash
cannot establish it. Issuance follows all applicable checks and successful
retention. The existing single- and two-receipt wire forms are unchanged;
the additional enforcement facts remain owned by their trusted live issuer.

<!-- requirement-block: query-resource-scopes.failure -->
Implementations MUST accept equality and reject excess at each selected scope,
including checked accounting overflow, without successful capture after failure.
Empty output has zero rows but does not waive input admission or input budgets;
all-filtered input still requires complete source validation. Empty input incurs
no row evaluation, but framing, receipt and retention still use their own measures.
Input admission precedes predicate evaluation. Exhaustion of a physical or
selected realization budget can terminate the attempt before a later value
error; it does not require continued evaluation to find that error. With those
budgets sufficient, changing realization cannot hide an invalid unused source
field or demanded expression failure. Existing expression failure ordering
continues within its specified evaluation scope, not across physical candidates.

<!-- requirement-block: query-resource-scopes.consumer -->
Downstream consumer limits MUST remain bound to their own input and execution,
not be enlarged, reset or charged for the acquisition's residual evaluation.
A Local-only fragment limit can fail on valid input while a native realization
of the same acquisition succeeds under all its selected contracts. Such success
does not imply that the Local fragment would succeed, or that the downstream
consumer succeeds. A later consumer failure preserves the completed upstream
observation and does not authorize rereading. Actual engine work, each receipt
and retention copies retain their separate Host physical budgets and accounting;
two transfers are not hidden or conflated with logical output rows.

<a id="fixed-compute-capacity"></a>

### Fixed-input filter/select Compute capacity

<!-- machine-import: ../../spec/contracts/actql-fixed-compute-capacity.json# sha256:18acad6522ba361fe72b0de47e6ec7bf808423afe3e222739235d5101d72d88c -->
The [fixed-input capacity profile](../../spec/contracts/actql-fixed-compute-capacity.json)
applies to filter followed by select over one completed, retained ProducerRead.
It clarifies the application of the existing consumer capacity law, and fixes
the common-versus-realization selection boundary for this initial profile. It
does not change the consumer capacity law, its CID, or acquisition/receipt wire.
`FixedComputeRequest` names a Host-local owned request, not a new wire envelope.

<!-- requirement-block: fixed-compute-capacity.selection fixed-compute-capacity.no-acquisition-exemption -->
Before comparing candidates, the Host MUST bind explicit `max_rows` and
`max_value_bytes` with the exact `actql-consumer-capacity/0.1` contract CID to
the fixed input, its receiver/consumer owner, effective Parameters and checked
expression demand. Every candidate implements this same selection. Acquisition's
Local-fragment distinction MUST NOT exempt Compute from these consumer limits.
A fresh read, an equal-content input handle from another owner, a substituted
consumer or changed limits cannot replace this request. Successful acquisition
or capture does not establish successful consumer admission or computation.

<!-- requirement-block: fixed-compute-capacity.rows fixed-compute-capacity.values -->
The common `max_rows` MUST separately cap input occurrences before computation
and output occurrences before handoff. The common `max_value_bytes` MUST retain
the existing per-top-level-input-value, demanded-context-value, evaluated-root
and output-value canonical wire UTF-8 scopes, not whole-row, batch, transfer,
database storage or heap sizes. All known input fields obey their contracts,
including fields removed by select and rows removed by filter; input admission
precedes predicate evaluation. Undemanded expressions are not evaluated for
measurement. Demand, result contracts, relative input order and multiplicity
remain those of the checked filter/select. Physical enumeration does not become
new total-order evidence. Empty input and all-filtered output do not waive any
applicable input checks; empty input has no demanded row roots. Equality passes
and excess or accounting overflow fails the whole consumer without partial output.

<!-- requirement-block: fixed-compute-capacity.local-fragment fixed-compute-capacity.common-fragment -->
A fragment selected only to implement the Local candidate MUST retain its own
limits without imposing them on another realization. If the Host instead selects
that fragment contract as common to the request, every candidate MUST enforce
its exact limits and retain its exact consumer/Parameter ownership. Equivalent
reconstruction is not owner equality. Fragment input/operation-boundary rows,
value bytes and any applicable work/live-value measures keep their own subjects;
common consumer output rows cannot substitute for those counters. This initial
filter/select shape has no ordered derive and does not synthesize
`row_kernel_limits`. It adds no native implementation of ordered-kernel measures.

<!-- requirement-block: fixed-compute-capacity.native -->
Native eligibility MUST establish an admissible exact measurement/enforcement
path for every selected common scope before candidate selection. Known retained
row counts, streaming canonical-wire value meters, and exact measurements for
the checked demanded roots and operation boundaries may satisfy that path;
Local full recomputation is not required. Unreturned SQL roots still require
their exact checks. Estimates, SQL success, equal final results, physical memory
measurements or a capability boolean alone are insufficient. A candidate lacking
an exact path for a selected fragment measure is ineligible, not budget-exempt.
Completion evidence binds actual successful enforcement and output retention to
the same fixed input, consumer, Parameters, demand, selected limits, task and
attempt. It does not mint a new acquisition observation or infer source evidence.

<!-- requirement-block: fixed-compute-capacity.failure -->
A common guard violation MUST NOT be bypassed by changing candidates. A valid
input may exhaust a Local-only fragment budget while native succeeds under all
its selected contracts. Physical budgets remain candidate-specific, with engine
work, transfers and retained copies separately accounted. Such exhaustion may
stop before a later semantic error; cross-candidate diagnostic equality is not
required. With these budgets sufficient, invalid known input values and demanded
expression failures cannot be hidden. Consumer failure leaves the previously
completed input intact and does not authorize reacquisition. Correct filter/select
cannot expand the row count; output-guard rejection tests of an expanding native
result test faulty output, not an additional admitted operation.

<a id="query-process-evidence"></a>

#### Process-retained query evidence

<!-- machine-import: ../../spec/contracts/actql-query-process-evidence.json# sha256:5cbd39d6847336c5961e222b083ca1395ab68be466ac69cadfbf7021cf617b89 -->
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

<!-- requirement-block: query-process-evidence.host-adapter -->
A Host-local source adapter using this profile MUST be independently authorized
by the Host for the selected source and read extent, execute the required full
scan validation under the selected value contracts, and own live provenance
linking that validation and native query to the same requirement, attempt and
consistent source read view. This specializes the existing trusted-issuer route;
it does not exempt an external provider from source-attestation admission.
Running a driver inside the Host, read-only access, SQL success, a validation
boolean or a content hash alone establishes none of these facts. The adapter
ensures that filtering, projection, casts or engine coercions do not suppress
invalid source values before mandatory validation, and that native expression
semantics and failures match the checked operations. Otherwise native execution
is unsupported, even when the selected output would be well typed.

<!-- requirement-block: query-process-evidence.read-view-ownership -->
The issuer and capture verifier MUST retain and check the owned read-view binding
for validation and query, including the actual session/transaction lifetime when
that is the adapter's consistency mechanism, rather than trusting submitted
identifiers or identical rows. A same-connection read transaction is one possible
mechanism, not itself evidence of contract conformance. Validation from another
attempt, session or transaction cannot be attached to this attempt under that
mechanism. Private completion handles bind the successful scan, query output and
immutable retention to the owned task; failure, cancellation or loss of consistency
before retention prevents issuance of all three records. Session/transaction
handles stay private and do not add wire fields or replace source snapshot
identity. An applicable snapshot is verified under its source contract; a local
path, file modification time or connection identifier is not a substitute token.
No snapshot token is synthesized when none applies.

<!-- requirement-block: query-process-evidence.access-accounting -->
The Host MUST distinguish source-engine internal scanning, typed-row receipt by
the Host from that engine, and retained output storage. Internal validation that
does not export scanned rows is not Host row receipt, but retains its full-scan
provenance and remains subject to applicable engine/work budgets. Rows exported
to Host code for validation count as actual receipt even when used only for
validation or later discarded. Query rows exported separately are a separate
receipt; copies and repeated consumers of an already received batch do not count
that same transfer again, although their allocations and retention consume the
applicable memory budgets. Control metadata is not invented as typed data rows
and remains subject to its applicable physical budget. `received_bytes` retains
the acquisition contract's canonical typed-wire measurement, not database pages,
compressed transport size or heap size. Equal numerical counts cannot exchange
these scopes, and final selected output size cannot replace actual receipt.

<!-- requirement-block: query-process-evidence.single-receipt -->
The existing single `actual_access` scope MUST describe one complete logical
received row sequence and its field set, including ordinary transport batches
of that same sequence; it cannot hide additional validation reads or encode
independent query results by concatenation, union or deduplication. Internal full
validation followed by one native projected receipt fits this scope. A single
full receipt reused for Host-side validation and residual filter/select also
fits, with the broad received scope and separate selected output. Exporting a
validation scan and independently exporting a native query result requires a
separately admitted multiple-access contract, which this initial profile does not
define. Such an execution cannot issue a completed observation under this profile;
its private resource ledger still charges both receipts. An opaque provider scope
CID does not cure the missing Host-access representation. The requirement and
record schemas, record preimages and original access-scope preimage are unchanged.

<!-- requirement-block: query-process-evidence.validation-failure -->
Mandatory scan validation MUST reject an invalid known field even in a row that
the query filter excludes. A fixture may fix a validation scan traversal to
identify its first encountered failure; that fixture does not establish a shared
representative diagnostic across different physical traversals or a logical total
order. Physical budget exhaustion can stop validation earlier under the existing
failure rules. Validation ordering never supplies missing source-order evidence.

<a id="query-two-receipt"></a>

#### Host-local two-receipt query evidence

<!-- machine-import: ../../spec/contracts/actql-query-two-receipt.json# sha256:7d9eec132b742aca27b78a801c6bea187a251b7423967950e285755c50e853d8 -->
<!-- machine-import: ../../spec/contracts/actql-query-two-receipt.json#/schemas/receipt sha256:d3994a9a48aab18e3d0c75e2ef2d549c6c6227536313c3d66c53b543f2868b6a -->
<!-- machine-import: ../../spec/contracts/actql-query-two-receipt.json#/schemas/record sha256:cd3c30fbe01c375642b42f7dac2391a5ea008d117a2489c8c646d78745f86334 -->
<!-- machine-import: ../../spec/contracts/actql-query-two-receipt.json#/schemas/completed_observation sha256:566fc1955ac77a2c074ddba0b8be22b75f18acdd6af8ca86e5f68443ab366af1 -->
The separate [two-receipt contract](../../spec/contracts/actql-query-two-receipt.json)
specializes the same canonical acquisition requirement for a Host-local adapter
that exports the validation scan and independently exports the native query
result. It does not modify the single-receipt schemas or reinterpret their
`actual_access`. The selected verifier pins this entire contract and both pinned
dependencies. Record shape alone is not verification, authorization or backend
support. Database-specific execution APIs remain adapter responsibilities.

<!-- requirement-block: query-two-receipt.execution -->
This profile MUST use exactly two logical row receipts: `validation_scan` contains
every row and every known field of the selected scan, and `native_result` contains
the complete native filter/select result. The Host applies the pinned value
admission contracts to the validation receipt before executing the native query,
including fields and rows that query would discard; SQL typing or casts cannot
replace that admission. Both reads use the same owned consistent source view,
requirement and Host task/attempt. Source-specific snapshot conditions still apply
without synthesizing a token from a path, mtime or private read-view identifier.
The adapter verifies the native semantics, demanded failures and relative row
order against the checked query; this profile keeps `source_order_cid: null` and
does not create total-order evidence. Additional independent row receipts are
outside this two-receipt profile, even if their results equal one of these two.

<!-- requirement-block: query-two-receipt.receipts -->
Each receipt MUST conform to `/schemas/receipt`, with every property present and
no unknown properties. The entire object is its canonical JSON UTF-8 SHA-256
preimage, with no self-CID. `received_rows_cid` hashes its complete ordered typed
wire row array, preserving multiplicity and canonicalizing object key order;
`received_rows` is that array's length and `received_bytes` its canonical UTF-8
byte length. `received_fields` is the unique UTF-16-sorted field set: exactly the
known validation fields for `validation_scan`, and exactly the checked output
field names after aliases for `native_result`. Every row conforms to the
appropriate input/output contract, including nullability, exact field membership
and canonical decimal wire strings. The role participates in receipt identity;
equal row contents do not make the two roles interchangeable. `scan_scope_cid`
has the existing selected-scan preimage, not the projected extent's identity.

<!-- requirement-block: query-two-receipt.ownership -->
The authorized issuer MUST allocate the attempt and a nonempty process-local
`read_view` identifier outside candidate input and retain the exact private task,
session/transaction or equivalent consistency handle associated with it. The
identifier is never reassigned to a different view during that issuer's lifetime;
matching strings cannot substitute for live handle ownership. Both receipts and
all three execution records carry the same issuer, attempt, read_view, requirement
CID, selected scan scope and applicable snapshot. The requirement binds Program
Definition owner, source, request, Parameters and contracts as before. Private
evidence of another attempt, transaction or session cannot be combined with this
task, even if its rows, public identifiers or hashes match. Read-view identity is
an execution discriminator, not a new source snapshot or static request identity.

<!-- requirement-block: query-two-receipt.records -->
The `source_validation`, `filter` and `select` records MUST conform to
`/schemas/record` and each reference both receipts through the closed `accesses`
object `{validation_scan_cid, native_result_cid}`. Each record retains the same
completed `output` and exact bindings; its CID hashes its entire canonical object
without a self-CID. The completed observation uses the distinct version
`actql-query-two-receipt-observation/0.1`, the same receipt references, the
`execution` identifiers, and `evidence_contract_cid` equal to the independently
selected root contract pin. Its coverage contains the three exact record CIDs.
Its owner/source/request/Parameter/snapshot/output/retention meanings are unchanged.
Its entire body is the observation CID preimage. Receipt bodies do not reference
records or the observation, and records do not reference the observation.
`native_result.received_rows_cid` and count equal the output rows CID and count;
this equality does not collapse receipt, output, record or capture identities.

<!-- requirement-block: query-two-receipt.accounting -->
Physical receipt accounting MUST charge each of the two actual transfers once,
including all rows and canonical typed-wire bytes of the validation scan even
when discarded. Aggregate receipt limits apply to the sum using overflow-checked
accounting; per-transfer limits, when selected, apply independently. Reusing a
received batch for validation or copying retained output does not create another
receipt, but retention/copy allocations consume their own memory budgets. Engine
scans, engine work, transport allocation and retained storage keep their separate
scopes; neither final output size nor a concatenated or deduplicated row sequence
substitutes for the two receipt records. Logical output guards apply to the
completed selected result and the existing value guards to admitted records and
demanded expressions. Separate roles are not double charging one transfer: this
profile describes two genuinely distinct transfers.

<!-- requirement-block: query-two-receipt.completion -->
The issuer MUST issue both receipts and all three evidence records for capture
only after successful complete validation, native query verification, physical
and logical limits, and immutable output retention. Missing either receipt,
validation/evaluation failure, cancellation, retention failure or lost read
consistency makes the attempt terminal without successful capture or consumer
admission. Provisional accounting is not issued completion evidence. The capture
verifier resolves every referenced receipt and record to an authorized live
immutable handle, verifies task/read-view ownership, all exact bindings, shape,
content CIDs and counts, and the retained output. Hash-correct JSON, booleans,
candidate promises or deserialized records cannot restore provenance. This is
process retention only, not durable Run, replay or checkpoint completion.
Validation fixtures may fix traversal to choose their first failure without
prescribing representative diagnostics across physical plans. Existing single
broad-receipt execution remains supported by its original contract; its verifier
does not admit this new observation version.

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

<!-- machine-import: ../../spec/contracts/actql-numeric-reduction.json# sha256:d771391b2e4f3e52a3cf48810571a09c6c272df64fbb77c245dfabcf456be5df -->
<!-- machine-import: ../../spec/contracts/actql-numeric-reduction.json#/contracts/left_fold sha256:4077bb93149235757642468a512543d949f48d5a81f04f49827193f3e9420f55 -->
<!-- machine-import: ../../spec/contracts/actql-numeric-reduction.json#/contracts/adjacent_pairs sha256:48158d55d2a97e7c1d3ea95c8b7e085469eedc6186f24b57427aa8e610dceeba -->

<!-- requirement-block: numeric-observation.reduction-profile -->
The [numeric reduction profile](../../spec/contracts/actql-numeric-reduction.json)
defines two explicitly selectable binary64 reduction contracts, not a default
algorithm and not an exhaustive restriction on future admitted contracts.
Each member CID hashes its entire canonical JSON body; the profile CID hashes
the entire profile, including its member bodies, pins and selection rules.
The existing numeric observation's `numeric_contract_cid` MUST identify the
selected member, not the profile or an unregistered algorithm label. Selecting
the profile does not establish Host permission or backend implementation support.

<!-- requirement-block: numeric-observation.contributor-sequence numeric-observation.contributor-domain -->
For these contracts, contributor evidence MUST bind the exact ordered sequence
derived from the bound logical input artifact for the group or frame. Apply the
aggregate filter before evaluating the argument, exclude NULL, then apply an
authored distinct operation by numeric equality, retaining first occurrences.
The count is the resulting nonnegative safe-integer length, not the pre-filter
row count. Input values MUST already satisfy their finite binary64 contract.
This aggregate demand rule does not waive mandatory source-wide validation.
Recording a contributor sequence does not establish a logical total-order
witness for another consumer. Neither a reordered sequence nor a wrong group,
count, demand or artifact can be accepted as numerical tolerance.

<!-- requirement-block: numeric-observation.reduction-arithmetic -->
Implementations MUST use the following exact arithmetic for the selected member.
The `left_fold` member starts at positive zero and adds contributors from left
to right. The `adjacent_pairs` member sums adjacent pairs from left to right,
carries an odd final element unchanged, and repeats on that resulting sequence
until one value remains; a singleton is unchanged. Each addition rounds to
binary64 nearest, ties to even. For `avg`, divide that rounded sum once by the
exact binary64 representation of the contributor count, using the same rounding.
An empty sequence returns NULL for both operations. Any nonfinite intermediate
or final value fails, even if a later operation could return to a finite range.
Internal signed zeros retain IEEE semantics; normalize a final negative zero to
positive zero at the public operation boundary. The error law is exactly this
operation sequence: no epsilon, reassociation, widened accumulator or implicit
algorithm substitution is admitted by these members.

<!-- requirement-block: numeric-observation.reduction-selection -->
Static slot preparation pins the admitted profile and aggregate semantics,
without future response bytes or physical parallelism. Before a reduction
attempt, the executor MUST select one admitted member and bind it, the contributor sequence and
group/frame to that attempt's policy and accounting evidence. Failure cannot
silently select another member or emit a partial observation. Local and remote
execution both require the existing durable numeric capture barrier before any
consumer; replay reads the adopted value and performs no new reduction. Profile
membership and self-consistent CIDs alone are not completion evidence. This
profile does not define a replacement aggregate-slot preimage or weaken the
existing slot ownership requirements.

<!-- machine-import: ../../spec/contracts/actql-numeric-slot.json# sha256:3bbd17b81b40403cea2b43db3324a9c2b2185bc8c86a994d58f009e317b1a73d -->
<!-- machine-import: ../../spec/contracts/actql-numeric-slot.json#/schemas/group_slot sha256:56381c50a36da58d99c04b753bd258cb1931a2be7320b42984bae09662b927a9 -->

<!-- requirement-block: numeric-observation.group-slot-preimage -->
For an ordinary `group` binary64 sum/avg, the aggregate slot CID MUST hash the
entire canonical JSON body defined by the [group slot schema](../../spec/contracts/actql-numeric-slot.json):
`{version: "actql-group-numeric-slot/0.1", unit_definition_cid,
source_ordinal, aggregate_name, reduction_profile_cid}`. The ordinal is the
owning Unit's authored step ordinal, not a producer-visit, obligation or lowered
node index. The name is the exact canonical authored aggregate name, not a
position in the aggregate map and not an escaped path. The Unit Definition
already binds the operation's semantics, effective used Parameters and local
contracts. The profile CID identifies the explicitly admitted profile, not a
member selected for a future attempt. This fixes the previously unspecified
ordinary-group slot preimage. Pivot, window_group and analytic calls use the separate definitions
below, not the ordinary-group domain.

<!-- machine-import: ../../spec/contracts/actql-window-numeric-slot.json# sha256:868fc8f92638572086e4063a815ba235ebe8bc1f207c935c5a99cc82ddabe8ee -->
<!-- machine-import: ../../spec/contracts/actql-window-numeric-slot.json#/schemas/window_slot sha256:25ba88c7f5c7ec1ea184e4449fa42f94ee2022af7d07a45f59b052080090a18f -->

<!-- requirement-block: numeric-observation.window-slot-preimage -->
For a `window_group` binary64 sum/avg, the static slot CID MUST hash the entire
canonical JSON object `{version: "actql-window-numeric-slot/0.1",
unit_definition_cid, source_ordinal, aggregate_name, reduction_profile_cid}`.
The ordinal and exact canonical authored name identify the call in its owning
Unit, not a producer visit, map position or escaped path. This fixes the
previously unspecified window-group slot preimage in a separate domain; ordinary
group and analytic preimages are unchanged. Window configuration, grouping and
aggregate semantics, effective used Parameters and local contracts are already
bound by the Unit Definition, without adding a future window key to the slot.

<!-- requirement-block: numeric-observation.window-slot-owner -->
Window-group slot admission MUST verify the same checked Program, owning Stage, pipeline, step,
binary64 sum/avg call and admitted reduction profile. The window slot contract
and schema, profile and its declared dependencies belong to that Unit's local
contract closure. Imports retain the producer's slot, never a consumer rebasing.
The static preimage excludes future input artifacts, group/boundary values,
contributors, counts, adopted values, selected algorithm members, attempts,
Invocation, placement and cost. The Unit does not include its derived slot CID;
shape and self-hash alone do not establish ownership or completed execution.

<!-- requirement-block: numeric-observation.window-slot-observation -->
Execution MUST bind each observation to this slot, exact input artifact, full
group key including the window-boundary prefix, contributor demand, count, type
and attempt. Equal results or contributor sequences do not alone identify
distinct window groups. Group membership does not prescribe a floating-point
reduction order. The selected reduction member and contributor sequence remain
bound to the attempt, and the existing durable numeric capture barrier before
consumers remains mandatory. A static slot is neither future observation
identity nor completed capture evidence and does not authorize process-local
retention in place of durable capture.

<!-- machine-import: ../../spec/contracts/actql-analytic-numeric-slot.json# sha256:6d88bdc63c0a7eb77ee1dc976003fcec1ace74ca46ce61af5a956d2e89b30a43 -->
<!-- machine-import: ../../spec/contracts/actql-analytic-numeric-slot.json#/schemas/analytic_slot sha256:89b1d3c4450466f1ebf758c876ca8209787490cdf852b7e16c1b4ec41a862ae6 -->

<!-- requirement-block: numeric-observation.analytic-slot-preimage -->
For an analytic binary64 sum/avg, the static slot CID MUST hash the entire
canonical JSON object `{version: "actql-analytic-numeric-slot/0.1",
unit_definition_cid, source_ordinal, output_name, reduction_profile_cid}`.
It identifies the call template, not a future output frame. The ordinal is
the producer Unit's authored step ordinal; the name is the exact canonical
authored output name, not a call-array index or escaped path. The Unit already
binds the partition, authored order, frame, expressions and effective used
Parameters. This fixes the previously unspecified analytic slot preimage in a
separate domain, without changing the ordinary-group preimage.

<!-- requirement-block: numeric-observation.analytic-slot-owner -->
Admission MUST verify the same checked Program, owning Stage, pipeline, step,
binary64 sum/avg call and admitted reduction profile. The slot contract and
schema, selected profile and declared dependencies belong to that Unit's local
contract closure.

<!-- requirement-block: numeric-observation.analytic-slot-imports -->
Imports retain the producer slot; they MUST NOT rebase it to
the consumer. The static preimage excludes future input artifacts, partition
keys, output positions, members, contributor values, counts, adopted values,
selected algorithm members, attempts, Invocation, placement and costs. The Unit
does not include the derived slot CID. Shape and self-hash do not prove ownership.

<!-- requirement-block: numeric-observation.analytic-slot-frame-binding -->
Execution MUST bind each frame observation to the static slot, exact input,
partition and output-row occurrence, completed position evidence and actual
contributor demand. Equal frame values or contributor sequences do not alone
identify output occurrences, including repeated rows and empty frames. Frame
position determines demand, not a prescribed floating-point summation order.
The existing reduction-profile admission, attempt binding and durable capture
barrier before consumers remain mandatory. A static slot supplies neither a
future observation identity nor evidence of completed capture; this contract
does not substitute process-local retention for that barrier.

<!-- machine-import: ../../spec/contracts/actql-pivot-numeric-slot.json# sha256:54c19c5dc586979bfd5cfa7afed23011e8394dd4a8623c32ba6ca0f83fb01858 -->
<!-- machine-import: ../../spec/contracts/actql-pivot-numeric-slot.json#/schemas/pivot_slot sha256:53d96b4ac1e98bf6b829fad4abe700fd12eeee534c1d02e18c19718f80109879 -->

<!-- requirement-block: numeric-observation.pivot-slot-preimage -->
For pivot binary64 sum/avg, each generated column's static slot CID MUST hash
the entire canonical JSON object `{version: "actql-pivot-numeric-slot/0.1",
unit_definition_cid, source_ordinal, output_name, reduction_profile_cid}`.
The name is the exact canonical declared pivot value and generated output name,
not its position in authored values or canonical columns, nor an escaped path.
The ordinal identifies the authored pivot in its producer Unit. The Unit already
binds index fields, column/value selectors, aggregate, fill and effective used
Parameters. This fixes a previously unspecified pivot preimage in a separate
domain, without changing group, window-group or analytic slot identities.

<!-- requirement-block: numeric-observation.pivot-slot-owner -->
Admission MUST verify the same checked Program, owning Stage, pipeline, pivot
occurrence, declared generated column, effective binding and admitted profile.
The slot contract and schema, profile and its declared dependencies belong to
that Unit's local contract closure. A non-selected string is not another valid
column merely because it satisfies the wire shape. Shape and self-hash alone
do not establish this correspondence or process-local ownership.

<!-- requirement-block: numeric-observation.pivot-slot-imports -->
Imported uses MUST retain the producer slot, not rebase it to the consumer Unit.
The static body excludes future input artifacts, actual index-group keys,
contributors, counts, adopted values, filled results, algorithm members, attempts,
Invocation, placement and costs. The Unit does not include its derived slot CID
or future observations. These exclusions do not remove the authored fill or
values sequence from the Unit's ordinary semantic projection.

<!-- requirement-block: numeric-observation.pivot-slot-bucket -->
Execution MUST bind each observation to the static column slot, exact input
artifact, index group, that column's bucket, non-null contributors, count, type,
selected reduction member and attempt. Null or undeclared column values do not
contribute to a generated bucket but still establish index groups. Equal results
or contributor sequences do not identify different index groups or slots.
The declared index/column sequences do not prescribe floating-point summation
order. Sum/avg on an empty non-null bucket yields null before applying fill;
the fill value is not a reduction contributor or replacement observation.

<!-- requirement-block: numeric-observation.pivot-empty-slots -->
Empty declared values MUST produce zero numeric column slots without omitting
operation, type, admitted-profile, fill or budget checks. This differs from an
existing generated column with an empty bucket, whose static slot still exists.
The existing attempt-bound durable numeric capture barrier applies before
consumers; static templates provide no completed observations and do not permit
process-local retention to substitute for that barrier.

<!-- requirement-block: numeric-observation.group-slot-owner -->
Slot admission MUST verify the same checked Program, owning Stage, local
pipeline, source step, sum/avg call and selected profile. The slot contract and
schema, reduction profile and its declared dependencies belong to that Unit's
local contract closure. Importing a result references its producer's slot; it
does not rebase it to the consumer Unit. Wire shape, valid digest syntax or an
equal self-hash cannot establish this ownership. An aggregate name that is not
canonical or does not identify the selected call is rejected without repair.

<!-- requirement-block: numeric-observation.group-slot-acyclic -->
The preimage MUST exclude future input/contributor artifacts, group/frame key,
count, adopted value, selected algorithm member, attempt, placement, costs,
Stage Invocation and Result identities. These bind to the captured observation
or execution attempt instead. The Unit Definition does not include the derived
slot CID or future observation, avoiding a circular identity definition.
Constructing a slot is not evidence of successful reduction, durable capture,
authorization or a backend's ability to enforce the selected contract.

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
| `waiting_checkpoint` | `cancelled` | The Checkpoint was rejected or expired without dispatching its continuation, and no earlier Effect outcome of the Run remains unknown. |
| `waiting_checkpoint` | `needs_reconciliation` | The Checkpoint was rejected or expired, or cancellation was admitted, without dispatching its continuation while earlier Effect outcomes recorded by the Run owner remain unknown ([Checkpoints and Resolutions](#checkpoints)). |
| `preparing`, `waiting_checkpoint`, `resuming` | `cancelled` | Cancellation was admitted with no dispatch in flight or unresolved Effect outcome. |
| `preparing`, `running`, `resuming` | `succeeded`, `failed`, `needs_reconciliation` | The continuation completed or failed; admission, publication, and Effect aggregation conditions determine the destination ([Capture, execution, and replay](#capture-and-replay), [Outcomes and reconciliation](#reconciliation)). |
| `needs_reconciliation` | `needs_reconciliation`, `succeeded`, `failed` | A valid reconciliation receipt extended the sealed member history and all member outcomes were aggregated ([Outcomes and reconciliation](#reconciliation)). |

<!-- requirement-block: run-states.a-resumed-continuation-must-not-return-to-running -->
A resumed continuation MUST NOT return to `running`: it remains `resuming`
while it executes and until it exits to `waiting_checkpoint`, `succeeded`,
`failed`, `needs_reconciliation` or `cancelled`. That exit transition is the
resumed Run transition that completes the claimed resume intent. No additional
state is introduced.

<!-- requirement-block: run-states.a-transition-must-not-dispatch-a-continuation-across-an-unresolved run-states.a-terminal-state-must-not-transition-to-another-state -->
A transition MUST NOT dispatch a continuation across an unresolved Checkpoint.
A terminal state MUST NOT
transition to another state. Exact redelivery of already committed evidence
is idempotent; conflicting terminal evidence is rejected. Cancellation does
not roll back previously applied Effects. An `accepted` asynchronous Effect
can complete its Run while its provider operation remains pending ([Outcomes and reconciliation](#reconciliation)).

<!-- requirement-block: run-states.run-creation-and-lifecycle-operations-must-expose-the-closed-actql-run-state-0-2 -->
Run creation and lifecycle operations MUST expose the closed
`actql-run-state/0.1` projection: Run identity, immutable outcome state, update
time, optional Checkpoint identity, per-Result availability observations, their
all-Results aggregate, and one state-consistent next action. Each availability
entry distinguishes `available`, `unavailable`, and `unknown`, records the
observation time and bounded reason, and may cite a cause. A failed Store query
is `unknown`, not evidence that data is absent. `result_available` is true only
when every declared Result is confirmed available. A confirmed available
subset remains individually retrievable when the aggregate is false.

<!-- requirement-block: run-states.run-state-lookup-must-not-reveal-publication-existence-to-an-unauthorized-caller -->
Availability does not grant access. `read_result` identifies Results for which
the caller may request a separately authorized read; it is not read authority.
Expired or deleted Results are not offered for reading. When freshness rather
than absence is unresolved, `refresh_availability` identifies the Results whose
Store state may be checked. Run-state lookup itself is authorized and MUST NOT
reveal publication existence to an unauthorized caller. Result Manifests,
Result payloads, and restricted Review Projections are retrieved separately
under their respective authority and policy checks. Expiry, deletion, policy
loss, or Store uncertainty changes current availability but never rewrites a
previously committed Run outcome.

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

This runtime action results from execution-account evaluation and, for a
delegated outcome, the Host's answer ([Account authorization routing](#policy-routing)).
Account `allow` and an immediate delegated permit yield `allow`; account `deny`
and an immediate delegated reject yield `deny`; only a deferred delegated
answer yields `checkpoint`. Checkpoint message variants and authenticated
decisions use the Run protocol binding.

<!-- requirement-block: checkpoints.the-host-must-reuse-already-captured-unit-outputs checkpoints.the-host-must-not-silently-regenerate-a-new-review-artifact checkpoints.before-dispatch-after-a-delayed-resolution-it-must-revalidate-the -->
An approved preparation Resolution continues the same preparation attempt;
an approved Run-unit Resolution resumes the same Run and continuation. The Host
MUST reuse already captured unit outputs. The Host MUST NOT silently regenerate
a new review artifact under the old approval. Before dispatch after a delayed
Resolution, it MUST revalidate the bound authorization-context and
environment-binding CIDs. Artifact availability and exact target freshness are
then revalidated at their existing provider-access and Effect-commit boundaries.

<!-- requirement-block: checkpoints.every-resumed-protected-dispatch-must-pass-the-resume-admission-whatever-the-account-outcome checkpoints.an-account-allow-at-resume-must-not-admit-a-stale-superseded-or-unclaimed-continuation checkpoints.a-configuration-changed-while-waiting-must-not-admit-a-resumed-dispatch -->
Every resumed protected dispatch MUST pass the same resume admission whatever
the current account outcome of its tuple: the current live claim of the resume
intent, the committed approval still valid at the Host trusted time, the
admitted configuration CID the decision was deferred under, and at most one
protected dispatch start per claim generation. An account `allow` at resume
removes only the need for an approval of that tuple; it MUST NOT admit a stale,
superseded or unclaimed continuation, and a configuration changed while the Run
waited MUST NOT admit a resumed dispatch even when it now allows the tuple.

<!-- requirement-block: checkpoints.a-failed-resume-revalidation-must-not-dispatch-and-must-end-the-continuation -->
If a bound authorization-context or environment-binding CID no longer
revalidates, the Host MUST NOT dispatch the continuation. A Run-unit
continuation then exits `resuming` to `failed`, or to `needs_reconciliation`
when earlier Effect outcomes remain unknown, with runtime error phase
`admission` and `terminal_error.code` `ACTQL_E_RESUME_REVALIDATION_FAILED`;
that exit completes the resume intent atomically. The unknown Effects are those
the Run owner's recorded Effect outcomes still mark unknown; the continuation does
not invent or drop them. A preparation continuation ends without creating a Run.
An approved preparation continuation that revalidates creates its Run directly in
`running`; preparation already completed before the Checkpoint. The Host does not weaken or reinterpret the old
approval, and a changed artifact or target found at a later boundary uses that
boundary's existing failure.

<!-- requirement-block: checkpoints.a-rejected-expired-or-cancelled-wait-must-not-hide-unknown-effect-outcomes -->
A rejected or expired Checkpoint, or an admitted cancellation of a waiting Run,
never dispatches the continuation and creates no resume intent. Such an exit
MUST NOT hide unknown Effect outcomes: when earlier Effect outcomes recorded by
the Run owner remain unknown, the Run exits `waiting_checkpoint` to
`needs_reconciliation` with next action `reconcile` over exactly those Effects
and its prior facts are preserved; otherwise it exits to `cancelled`. A
preparation Checkpoint precedes its Run and has no Effect outcomes; it ends
without creating a Run.

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
started. An account deny, a no-match deny or an immediate delegated reject at
the preparation boundary is such a denial; a technical decision failure there
creates no Run either, but it is not recorded as a rejection.

<!-- requirement-block: checkpoints.current-effect-authorization-identity-must-bind-account-outcome-and-host-decision -->
Current Effect authorization identity MUST bind the admitted execution-account
configuration CID and its evaluated `allow`, `deny`, or `delegate` outcome and,
for a delegated outcome, the Host policy-contract CID and its evaluated `allow`,
`review`, or `deny` decision; that complete identity is revalidated before
resumed Effect dispatch.

<!-- requirement-block: checkpoints.an-expired-or-superseded-resume-claimant-must-not-release-fail checkpoints.a-resumed-run-transition-and-resume-intent-completion-must-occur-in -->
An expired or superseded resume claimant MUST NOT release, fail, complete, or
otherwise alter a resume intent or its Run. A resumed Run transition and
resume-intent completion MUST occur in the same transaction; the portable store
does not expose intent-only successful completion. The resumed Run transition
is the Run's exit from `resuming` ([Run states and transitions](#run-states)).

The Effect Set proposal and commit boundary follow [Effect declarations](language.md#effects) and [Effect preview, approval, and application](#effect-application). When a delegated
decision is deferred, the complete Effect Set Preview is the sealed artifact of the
Effect Commit Checkpoint; its Resolution resumes the same Run's Effect application.

<!-- requirement-block: checkpoints.member-count-alone-must-not-require-a-checkpoint-or-risk-claim checkpoints.a-host-required-risk-claim-must-be-authenticated-and-recorded-as-host-policy -->
The number of Effect Set members alone MUST NOT require a Checkpoint, a
delegated decision, or `partial_application_accepted` evidence. An account
`allow` commits a multi-Effect Set after whole-set preflight without a risk
claim, and its evidence does not state that anyone accepted business risk.
A Host MAY declare a policy that requires `partial_application_accepted` for
its delegated decision. That claim MUST then be authenticated, bound to the
exact Preview and review projection, and recorded as that Host's declared
policy requirement; a missing required claim is not an accepted delegation.
A deferred decision uses one Checkpoint for the complete stage Preview.
Run-level allow is insufficient unless the current concrete scope is proved
inside its admitted envelope.

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
Effect commit authority comes from execution-account evaluation and, for a
delegated outcome, the Host's answer ([Account authorization routing](#policy-routing));
source validation does not approve a concrete Effect. Mapping and Command
Contracts declare exact technical permission requirements, not approval policy.
Parameter declarations, authored Mapping or Command Contract references, and
Effect semantics belong to Program identity. Resolved permission sets and
Contract evidence belong to checked Plan and Effect Preview identity, not to
author-declared Program fields. Concrete bindings and typed parameter values
belong to Invocation and Effect Preview identity as specified in [Canonical identities](language.md#canonical-identities).
The exact target set and before/after rows belong to the Effect
Preview CID. When approval is required, its attestation MUST sign the Effect
Preview CID, and the apply receipt MUST bind both the preview identity and
approval evidence. When the account outcome is `allow`, the receipt instead
records the account configuration identity and that no approval attestation or
risk claim was required.

A Connector contract cannot raise or lower account routing, and no Host answer
converts an account `deny` into permission. The absence of approval syntax does
not grant permission to bypass account evaluation; a configuration without a
matching entry denies.

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

<!-- requirement-block: effect-application.effect-member-preview-cid-uses-the-noncyclic-canonical-member-body effect-application.effect-preview-cid-excludes-only-the-listed-derived-bindings -->
For the private `actql-effect-preview/0.1` body, a member's
`effect_member_preview_cid` MUST be the CID of the canonical envelope
`{version: "actql-effect-member-preview/0.1", member: MemberSemanticBody}`.
`MemberSemanticBody` is the complete member object with only its
`effect_member_preview_cid` and every
`changes[].row_idempotency_key` removed. The row preview CIDs remain in this
body and are established first by the row preimage in
[Private preview row state](protocols/run.md#preview-row-state).

The set `effect_preview_cid` MUST be the CID of the canonical complete private
Preview body with only `effect_preview_cid`, `run_identity_cid`,
`authoring_context`, and every `changes[].row_idempotency_key` removed.
Computed member CIDs remain in the set preimage. Establish and verify row preview CIDs,
then member CIDs, then the set CID, and only then derive row idempotency keys.
No other semantic field is excluded. The omitted physical Run, Authoring
Context, and derived keys remain required fields of the transported Preview;
apply admission checks their exact bindings independently of the semantic CID.

<!-- requirement-block: effect-application.when-a-delegated-decision-is-deferred-the-runtime-must-pause-at-one effect-application.the-host-must-preflight-every-member-before-the-first-mutation effect-application.before-the-first-mutation-dispatch-a-data-connector-must-advertise -->
Application remains a separate host-authorized phase inside that Run.
When a delegated commit decision is deferred, the runtime MUST pause at one Effect Commit
Checkpoint bound to the complete previewed Effect Set. Resolving that
Checkpoint resumes the same Run; no interface may
release a subset. The host MUST preflight every member before the first
mutation dispatch. A multi-Effect set requires acceptance of
partial-application risk only when a Host-declared policy requires it for a
delegated decision ([Checkpoints and Resolutions](#checkpoints)). Before the first mutation
dispatch, a data Connector MUST advertise exact
mutation atomicity, row-error identity, idempotency, request-order behavior,
and unknown-outcome reconciliation. `store` remains relation materialization
and is not generalized into binary upload.

> **Note (informative):** `partial_application_accepted` records a human or
> policy issuer's acceptance of business risk that a Host required. It is not
> a compiler proof of atomicity and is never fabricated from an account allow.

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

<!-- requirement-block: effect-application.two-conforming-implementations-must-produce-the-same-row-key-for -->
`effect_identity_cid` binds the local Unit Definition CID and local Invocation,
Effect ID, canonical Effect semantics, the exact Result Artifact
CID when a Result is consumed, and the resolved Mapping or Command Contract
CID. Distinct Effect IDs in one Preview therefore require distinct Effect
identities; admission rejects a repeated `effect_identity_cid` across members.
Physical Run identity is excluded. Recovery across workers or physical
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

### Account authorization routing

<!-- requirement-block: policy-routing.the-run-owner-must-evaluate-the-account-configuration-before-each-protected-dispatch policy-routing.program-input-must-not-select-or-strengthen-the-execution-account -->
Execution authority is configured for an execution account, not authored in
a Program. Before each protected dispatch, the trusted Run owner MUST evaluate
the admitted execution-account configuration for the trusted execution
principal and the boundary's connection, resource and operation. Protected
boundaries include preparation input capture, provider access for acquisition
or inference, data egress or transfer, and Effect commit; covered pure
computation needs no decision request. Program input MUST NOT select or
strengthen the execution account. Configuration identity is authorization
evidence, not Program Definition identity.

<!-- requirement-block: policy-routing.account-outcome-execution-behavior -->
| Account outcome | Execution behavior |
| --- | --- |
| `allow` | Continue after the remaining technical and current-context checks, with no delegated-decision callback, no Checkpoint and no fabricated risk claim. |
| `deny` | Dispatch none of the affected work. No Host answer, Resolution or operator resume overrides it. |
| `delegate` | Hand the exact decision subject to the Host's delegated-decision adapter; cross the boundary only after an admitted permit. |

<!-- requirement-block: policy-routing.host-answer-execution-behavior -->
| Host answer to a delegated decision | Execution behavior |
| --- | --- |
| immediate permit | Authenticate the answer and bind it to the exact decision subject, then continue without creating a Checkpoint. |
| immediate reject | Dispatch none of the affected work and retain earlier facts; no Checkpoint is created. |
| defer | Persist the existing sealed Checkpoint and continuation before relinquishing execution ([Checkpoints and Resolutions](#checkpoints)). |
| missing, malformed, unauthenticated, timed out or unavailable | Technical decision failure: dispatch nothing and record neither a permit nor an intentional rejection. |

<!-- requirement-block: policy-routing.account-routing-runtime-action-and-host-answer-vocabularies-must-remain-distinct -->
Account `allow`/`deny`/`delegate` routes authority, runtime
`allow`/`deny`/`checkpoint` is the resulting execution action, and Host
`permit`/`reject`/`defer` is adapter vocabulary. These vocabularies MUST remain
distinct types. Existing Host policy decisions keep their spelling: for a
delegated request, a Host policy decision `allow`, `review` or `deny` means
immediate permit, defer, or immediate reject respectively, and
`require_review` means defer. Core checks the answering authority, exact
subject and permitted transition, not the Host's business decision method,
which may be an embedded function, automated policy, external service, human
review or a combination.

<!-- requirement-block: policy-routing.admission-must-reject-overlapping-entries-with-different-outcomes policy-routing.an-unmatched-tuple-must-be-denied-as-no-match policy-routing.a-missing-or-invalid-configuration-must-not-be-treated-as-allow policy-routing.a-bootstrap-profile-adoption-must-be-recorded-durably-before-use -->
Configuration entries address principal × connection × resource × operation.
An explicit all-target selector includes future members of its dimension; a
finite selector does not. Each entry's tuple exclusions are subtracted from its
own selected tuple set before overlap is checked. Admission MUST reject a
configuration in which two entries with different outcomes have a nonempty
exact tuple-set intersection. Overlap is decided symbolically over the open
universe, independently of discovered resources; entry order, specificity and
deny-wins never resolve it. A tuple that no effective entry matches MUST be
denied as no-match, reported distinctly from an explicit deny. An explicit deny
makes a later overlapping allow or delegate a configuration conflict; a no-match
does not. A missing, unreadable, conflicting or otherwise invalid configuration
MUST NOT be treated as allow. A Local Host may instead materialize an explicit
versioned bootstrap profile identified by its exact content CID. Its adoption
MUST be recorded durably before any protected dispatch relies on it, and it is
never re-materialized to restore removed or restricted grants. The
configuration document is `actql-execution-account-config/0.1`, whose wire form
and exact overlap rule are bound by the [Run protocol](protocols/run.md#account-config).

<!-- requirement-block: policy-routing.a-technical-decision-failure-must-not-dispatch-or-record-a-rejection -->
Initial denial and later denial are distinct. A denial or technical decision
failure before Run creation follows [Checkpoints and Resolutions](#checkpoints).
Inside a Run, a deny or immediate reject leaves the affected unit undispatched
and the Run ends `failed`, or `needs_reconciliation` when earlier outcomes are
unknown, retaining prior acquisitions, costs and Effect outcomes. The runtime
error uses phase `admission` and code `ACTQL_E_ACCOUNT_DENIED`,
`ACTQL_E_ACCOUNT_NO_MATCH`, `ACTQL_E_ACCOUNT_CONFIG_INVALID` or
`ACTQL_E_DELEGATION_REJECTED`. A technical decision failure MUST NOT dispatch
the unit or be recorded as a rejection: the Host may retry the decision request
for the same subject without dispatching, or end the Run as above with
`ACTQL_E_DELEGATION_UNAVAILABLE`. No new Run state is introduced.

<!-- requirement-block: policy-routing.core-routing-and-connector-contracts-must-not-consume-count-proxies policy-routing.packaging-equivalent-work-must-not-change-account-routing-or-the-decision-subject -->
Core account evaluation and Connector contracts MUST NOT route authority on
Effect/stage counts, multiple/later flags, array lengths, source AST, arbitrary
metadata or equivalent proxies. A Host's delegated-decision policy is
Host-defined; the [Reference Host](../design/reference-host.md) recommends
routing on current semantic risk, which may include operation, target scope,
permissions, classification/egress, actual logical item/record count,
amount/cost/write bytes, irreversibility, partial application and
reconciliation capability, actor and current allowances. One 1000-item Effect
is not presumed safer than two one-item Effects.

Packaging independent work without changing action semantics, failure guarantees
or authority MUST NOT change account routing or the decision subject presented
to the Host. Provider atomicity or real ordering changes are not such a
packaging equivalence. An earlier decision is reusable only while its bound
scope, context and validity still apply; changed egress, destination, Site,
cost or other decision inputs require a valid new decision or foregoing the
transformation. Cumulative risk/spend uses logical request or explicit
operational-period scope, not a reset per stage. Unknown future values use
finite reservations and concrete admission, not forced review based on stage
count. Node-count capacity is separate and not overridable by a decision.
Record the account configuration identity and outcome and, for a delegated
decision, the Host decision evidence. Graph launch allowlists remain separate
admission.

<a id="logical-request"></a>

### Logical request and item recovery

<!-- requirement-block: logical-request.product-2af972f63b66 logical-request.product-5fbdd5fa2eb2 logical-request.product-c3acfb1394ec logical-request.product-a93ff1904dcb -->

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
The 0.1 caller ID is nonempty, NFC/LF-canonical, contains no C0/C1 control or
DEL character, and is at most 256 UTF-8 bytes. A caller may impose a tighter
limit before durable admission. Both Client ingress and Effect dispatch use
the same logical-request owner and canonical preimage; a stored nonconforming
key is rejected rather than silently normalized during recovery.
The request fingerprint binds Program Definition, effective parameters and
caller input intent, not physical workers, attempts, secrets or wall clocks.
The same scoped ID with a different fingerprint MUST fail as a conflict.
Separate scoped IDs permit intentional repeated business requests.

The following CID preimages are closed. CID fields identify canonical envelopes
without self-CIDs; schema/law IDs are pinned by the checked contract.

```text
LogicalRequestScope = CID({version: "actql-logical-request/0.1",
  authority_scope_cid, caller_request_id})
IntentFingerprint = CID({version: "actql-logical-request-intent/0.1",
  caller_input_intent_cid, parameter_values_cid,
  program_definition_cid})
LogicalItemLocator = CID({version: "actql-logical-item/0.1",
  logical_request_scope_cid, unit_namespace, effect_id,
  item_correlation})
DispatchKey = CID({version: "actql-row-idempotency-key/0.1",
  logical_request_scope_cid, effect_preview_cid, row_or_item_key})
```

The intent fingerprint uses the checked Program Definition and effective
Parameter Values identities. `caller_input_intent_cid` must identify the
admitted caller input selection, including its explicit absence for a
source-free Program. It is not a hash of raw source text, transport JSON,
physical Run identity, Site placement or authorization timestamps. An
environment must establish that input CID under its applicable input
contract before accepting the request; an arbitrary caller-supplied CID does
not itself prove that input is admitted. The logical request key and intent
fingerprint are distinct: an identical intent under a new caller request ID
is a new logical request, while a changed intent under the same key conflicts.

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

<!-- requirement-block: preview-strength.current-row-outcome-halt-continue preview-strength.unknown-row-must-not-invent-terminal-receipt -->
| Current row outcome | `halt` | `continue` |
| --- | --- | --- |
| `applied` or valid `accepted` | Dispatch next row | Dispatch next row |
| `failed` | Later rows unattempted | Dispatch next row |
| `unknown` | Later rows unattempted; reconcile current row | Dispatch other rows only; reconcile current row without resending it |

Admission/preflight failure dispatches no rows under either policy. Per-item
continuation does not override whole-set preflight or the Effect Set's separate
`attempt_all` member policy. A member receipt contains one ordered `rows`
entry per Preview row. It binds the Run, Preview, and member identities;
each entry binds a distinct Preview row CID and ordered index. Terminal rows
(`applied`, `accepted`, `failed`) reference the exact dispatch, attempt, and
durable typed Outcome Receipt. An `unknown` row references the exact durable
Ledger head instead; it MUST NOT invent a terminal Outcome Receipt. An
`unattempted` row has no dispatch. A `rolled_back` row references the failed
typed Outcome Receipt and common provider-atomic batch result, never an
independent success. Identical row content in distinct occurrences retains
distinct row identities. `accepted` does not assert provider completion
([Outcomes and reconciliation](#reconciliation)).

<!-- requirement-block: preview-strength.effect-set-receipt-must-match-member-partitions -->
An Effect Set apply receipt MUST agree with the referenced member receipts.
Each entry's state reflects its member's row partition: `unknown` takes
precedence; any failed row, or unattempted/rolled-back rows mixed with success,
yields `failed`; only unattempted rows yield `unattempted`, and only rolled-back
rows yield `rolled_back`; otherwise any accepted
row yields `accepted`, and the remaining case is `applied`.
The set status is `unknown_outcome` if any row is unknown; otherwise it is
`partial_failure` for both successful and failed/unattempted/rolled-back rows,
`failed` for only failed/unattempted/rolled-back rows, `accepted` if any row is accepted, and
`applied` otherwise. The set receipt references every member receipt exactly
once; it does not duplicate all rows or carry a singleton member outcome.
These consistency checks do not prove physical row outcomes; their evidence
remains a separate Host admission obligation. Reconciliation targets only
unknown rows, leaves prior receipts immutable, and never resends a known
successful row.

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

<!-- requirement-block: reconciliation.effect-row-outcome-receipt-binds-saved-response -->
For a physically observed row, `actql-effect-row-outcome-receipt/0.1` binds
the exact private Preview, member and row CIDs, the durable dispatch entry,
credential-use CID, HTTP status, response byte count and physical SHA-256,
and the complete typed provider outcome with its independently computed CID.
Its `receipt_cid` is the CID of the complete canonical body without that
self field. The response digest identifies the saved bounded HTTP bytes; it
is not a logical Result CID. The common Host MUST verify that the saved
response belongs to the exact dispatch, issue and durably retain this receipt,
and admit its Preview, response and typed-outcome bindings before recording
that CID as a terminal row Ledger `outcome_receipt_cid`. A response that was
possibly sent but not saved and admitted remains `unknown` without a terminal
Outcome Receipt. Shape validation or a matching current provider value alone
does not prove the earlier attempt succeeded. Evidence viewing and replay
require their own current authorization and never permit another send.

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
| `run_identity_cid`, `effect_preview_cid`, `effect_member_preview_cid`, `row_preview_cid` | Exact original Run, Preview, member, and one unknown row. |
| `dispatch_entry_cid`, `dispatch_attempt_sequence`, `prior_ledger_head_cid` | Original physical dispatch occurrence and latest unresolved Ledger head. |
| `effect_set_receipt_cid` | Exact pending Effect Set receipt. |
| `prior_receipt_cid` | Original member apply receipt, unchanged across attempts. |
| `attempt_sequence` | Positive attempt number, beginning at 1. |
| `previous_reconciliation_receipt_cid` | Immediately preceding attempt; absent on attempt 1 and required thereafter. |
| `terminal` | `false` exactly when `outcome.state` is `unknown`. |
| `operation_ref` | Operation correlation; mutually exclusive with command correlation. |
| `command_id`, `idempotency_key` | Command correlation; both required when `operation_ref` is absent. |
| `outcome` | One fully validated closed `EffectOutcome`, not just a state name. |
| `outcome_receipt_cid` | Required for terminal row resolution; absent while outcome remains unknown. |
| `reconciliation_receipt_cid` | Self-CID of the receipt. |

<!-- requirement-block: reconciliation.the-host-must-validate-the-original-member-and-effect-set reconciliation.subsequent-receipts-must-extend-the-latest-receipt-for-the-same -->
The Host MUST validate the original member, Effect Set, and exact unknown
Preview row and Ledger bindings before accepting a receipt. A known terminal
row is not eligible for reconciliation. Exactly one correlation form is
required. Subsequent receipts MUST extend the latest receipt for the same row, with
`attempt_sequence` incremented by one and its exact CID as
`previous_reconciliation_receipt_cid`.

<!-- requirement-block: reconciliation.exact-receipt-redelivery-is-idempotent-a-different-receipt-after-a -->
Only a nonterminal `unknown` outcome permits a further attempt. `applied`,
`accepted`, and `failed` close the chain. Exact receipt redelivery is
idempotent; a different receipt after a terminal attempt MUST fail as a
conflict. Thus `unknown → unknown → applied` is valid for one row, but a
terminal result cannot be replaced by a later attempt. Reconciliation is an
observation of the old dispatch, not authority to re-send it.

<!-- requirement-block: reconciliation.initial-application-and-each-reconciliation-must-determine-the-run-outcome -->
Initial application and each reconciliation MUST determine the Run outcome
from every row of every member of the original Effect Set, using its latest
validated outcome. The following table is evaluated from top to bottom:

<!-- requirement-block: reconciliation.effective-member-outcomes-run-state-any -->
| Effective row outcomes across all members | Run state |
| --- | --- |
| Any `unknown` | `needs_reconciliation` |
| No `unknown`, but any `failed`, `unattempted`, or `rolled_back` | `failed` |
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
