---
spec_id: actql.protocol.run-graph
status: adopted
version: actql/0.1
normative_dependencies: [actql.execution, actql.protocol.artifacts]
---

# ActQL run-graph

[Specification index](../README.md)

<!-- normative-import: actql.execution actql/0.1 -->
<!-- normative-import: actql.protocol.artifacts actql/0.1 -->

This document owns finite-process-graph, typed-activation, attempt-lifecycle, cross-run-bindings. It does not define other owners' wire protocols or a particular Host implementation. Cross-owner links outside the declared dependencies are informative navigation to protocol bindings or conformance evidence; they do not import those documents' requirements. Narrow machine contracts remain authoritative for their explicitly referenced values and envelopes.

<a id="run-graph"></a>

### Run Graph companion protocol

`actql-run-graph/0.1` is a separate portable process protocol. It is not an
ActQL source operation or hidden intermediate language. ActQL's own linear
stage order may be lowered to its constrained generated form below; the general
companion's business routing is not Program vocabulary.

The boundary with a single Run is defined in [Boundary with later work](../execution.md#later-work). A Run Graph is finite and
static. Its closed `activation.all` conditions and typed Artifact bindings are separate.
Activation waits for every listed predecessor outcome or exact contract-bound
ControlToken value; it does not transform data.
Node kinds are limited to `program_invocation`,
`effect_apply`, `effect_reconcile`, `approval_gate`, `timer`, `opaque_task`,
and `observation_capture`; arbitrary expressions, business
predicates, loops, and recursion are absent. Operational transitions are
separate from typed data bindings. Business routing is possible only through a
content-addressed `ControlToken` whose exact value belongs to a closed token
contract produced by an earlier Result Artifact; the Run Graph cannot evaluate
the business predicate itself.

<!-- requirement-block: run-graph.same-observation-replay-must-not-read-a-provider-and-effect-unknown-must run-graph.same-observation-replay-must-not-read-a-provider-and-effect-unknown-must.second stage-lowering.product-e7f128ebec10 control-milestones.product-4f5627f5ce25 control-milestones.product-47f57b011863 shared-context.product-69cffe9bc844 shared-context.product-04a9e7a8f441 commit-scopes.product-5a78a63bbf72 commit-scopes.product-67654191511e -->
Retries distinguish computation replay over the same materialized
ObservationSet, recapture as a new Invocation, retry of an idempotent Effect,
and reconciliation of an outcome-unknown Effect. Same-Observation replay MUST
NOT read a provider, and `effect.unknown` MUST NOT transition to ordinary apply
retry. A same-Run retry preserves the bound continuation plus the deterministic
Effect and row idempotency keys. Every graph pins a transitive lock and produces
typed node-attempt and run receipts with explicit time, request, byte, row, and
task budgets. Only idempotent Opaque Tasks may use explicit retry. Reconcilable
tasks use reconciliation, and tasks with no idempotency guarantee forbid retry.

<a id="stage-lowering"></a>

### Linear Program stage lowering

The general companion's routing capability does not become ActQL source
workflow syntax. A Program stage list MUST lower to a fixed linear sequence of
ordinary Run units, with both predecessor success and typed import availability in
activation. Completed is the default; explicit accepted changes only the success
gate, not data availability. No-data-dependency notifications keep their place.
Fresh reads cannot be hoisted. Each stage retains an unordered Effect Set and
its own captured invocation; stages need not map one-to-one to physical tasks.

Unknown outcomes route to reconciliation, failure/partial application blocks
normal successors, and no rollback or failure branch is synthesized. Completion
polls are bounded Host work producing separate evidence; they do not mutate a
prior ObservationSet. Resume preserves Program engine/contract pins and the
logical request/item ledger. Watch, scheduling and explicit recovery Programs
remain outside the finite Program; dynamic/self-recursive stage lists are invalid.

Stage-specific orchestration laws and runtime dispatch branches are forbidden.
The compiler shares static checking, lock resolution, effective parameters and
typed producer-interface inference, then emits ordinary graph nodes, control
milestones, data bindings, commit scopes and output references. It must not wrap
a stage interpreter in opaque_task. General explicit failure/ControlToken routing
remains legal; linear stages simply do not synthesize those edges or a Saga.

<a id="control-milestones"></a>

### Control milestones and data readiness

DependenciesReady is the conjunction of all control milestones and verified
availability of every required binding. Dispatch also requires current node
admission. A synchronous applied item satisfies accepted as well as completed;
failed, unknown and unattempted items satisfy neither success milestone. Unit
success covers all required items; a node's terminal status alone does not prove
asynchronous provider completion. Completed edges additionally require the
specified provider completion. Missing finite completion capability is unsupported.

An empty typed Relation is available data, not an absent port. An accepted edge
with a completion-only file Ref still waits for that Ref. Impossible success
conditions record downstream unattempted with a reason; unknown remains pending
reconciliation. No-data-dependency notifications retain control edges, and fresh
reads start only after activation. Completion observations use the common bounded
timer/capture contracts, not mutation of an already sealed ObservationSet.

The static requirements live in the narrow
`actql-run-graph-execution-definition/0.1` extension, not in runtime activation
evidence or hidden stage metadata. It binds an unchanged base Run Graph
Definition, shared-context contract, named success/data requirement CIDs,
commit-scope CIDs, each node's exact control/data requirement arrays and exports.
The corresponding execution lock binds this extension, the base graph lock and
every extracted unit contract. The effective execution identity is the extension
CID; loading the base definition alone MUST NOT execute a bundle requiring it.
This is one common extension for extracted and authored graphs, not a second
stage scheduler. Old Run Graph schema/CID laws are unchanged and do not claim
support for this extension.

shared_context_contract_cid resolves to `actql-run-graph-shared-context/0.1`:
the pinned engine contract, effective-parameter binding, whole lock, canonical
base resource-budget value, logical-request contract and source-ownership
contract. Its effective_parameters_cid uses the registered effective binding;
resource_budget_cid hashes the base definition's exact resource_budget value.
All nodes inherit this one context, while local semantic projections retain only
their used values/contracts. Load checks lock/context/budget correspondence;
it does not accept independently chosen per-node budgets or caller defaults.

Success requirements bind producer computation, milestone, exact Effect-node
and Effect-contract maps and any completion-node/contract maps. Data requirements
bind producer port, consumer input, value contract, semantic artifact kind and
availability. These maps must match checked producer interfaces exactly; missing
an Effect is not an optimization. Activation names the exact execution definition
and node; the validator resolves its sealed requirements and verifies every
control and binding proof against them, including issuer, correlation and scope.
Evidence cardinality, an empty list or a self-CID alone never proves readiness.
Base exact-outcome/ControlToken conditions remain additional conjuncts.

The canonical generated topology is fixed below. Node IDs are canonical JSON
strings encoding `[Program.id, stage.id, role, declared_slot]`; role is compute,
apply or completion, and compute uses an empty slot. No global counter or source
array index enters a node ID. Base nodes retain stage order for serialization;
within a stage emit compute, then apply nodes by canonical Effect name, then
required completion nodes by that same name. Physical scheduling does not use
that serialization order to order sibling Effects.

| Declared work | Base node/binding | Extension requirement |
| --- | --- | --- |
| Each stage | program_invocation compute node, same-observation replay | predecessor success gate plus every import's data requirement |
| Each Effect | effect_apply node; compute effects.NAME.preview to apply preview | compute completed; admission/review inside the ordinary Effect boundary |
| Provider completion demanded by gate/import | observation_capture node with pinned bounded completion contract; semantic completion_source binding from apply receipt to artifact | accepted gate; synchronous applied is a no-provider completion witness |
| Result import | semantic data binding from compute results.NAME to consumer source.NAME | producer unit success and result availability |
| Receipt import | semantic data binding from apply receipt (and completion evidence if required) | whole producer success plus exact accepted/completed availability |
| Zero Effects or zero items | compute/preflight evidence, typed empty ports | successful computation and complete checked empty item set; no fake apply receipt |
| Failure or unknown | preserve item/attempt evidence | no success gate; reconcile through common bounded recovery, never implicit retry |

Generated base activation contains only compute-completed conditions for apply
nodes. Success gates and semantic imports are stored only in the extension,
not duplicated as exact effect.accepted edges (which would reject synchronous
applied). Its data_requirements are the canonical wiring for semantic imports;
base bindings carry preview transport only. A completion_source contract is a
closed union of verified synchronous applied/empty-item evidence and accepted
item evidence carrying genuine OperationRefs. Its input is not an invented
OperationRef for a synchronous or empty result. The common completion capture
performs no provider call for the former and only bounded contract-admitted
observation for the latter. Unsupported finite
completion/reconciliation capability remains unsupported rather than invented.
Each accepted/completed requirement has a stable key derived from producer
namespace and milestone; import keys use consumer namespace/input name. Final
unit success defaults to completed; any independently authored graph override is
explicit in its sealed requirements. No stage-only final-success assumption is
read at runtime. Load validates all unit definitions, graph acyclicity, exact
bindings, budgets and requirements before dispatch, including static completion
work ceilings. General graph admission uses the same rules.

<a id="shared-context"></a>

### Shared compilation and extracted equivalence

All nodes and producer interfaces MUST pass static checking before any provider
work, including independently extracted Programs loaded as a graph. Future typed
ports are not missing user parameters and do not contain fabricated values.
Bind effective user values once; each node uses its normative projection. Whole
lock, shared budget and source batch ownership stay graph-level. Current node
admission still verifies concrete imports, issuer, scope, policy and limits.

canonical_graph(lower_stages(P,C)) equals canonical_graph(load(extract(P,C))).
The extraction bundle includes namespaces, membership, control edges, bindings,
shared context, budget, commit scopes and exports, not just separate source files.
With the same scripted observations/clock/policy/logical request, both entry
paths MUST have equivalent approvals, allowed Effect orders, outcomes, normal
and exceptional commits, recovery and resend eligibility. Independent fresh
provider IDs, clock values and signature nonces need not be byte-identical.

<a id="commit-scopes"></a>

### Source commit scopes and recovery ownership

Enroll a producer in its commit scope before capture. Persist the exact raw
batch/checkpoints, source contract, previous generation and required node
milestones. Generated stages use all required ordinary nodes. Normal eligibility
waits for those milestones; a valid accepted final node needs no extra completion
requirement if the graph declares none. Graph output availability, flow success,
provider completion and delivery success remain separate axes.

A pending subscription batch MUST resolve to its durable capture and logical
request before a scheduler fetches another page or invents a new request id.
Source ownership uses stable Program namespace/local source, Connector/SourceView,
checkpoint law and semantic request, not unrelated downstream revision bytes.
Membership/deployment admission and generation fencing prevent two revisions
from committing concurrently. A real source/request/checkpoint change requires
explicit migration. Separate subscriptions are separate scopes.

Normal or exceptional eligibility is a narrow versioned artifact verified by
Execution. Exceptional advancement requires the separate operator claim and an
exact disposition for every unmet obligation. Known failed/unattempted work may
be explicitly abandoned. Unknown or incomplete accepted work MUST be durably
handed off with original intent, keys, OperationRef and uncertainty preserved;
without a valid owner/retention/resume contract it remains pending. A handoff is
not proof of not_applied and does not authorize resend or satisfy a success edge.

Fence new dispatch before issuing the claim over a state revision. Atomically
bind claim, dispositions, handoff ownership and commit eligibility; provider ack
uses a recoverable outbox, not a claimed distributed transaction. Per-partition
CAS and ack evidence remain distinct. Changed outcomes/generation invalidate the
old claim; identical redelivery is idempotent. Late provider responses remain
evidence for the original item but cannot grant a fenced worker new authority.
Graph/node failure history is immutable; exceptional commit is not graph success.

commit_scope_cid resolves only to `actql-graph-commit-scope-definition/0.1`.
It seals producer/source-input identity, SourceView and checkpoint contracts,
ownership/partition-state contracts, policy and the exact nonempty required
gate list. The execution definition and lock bind it before capture. Enrollment
then binds that static scope to captured batch, actual state revision and prior
generation; runtime eligibility must refer to that same scope/enrollment.
Generated scopes require the capturing unit and all dependent suffix units,
using their declared outgoing milestone (final defaults completed). Independently
authored A-only versus A+B commit scopes therefore have different execution/lock
identities and require separate admission. Neither capture nor an operator may
substitute a narrower scope afterward.

Cancelled, timed_out, budget_exhausted and rejected node obligations remain
truthfully labelled in exceptional claims. Item evidence is complete even under
cancelled parents; applied work is retained and unknown/accepted-pending work
requires durable handoff. Only proven known nonapplication may be abandoned.
Claims bind both node-milestone and item obligations explicitly. The total
classification and fencing rules are owned by Execution's cursor recovery;
exceptional commit never satisfies an ordinary success gate.

<a id="graph-outputs"></a>

### Local Results and graph outputs

Every declared node Result remains an execution root. Public outputs reference
existing node Results and do not compute a second Invocation. Complete output
indexes require every declared export and truthful flow-status evidence. Earlier
Results survive later failure for authorized inspection, without fabrication of
complete business success. Result-derived receipt values require a later node;
they cannot be appended to the producer's already materialized Result.

<a id="machine-contracts"></a>

## Machine contracts

These exact schema/law references are owned here. Their identities do not include this document or another owner's aggregate contract.

<!-- requirement-block: machine-contracts.exact-artifacts -->
<!-- normative-code: law -->
```text
../../../spec/contracts/actql-production-profile-schemas.json#/schemas/run_graph_definition sha256:749011ea74c80247102429b3cc9c0551b8dabbbfbf9d1a125ff74d989b21ec31
../../../spec/contracts/actql-production-profile-schemas.json#/schemas/run_graph_lock sha256:d0fc4243dac87b489db90bf1a25a12f367563c1281b38c9ffb53741f9e74411f
../../../spec/contracts/actql-production-profile-schemas.json#/schemas/run_graph_node_attempt sha256:bae9dc848bbafbf49fe53aeb22b7b011cc75b9fe0407f0f85544a36b69b0f3b4
../../../spec/contracts/actql-production-profile-schemas.json#/schemas/run_graph_run sha256:285ddce81ff649877f0b715549fe24554c7aa688fcacf2197c858a3bff49e7a2
../../../spec/contracts/actql-production-profile-schemas.json#/schemas/run_graph_receipt sha256:6a868ac5d876ee1c54c4e0d96b8a86e08dfb097afa0cfe37bf8c03be32d41aed
../../../spec/contracts/actql-production-profile-schemas.json#/schemas/control_token_contract sha256:9598f3a03a80d05513d05a5d57e6860b4cc7c82d3867c4e520825288eb084a5f
../../../spec/contracts/actql-production-profile-schemas.json#/schemas/control_token sha256:2a388b541a648dab8799ed93530d5a0b7fcca2c0cf84db69d18b5dca60bc9f3b
```

<!-- stage-contract-pins:start -->
```text
../../../spec/contracts/actql-stage-contracts.json#/schemas/activation sha256:5f9c1d24c764ce33a350969e4fe07d56ead5c1e8df184c8872adce40a5792fba
../../../spec/contracts/actql-stage-contracts.json#/schemas/membership sha256:be3ea349d346317939af46d20a883c4c6d8087cb5b42ed2d57117ec8270f61c5
../../../spec/contracts/actql-stage-contracts.json#/schemas/graph_success sha256:3ca71240e13c2ae429eb48a3069d2c378c7ef6abefc53a7cb4754269aedbec4b
../../../spec/contracts/actql-stage-contracts.json#/schemas/graph_outputs sha256:d0bbdb49780ca608792eca708ae6bc7dfbf79b2b63dcf768ad9d7e3d47b4c5ce
../../../spec/contracts/actql-stage-contracts.json#/schemas/recovery_link sha256:76a96bfbd35b3614ea8ae4cea96ec13953d164c8a8a36868d791d2fae41f7d85
../../../spec/contracts/actql-stage-contracts.json#/schemas/gate_requirement sha256:7556fa58d35f66d498511ef31800cddda05bacdb1f4eba7d654010ee9994351d
../../../spec/contracts/actql-stage-contracts.json#/schemas/data_requirement sha256:271f95c2ebe994717bd97fd1ea527c53663f77dbf6d3f01779c41bb480b5bd35
../../../spec/contracts/actql-stage-contracts.json#/schemas/commit_scope sha256:087ce38cb682aedfce9ef5658bf22133df549608668d2c6361f913c9a2cea22d
../../../spec/contracts/actql-stage-contracts.json#/schemas/graph_execution_definition sha256:1631353b8af6dfe7363b3e09afdc96ce5a55ef1edc0eb188f73ac5fa6e542952
../../../spec/contracts/actql-stage-contracts.json#/schemas/graph_execution_lock sha256:4a32e2ee2507e68dbb2f9319d6cf978741bfbb7c1ba77ae6f79cc9b08185006d
../../../spec/contracts/actql-stage-contracts.json#/schemas/graph_shared_context sha256:8df501dc3d23a6342066379d942f696174ae83464e24a082f1a35b6f4945e2c0
```
<!-- stage-contract-pins:end -->
