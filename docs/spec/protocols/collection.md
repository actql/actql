---
spec_id: actql.protocol.collection
status: adopted
version: actql/0.1
normative_dependencies: [actql.execution, actql.protocol.artifacts]
---

# ActQL collection

[Specification index](../README.md)

<!-- normative-import: actql.execution actql/0.1 -->
<!-- normative-import: actql.protocol.artifacts actql/0.1 -->

This document owns collection-definition, collection-execution, accounting, collection-evidence, coverage, integration-binding. It does not define other owners' wire protocols or a particular Host implementation. Cross-owner links outside the declared dependencies are informative navigation to protocol bindings or conformance evidence; they do not import those documents' requirements. Narrow machine contracts remain authoritative for their explicitly referenced values and envelopes.

<a id="collection"></a>

### Read collection protocol

<!-- requirement-block: sealed-admission collection.product-10e756419aa6 -->
`actql-read-collection/0.1` defines `slots`, execution `budget`, and its
`collection_definition_cid`. `actql-collection-evidence/0.1` binds that definition,
canonical current outcomes, their usage, `coverage_complete`, and its own CID.
Self-CIDs hash the complete envelope without the self-CID. Slot and allowed-class
sets use canonical lexical order; attempts retain execution order. Budgets count
requests, bytes, tokens, integer cost units, and cumulative attempt milliseconds.
Factory inputs may be ordered into canonical sets. Sealed Definition and
Evidence admission MUST validate the received body, set order, closed shape,
and self-CID without sorting or repairing the artifact.
An Execution binds the accounting contract that fixes cost-unit interpretation. Host admission
verifies each exact Program is Effect-free before any dispatch. Attempt evidence
verification authenticates Program identity, execution scope, consumption, and
successful Result/schema/policy linkage; a caller-provided hash is insufficient.

A collection MUST remain a read-only same-type union boundary across all stages
of its source Programs. It does not admit Effects or heterogeneous composition.
All source Runs failing cannot produce a successful collection; this is distinct
from an infer stage successfully capturing explicit failure outcomes for every
model slot. Program export references bind successful complete manifests, not
an earlier stage artifact taken from a failed Program.

A finite read collection coordinates Effect-free source Runs independently of
the general Run Graph protocol. Integration is a separate, explicitly started
Effect-free Run. Each source slot declares required/optional status,
accepted failure classes, exact Result names/types, attempt limits, and budgets.
Completion requires every slot resolved, all required sources successful, only
explicitly permitted optional failures, and at least one successful source.

The initial allowlist covers contracted provider unavailability, transport
timeout, and provider-specific rate-limit exhaustion. Authentication,
authorization/egress denial, cancellation, schema/CID/issuer invalidity, engine
failure, global budget exhaustion, safety refusal, unknown classes, and unresolved
Effects are not optional failures. Classification is versioned evidence, not
message matching. Failed attempts retain all consumed resources.

`CollectionEvidence` binds the collection definition and every source slot
exactly once in canonical slot order, with Run/attempt evidence and either exact
successful Result references or permitted failure evidence. It never invents
an Invocation or Result Manifest for a failed attempt. Unattempted or unresolved
work cannot count as permitted unavailability. Integrity, issuer trust, and
disclosure authority are checked separately.

`actql-collection-inputs/0.1` projects successful Result references and a typed
coverage Relation with `source`, `status`, `reason`, and
`observation_completeness`. Available rows have null reason and preserve their
Result's `complete` or `partial` value. Unavailable rows have a permitted failure
reason and null observation completeness. Contradictory variants are rejected.
Required means successful, not necessarily complete. A user-authored status table alone
is not evidence. Public labels/reasons are authorized projections, not raw
provider errors. ModelTask input mappings explicitly include required coverage;
the Host does not inject explanatory prompts. Collection completion proves
declared handling, not observation of every source. Coverage remains in Result
provenance and review even if omitted from displayed columns. It neither grants
write authority nor supplies missing absence evidence for a later Effect Run.

Failed Runs remain failed. Replay reuses fixed outcomes without provider access;
explicit recapture creates new evidence and a new downstream invocation without
resetting collection budgets. Effect `unknown` still requires reconciliation.
Same-Run per-key acquisition outcomes are a separate future profile, not a
`nullify` option on ordinary join or inference.

##### Execution identity and accounting

`actql-collection-execution/0.1` binds a fresh execution ID, Definition CID,
authenticated scope CID, accounting-contract CID, exact per-slot bound-invocation
CIDs, and initial budget. Its self-CID identifies this execution, not the reusable
Definition. Starting another execution is explicit and produces another identity.

`actql-collection-execution-state/0.1` binds the execution, revision, predecessor
state CID, cumulative attempt ledger, current slot outcomes, and an optional
reservation. Initial state has revision zero, no predecessor, empty ledgers,
and no reservation. Later transitions increment revision and bind the previous
state. Attempt IDs cannot repeat across slots or recaptures; cumulative per-slot
attempt counts and every resource dimension remain within the Definition.
Current outcomes refer only to attempts accounted for in that execution.

<!-- requirement-block: execution-reservation-admission -->
Before dispatch the Host MUST authenticate the current scope, invocation and
accounting contexts and latest saved state, then durably compare-and-swap a
reservation. The finite serial adapter reserves all remaining resource budget
for that dispatch. Remaining budget is initial minus cumulative usage minus
outstanding reservation; duration counts attempt milliseconds, not a deadline.
Execution enforces the supplied remaining limits before and during I/O.
Only verified consumption can release unused reservation. An exception, lost
response, invalid outcome, or failed completion persistence leaves consumption
unresolved; retry cannot reset it to zero or dispatch through the reservation.
Accounting reconciliation is required before that execution can continue.

Recapture names already resolved slots explicitly, retains their old attempt
ledger, and replaces only their current outcomes. Resume reuses saved outcomes.
`actql-collection-execution-evidence/0.1` binds final execution/state identity,
cumulative usage, and the current CollectionEvidence. Snapshot evidence alone
does not attest execution-wide accounting across recapture. Host persistence
and current-state authentication are mandatory adapter responsibilities, not
claims derived from self-CIDs or a specific database implementation.

##### Homogeneous integration binding

The standard `actql-collection-union/0.1` adapter fixes one checked closed row
schema, a fresh string source field, and non-null primitive row-identity fields.
Identity fields are unique within each successful source; source plus that tuple
distinguishes rows across slots. This restriction belongs to the union adapter,
not collection's ability to retain heterogeneous Result references.

<!-- requirement-block: homogeneous-union-materialization -->
The adapter MUST validate authorized successful Result materializations,
schema and payload identities, then use `REL.derive` to add the source literal
and `REL.unionAll` to concatenate them in canonical slot order, preserving each
Result's row order. It supplies exactly two typed Relations: `observations`
and `coverage`. Failed slots contribute no invented input or placeholder row.
At least one source must succeed; a successful zero-row Result retains its
schema and available coverage row. No JSON conversion or provider access occurs.
Observations are partial for the declared all-slot scope if any slot is
unavailable or partial; coverage is complete as a record of slot outcomes,
not as evidence that all business data was obtained.

<!-- requirement-block: integration-completeness-provenance -->
`actql-collection-integration-binding/0.1` binds CollectionEvidence, union
contract, exact source Result references, canonical union pipeline, both input
materializations (schema, rows, completeness), and their CIDs. Before explicitly
starting integration, the Host reauthorizes that binding; Core checks the exact
Program is Effect-free and its observations/coverage declarations accept the
checked input contracts under `Assignable` ([Closed value contracts](../language.md#value-contracts)).
Success Results still have exactly the union's checked schema. Stronger input
bounds and nullability remain source evidence in the pinned Check Environment.
An unbound template cannot start integration. The private start request fixes
the checked parameter and opaque values and their identities, Program Definition,
bound Invocation Template, checked Plan, resolvable Check Environment, both
materialization identities and IntegrationBinding provenance. The Host MUST
preserve those values, contracts, completeness and provenance, rejecting an
environment or bound-identity mismatch before dispatch rather than importing
just the rows as ordinary complete local inputs or recovering bindings implicitly.
The collection API does not secretly start integration or authorize later Effects.

<a id="machine-contracts"></a>

## Machine contracts

These exact schema/law references are owned here. Their identities do not include this document or another owner's aggregate contract.

<!-- requirement-block: machine-contracts.exact-artifacts -->
<!-- normative-code: law -->
```text
../../../spec/contracts/actql-read-collection.json#/schemas/read_collection_definition sha256:87e910f098f6155fcb02291641a125955edf4f8171bd8a08171851b61f428ade
../../../spec/contracts/actql-read-collection.json#/schemas/read_collection_outcome sha256:5bdf3059c36051367cc695a003e0b314614fcdad188a61e0606e3ed985321a61
../../../spec/contracts/actql-read-collection.json#/schemas/collection_evidence sha256:ff73f8399cad730f9283d8cbe5b934038d712b9602417354aa1b944bb54c7328
../../../spec/contracts/actql-read-collection.json#/schemas/collection_execution sha256:ecec7bddd86ceddbcae23bec38f4ed2b2bc556c6b5a2b03367ac3a918a2c717e
../../../spec/contracts/actql-read-collection.json#/schemas/collection_execution_state sha256:06233f48ac77835af9d446ec3027958d5a2b2b411403fa06074a90b01ce6f412
../../../spec/contracts/actql-read-collection.json#/schemas/collection_execution_evidence sha256:fffc7a866c73f77a5d1bbe1cacef1f01fe7eb937bb2480e3c233259c10c7d87a
../../../spec/contracts/actql-read-collection.json#/schemas/collection_union_contract sha256:a047a8e9bfe7178dc1d1ffdc2e237d327acec776bbbece5dcd014eea20d42931
../../../spec/contracts/actql-read-collection.json#/schemas/collection_integration_binding sha256:b37e6a524bdf6509420fdcb47b1f8a4573806c17474838e90af093d84203b3da
../../../spec/contracts/actql-read-collection.json#/schemas/collection_inputs sha256:1a17c5a8795ecada711e9fbee0ca4b5b159c10cf6b5a005965af705e67c5c9ae
../../../spec/contracts/actql-read-collection.json#/laws sha256:017718057ac839a8db9727fff36302971a9e3e677faa70c591a5e6f027a46d0f
```
