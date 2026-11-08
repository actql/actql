---
spec_id: actql.protocol.artifacts
status: adopted
version: actql/0.1
normative_dependencies: [actql.language, actql.execution]
---

# ActQL artifacts

[Specification index](../README.md)

<!-- normative-import: actql.language actql/0.1 -->
<!-- normative-import: actql.execution actql/0.1 -->

This document owns result-artifact, result-manifest, result-delivery, store-admission, availability-leases. It does not define other owners' wire protocols or a particular Host implementation. Cross-owner links outside the declared dependencies are informative navigation to protocol bindings or conformance evidence; they do not import those documents' requirements. Narrow machine contracts remain authoritative for their explicitly referenced values and envelopes.

<!-- page-contents:start -->
## On this page

- [Terms](#artifacts-terms)
- [Result Artifacts and Manifest](#result-artifacts)
- [Lookup acquisition identities](#lookup-acquisition-identities)
- [Result delivery](#result-delivery)
- [Reference admission and availability](#reference-admission)
- [Stage receipt views and manifests](#stage-receipt-view)
- [Machine contracts](#machine-contracts)
<!-- page-contents:end -->

<a id="artifacts-terms"></a>

## Terms

- **Result Artifact** — the content-addressed metadata and logical identity of
  one materialized named Result. Its row payload is stored separately under the
  Result's effective policy ([Named Results and Effect declarations](../language.md#results-and-delivery)).
- **Result Manifest** — the bounded name-to-Result-Artifact index produced by
  one Run. It contains no Result rows or serialized Result bytes ([Named Results and Effect declarations](../language.md#results-and-delivery)).
- **Result delivery** — an independently authorized release of one Result in
  one canonical serialization, recorded by a delivery receipt ([Result delivery](#result-delivery)).

<a id="result-artifacts"></a>

### Result Artifacts and Manifest

Each named Result published under this protocol emits `actql-result-artifact/0.1`.
The explicitly selected [managed retained execution profile](../execution.md#managed-retained-execution)
can instead expose an owned read handle; that handle is not this Artifact and
conversion into this protocol retains all requirements below. Its closed shape
is:

<!-- requirement-block: result-artifacts.resultartifact -->
<!-- normative-code: grammar -->
```text
ResultArtifact := {
  version: "actql-result-artifact/0.1",
  result_definition_cid: Cid,
  invocation_cid: Cid,
  logical_result_cid: Cid,
  result_schema_cid: Cid,
  ordering_evidence_cid: Cid,
  actual_row_count: NonNegativeSafeInteger,
  actual_completeness: "complete" | "partial",
  effective_data_policy_cid: Cid,
  effective_retention_policy_cid: Cid,
  provenance_evidence_cids: [Cid, ...] | [],
  result_artifact_cid: Cid
}
```

<!-- requirement-block: result-artifacts.concrete-result-data-must-retain-the-policy-derivation-fixed-during -->
The logical Result CID binds the fully ordered Relation value. Concrete Result
data MUST retain the policy derivation fixed during check.

<!-- requirement-block: result-artifacts.after-result-computation-succeeds-the-host-must-create-one-actql-result-manifest-0-1 -->
After Result computation succeeds, the Host MUST create one
`actql-result-manifest/0.1` with the following closed shape:

<!-- requirement-block: result-artifacts.resultmanifest -->
<!-- normative-code: grammar -->
```text
ResultManifest := {
  version: "actql-result-manifest/0.1",
  run_definition_cid: Cid,
  invocation_cid: Cid,
  results: { ResultName: ResultArtifact }+,
  result_manifest_cid: Cid
}
```

The `results` map is name-sorted for canonical serialization and contains every
declared Result exactly once. The manifest contains no Relation rows or
serialized Result bytes. The Run Receipt binds its `result_manifest_cid`.
This keeps Run completion and inspection bounded even when Result payloads are
large; payload bytes remain in authorized artifact storage and MAY be streamed
during delivery.

#### Run-bound publication chain

<!-- requirement-block: result-artifacts.a-run-bound-result-definition-must-resolve-one-exact-checked-result-occurrence -->
A Run-bound Result Definition MUST resolve one exact checked Result occurrence
from its Program Definition and Result name. Its self identity excludes only
`result_definition_cid`. Because this is a Run-bound definition, any Program
Definition change, including a change to another declared Result, changes the
Result Definition identity. It is not the local semantic Result projection.

<!-- requirement-block: result-artifacts.a-run-bound-invocation-must-bind-the-exact-template-and-complete-admitted-observation-set -->
A Run-bound Invocation MUST bind the exact Bound Invocation Template and the
complete admitted ObservationSet. The ObservationSet's template reference must
match, and every required observation must be established before issuance. It
does not contain a future Run Manifest or Run Definition. Equal Invocation
content does not merge distinct Run occurrences.

<!-- requirement-block: result-artifacts.a-durable-result-binding-must-bind-logical-and-physical-identities-with-the-effective-retention-policy -->
A durable Result binding MUST bind the exact Run, Result Definition,
Invocation, ordered logical Result, schema, ordering evidence, codec, material
generation, Store authority, physical digest and size, exact declared Result
field order, and effective retention policy. The payload digest,
LogicalRelation CID, and delivery-byte hash remain different identities even
when one bounded pass computes them. The field order is retained from the same
checked Result export and is not reconstructed from canonical object-key order.

<!-- requirement-block: result-artifacts.effective-result-retention-separates-payload-availability-deletion-and-metadata-deletion result-artifacts.retention-deadlines-have-distinct-authority-and-fixed-order result-artifacts.one-manifest-has-one-metadata-retention-deadline result-artifacts.metadata-reclamation-retains-only-a-minimal-fence -->
An effective Result retention policy MUST bind the admitted retention contract,
effective data policy, payload availability deadline, payload deletion
deadline, extension ceiling, metadata retention policy, metadata deletion
deadline, and trusted clock contract. The closed
`actql-result-retention-policy/0.1` shape is:

```text
ResultRetentionPolicy := {
  version: "actql-result-retention-policy/0.1",
  retention_contract_cid: Cid,
  effective_data_policy_cid: Cid,
  available_until: Timestamp,
  delete_by: Timestamp,
  extension_ceiling_at: Timestamp,
  metadata_retention_policy_cid: Cid,
  metadata_delete_by: Timestamp,
  clock_contract_cid: Cid,
  effective_retention_policy_cid: Cid
}
```

`available_until` is a Store guarantee for an otherwise authorized read, not
read authority. `delete_by` bounds payload reclamation, while
`metadata_delete_by` independently bounds the published Manifest, receipts,
provenance, grants, delivery records, and other Run publication metadata. The
intervals MUST satisfy `available_until <= delete_by <= metadata_delete_by`.
An extension may not change the metadata policy or deadline and may not move
payload availability beyond the extension ceiling or payload deletion
deadline. Retry uses the originally admitted deadlines; it never renews them.

Every Result in one committed Manifest MUST use the same metadata retention
policy and metadata deletion deadline because the Manifest and its Run-bound
evidence form one indivisible publication chain. Payloads may expire or be
reclaimed independently. Metadata reclamation first makes the public index
unavailable, retains unresolved cleanup and capacity responsibility, and then
removes only allocations not shared by another live publication. A minimal
Store fencing record may remain to prevent a deleted Run from being silently
republished, but it MUST NOT retain the deleted Manifest, receipts, provenance,
grants, delivery records, or payload identity inventory.

<!-- requirement-block: result-artifacts.a-publication-attempt-must-not-contain-its-future-outcome-or-terminal-record -->
A Publication Attempt MUST bind immutable request intent, Run, unique attempt,
fence, and start time without containing its future outcome or terminal record.
Append-only progress is serialized with Store compare-and-swap or equivalent
fencing. An unknown commit outcome is reconciled before another attempt; a
durable commit wins a concurrent cancellation request.

<!-- requirement-block: result-artifacts.a-committed-run-must-have-one-public-index-entry-for-its-authority-scoped-run-definition -->
A committed Run MUST have one public-index entry for its namespace and authority
scoped exact Run Definition. The first atomic durable commit fixes its
Invocation, Manifest, and the durable binding for every declared Result. The
same publication intent returns that commit; conflicting Invocation, Manifest,
binding inventory, or intent is rejected. Prepared objects are not visible
through ordinary Result lookup before this commit.

<!-- requirement-block: result-artifacts.manifest-and-result-read-grants-must-be-separate-and-bind-an-exact-committed-manifest -->
Manifest and Result read grants MUST be separate and bind an exact committed
Manifest, principal, namespace, authority scope, purpose, data ceiling, byte and
use limits, and expiry. Result grants also bind exact Result Artifacts, allowed
formats, and egress admission. A pre-commit publication permission is not a
read grant, and an unknown Manifest CID or unrestricted wildcard is invalid.

<!-- requirement-block: result-artifacts.a-delivery-attempt-must-have-an-immutable-identity-separate-from-progress-and-terminal-records -->
A Delivery Attempt MUST have an immutable identity separate from progress and
terminal records. A failed sink records the confirmed prefix separately from
any unknown additional exposure. Retry performs fresh authorization and egress
admission from byte zero and may duplicate bytes; the protocol does not imply
midstream resume or exactly-once delivery.

<!-- requirement-block: result-artifacts.product-09af8ecc4189 result-artifacts.local-result-definition-reference result-artifacts.local-result-invocation-reference -->
That Run-bound Manifest remains an audit/delivery index; its shape and CID law
are unchanged. A local semantic dependency MUST instead use the registered
`actql-local-result-manifest/0.1` projection: `{version, unit_definition_cid,
local_invocation_cid, results, table_inputs?, self_cid}`, where results maps every declared
Result name to its exact Result Artifact CID, sorted by name. No Run Definition,
start/deadline, graph membership or approval is a member. Local Invocation is
`actql-local-computation-semantics/0.1`, binding the local unit, used values,
local contracts, complete observation set and policy. In this combination
the Result Artifact's invocation_cid resolves to that local computation, never
the Run-bound invocation wrapper. Result-definition, ordering, policy and
provenance dependencies must also resolve to their typed semantic contracts.
The local Result Definition is a distinct `actql-local-result-definition/0.1`
contract with `{version, unit_definition_cid, result_name, self_cid}`. Its
semantic preimage is exactly `{result_name, unit_definition_cid, version}`;
`self_cid` hashes that canonical preimage. The checked Unit must declare that
Stage Result name. Run ID, Invocation, physical placement and actual Result
value are not members. A Run-bound `actql-result-definition/0.1` is not an
admissible substitute, even though both identities use the same CID syntax.
The Result Artifact shape above is registered as local_result_artifact in the
stage registry; its `result_definition_cid` MUST resolve to the local Result
Definition, and its `invocation_cid` MUST resolve to the local computation.
Result schema, order and retention fields come from authenticated
checked Result contracts/evidence, never guessed defaults. The artifact and
local Manifest each bind their complete canonical body. Projection context and
the source Run-bound Manifest are retained and authenticated; unavailable
metadata blocks projection.

<!-- requirement-block: result-artifacts.local-table-input-definition result-artifacts.local-table-input-manifest result-artifacts.local-table-input-reference-kind -->
A private Table input MUST use the distinct producer
`actql-local-table-input-definition/0.1` with the closed body
`{version, unit_definition_cid, table_input_name, self_cid}`. Its semantic
preimage is the entire canonical body except `self_cid`; the checked Unit
declares the exact source and projection under that private name. It does not
become an ordinary Result, export or Result import. Its Relation schema retains
presence separately from nullability; the all-Required publication requirement
for ordinary Named Results is unchanged.

The local Manifest MUST additionally map every distinct private input consumed
by a checked Effect in its Unit to its exact Artifact CID in `table_inputs`.
Unused private declarations do not invent capture responsibility. Both maps
are sorted independently by name and remain separate even for equal names or
values. `results` still covers every declared ordinary Result, not merely
Effect-consumed Results. `table_inputs` is omitted when no private input is
consumed and, when present, is nonempty; ordinary-only Manifest preimages are
unchanged. Repeated consumption shares the semantic inventory entry, not the
physical pin or per-occurrence holding responsibility.

The stage registry's `local_table_input_artifact` role MUST resolve its
`result_definition_cid` to `local_table_input_definition`, rather than
`local_result_definition`. It reuses the same sealed semantic Artifact shape,
local Invocation, ordering, policy and retention owners. The private producer
role cannot be inferred from equal payload bytes or substituted for an ordinary
Result role. Missing inventory or unavailable typed dependency bodies block
recovery; a private source is never downgraded to a source-free Effect.

<!-- requirement-block: result-artifacts.local-table-input-capture-kind result-artifacts.local-table-input-capture-correspondence -->
Captured dependency inventories MUST retain private producer, Artifact,
derivation and ordering roles as `local_table_input_definition`,
`table_input_artifact`, `table_input_derivation` and `table_input_ordering`.
The latter three reuse the existing sealed Publication bodies and CIDs while
their typed references resolve the private producer; their kind is not a new
execution owner or a substituted ordinary Result role.
Recovery MUST re-admit the closed producer, both Manifest maps and all semantic
evidence. A private Artifact must match its `table_inputs` name, Unit and local
Invocation; ordinary Manifest entries continue to resolve ordinary producers.
The exact physical source, Preview member and Store holding must also agree.
Missing bodies, a changed namespace or a mismatched projection remain refusal,
not permission to reexecute, invent a Result or send a commit.

The reference-role table in the stage registry is normative for these
projections; reference_graph is generated from it. Every listed CID must resolve
with the expected kind and role. External roles are not opaque exemptions:
their pinned schemas/admission laws recursively classify all references,
retaining required observation, issuer, scope, policy and genuine Ref identity.
Unclassified references, audit ancestry or missing dependency bodies reject local
admission. Canonical relation-value CIDs terminate at validated typed values,
not arbitrary purported artifacts. The entire bundle, not just root field names,
is checked for locality and cycles.

<!-- requirement-block: result-artifacts.local-model-observation -->
A local Model dependency MUST use `actql-local-model-observation/0.1` with
the closed body `{version, unit_definition_cid, source_ordinal,
input_logical_relation_cid, input_relation_schema_cid,
outcome_logical_relation_cid, outcome_relation_schema_cid, self_cid}`. Its
semantic preimage is the complete canonical body except `self_cid`. The same
checked Unit and zero-based logical source-step ordinal select the original
INFER and its task from that Unit's contract closure. The two Relations are
the complete original pre-INFER input and complete adopted Model outcomes
before any later filter, projection or Result selection, including every
adopted non-success outcome. Their logical identities preserve typed values
and genuine Ref identity rather than physical encoding or row placement.

<!-- requirement-block: result-artifacts.local-model-observation-originals -->
Projection MUST retain and authenticate the original Model execution, complete
observation issuer, effective inputs and selected execution contract as its
projection context. Only matching complete export receipts from those same
input/outcome owners can issue the local observation. Run/attempt/provider
audit references are not semantic members or opaque leaf exemptions; missing,
foreign, retired or unresolved originals refuse projection. This observation
does not grant another Model call, publication, Effect application or Saved
restoration. Existing local computation and Result identities are unchanged
when no Model observation is present.

<!-- requirement-block: result-artifacts.result-import-observation-binding result-artifacts.result-import-observation-manifest result-artifacts.result-import-observation-recovery -->
A Stage Result import contributes an
`actql-result-import-observation/0.1` to the consumer's local Invocation
`observation_cids`. Its closed body contains `version`,
`consumer_unit_definition_cid`, `input_name`, `import_interface_cid`,
`producer_local_manifest_cid`, `result_artifact_cid`, and `self_cid`.
The semantic preimage is the complete canonical body except `self_cid`.
The checked input name and import interface MUST select that producer Unit
and Result; its complete local Manifest MUST name the exact Artifact.
The actual read owner issues the observation from its retained input, not
from caller-supplied identities. Equal types or values do not transfer owner.
Every declared Result import has exactly one matching observation, including
an import not subsequently used by a Compute step.

Dependency direction is producer Artifact/Manifest to import observation to
consumer Invocation. Consumer Invocation, consumer Manifest, Run identity,
physical location and current permission are not observation members.
Current Run/namespace membership and permission remain separate checks.
The observation and its complete typed dependency bodies MUST be durable
before exposing resumable approval wait. Restore rejects missing, mixed,
foreign or mismatched dependencies without acquisition or Compute repair.

Projection is deterministic over authenticated Captured Run/apply evidence.
<!-- requirement-block: result-artifacts.product-76552b0b4805 -->
`actql-semantic-projection-attestation/0.1` binds the local semantic CID, original
audit CIDs, graph membership, projection law, issuer, scope, policy and detached
authentication. Recompute the projection from the admitted source and compare
the complete result; a signature over unrelated source/projection bytes is not
enough. The attestation remains outside semantic preimages and MUST be present
at use. A matching unsigned JSON object alone is not an authoritative receipt.
Changing only physical Run/graph revision changes audit/attestation identity,
not fixed local content. Changed producer, actual observation, scope, policy,
guard or genuine provider evidence changes local identity. Old audit receipts
are retained; their CIDs never substitute for local_manifest_cid.

<a id="lookup-acquisition-identities"></a>

### Lookup acquisition identities

<!-- requirement-block: lookup-acquisition-identities.product-774467c23fbe lookup-acquisition-identities.product-4554f0d2d0bd lookup-acquisition-identities.product-7ea9da11d811 lookup-acquisition-identities.product-eaa3962db019 lookup-acquisition-identities.product-bf2864bb4433 lookup-acquisition-identities.product-2ac42b610ae9 lookup-acquisition-identities.product-354e1495b498 lookup-acquisition-identities.product-e655e0e2e3f2 -->
The lookup identity registry fixes the five references in the existing
`actql-lookup-evidence/0.1` schema. These are not aliases for a published Result
Artifact. Both Relation slots use the same `actql-acquisition-relation/0.1`
envelope, with different admission roles. The other envelopes are
`actql-lookup-key-set/0.1`, `actql-lookup-batch-plan/0.1` and
`actql-lookup-attempt-receipt/0.1`. Their complete closed schemas and field-to-kind
mapping are pinned in Machine contracts. Every self_cid is AoA computeCid of
the entire canonical body with only self_cid removed, including version. An
incoming noncanonical body MUST be rejected, not sorted, defaulted or repaired
before checking its hash. Neither a CID-shaped string nor a valid self hash
establishes a reference's kind, authority or correspondence to this acquisition.

| Lookup Evidence field | Required envelope | Identity distinction |
| --- | --- | --- |
| input_relation_artifact_cid | acquisition-relation | The actual evaluated left input, including order, multiplicity and upstream provenance |
| request_key_set_cid | lookup-key-set | Typed distinct non-null request tuples, independent of input enumeration |
| batch_plan_cid | lookup-batch-plan | The exact ordered partition and pinned transport plan |
| attempt_receipt_cid | lookup-attempt-receipt | The actual cumulative acquisition history, not a future Invocation |
| validated_lookup_relation_cid | acquisition-relation | Validated right rows in canonical logical order, with their captured provenance |


An acquisition Relation's logical_value_cid is exactly
`computeCid({sort: "relation", value: canonical_rows})`, reusing the logical
Result value encoding. canonical_rows is the admitted row array, not storage
bytes or an object containing the array. Row order and multiplicity are
semantic; object-member enumeration is not. Canonical typed wire values follow
the existing value contracts, including decimals, timestamps and references.
Exact response/snapshot bytes retain a separate physical artifact identity.
relation_schema_cid is computeCid of the complete resolved field-contract map
(field names to closed recursive machine value contracts). An empty Relation
still binds that map. actual_row_count must equal the row array length.

producer_contract_cid is the checked Relation output-contract CID bound to
barrier.input_ref in the Compiled Plan for an input, and exactly the barrier's
output_contract_cid for a validated output. A whole Plan or AoA fragment CID is
not an alternative producer-contract spelling. It is
not a provisional invocation, fabricated ResultDefinition or current consumer
barrier for the input. ordering_evidence_cid resolves to the actual retained
total logical order witness. observation_scope_cid binds the supplied
observation scope; complete means complete within that scope, not the whole
external Resource. Unknown/partial upstream evidence stays unknown/partial.
When a Result consumes unknown acquisition completeness, it MUST NOT claim
complete: its existing complete|partial wire enum publishes partial while
retaining the original unknown provenance. A consumer requiring complete
coverage rejects unknown or partial evidence for that required scope. This
does not make the left candidate extent a prerequisite for complete lookup
coverage of the explicitly requested right-side keys; those remain distinct.
effective_data_policy_cid and effective_retention_policy_cid are resolved
authoritative policies, not defaults inferred by an adapter. Sorted,
duplicate-free provenance_evidence references bind all contributing upstream
observations and derivation evidence. Required schema, order, scope, policy,
retention or provenance evidence cannot be omitted for an empty Relation.

The three acquisition-only lists are now provenance_evidence, witness_evidence
and lifecycle_evidence, with closed {kind, cid} elements. Their former *_cids
spellings are not aliases. This does not change the Result Artifact's existing
provenance_evidence_cids field. evidence_kinds in the registry fixes the
schema and self-CID member for every admitted kind; reference_roles dispatches
each list through that map. Provenance admits source, derivation, relation and
attempt_receipt; order witnesses admit source and derivation; lifecycle admits
accounting, attempt_event, activation and adoption. Unknown kinds, kind/body mismatches, absent
schemas and missing referenced bodies reject admission. source reuses the
existing pinned Source Evidence schema; it is not a new generic evidence bag.

Typed reference lists sort by kind then cid in ascending canonical string
order, and reject duplicate pairs. CID-only sets sort by CID. scope.sources
sorts by canonical JSON UTF-8 bytes; key_set.tuples sorts in typed key order,
not JSON text order (numeric 2 precedes 10). JSON Schema uniqueItems enforces
exact duplicates, not semantic tuple equality, duplicate identities with
different payloads, or sorting. Semantic admission MUST reject all those
violations on the sealed incoming body before any downstream use, without
sorting, deduplicating or resealing it. Ordered row arrays and tuple-cell
arrays retain legitimate repeated values and are not sets.

The closed derivation evidence binds the exact producer and computation
contracts, sorted distinct input Relation CIDs, output logical value/schema,
scope, effective policy and resolved order terms. Its issuer_id and
authority_scope_cid identify the authenticated Host capture authority, not an
author-selectable signer. The evidence's inputs must be upstream admitted
Relations; it never references its own output acquisition Relation or ordering
envelope. Empty inputs require a checked input-free computation. At admission,
its output and order must match the consuming envelope and the checked
computation's order-transfer law. A CID or issuer string alone is not evidence
that a computation executed: existing authenticated capture/store admission
must establish issuance, scope and correspondence. This is not permission for
an adapter to attest an arbitrary result or invent an ordering witness.

The supporting ordering and scope bodies are also closed registry schemas,
not adapter-defined CID slots. `actql-acquisition-ordering/0.1` binds
producer_contract_cid, kind, terms and witness_evidence. occurrence has
empty terms and preserves the admitted source/producer's occurrence order;
keys has nonempty ordered {field, dir, nulls} terms and a proven total key or
total stable witness. Its sorted duplicate-free witness set is nonempty,
including on empty inputs. Provider enumeration alone is not an order witness.
References in ordering evidence may point upstream, never back to the Relation
whose identity uses it. This ordering body is also the target Result Artifact's
ordering_evidence_cid; its producer is exactly result_definition_cid at that
boundary. result_schema_cid uses the same complete field-map hash law.

`actql-acquisition-scope/0.1` has sources, a list of closed
{source_contract_cid, request_values_cid, request_key_set_cid} entries. Sort and
deduplicate entries by their canonical JSON bytes. Local captured inputs name
their checked input contract and null request values/key set. A local generator
has an empty sources list, not fabricated external coverage. For a SourceView,
request_values_cid is computeCid of its canonical bound static request object
(including {}); request_key_set_cid is the key set for a keyed observation and
null for a non-keyed observation. Derived inputs preserve the union of actual
upstream scopes and their completeness limitations. Output scope is the one
entry for the barrier's SourceView/static request/key set. Retention policy
identity reuses the resolved Result/Host retention-policy contract; it is never
the hash of a guessed duration or storage path.

For the input slot, retain every actual left occurrence, including repeated
keys and excluded null keys. For the output slot, admit the barrier's complete
response schema, correlation, response identity, cardinality and missing-key
laws before ordering by canonical request tuple then response identity.
Transport arrival order never becomes this logical order. Output provenance
includes the exact attempt receipt and captured source evidence. Its scope
binds the SourceView, static request and requested key set. Complete lookup
coverage for those keys does not upgrade the left input's candidate extent.
No incomplete successful lookup Relation is published under the complete keyed
join contract. Changed schema, order, scope, policy, retention or provenance
changes acquisition identity even if logical_value_cid remains equal.


key_roles is a nonempty list of the SourceView's correlation request roles and
their resolved recursive value contracts, sorted by canonical UTF-16 role name.
Each tuple has exactly that arity in that order. Read the barrier's explicit
correlation/request mapping; do not use left column position or rename a role
heuristically. Under no_match, exclude tuples with any null component; under
fail, reject before dispatch. Then deduplicate by the existing typed
KeyComparable equality and sort lexicographically in canonical typed AoA key
order (including semantic reference order, not capability bytes or hash order).
Tuple cells are canonical typed equality-key values: ordinary scalar keys use
their canonical wire value. A ResourceRef cell is exactly its identity_cid
string; an ContentRef cell is exactly its content_ref_cid string. Components
are never expanded into an object, and neither the capability envelope nor
its issuer/signature bytes are a cell. The declared role contract determines
this projection, so it is not an untyped alternative value grammar. A key-set
cell cannot be used to fabricate a Ref or authorize egress. Actual request
values come from admitted input references through the pinned request mapping;
if identity-equal inputs give different request values and that mapping does
not define one canonical request, admission fails before dispatch rather than
selecting an occurrence by enumeration. The captured
input remains unchanged. excluded_null_key_row_count counts excluded left
occurrences, not distinct tuples, and belongs to Lookup Evidence, not the key
set. The key set also binds source_view_contract_cid and request_schema_cid.
Static request, input identity, effective policy, clock and batch choice are
not key-set members; the surrounding barrier/evidence binds them. This permits
the same key-set CID across different authorized observations without treating
that CID as permission or proof of equivalent requests.

`EqualityKeyCell(roleContract, admittedValue)` has exactly these cases:

| Resolved role type | Exact cell wire value |
| --- | --- |
| Non-reference KeyComparable scalar | Its canonical typed wire value; decimal uses the declared fixed scale and numeric comparison, not string sorting |
| resource_ref | The exact identity_cid string, without a wrapper or expanded components |
| content_ref | The exact content_ref_cid string, never content_cid |

Null exclusion precedes this encoder. Full Ref admission precedes identity
projection; changing outer authorization evidence for the same admitted identity
does not change a key. Resource scope and provider boundary remain part of
identity_cid. A foreign or expired authorization fails admission rather than
becoming acceptable because its equality cell matches. Role names sort by
UTF-16 code units; tuple comparison uses each role's typed law.

Batch plan batches has contiguous zero-based batch_index. key_indices is a
nonempty ascending list of zero-based indices into the canonical tuples. The
flattened lists must equal exactly [0, ..., key_count-1]; no omitted, duplicate
or reordered key is permitted. Zero keys has zero batches. Each batch and the
total plan must satisfy the barrier's resolved bounds and native batching
capability; without that capability every batch has one key. Different legal
partitions intentionally have different batch_plan_cid values. transport_plan_cid
resolves to the pinned checked adapter plan, including static request mapping,
batching and pagination/retry capability, and excludes runtime continuation
tokens. Its preimage is exactly the closed `actql-lookup-transport-plan/0.1`
registry body excluding only self_cid. This binds the SourceView, its admitted
adapter_contract_cid, per-call request and response schemas, bound static
request object, batching, pagination and retry policy. adapter_contract_cid is
the exact read execution contract admitted by that SourceView capability (for
HTTP, the existing actql-http-read-transport/0.1 transport_cid), not the hash
of another unspecified checked-plan wrapper. The wrapper does not authorize
an undeclared adapter or expand an execution profile's support.

Single batching has max_keys_per_batch = 1; native batching requires the
SourceView's semantics-preservation claim and a compatible maximum. Pagination
none has null token_contract and max_pages_per_batch = 1; cursor has a checked
recursive token contract. Retry binds a positive maximum per logical request
and a sorted duplicate-free list of declared retryable error codes. A maximum
of one requires an empty list. Codes, bounds and retries require both the
SourceView capability and Host admission; this adds no implicit retry. All
ceilings also fit the barrier's shared envelope. static_request_values is
validated against precisely the SourceView's static request roles; unknown
keys fail. Changed transport policy or configuration changes the plan CID.
Pages discovered during execution are recorded in attempt evidence,
not inserted retrospectively into the batch plan. Changed partitioning on a
fresh acquisition is not exact replay of an old acquisition.


The attempt receipt binds the barrier, input acquisition Relation, key set,
batch plan and pre-dispatch egress admission (null only when the barrier proves
egress is not required). It reuses the existing lookup attempt-row fields,
with the outcome constraints specified below.
Attempts are ordered by (batch_index, page_index, network_attempt), uniquely;
batch/page indices start at zero, network attempts at one; all indices and
counts are safe integers. The supporting `actql-lookup-semantic-request/0.1`
binds source_view_contract_cid, request_schema_cid, transport_plan_cid,
request_values and continuation. request_values is the complete typed batch
request after static/dynamic role binding, excluding transport authentication
secrets; typed opaque Ref identity is preserved. request_schema_cid resolves to
the actual per-call schema: the declared native batch request schema when
batching, otherwise the single-key request schema. It need not equal the key
set's logical request_schema_cid; the pinned SourceView capability proves the
mapping between them. continuation is null on the
first page, otherwise {previous_response_artifact_cid, token}, binding the real
preceding response and exact token admitted by the transport profile. The
token is canonical typed wire data, not reparsed code or a fabricated page
number. The pinned request and continuation schemas admit the values before
hashing. The captured physical request separately binds actual wire bytes.
The registry's structurally open request_values and token slots are dependent
types, not permission to hash unvalidated JSON. Resolve request_schema_cid,
reject unknown request keys and type/nullability violations, and validate a
continuation token against transport_plan.pagination.token_contract before
computing or accepting its CID. Missing contracts reject; no coercion,
unknown-key dropping or guessed schema is allowed.

All lookup request_schema_cid and response_schema_cid slots refer to semantic
Catalog Contract Envelopes, not raw JSON Schema documents or isolated body
hashes. Their preimage is the entire {schema, id, version, kind, body} envelope,
excluding only cid. Resolve through the checked Catalog and exact SourceView
role, verifying membership, ownership/version, kind and body as required by
[Catalog and lock](contracts.md#catalog-and-lock). Equal body types do not make
different envelopes interchangeable.

| Slot | Exact SourceView contract role |
| --- | --- |
| key_set.request_schema_cid | acquisition.request_schema, kind request_schema; key_roles are the explicit correlation projection of this logical request |
| request/transport_plan.request_schema_cid, single | acquisition.request_schema, kind request_schema |
| request/transport_plan.request_schema_cid, native | acquisition.batching.batch_request_schema, kind lookup_batch_request |
| transport_plan/adoption.response_schema_cid | output.schema, kind carrier_schema; admitted extracted Relation rows, not an HTTP {rows, next} wrapper |

Native admission also resolves acquisition.batching.request_key_schema and
response_key_schema with kinds lookup_request_key and lookup_response_key.
The pinned mapping must preserve those typed key roles and bind static request
roles and the native request value. A native request must fit the existing
request_values object shape and its referenced batch_request_schema. A
capability with a non-object batch value cannot be used here by inventing a
wrapper: it needs an explicitly declared object-valued batch request contract
and checked transport mapping. No implicit array wrapping or schema inference
is permitted.

Validate envelope bodies using ActQL recursive fields, nullable, decimal and
Ref laws. ActQL type objects are not executable JSON Schema. The read transport
contract binds request encoding and response extraction, including the cursor;
its schema CIDs refer to the same semantic envelopes in these lookup bindings.
Wire JSON Schema, if used internally to validate HTTP framing, is distinct and
does not replace any of these slots. No generated wire schema is required.
Decimal fixed-scale strings and complete admitted Refs cross this boundary
only through the pinned typed mapping; equality-key CID strings never substitute
for request Ref values. Raw capture remains exact bytes, independently of the
extracted rows and their semantic carrier schema.
`actql-lookup-call-slot/0.1` binds batch_plan_cid, batch_index, page_index and
semantic_request_cid. A retry retains its logical call slot and changes
network_attempt; a new page has a new call slot. Replacing request values or
continuation cannot masquerade as a retry of the same slot. This fixes the
supporting preimages without adding author-visible operations or relying on
adapter-local hash conventions.

Each call slot has a durable, authenticated activation chain. The closed
activation body binds slot, barrier, batch plan, monotonically consecutive
network_attempt, fixed deadline and previous activation/event. The first
activation has both predecessors null. Retry requires the previous active
attempt's failed or unknown event, the pinned read retry capability, and
remaining reserved capacity. Activation and adoption are serialized per slot
by the durable Host; a stale worker cannot activate or adopt after losing that
slot's ownership. Persist activation and reservations before dispatch. A crash
does not permit reusing a network_attempt number or erasing an unresolved call.

An adoption is an immutable one-time seal for one logical page. It names the
active activation, matching captured event and raw response, response schema,
admitted page-value CID, predecessor page adoption, terminal flag and exact
next_token. page_value_cid uses the Relation logical-value encoding on the
validated page rows in their admitted response order. Capture alone is not
adoption: status, schema, requested keys, response identities, bounds and the
profile's continuation rule must pass. Cross-page duplicate identities and
final missing-key/cardinality checks still precede whole-acquisition success.
Adoption is committed atomically while its activation is current and the slot
has no prior adoption. Concurrent completion order never selects a substitute.

The first page has null previous_adoption_cid. Every later page references the
same batch's immediately preceding adoption; its semantic request continuation
must contain that adoption's exact raw response CID and next_token. Terminal
adoptions have null next_token and no successor. Nonterminal tokens satisfy
the pinned token contract. A succeeded receipt contains exactly one adoption
for every page in contiguous, terminal-ended chains covering every planned
batch. All adopted attempts are captured and retain their matching events and
activations. Nonempty keys with no attempts, all-unknown attempts without an
adopted captured winner, missing pages, forks and unclosed pagination cannot
be succeeded. Zero keys alone permits zero calls and zero adoptions.

Validated lookup rows are derived only from adopted pages, then validated and
canonically ordered under the complete keyed-join law. Failed attempts may
precede a successful retry; receipt state is not the worst historical attempt
outcome. Late obsolete responses remain authenticated audit/capture and usage
evidence but never replace an adoption or change its next token. A resumed
receipt preserves every preceding adoption and the complete activation/attempt
history; lost ownership cannot be repaired by rehashing a new body.

Lookup Evidence pins the exact succeeded receipt once. After this success seal,
late capture and accounting reconciliation append audit snapshots linked through
previous_receipt_cid/previous_accounting_cid; consumers and replay continue to
use the original seal. They MUST NOT recreate the validated Relation, Lookup
Evidence or final Invocation from later audit snapshots.

This is a read contract: an obsolete unknown read does not prohibit an admitted
finite retry. Success with such an outstanding read requires a captured adopted
winner, complete logical coverage, and durable conservative reservations for
all unresolved usage. Each accounting row records usage_final and remaining
reserved_wire_bytes, reserved_decoded_bytes and reserved_duration_ms in addition
to measured usage. Measured plus reserved consumption must fit the sealed
envelope, including its other attempt/cost ceilings. Reservations are the pinned
per-attempt worst-case remaining capacity, not arbitrary authored estimates.
Nonfinal unknown attempts cannot have their reservation silently cleared.
Final usage has zero reservations. Authenticated reconciliation can transfer
reserved usage to measured usage, never erase a possible charge. At the fixed
activation deadline the Host fences further work and charges any unresolved
reservation at its full bound; later audit may establish actual usage without
reopening the original budget or success seal. If no finite worst-case bound
and durable accounting owner exist, success with unresolved usage is forbidden;
the acquisition terminates at its bounded deadline without a validated result.
When a nonfinal row becomes final through reconciliation,
usage_resolution_event_cid names its authenticated captured/failed event with
the same slot and attempt; initial final rows use null. Deadline settlement
instead retains the unresolved row and conservatively charges the reservation
in the durable Host budget ledger; it does not fabricate a captured/failed
event or mark usage_final true. Later definitive evidence may finalize it.

The auxiliary references have these exact targets, before final Invocation:

| Reference | Contract and admission |
| --- | --- |
| transport_plan_cid | Registry transport_plan; adapter_contract_cid resolves the SourceView's checked read execution contract, HTTP production schema http_read_transport with self field transport_cid; not runtime SourceReadPlan |
| activation / adoption lifecycle refs | Registry activation / adoption, self_cid; authenticated durable slot ownership and cross-bindings above |
| accounting / attempt_event lifecycle refs | Registry accounting / attempt_event, self_cid; same barrier, input/batch/slot and cumulative history |
| raw_response_artifact_cid | Registry raw_response, self_cid; content_cid is SHA-256 of exact decoded response bytes and size_bytes is that byte length; wire and decoded accounting remain separate |
| source_request_egress_admission_cid | Registry egress reproduces existing SourceRequestEgressAdmission; computeCid of the full body excluding admission_cid, not self_cid; barrier/input, request requirements, Ref availability and current provider/Host authority are checked before dispatch |
| ordering/provenance witnesses | evidence_kinds maps source to the existing Source Evidence schema and derivation to the local closed computation evidence; producer, schema, order, scope and policy must match |

Raw capture is an authenticated Host byte-store envelope, not a published Result
Artifact or a fabricated ContentRef. Its slot and network_attempt must match
the capturing event; actual retained bytes must match content_cid/size_bytes.
Egress null is permitted only when the barrier proves no admission is required.
The original egress contract's artifact availability references retain their
existing ContentRef/availability admission rules; the lookup registry does not
replace those authority contracts. Every external schema/profile is resolved
from checked bindings, not chosen by arbitrary evidence payloads. Reference
closure follows only declared typed reference positions, including those of the
resolved external contract. A business string beginning with sha256: is data,
not an implicit graph edge. Rehashed foreign captures, accounting from another
acquisition, or evidence depending on the future Invocation fail admission.

started_at and recorded_at are canonical UTC millisecond timestamps with
started_at <= recorded_at. previous_receipt_cid is null initially; later
immutable snapshots bind their predecessor and preserve started_at, barrier,
input, key set and batch plan. The receipt is a cumulative table, not a list
silently reset on resume. lifecycle_evidence is a sorted duplicate-free
set of typed, authenticated dispatch, capture, failure, reconciliation and capacity
accounting evidence sufficient to validate the table and cumulative ceilings.
Wall-clock timestamps alone are not duration accounting. Planned/unattempted
rows are not provider attempts. Dispatched, failed and unknown attempts count
against the sealed transport envelope; retries, redirects and failed response
bodies cannot disappear from accounting on resume. Captured requires actual
raw_response_artifact_cid; failure requires runtime_error_cid or authenticated
failure evidence; unknown never fabricates either a response or successful
completion. A previously captured attempt is immutable. A dispatched/unknown
attempt may acquire a definite outcome only with matching authenticated
resolution evidence; prior snapshots remain retained, never rewritten.
Between snapshots, slot, semantic request, batch/page and network_attempt are
fixed; known evidence cannot be removed. Do not compare entire attempt rows
for permanent equality: dispatched/unknown may settle to captured/failed through
the exact matching authenticated event chain. Captured response bytes and
adopted pages remain immutable. A same-attempt resolution before retry is legal;
a superseded attempt's resolution remains audit evidence, not a new winner.

The attempt-row schema requires a real raw_response_artifact_cid for captured and forbids
runtime_error_cid; planned/dispatched/unknown/unattempted forbid both. Failed
may retain a real error response. It requires runtime_error_cid or a matching
authenticated failed attempt_event. The receipt schema requires an event
reference when any failed row lacks runtime_error_cid; semantic admission must
resolve it and match barrier, batch, slot, attempt and failure outcome. Merely
including an unrelated event cannot satisfy this requirement. Unknown partial
transport bytes may be retained as private diagnostics outside these successful
response fields; they do not become a captured response.

Each attempt_event is a closed immutable envelope binding barrier, batch plan,
call slot, network attempt, previous_event_cid, timestamp, outcome and nullable
actual response/error CIDs and failure code. Captured requires a response and
no error/code; failed requires a nonempty admitted failure code;
dispatched/unknown/unattempted have null response/error/code. Event chains keep
the slot/attempt identity fixed and preserve previous evidence. Resolution of
unknown requires authenticated provider/Host evidence, never a timestamp-only
state change. The issuer and authority scope are checked under the same
capture admission as derivation evidence. Every dispatched or terminal attempt
row must have a matching authenticated event; planned rows need no dispatch
event. Root response-validation failures remain acquisition failures even if
all transport rows are captured.

Exactly one current accounting reference is required in every receipt,
including zero-call success. Its closed envelope binds barrier, batch plan,
input Relation, previous_accounting_cid, recorded_at, elapsed_ms, an attempt
table and totals. Accounting rows sort by (call_slot_cid, network_attempt), with
unique pairs matching the complete receipt attempt table. They contain
dispatched, request_bytes, response_wire_bytes, response_decoded_bytes,
redirect_count and duration_ms. Undispatched rows have zero counters.
Matching means exact equality of the (call_slot_cid, network_attempt) sets,
not merely equal row counts. Captured response size_bytes must be included in
that attempt's measured decoded bytes; redirects and error bodies may make the
counter larger. Wire bytes are independently measured and may differ because
of compression. usage_final requires authenticated completed measurements,
not simply outcome = captured or failed. Resolving a reservation must validate
the resolution event's actual capture and corresponding measured counters;
an event alone cannot justify zeroing consumption. Independent uncompressed
fixtures without other responses must use the exact captured byte length.
network_attempts is the count of dispatched rows plus their redirect_count;
network_attempt indexes the initial dispatch and retries for one logical slot.
Redirect hops are counted inside that row, not also as separate attempt rows.
byte totals are checked sums of the corresponding counters, including redirects
and failed bodies. Failed and unknown dispatched attempts count; planned and
unattempted rows do not. Counter overflow rejects, never saturates. Per-request,
per-attempt and aggregate limits all remain enforced. Parallel attempts' times
are not summed into elapsed_ms: it is the authenticated acquisition-wide
elapsed deadline measurement, including resumed waiting, and cannot reset on
resume. It is at least every attempt's duration; unknown deadline measurement
does not become zero. Within an accounting chain, counters, elapsed time and
already recorded attempts cannot decrease or disappear. Different batch plans
or inputs cannot be spliced into that chain. The retained authenticated Host
measurement must justify the counts and elapsed deadline; an unsigned,
self-reported ledger with a valid CID is insufficient admission evidence.

Receipt state is in_progress while work is pending, unknown when an unresolved
dispatch prevents completion, failed on a definite acquisition failure, and
succeeded only after all required pages and response admission complete. Zero
keys succeeds with no attempts and a typed empty output. Lookup Evidence is
published only for succeeded, with attempts exactly equal to its receipt's
table and all five references cross-checked. Failed/unknown/in-progress
receipts are retained for diagnosis/recovery without inventing a validated
Relation or a successful Lookup Evidence. A response-validation failure may
therefore have captured transport attempts but a failed receipt. Resume reuses
already adopted pages; only the pinned capability and remaining shared
budget may authorize another request. This does not introduce hidden retries.

<!-- requirement-block: lookup-acquisition-identities.product-850e83f1148e -->
The dependency order is upstream contracts/observations -> input acquisition
Relation and key set -> batch plan -> captured attempts/attempt receipt ->
validated acquisition Relation -> Lookup Evidence -> completed local Invocation
-> published Result Artifacts. The attempt receipt MUST NOT reference the
validated Relation, Lookup Evidence or completed Invocation, directly or
transitively. Raw response artifacts and lifecycle evidence used here must
likewise be pre-Invocation captures, not final Result Artifacts. Prior-stage
Results enter through authenticated upstream semantic projections, never an
enclosing current Run's eventual Manifest. No current Invocation, parent Run,
future Result, provisional/zero CID or self-dependent provenance may occur in
the pre-Invocation closure. Post-completion audit wrappers may reference the
whole closure without becoming its ancestors.

Saved admission resolves every referenced body with its pinned schema and
role, verifies all hashes, detects dependency cycles, validates actual rows,
recomputes keys/partition correspondence and validates request, scope, issuer,
policy and accounting evidence. In particular, a rehashed envelope carrying
another acquisition's valid provenance fails. The evidence's barrier/input/key/
batch/receipt/output references must describe the same acquisition; the output
contract and policies must match that barrier, and upstream_candidate_extent
must match the input scope evidence. Hash equality never substitutes for those
checks or current reference availability and authorization.

The Result Artifact's result_schema_cid, ordering_evidence_cid and
effective_retention_policy_cid are required. An acquisition Relation is not a
Result Artifact. Projection follows the authenticated rule above; missing
metadata blocks conversion. Independent vectors verify the complete artifact
and CID, including metadata.

<a id="result-delivery"></a>

### Result delivery

<!-- requirement-block: result-delivery.delivery-must-not-evaluate-a-shape-language-perform-joins-or -->
Nested value construction belongs to computation ([Object and array construction](../language.md#value-construction)). Delivery MUST NOT
evaluate a shape language, perform joins or aggregation, or acquire new data.
Changing a delivery format does not rerun construction or computation.

ActQL 0.1 has no top-level `output` member. Result selection and byte format
belong to delivery, not to Program semantics. One delivery request selects
exactly one declared Result and exactly one canonical format: `json`, `jsonl`,
or `csv`. A caller retrieves several Results through separate requests. The
selection resolves respectively to `actql-json/0.1`, `actql-jsonl/0.1`, or
`actql-csv/0.1`; it does not change Program Definition, Invocation, or the
logical Result Artifacts produced by the Run.

<!-- requirement-block: result-delivery.typed-json-wire-profile -->
Each Result serialization profile preimage MUST contain its `version` and
`json_value_wire_contract_cid`, identifying the common
[typed JSON wire](../language.md#value-construction) law. A non-SQL-NULL JSON
cell uses `{"$json":payload}`; SQL NULL uses `null`. JSON properties inside
closed objects and arrays retain the same typed-cell encoding. The selected
profile CID changes when that wire law changes. Delivery never infers the
JSON domain from a row's spelling or an untagged scalar.

JSON and JSONL use UTF-8, exact retained string values, AoA canonical number spelling, minimal JSON escaping, and
no insignificant whitespace. Top-level relation-row keys follow the selected
ResultDefinition's resolved `fields` exactly. Nested object keys use
UTF-16 code-unit order. JSON is one canonical array with no trailing newline.
Non-empty JSONL is one canonical object per line with a required final newline;
empty JSONL is zero bytes.

<!-- requirement-block: result-delivery.a-job-that-needs-a-custom-csv-dialect-or-an result-delivery.a-missing-declared-field-must-fail-the-result-contract-rather -->
Canonical CSV is one fixed Result delivery format, not a dialect
configuration surface. It uses UTF-8 without BOM, LF, comma, double quote, a
required header in the selected Result field order, and exactly one trailing
newline (including an empty result, which emits only the header). Strings and
headers are quoted with doubled quote characters; numbers use AoA
canonical spelling; decimals use the fixed-scale text defined in [Exact decimal values](../language.md#decimal-values);
booleans are lowercase; null is the unquoted token `\N`;
nested values are quoted AoA canonical JSON text; and NUL is rejected. A job
that needs a custom CSV dialect or an `content_ref` for later consumption MUST
use the optional `serialize` profile instead. A missing declared field MUST fail
the Result contract rather than serialize as null ([Closed value contracts](../language.md#value-contracts)).
A conforming delivery binds the corresponding `serialization_contract_cid`;
a host-dependent serializer is not conforming.

> **Note (informative):** Missing-field rejection is an intentional contract
> decision: a nullable field permits a present null, not omission. CSV does not
> implicitly repair an invalid Result by supplying null for a missing field.

<!-- requirement-block: result-delivery.before-exposing-a-manifest-or-reading-or-returning-a-result result-delivery.a-review-projection-may-be-redacted-even-when-the-underlying -->
Result declaration, Effect approval, and access to a Review Projection do not
grant Result read authority. Before exposing a manifest or reading or returning
a Result payload, a Host MUST independently authorize the read and enforce
current data-policy, retention, and egress admission. A Review Projection MAY be redacted even when
the underlying Result is exact, and authority to approve that projection MUST
NOT be treated as authority to read the Result.

A successful delivery emits one `actql-result-delivery-receipt/0.1`:

<!-- requirement-block: result-delivery.resultdeliveryreceipt -->
<!-- normative-code: grammar -->
```text
ResultDeliveryReceipt := {
  version: "actql-result-delivery-receipt/0.1",
  run_definition_cid: Cid,
  invocation_cid: Cid,
  result_manifest_cid: Cid,
  result_name: ResultName,
  result_artifact_cid: Cid,
  serialization_contract_cid: Cid,
  delivered_byte_count: NonNegativeSafeInteger,
  delivered_sha256: Sha256Hex,
  authorization_context_cid: Cid,
  egress_admission_cid: Cid,
  result_delivery_receipt_cid: Cid
}
```

<!-- requirement-block: result-delivery.a-delivery-must-read-the-exact-immutable-result-payload-bound result-delivery.it-must-not-rerun-the-program-reacquire-a-sourceview-or -->
A delivery MUST read the exact immutable Result payload bound by
`result_artifact_cid`, verify its logical Result CID, and apply the selected
canonical serializer. It MUST NOT rerun the Program, reacquire a SourceView or
ModelTask response, or substitute another Result with equal-looking rows.

<!-- requirement-block: result-delivery.modifying-either-the-delivered-bytes-or-any-bound-receipt-field -->
A Run Receipt proves which logical Results the Run produced; a delivery receipt
proves which canonical bytes were later released. Modifying either the delivered
bytes or any bound receipt field MUST make delivery verification fail.

<!-- requirement-block: result-delivery.single-receipt-preserves-canonical-object result-delivery.multiple-receipts-preserve-ordered-array result-delivery.receipt-export-failure-does-not-resend -->
The CLI receipt-file container is separate from this closed receipt object.
For one requested Result delivery, `result --receipt` MUST preserve the canonical
object bytes and existing self-CID. For multiple requested deliveries it MUST
export a bounded ordered JSON array of successful per-delivery receipt objects,
remaining an array after a partial outcome with zero or one successful delivery.
The array introduces no kind, version, aggregate CID, aggregate success or atomic
rollback. Export failure MUST NOT resend any output or erase an Unknown outcome.
`run --receipt` remains a Run receipt.

<!-- requirement-block: result-delivery.verify-output-admits-all-receipts result-delivery.verify-output-matches-count-and-digest -->
`verify output` MUST admit every supplied object and its existing self-CID before
accepting any match. It MUST match both the observed byte count and SHA256 of one
explicit file, reject invalid unrelated members and zero matches, and report all
matching existing receipt identities when equal bytes match several receipts.
Other valid members are not verification of files that were not supplied. The
container preserves order and occurrences; identity reporting MAY deduplicate
identical members. This integrity operation creates no authority or physical ACK.

<a id="reference-admission"></a>

### Content generation evidence

`actql-content-derivation-evidence/0.1` is the existing production-profile
record for generated bytes: it binds the checked barrier, actual input
Artifact, Content CID, issued ContentRef and issuer evidence, exact row/byte
counts, media type, name and original effective data policy. A computation
fragment CID does not identify the actual input rows.

The closed `actql-content-input-artifact/0.1` identifies the actual completed
ordered Relation and presence-bearing schema, with the checked Program,
parameter/binding identities and task/step occurrence. Its row identities
come from the existing bounded completed-Relation export receipt of that
exact input, not a caller-supplied digest or an equal-looking output. The
source-free input form does not attest acquired Source observations.

`actql-content-generation/0.1` separately binds that derivation evidence to
the admitted Run Definition, invocation template and checked output node,
plus the original Store/workspace/availability binding. It references the
existing derivation record instead of defining a second content byte record.
An Observation's ordered `content_generation_cids` inventories these actual
completed occurrences. Current reference availability, policy and the exact
availability evidence are checked before the containing Invocation is issued.
Plain pure-Run or Model-only issuance does not discharge Content generation.

The Run Receipt inventories each generation as `content_generation`, separately
from Source and Model observations. Its CapturedRun context retains the original
Content derivation, generation, actual input Artifact, ContentRef envelope and
bound invocation template together. The ordered inventory and all self-identities
and cross-links are validated by the existing bounded computation evidence owner.
This optional context is absent for computations without generated Content.
Saved proofs do not issue fresh reference authority or extend byte availability;
live issuance still uses the original typed generation and ReferenceIssuer.

These records do not introduce an execution, input, holding or cleanup owner.
After successful generation, the saved Content follows its own byte custody
and does not depend on the released source rows. An incomplete generation,
compiler fragment, self-hashed wire or saved Ref alone is not byte custody.

### Reference admission and availability

<!-- requirement-block: reference-admission.before-preview-apply-the-connector-host-must-resolve-it-against-the reference-admission.hydrated-references-must-not-enter-ordinary-carrier-values reference-admission.apply-must-repeat-hydration-and-verify-that-the-target-authority reference-admission.a-mismatch-or-inability-to-establish-these-conditions-must-fail reference-admission.the-artifact-issuer-evidence-and-external-egress-admission-must-respectively reference-admission.resolution-must-validate-store-workspace-scope-availability-expiry-size-range-and-content -->
A projected reference is an identity value, not an authority proof. Before
preview/apply, the Connector host MUST resolve it against the current bounded
identity SourceView and hydrate it with a host-private native locator, current
connection revision, boundary, authority, schema/source contract, and hydration
evidence. Hydrated references MUST NOT enter ordinary Carrier values. Apply MUST
repeat hydration and verify that the target, authority scope, boundary,
governing contracts, and mutation preconditions still satisfy the preview.
A mismatch or inability to establish these conditions MUST fail with
`ACTQL_E_STALE_PREVIEW` before provider mutation. Fresh hydration evidence or
authentication-secret rotation alone does not invalidate approval when those conditions
remain satisfied and current authorization is valid. This does not waive the
evidence-drift checks of [Check Environment and source evidence](contracts.md#check-environment).
A content/binary SourceView may issue `content_ref<Mime>` only after enforcing
its byte budget. The ref records truncation and the exact captured content CID;
it also records the artifact-store identity, retention class, optional expiry,
availability-evidence CID, mandatory data classification, and the exact
effective data-policy CID. The Content issuer evidence and external egress
admission MUST respectively bind that same effective data-policy CID and reject
unknown classification before any provider call. Resolution MUST validate store/workspace scope,
availability, expiry, size/range, and content CID. Raw bytes remain in host
artifact storage.

<!-- requirement-block: store-normalization.original-issuer-retained store-normalization.missing-original-refusal store-normalization.no-current-reconstruction store-normalization.original-selection-retained store-normalization.mapping-not-discarded -->
The canonical `store` opcode remains relation materialization.
The authored [`EFFECT STORE`](../query-text.md)
spelling also admits object/file/stage writes with an original typed ContentRef;
it does not imply a format or codec. Such a write may normalize to an existing
typed Connector Command only through an explicitly published, checked relationship
between the original write Mapping, exact Command Contract/member, target and
installation. The canonical Command carries that selection as
`target: {published_store: {target_ref, mapping_ref}}` alongside its exact
`contract` reference; this is the narrow exception to the ordinary ResourceRef
field target, not a second authored upload spelling. These references do not
issue a ResourceRef or permission. The existing installed owner MUST obtain the
original target from its trusted issuer, retain its current-check closure, and
validate exact kind, target, scope, generation and installation/registration/
revision correspondence. It MUST refuse missing originals before send and MUST
NOT reconstruct them from current configuration on restore. The checked selection and all those identities MUST remain bound
through compilation, original Run materials, Preview, apply and restore. A matching
name or schema does not establish the relationship, and the Mapping MUST NOT be
discarded after selection. Current installation and grants remain independently
checked; ContentRef availability/egress custody, approval, overwrite conditions,
Unknown, nonresend and cleanup obligations are unchanged.

<!-- requirement-block: reference-admission.each-concrete-artifactref-presented-for-external-egress-must-have-exactly reference-admission.before-provider-access-admission-must-check-checked-at-now reference-admission.lease-evidence-must-bind-the-store-contract-and-host-policy reference-admission.the-interval-must-satisfy-both-sets-of-limits-and-must reference-admission.the-interval-must-satisfy-both-sets-of-limits-and-must.second reference-admission.a-store-unable-to-promise-availability-for-the-requested-interval reference-admission.the-host-must-maintain-a-valid-lease-until-it-has reference-admission.if-continued-coverage-cannot-be-established-the-host-must-stop stage-receipt-view.product-11ae22332ea1 stage-receipt-view.product-5566e5e2191f -->
Each concrete ContentRef presented for external egress MUST have exactly one
live store-issued availability lease binding the final ContentRef CID, store
CID, content CID, size, and issuance-time availability anchor. Before provider
access, admission MUST check `checked_at <= now < valid_until` and Artifact
expiry. Lease evidence MUST bind the Store contract and Host policy identities
governing its finite validity interval. The interval MUST satisfy both sets of
limits and MUST NOT extend beyond Artifact expiry. Its duration is not an
authoring field or a fixed language constant. A Store unable to promise
availability for the requested interval MUST refuse to issue the lease.
The Host MUST maintain a valid lease until it has finished reading the
required bytes from that Store, renewing it before expiry if necessary.
If continued coverage cannot be established, the Host MUST stop reading and
fail the acquisition. Once those bytes have been captured in protected Host
storage and their content CID verified, the original Store lease need not
cover subsequent external transmission; the captured copy remains subject
to retention, expiry, data-policy, and egress authorization checks.

> **Note (informative):** The issuance anchor remains inside immutable
> ContentRef metadata, while the later live lease binds the final ContentRef
> CID. This split avoids a self-referential content-addressing cycle.

<a id="stage-receipt-view"></a>

### Stage receipt views and manifests

These are ordinary node-local Result/receipt views shared by all Run Graph
entry paths, not stage-only artifacts. Local semantic CIDs bind Unit Definition
and exact local observation/authority evidence. Global Program/lock/history
membership is authenticated separately and must not return through a manifest
or producer receipt into local Preview identity. New projections have distinct
CIDs. Graph public output indexes reference existing Results, without generating
a second Invocation. Flow success, Result availability, provider completion and
delivery are distinct; all declared Results remain roots.

A typed receipt success view MUST materialize from existing exact producer
evidence, never a provider re-fetch or JSON audit dump. Its contract fixes source
stage, Effect ID, item correlation, schema CID, field availability, policy and
semantic_outcome_cid. Rows correlate by logical `item_key` and typed `input_key`
when present, with declared external ID/version/result fields. Provider order
is not correlation. The audit receipt retains applied, accepted, failed,
unknown and unattempted outcomes; a success view exists only under its stage
success and data-availability proofs, not an implicit filter of a partial stage.
Empty views retain schema. Ref values require genuine issuer/admission evidence.

local_receipt.local_manifest_cid permits only the local-result-manifest kind;
effect_outcome_cids and receipt_view.semantic_outcome_cid permit only
`actql-local-effect-outcome/0.1`. This projection binds complete item/input
correlation, canonical requests and operation contract, actual results and
OperationRefs, item outcomes, guards, issuer/scope/policy and provider evidence.
It does not copy the full apply receipt's approval, Run, membership or audit
links. The projection attestation proves correspondence to those original
receipts and authorized producer membership. Availability evidence is likewise
local provider/result evidence, not the entire graph activation artifact.
Opaque Ref scopes and provider observation times remain material, even when
their content bytes coincide. Stable local identity does not waive new launch
admission, current read authority or one-shot checkpoint rules.

A local Result Manifest binds every local Result. The graph output index
contains only explicit root exports, preserving schema/order/policy, and MUST
not be published as complete with missing exports. It carries truthful flow
status/evidence separately: export completeness does not mean graph or business
success. Later failure leaves earlier private artifacts inspectable, not a
fabricated successful partial Program Result. A receipt is imported in a later stage
before it can become a public Result; it is not appended to an already frozen
same-stage Result. Delivery remains one Result and one format per request and
does not select execution roots.

ModelTask attachment admission verifies full scoped Ref identity, issuer,
availability, retention, exact content bytes/CID, MIME, complete/truncated state,
size and current egress. A repeated content CID is not authority equivalence.
Capture resolves authoritative classification inheritance and applicable published
defaults before issuance, binding identical policy in Ref, issuer and evidence.
Only a missing label can use a declared default; unknown/malformed labels and
missing policy fail. Sealed Ref admission never adds a convenient lower default.
SDK single-row/single-value conveniences require exact arity and return explicit
errors rather than truncating to a first row. Canonical CSV is unchanged; human
formatting or formula escaping is an explicit transformation producing a distinct
artifact, while original bytes remain an Artifact.

## Private Model raw response custody

The owned `actql-model-raw-capture-policy/0.1` body fixes a Host-selected
private capture purpose, original Run/ModelTask/invocation scope, physical
response profile, Store authority, effective data policy, actual retention
contract, metadata retention policy and clock contract. Its timestamp members
are explicit Host selections, not derived from Provider retention or a Result
policy. Their canonical order is
`selected_at <= available_until <= delete_by <= extension_ceiling_at` and
`delete_by <= metadata_delete_by`. Retry, restart and a late saved acknowledgement
do not extend any of these values. Integrity admission of this body or its
references is not authority to capture, read, disclose or execute.

The installed Host's private registration must bind these admitted originals
to the original compiled observation policy, actual private capture permission,
selected policy applicability, trusted clock and existing Store custody.
An encryption key, authority string, caller CID or Provider retention claim is
not this registration. Private saving and disclosure are separately authorized;
expiry, revocation and cleanup use the existing Artifact/Store owners.

The closed `actql-model-raw-response/0.1` envelope identifies one original Run,
scope, Slot, attempt (initial index 1), existing `entered` phase, response
profile, Store authority and selected raw capture policy. It records the exact
raw content CID, observed byte count, actual HTTP status and transport EOF,
and the Host's observation timestamp. Missing model/request/usage/media facts
are not filled. Its identity excludes exactly `self_cid`; raw content is hashed
as original bytes, independently of the canonical descriptor and later
structured-response identity. There is no future Invocation reference or
response-success assertion in either preimage. Existing closed bodies and
their preimages are unchanged.

The existing private holding retains an encrypted descriptor and original
encrypted byte object under the same scoped cell. A trusted Store adapter
reconfirms both byte identities and directory durability before reporting a
saved observation to the original Model Entry owner. A different Entry cannot
adopt that observation by presenting equal CID strings. The saved observation
is not dispatch, completion, retention or disclosure permission. A lost commit
response reconciles the same cell; unresolved persistence remains pending or
unknown without another Model send.

Invalid UTF-8, malformed JSON, a rejected shape and partial/no-EOF responses
may have saved raw observations but do not become successful answers. Only
fatal UTF-8 decoding of the same confirmed complete body may enter the Chat
child. All remaining raw bytes, decoded text, parser/answer aliases, Store
encoding/AEAD buffers and controls remain included in the original Ledger's
funded simultaneous holding until actually retired. Saving alone does not prove
heap retirement or enable an unfunded public profile.

### Original Model private storage binding

`actql-model-original-storage-binding/0.1` is a closed, self-addressed
projection of one actual selected private Store and installation key
generation. It is not a grant. Its complete required fields are `version`,
`store_contract_wire`, `store_contract_cid`, `store_authority_cid`,
`key_generation_cid`, `private_namespace` and `self_cid`.

`store_contract_wire` is the existing Store admission's exact three-field
serialization, ordered `version`, `isolation`, `store_authority_cid`, without
whitespace. Its version is `actql-local-publication-store/0.1`; isolation is
`execution-namespace`. Its SHA-256 over those UTF-8 bytes must equal
`store_contract_cid`; its authority must equal the outer authority. This
does not change the existing Store file admission or repair a saved artifact.
`key_generation_cid` is the digest of the actual installation key generation;
the raw key and directory/path are not present. `private_namespace` is exactly
`local-continuation-private`. The outer canonical JSON preimage orders keys
lexicographically and excludes only `self_cid`.

Neither a holding CID nor the original resource artifact's own CID is included:
the origin's `storage_binding_cid` refers to this prior installation projection,
and the later receipt separately authenticates the derived holding. Thus no
self-hash cycle is introduced. The existing Store/Private Evidence admission
also retains a separate opaque nominal handle to its actual original custody.
Copying these fields, admitting their semantic CID, comparing configurations,
or restarting with a saved handle does not reproduce that custody. Re-observe
the actual Store before adopting the binding; foreign or changed originals
refuse. No read, resource-restoration, dispatch or release permission follows.

The physical supplier must fund the projection, original handle, verification
and metadata/Store workspaces before public use. This kind alone does not adopt
a numerical profile, current resource cut or journal CAS.

<!-- model-original-storage-binding-pins:start -->
```text
../../../spec/contracts/actql-run-publication.json#/schemas/model_original_storage_binding sha256:b3906487cb64d2c9a7c5a271358d971051e76884e0d795b1c6ad64c3f00d96f1
```
<!-- model-original-storage-binding-pins:end -->

### Original Model journal data identities

`actql-model-journal-entry/0.1` and
`actql-model-journal-settlement/0.1` identify admitted original journal facts.
Their closed canonical JSON preimages preserve original string values, order
keys lexicographically and exclude exactly `self_cid`. They are data identities,
not acknowledgement, custody, park, current-cut, restoration or send grants.
Neither changes the existing attempt, authority or capture preimages.

An Entry contains the original `run_id`, `run_definition_cid`,
`prepared_invocation_cid`, `scope_cid`, `provider_binding_cid`,
`input_artifact_cid`, `task_index`, `strategy_revision`, `ordinal`, `slot_cid`,
`attempt_index`, `attempt_cid`, `dispatch_authority_cid`, `admitted_at` and
`model_grant_expires_at`. These map to the original admitted full Entry's
camel-case members; `dispatch_authority_cid` names the actual original admitted
dispatch authority (including its Run, context, policy and principal bindings).
It is not inferred from the attempt CID. Journal integer members retain the
existing nonnegative safe-integer domain; attempt and claim generation are
positive. This does not change the Ledger's quantity domains.

`provenance` is `immediate` or `deferred`. Exactly the corresponding nested
object is present and the other is null. `immediate` contains the actual
admission's `run_valid_until`, `dispatch_valid_until` and nullable
`parent_resume_fence`. An observed parent contains exactly `checkpoint_cid`,
`intent_id`, `claimant` and `generation`; an ordinary immediate Entry has null,
not a fabricated approval or resolution. `deferred` contains the actual
admission's `checkpoint_cid`, `intent_id`, `claimant`, `generation`,
`resolution_cid`, `verified_resolution_cid`, `lease_expires_ms`,
`prepare_attempt_id` (null for this Model admission), `kind`
(`model_invocation`), `required_artifact_cid`, nullable `decision_subject_cid`,
`requested_claims`, nullable `configuration_cid`, `observed_claims`,
`authority` and `approval_expires_at`. Ordered claim strings are preserved.
These members are projections of the original admission and continuation,
not caller authority. Original admission/Entry/authority cross-references must
agree before a trusted journal issuer may use this data identity.

A settlement contains `entry_identity_cid`, the actual saved `state`
(`SavedSuccess` or `SavedFailure`), `durable: true`, actual `retry_allowed`,
`settled_at` and closed `evidence`. Its required references are
`model_call_attempt`, `model_dispatch_authority`, `model_attempt_accounting`
and `model_attempt_outcome`; each contains the actual `cid` and `holding_cid`.
`model_slot_capture` and `model_capture_bundle` use that reference shape when
observed, otherwise null. `terminal_failure` preserves an observed boolean,
otherwise null. A partially saved failure does not lose an observed capture or
invent an absent response, receipt or bundle. `SavedSuccess` cannot allow retry.
Unknown/unsent attempts have no saved settlement identity. `settled_at` is the
actual original journal row's timestamp, not a fresh observation clock value.

The trusted issuer obtains these facts from the original admitted full Entry
and saved settlement rows in the same journal. Missing or unrepresentable
facts leave this projection unavailable and retain original custody; they are
not repaired, classified as answer failure or generalized into a language ban.
Shape/CID admission of copied data never authenticates the actual journal,
Store or original resource state. A stable current cut additionally requires
the original parked/stopping resource receipt and committed journal fences.
Readonly observations and equal Run revisions alone do not establish that cut.

<!-- model-journal-identity-pins:start -->
```text
../../../spec/contracts/actql-protocol-schemas.json#/artifact_schemas/model_journal_entry sha256:2be8611d08d277590783ff06299130c78170eb4de49b4d76d67a940d0e3fccb7
../../../spec/contracts/actql-protocol-schemas.json#/artifact_schemas/model_journal_settlement sha256:e5739efb68a1d6059c5d9c58cd74eabbc8ca28c071e81c2b1984d26e5125161b
```
<!-- model-journal-identity-pins:end -->

<!-- model-raw-capture-pins:start -->
```text
../../../spec/contracts/actql-run-publication.json#/schemas/model_raw_capture_policy sha256:f542a5957ce196eb56105b6b5a81aa4f51c38ccc24d335855b8df0dad3dcac21
../../../spec/contracts/actql-run-publication.json#/schemas/model_raw_response sha256:07f7c91e32a97d3aaf58381b2fee15bed860021875b3cb2b0e5fc646aa5a5ca6
```
<!-- model-raw-capture-pins:end -->

<a id="machine-contracts"></a>

<!-- machine-import: ../../../spec/contracts/actql-run-publication.json#/schemas/result_definition sha256:13d36d24b7adcd346f7719a513f6850260bd84738c897c5bd41def223daba973 -->
<!-- machine-import: ../../../spec/contracts/actql-run-publication.json#/schemas/run_invocation sha256:6295e0fe2d2b066f39c3d5ecd7c16125018aa2d46d0cfa3537c213d109b96c81 -->
<!-- machine-import: ../../../spec/contracts/actql-run-publication.json#/schemas/result_retention_policy sha256:61bc287aae5c6b626bf7bea99ff8d40dd932e4fdf00495cedc3868f633f831c4 -->
<!-- machine-import: ../../../spec/contracts/actql-run-publication.json#/schemas/durable_result_binding sha256:f775ad3a57f76aa6fd0272d498e7c9045644874288f796b1d5daae3cbc15fed4 -->
<!-- machine-import: ../../../spec/contracts/actql-run-publication.json#/schemas/publication_request sha256:1dbb53f3905b65891e92f87dc0b2e7f4f917d86bc170d3052328aedcb0bb1f1d -->
<!-- machine-import: ../../../spec/contracts/actql-run-publication.json#/schemas/publication_attempt sha256:bd7b6a8ebf31e1c61c952fe2a5a5cf29813676f19777940fd771b573b86000a5 -->
<!-- machine-import: ../../../spec/contracts/actql-run-publication.json#/schemas/publication_record sha256:ebc1b92730a37fb67b3fed5b70ffca9e5a8b64aefcafc546cdc875dc7b5caa4d -->
<!-- machine-import: ../../../spec/contracts/actql-run-publication.json#/schemas/manifest_read_grant sha256:2988afee66209d63cd12d9174c1adea619231e49fca1e8dc7876b6655a6f7fd5 -->
<!-- machine-import: ../../../spec/contracts/actql-run-publication.json#/schemas/result_read_grant sha256:e154fb5adec4d242933cf93989188fb5bab5486ebb6999ae123fafa6b064488a -->
<!-- machine-import: ../../../spec/contracts/actql-run-publication.json#/schemas/delivery_attempt sha256:f26252778de76cc45e95559a1b9d95055d1f650af6d89ca1262592dcffba48cf -->
<!-- machine-import: ../../../spec/contracts/actql-run-publication.json#/schemas/delivery_record sha256:d4018bec28a046f7faf02d4f3d3eb06a7f9ce19f84f5dfa41ceb5155bd0a78a4 -->
<!-- machine-import: ../../../spec/contracts/actql-run-publication.json#/schemas/public_index_entry sha256:6f4d64b352c4f039d4a010322cebe6a818e11716dd5ce844fa51fa1cb7228a4e -->
<!-- machine-import: ../../../spec/contracts/actql-run-publication.json#/laws sha256:18e62f30a4120596c290b055c7bfacda84375eb3a4c0d02a7bfed1dae7af25a0 -->

## Machine contracts

These exact schema/law references are owned here. Their identities do not include this document or another owner's aggregate contract.

<!-- requirement-block: machine-contracts.exact-artifacts -->
<!-- normative-code: law -->
```text
../../../spec/contracts/actql-protocol-schemas.json#/schemas/hydration_evidence sha256:3ec3d5b17ddd5464544349529d9a1590ebe4ad8922e8da3fd805e28cc1e78660
../../../spec/contracts/actql-protocol-schemas.json#/schemas/content_availability_evidence sha256:784203dbc5f95925f83f57c0ff3230abef8bac867768bbe90b26f622fb2d867d
../../../spec/contracts/actql-protocol-schemas.json#/artifact_schemas/result_manifest sha256:bd718c411677e83cdf33258176d09c6dd690789b3cc7bb897cbff2b629290e02
../../../spec/contracts/actql-protocol-schemas.json#/artifact_schemas/result_delivery_receipt sha256:d68ae5fbe6b23410b08b4419e5ebfa10eb61c38d61273360399e71ae2681de21
../../../spec/contracts/actql-run-publication.json#/schemas/result_definition sha256:13d36d24b7adcd346f7719a513f6850260bd84738c897c5bd41def223daba973
../../../spec/contracts/actql-run-publication.json#/schemas/run_invocation sha256:6295e0fe2d2b066f39c3d5ecd7c16125018aa2d46d0cfa3537c213d109b96c81
../../../spec/contracts/actql-run-publication.json#/schemas/result_retention_policy sha256:61bc287aae5c6b626bf7bea99ff8d40dd932e4fdf00495cedc3868f633f831c4
../../../spec/contracts/actql-run-publication.json#/schemas/durable_result_binding sha256:f775ad3a57f76aa6fd0272d498e7c9045644874288f796b1d5daae3cbc15fed4
../../../spec/contracts/actql-run-publication.json#/schemas/publication_request sha256:1dbb53f3905b65891e92f87dc0b2e7f4f917d86bc170d3052328aedcb0bb1f1d
../../../spec/contracts/actql-run-publication.json#/schemas/publication_attempt sha256:bd7b6a8ebf31e1c61c952fe2a5a5cf29813676f19777940fd771b573b86000a5
../../../spec/contracts/actql-run-publication.json#/schemas/publication_record sha256:ebc1b92730a37fb67b3fed5b70ffca9e5a8b64aefcafc546cdc875dc7b5caa4d
../../../spec/contracts/actql-run-publication.json#/schemas/manifest_read_grant sha256:2988afee66209d63cd12d9174c1adea619231e49fca1e8dc7876b6655a6f7fd5
../../../spec/contracts/actql-run-publication.json#/schemas/result_read_grant sha256:e154fb5adec4d242933cf93989188fb5bab5486ebb6999ae123fafa6b064488a
../../../spec/contracts/actql-run-publication.json#/schemas/delivery_attempt sha256:f26252778de76cc45e95559a1b9d95055d1f650af6d89ca1262592dcffba48cf
../../../spec/contracts/actql-run-publication.json#/schemas/delivery_record sha256:d4018bec28a046f7faf02d4f3d3eb06a7f9ce19f84f5dfa41ceb5155bd0a78a4
../../../spec/contracts/actql-run-publication.json#/schemas/public_index_entry sha256:6f4d64b352c4f039d4a010322cebe6a818e11716dd5ce844fa51fa1cb7228a4e
../../../spec/contracts/actql-run-publication.json#/reference_roles sha256:3458373ea99e5bc9bb22d3a7ecbbe801abe98875bf7c6c7e748924d8b92bad9c
../../../spec/contracts/actql-run-publication.json#/reference_graph sha256:3078ae712b11a42f03eb5d8aedca521d942bed276c0e25f4fa231a1b7c8b2008
../../../spec/contracts/actql-run-publication.json#/laws sha256:18e62f30a4120596c290b055c7bfacda84375eb3a4c0d02a7bfed1dae7af25a0
../../../spec/contracts/actql-production-profile-schemas.json#/schemas/content_source sha256:18591195eb1c2484081052246944a32f9231dfe77b73decbdf61b558230e0e68
../../../spec/contracts/actql-production-profile-schemas.json#/schemas/content_barrier sha256:4b7fea87dfbed0e1f11e9421cd077793cd3bccfc3e981617fa2a1547960acee5
../../../spec/contracts/actql-production-profile-schemas.json#/schemas/content_evidence sha256:19cb6932ef23ba83de127214eb884249f127085ec48d1bbfa8945ec06e35d695
../../../spec/contracts/actql-protocol-schemas.json#/artifact_schemas/content_input_artifact sha256:ed5b46909842901d4b9836e77d1d1c77caf65ef09b0f57ae44dc2668526b6775
../../../spec/contracts/actql-protocol-schemas.json#/artifact_schemas/content_generation sha256:a8e96d9a2a9d9e721f69b30da117dc0cdeca4c864cb21747b5551a9853fe037c
```

<!-- stage-contract-pins:start -->
```text
../../../spec/contracts/actql-stage-contracts.json#/schemas/receipt_view sha256:411418a07c7422158e47cd3ca5cd9befe12d50b0de056206eae0596a12e9df1e
../../../spec/contracts/actql-stage-contracts.json#/schemas/model_slot_capture sha256:a9d707b52b274a066a3b30d196c2b2da4144db960b5eae9695ac86e1fd3f503a
../../../spec/contracts/actql-stage-contracts.json#/schemas/local_manifest sha256:1c04239d415476440f1badf2f229e49b3d40e543fdf8e03e35b540d503277922
../../../spec/contracts/actql-stage-contracts.json#/schemas/local_computation sha256:22055f9d843378b5a5d98a9b882a69bcc4229a448f97e1022685613e4340cbd3
../../../spec/contracts/actql-stage-contracts.json#/schemas/local_result_definition sha256:a4e97bbb8865697510ec0d0eff6664081da9cc5b7c1546c2af107b8d743392f4
../../../spec/contracts/actql-stage-contracts.json#/schemas/local_table_input_definition sha256:22699f824d1ed8137b7e62797bc636255823acdd803b944d61104354e4ba706b
../../../spec/contracts/actql-stage-contracts.json#/schemas/local_table_input_artifact sha256:16f69bbc38782a3ea42fafcfbbd992f9d1356a68c70dd1182cb102e269db04f1
../../../spec/contracts/actql-stage-contracts.json#/schemas/result_import_observation sha256:3a622a55cb9af3939de08583caf298abd7d66b357bcde4a060140e39cccdde8d
../../../spec/contracts/actql-stage-contracts.json#/schemas/local_effect_outcome sha256:8a56e3e7d5139fef571da480831e0df45c95beb96c228e737efdb12a1ef0b98d
../../../spec/contracts/actql-stage-contracts.json#/schemas/local_result_artifact sha256:16f69bbc38782a3ea42fafcfbbd992f9d1356a68c70dd1182cb102e269db04f1
../../../spec/contracts/actql-stage-contracts.json#/schemas/projection_attestation sha256:27c8c8a1215b705b6553f4db128f73c905b1c6a5f0c7d72c398e02541e7dc805
../../../spec/contracts/actql-stage-contracts.json#/reference_roles sha256:7b888e2691b7d48a3f525f2de0da7b09ce594fea6d3319bf5e75512c63217687
../../../spec/contracts/actql-stage-contracts.json#/reference_graph sha256:332f29e96a606665706639e1ab1dfcc6ae5d0374b77b7dd5cb3f399955ad58cd
../../../spec/contracts/actql-stage-contracts.json#/schemas/local_model_observation sha256:00c4c147c9f572366acaa670d0929ea2adbb9c9f4819c53a5f5ff8cf37706afc
```
<!-- stage-contract-pins:end -->

<!-- lookup-identity-pins:start -->
```text
../../../spec/contracts/actql-lookup-identities.json#/schemas/activation sha256:17e7fb651f28731805a2aa7d19da23cdadd679e775b7565765c9b8351654cf41
../../../spec/contracts/actql-lookup-identities.json#/schemas/adoption sha256:565792923a43d7caf62dacf25d0aaa4f2718da2642295f34a300bc4963f4e73c
../../../spec/contracts/actql-lookup-identities.json#/schemas/raw_response sha256:9cfcd5971b2ba28901bc41a75a00dac78f2b85e69b32a8dde6a7b34a8cc86b4e
../../../spec/contracts/actql-lookup-identities.json#/schemas/egress sha256:86faee61411d78b32a2b20d3e73532bb2988d837ba3101ad01b93692cb19bec0
../../../spec/contracts/actql-lookup-identities.json#/schemas/transport_plan sha256:a8a34e371dc0eb6c15597ca3a0c1bf4b56b8e2823aba5170bd06c588c4ed0178
../../../spec/contracts/actql-lookup-identities.json#/schemas/derivation sha256:2b26eb9af1fee57313bc5d339d3be9dd407608a458b249f41aa4d5d5fa340015
../../../spec/contracts/actql-lookup-identities.json#/schemas/accounting sha256:b39a1bffd1e47679b7092f5eefdb5830ae7d93ebc20afa2f3daddc1febaaea70
../../../spec/contracts/actql-lookup-identities.json#/schemas/attempt_event sha256:c9b5a6332e1bf918718bd4d5b58a34bcd7f420d4e55693f8f48ba28cb9067310
../../../spec/contracts/actql-lookup-identities.json#/schemas/ordering sha256:ff0b367507ede56d319fc041aacec38fa98f6683ec383b6c0475a2cbede64925
../../../spec/contracts/actql-lookup-identities.json#/schemas/scope sha256:cfd16a0890d0cc3fc1548d45be283f5b067791507f08a79c567acd186dba4bd4
../../../spec/contracts/actql-lookup-identities.json#/schemas/request sha256:89d3817588c84e52e7ab57911a9e4c667bb63a49b6051a90ec9ce3741c112a72
../../../spec/contracts/actql-lookup-identities.json#/schemas/call_slot sha256:dd49a504455f782e2d17059880512f1b133cd5b035107a7f96c0cef25f79d5bd
../../../spec/contracts/actql-lookup-identities.json#/schemas/relation sha256:b00bc1456e19c3809adaf69774b2af1a1ee1ca6a98fd02fcb2f8cc9cb7344cc0
../../../spec/contracts/actql-lookup-identities.json#/schemas/key_set sha256:66a400079a4e3385dd8f3f27b78c0d4007a22bd270ce7f40bd3599f63a4b93b0
../../../spec/contracts/actql-lookup-identities.json#/schemas/batch_plan sha256:df125a7737abbb76c72f9f4cd73a0ba8981506c1cdb7ae6465309a7d44517261
../../../spec/contracts/actql-lookup-identities.json#/schemas/attempt_receipt sha256:a48afadbe4bb2378a6bd3203f35c451081d84d316514f47e544a6c2c4f102620
../../../spec/contracts/actql-lookup-identities.json#/evidence_slots sha256:d5257ad4c6368df06bdd720a132c1759b46ed0d3457b46e66e750b1f7f4aaa66
../../../spec/contracts/actql-lookup-identities.json#/reference_roles sha256:24dd3184553911026820fbf87b96d32ac3ce4fb4d256f069fe3d1c9d5533240d
../../../spec/contracts/actql-lookup-identities.json#/evidence_kinds sha256:98e11850d4899e992f5b2405ed2e160ed6037fef63e6f0fa02994d8fe3903913
../../../spec/contracts/actql-lookup-identities.json#/external_contracts sha256:93c4120b39f30053b2713c6725675bc54c0c16dceefe82898fa8ba0d41f6fa1c
../../../spec/contracts/actql-lookup-identities.json#/laws sha256:2fb2ee20393958ca02aa8e3aa66e6900efb02acc71e3aaaf7aa64ed285a8b5db
```
<!-- lookup-identity-pins:end -->
