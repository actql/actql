# Check Environment envelope and admission boundaries

The normative owner is [Check Environment and source evidence](../spec/protocols/contracts.md#check-environment).
`spec/contracts/actql-check-environment.json` pins the outer schema and identity
rules; its `schema` is a standalone resource. This is not an executable registry,
backend capability declaration or admitted Host policy.

The eight evidence arrays, policy object and root self-identity match the explicit
shape at Sketch `87dc7144:src/actql-portability.ts`. That implementation also
orders each array by full member CID. Those details previously lived in reference
code rather than a pinned envelope schema. They are now explicit wire rules,
without extending aggregate hashing into evidence authorization.

The normative unique-selector rule takes precedence over the reference builder's
`sortUniqueEvidence` treatment of schema snapshots: identical duplicate snapshots
are rejected, not merged. The existing special rule for identical Contract
Envelopes still permits their canonical deduplication. No blanket deduplication
rule is inferred for capabilities or mappings. Unresolved/unknown policy bodies
can be represented and hashed without satisfying any policy-dependent compiler
obligation. Supporting the outer schema is not support for every member body.

The content preimage excludes only the root `evidence_bundle_cid`. Nested data
using that name remains hashed. `check_environment_cid` is an alias reference,
not another self-member. Fixed independent vectors cover an empty unresolved
environment, changed policy, nested identity-like data and a local schema body.
Their expected preimages and complete wire text are fixed using Node, never a
product compiler. Generated MoonBit tests verify preimage canonical hashing
and integrity-only wire admission. Negative wire cases cover missing/unknown
members, wrong section shapes, duplicate selectors/contracts and array order.
These are not full environment admission tests.
The small Node shape test covers the explicit outer schema keyword subset only.

Required implementation stages remain distinct: canonical envelope integrity;
member shape/identity and ordered section handling; exact Catalog-derived
closure; local/Connector snapshot correspondence; selected policy/component
validation; and binding that admitted environment to the exact Program context.
All supplied bodies need their governing validation, including unused evidence.
`check_environment.read` now returns a distinct opaque `WireEnvironment`, not
the final admitted checking environment. It checks closed shape, canonical full
bytes, root-excluded identity, all member object shapes and CID order, duplicate
snapshot selectors and duplicate canonical Contract Envelopes. It retains every
member with its independently recomputed full-body CID. Other component semantics
remain unverified, including malformed policy or Catalog contents represented as
objects. Such bodies are inspectable, not usable as admitted evidence.

The canonical emitter uses explicit frames and checks existing UTF-16 key order
instead of sorting/repairing wire data. Full wire and preimage go to hash sinks;
the full environment is never rebuilt as a String. Parsing, owned-tree admission
and hashing use byte/node/depth caps; the total member count is also bounded.
Per-member hashing covers disjoint subtrees, so aggregate payload work remains
linear rather than receiving an unbounded new allowance per selector. Returned
usage is full canonical body size/node count and total members, not heap usage.

`member_at` creates an opaque handle retaining the exact environment owner,
section, position, cursor and full-body CID. Re-reading identical bytes creates
a different internal owner, despite an equal content CID. Public cursors preserve
original locations and cannot mutate the owned tree. Tests cover member bounds,
ownership, noncanonical bytes and depth 1,000 without recursive emission.

`local_relation_snapshot.read_member` validates a SchemaSnapshots member using
its own computed CID and retains that exact Member in an `EnvironmentSnapshot`.
The same body in another section is rejected. Only the individual bounded member
is serialized for the existing snapshot reader; the whole environment is not.
This proves content membership plus local snapshot shape/type integrity. It does
not validate the rest of the environment or authenticate Host claims. The final
Program connection must retain this membership alongside exact source/type
agreement and the governing policy/Catalog checks, not unwrap and forget it.
`stage_local_inputs.reconcile_environment` now preserves this ownership alongside
resolved stage inputs and schema agreements. It rejects foreign member owners,
including separately read identical envelopes. Its selected member set may be
partial. `stage_local_inputs.assemble_environment` now requires every stage and
every supplied snapshot to be covered under the same source/environment owners.
This is local-Relation snapshot coverage, not admission of other sections or proof
that all inputs have the evidence their governing policy will require.

## Contract Registry integrity and exact references

`check_contract_registry` checks every member of the derived `contract_registry`,
including unused entries. The opaque result retains the exact `WireEnvironment`;
each opaque ContractEnvelope retains its original member handle and body cursor.
It validates the closed shape and 17 kinds in
`actql-protocol-schemas.json#/schemas/contract_envelope`, nonempty external
id/version strings, and each self-CID. External contract versions are not forced
to the owned specification baseline.

The preimage contains `schema`, `id`, `version`, `kind` and `body`, excluding only
the root `cid`. This follows the Catalog rule in
`actql-lookup-identities.json#/laws/catalog` and the reference
`87dc7144:src/actql-protocol.ts` envelope constructor. Nested `cid`, `$param`
and `literal` are ordinary data. A null body is legal at this envelope-shape
boundary, not proof that it satisfies a particular role's body contract.
Aggregate rehashing cannot repair a stale inner self-CID.

The indexed resolver matches id, version, CID and required kind independently.
Conflicting id/version identities fail; identical whole envelopes were already
rejected by wire admission because they must be deduplicated before constructing
the canonical environment. Tuple keys avoid concatenation collisions. Limits
charge all full envelope bytes/nodes and members cumulatively, with depth bounded
per envelope; hashing performs bounded nonrecursive passes without materializing
another complete JSON string. Usage is payload accounting, not a heap ceiling.

This result is deliberately **not Catalog closure**. Catalog ownership, reference
closure inside each Catalog, role-specific body validation, equality of derived
arrays to that closure, and issuer/Host authority remain required. In particular,
successful resolution here does not establish complete SourceView candidates or
authorize sole-view completion. Final assembly must retain these separate proofs.
Fixed independently calculated self-CIDs cover null and nested business data;
tests cover stale inner identity, role/version/CID mismatches, conflicting names,
closed shapes, cumulative limits, exact ownership and depth 1,000.

## Catalog contents and derived-array equality

`check_catalog_contents` consumes the exact checked ContractRegistry and returns
opaque CatalogContents. It checks closed Catalog headers, root-excluded Catalog
self-CIDs, unique Connector selectors, SourceView/Command self-CIDs and Connector
ownership, unique view triples and globally unique Command IDs. It matches each
embedded body to an exact full-body-CID member of the same environment, and
requires all three derived sections to be covered exactly. Only shared Contract
Envelopes are deduplicated across Catalogs; each Catalog retains its own contract
set. `resolve_catalog_contract` adds that local membership check to the registry's
exact identity/kind resolution. An envelope found only in another Catalog cannot
satisfy a reference. Returned view/command handles retain their original derived
section membership, and the Catalog handle retains its environment membership.

The normative Catalog preimage and array-order paragraphs make the reference
constructor's rules explicit (`87dc7144:src/actql-protocol.ts`,
`createActqlConnectorCatalog`). Catalog contents sort by member **self-CID**, not
the **full-body CID** used by outer environment sections. Readers reject wrong
order instead of invoking the reference builder's sorting repair. This clarifies
the canonical representation; it does not add defaults or change valid reference
Catalog identities. The Check Environment machine contract records these rules.

Limits count full Catalog bytes/nodes cumulatively, including repeated embedded
envelopes, and Catalog plus direct member occurrences. Each derived section is
also bounded by the member cap before indexing. Depth is bounded per Catalog;
the disjoint member hashing passes have the same cap, not an unbounded reset.
Indices are built once and tuple selectors preserve exact components. Payload
accounting does not claim a heap bound. Tests cover empty Catalogs, an independent
fixed self-CID, repeated/shared contracts, unsorted contents, stale inner bodies,
extra/missing derived entries, ownership, selectors and cumulative limits.

This is not yet full Catalog admission: SourceView/Command body grammars and
semantic constraints, role-reference closure, policy bodies, correlation/type
compatibility and issuer authority remain required at separate boundaries.
The shape-limited fixtures intentionally demonstrate that membership alone does
not prove these properties. CatalogContents is not a sole-view completion token,
and no Program input resolver consumes it as one. Those subsequent checks must
retain this exact proof instead of independently reconstructing candidate lists.

## Catalog role-reference closure

`check_catalog_references` consumes CatalogContents and checks every SourceView
and Command reference slot, including all acquisition modes and unused members.
It returns opaque CatalogReferences retaining that exact contents proof. Each
resolved occurrence retains its Catalog, original derived member, exact cursor
and resolved ContractEnvelope. Diagnostics preserve the offending reference
cursor (or the containing object when a required slot is missing), so path and
span are available without inventing a new source location.

There are 13 SourceView role paths and 6 Command role paths. Their role meanings
match `87dc7144:src/actql-protocol.ts`'s `contractRefsFromSourceView` and
`contractRefsFromCommand`. The generator `scripts/catalog-reference-roles.mjs`
derives required/optional parent hops from the pinned protocol schemas and
compares all discovered ContractRef paths against the explicit role map. It
rejects missing/extra classifications, unknown kinds and conditional reference
forms requiring a new routing decision. `check:contracts` checks both coverage
and the generated MoonBit table; adding a schema slot cannot silently leave it
out of this table. This is schema routing coverage, not execution conformance.

Absent optional containers or references contribute no occurrence. Present null,
nonobjects and missing required members fail; `id`, `version`, `cid` form a closed
reference. Resolution checks all identity components and role, and then membership
inside the same Catalog. It never scans arbitrary contract bodies or interprets
business `$param`/`literal` fields. All reference occurrences are retained, even
when several slots point at one contract. Explicit frames traverse mode arrays
without recursion or materializing all pending elements. Work counts Catalogs,
members, route visits, object keys and reference string units cumulatively;
reference-count limits apply to occurrences, not unique targets. The prior
Catalog payload budget remains a separate retained check, not reset evidence.

Fixed test locations independently enumerate all 19 roles for wrong-kind checks;
tests also cover optional absence versus null, late errors, exact ownership,
original diagnostic locations, cross-Catalog references, repeated mode slots and
budget boundaries. Test envelopes use existing canonical serialization only to
construct inputs, never to derive expected role resolutions. Full body grammars,
policy contracts, type/correlation compatibility, acquisition-mode coherence and
issuer authority remain unproven. Reference closure alone cannot authorize input
resolution, sole-view completion, planning or execution.

## Source data-policy bodies

`check_source_data_policies` consumes the exact CatalogReferences proof, validates
all `data_policy` envelopes in its registry (including unused ones), and links
each SourceView output-policy reference to an opaque SourceDataPolicy. Access by
SourceView member requires the same environment and correct section; equal bytes
read into a different environment cannot substitute. The result retains the
reference closure, exact output occurrence and original policy Envelope.

The closed `version/source_ref/classification` body is now explicit in the
normative Check Environment section and in
`actql-check-environment.json#/contract_bodies/data_policy`. This records the
existing reader at `87dc7144:src/actql-portability.ts` and publisher at
`87dc7144:src/connectors/local-kernel.ts`; previously the general `body: {}`
Envelope schema did not express the role-specific shape. No alternate `source`
spelling or new selector syntax is inferred from other reference-code hashes.
The publisher-supplied nonempty `source_ref` is retained exactly for subsequent
snapshot correspondence. The policy CID is the Contract Envelope identity, not
the bare-body hash. The fixed unknown-policy expectation was independently
calculated with Python hashlib.

DataClassification distinguishes all four known levels and Unknown. This check
does not replace Unknown with Public, compute a Host classification floor,
authenticate a publisher, establish source materialization or permit publication
or model egress. Snapshot source/policy/Carrier correspondence and effective
Host policy are separate obligations. A shared policy target can support several
reference occurrences without discarding those ownership relationships.

Work accounts for each registry entry and resolved occurrence plus the policy
keys and value string units; policy-count limits count all distinct envelopes,
including unused ones. Previous Catalog/reference budgets stay attached rather
than being treated as zero-cost completed global admission. Tests cover every
classification, closed shape, null/missing fields, unused malformed bodies,
cumulative limits, foreign environments and full-envelope identity.

## Protocol value-contract bodies

`check_protocol_value_contracts` validates the eight value-contract Envelope
roles through the canonical checked reader, including unused entries. The role
set matches Sketch `87dc7144:src/actql-protocol.ts`'s
`ACTQL_VALUE_CONTRACT_KINDS` and its Catalog validation. Pinning this classification
and the canonical checked schema makes that previously implicit routing explicit.
The generator classifies all 17 Envelope kinds and fails when an added or removed
kind has not been reviewed. Carrier schemas are deliberately not value contracts.

The opaque result retains SourceDataPolicies and therefore the same Catalog,
registry and environment proof chain. Each admitted type retains its Envelope;
foreign environments cannot substitute even when bytes and CIDs match. Ref type
declarations remain representable without asserting that any Ref value has been
issued or admitted. Behavioral bodies and actual request/value compatibility
still require their own checks before whole-environment admission.

`read_checked_usage` exposes the existing reader's node and text charges without
changing its acceptance rules. The registry pass applies one cumulative allowance
across bodies; depth is limited per contract. The envelope cap bounds all scanned
registry entries, including roles routed elsewhere. Counts are logical reader
usage, not JSON byte size or a heap ceiling. Empty registries consume no contract
budget, and a late invalid body returns no partial admitted result.

## SourceView shape admission

`check_source_view_shapes` retains ProtocolValueContracts and validates every
Catalog SourceView against the existing protocol schema. Its opaque result is
shape evidence, not complete SourceView admission. Correlation/type agreement,
read-mode coherence, Carrier bodies and authority remain distinct checks; the
reference constructor's correlation checks depend on those body meanings.

The generated rules cover the complete `schemas.source_view` resource. Generation
rejects new or changed unsupported schema keywords rather than silently skipping
them. This is a specialized compiler for the selected schema, not a general JSON
Schema engine. SourceView's positive-integer fields retain the schema's domain;
no extra safe-integer ceiling is inferred from an implementation preference.

Validation uses explicit traversal frames and schedules array elements one at a
time. Work charges node visits, array iterations, object keys and string units;
unique string arrays also charge their indexed strings. All views share one
budget, with a separate count cap. These measures are bounded validation work,
not heap bytes. Field lookup scans a fixed generated property table, so input
width cannot introduce quadratic lookup work. Diagnostics retain the original
cursor; a later failure exposes no partial result.

## SourceView read-mode coherence

`check_source_read_modes` consumes the shape proof and retains it with every
SourceView's mode objects and exact selected default. Mode names are unique,
snapshot is bounded, watch is unbounded, and non-snapshot modes carry checkpoint
contracts. This matches the validation in Sketch
`87dc7144:src/actql-protocol.ts`; the normative paragraph makes the cross-field
conditions explicit rather than treating schema shape as their proof.

Unlike the reference constructor, this reader does not sort or repair supplied
arrays. Supplied mode order and original cursors remain intact. Checkpoint and
delivery reference shapes and kinds are covered by preceding proofs; this pass
does not invent further expiration or acknowledgement constraints.

Catalog advertisement and Program selection are separate: bounded or unbounded
changes and unbounded watch can be described by a valid Catalog. A Program still
needs the profile's supported selected mode, actual bounds and runtime evidence.
No capacity proof follows from `bounded: true`. The mode pass charges visited
object members and mode records cumulatively across views, and returns no partial
result after a later failure. It does not close correlation, Carrier, Command or
authority admission.

## Capacity component selection

The normative component selector is now `/host_policy_profile/capacity`, with
the existing capacity-policy contract pinned as a dependency. Sketch at `87dc7144`
uses this same property in `hostCapacityPolicy` and its reference profile. The
prior normative text required environment selection but did not specify this
location; fixing it is an explicit wire clarification, not a new policy default.
The outer profile remains an object whose other components need their own checks.

`read_capacity` validates the selected body through `capacity_policy.admit` and
returns an opaque owner retaining both the exact wire environment and Policy.
The selected CID hashes the full component, distinct from profile/environment
identity. Missing capacity is unresolved; null or an invalid supplied body cannot
be treated as absent. Only this bounded component is serialized, not the whole
environment. Independent fixture identity, limit boundaries, malformed ceilings
and separate environment owners are tested. The envelope contract CID changes
because it now pins component selection/dependency; unchanged envelope bytes do
not change their own CID. Compiler policy matching and other component admission
remain separate work, and no Host authorization follows from this reader.
The compiler's `bind_capacity_policy` now matches the selected admitted Policy
CID while requiring this component's exact environment owner, and retains both.
`capacity_usage` reports canonical component bytes/nodes for aggregate accounting.

## Text-time component selection

The text-time component is `/host_policy_profile/text_time_evaluation`, matching
Sketch `87dc7144`'s profile. Its existing expression-fragment policy schema is
pinned by subtree CID rather than duplicated. This explicit component location
closes a previously unspecified envelope selection boundary. The expression
request continues to call the supplied body `text_time_policy` and its envelope
reference `host_policy_profile_cid`; both refer to this component's full-body CID,
not to the enclosing profile or Check Environment.

`read_text_time` retains exact environment ownership and an admitted
`text_time_policy.Policy`. Absence remains unresolved without defaults; supplied
null, wrong shape or invalid ceilings are errors, not absence. Component byte/node
usage is retained for aggregate accounting. Fixed independent component/envelope
identities and malformed/limit cases distinguish outer integrity from component
admission. Other policy components and full environment closure remain separate;
this does not resolve expression envelopes, validate patterns or run evaluations.
