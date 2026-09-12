---
spec_id: actql.protocol.contracts
status: adopted
version: actql/0.1
normative_dependencies: [actql.language]
---

# ActQL contracts

[Specification index](../README.md)

<!-- normative-import: actql.language actql/0.1 -->

This document owns catalog, sourceview, mapping, command, model-task, check-environment, lock, static-plan-artifacts, diagnostics. It does not define other owners' wire protocols or a particular Host implementation. Cross-owner links outside the declared dependencies are informative navigation to protocol bindings or conformance evidence; they do not import those documents' requirements. Narrow machine contracts remain authoritative for their explicitly referenced values and envelopes.

<!-- page-contents:start -->
## On this page

- [Terms](#contracts-terms)
- [Authoring Context sidecar](#authoring-context-wire)
- [Check Environment and source evidence](#check-environment)
- [Connector Catalog and lock](#catalog-and-lock)
- [Connector manifest and authorization boundary](#connector-manifest)
- [Deterministic Catalog generation](#mapping-generation)
- [Capture classification inheritance](#classification-inheritance)
- [Command item and recovery contract](#command-item-contract)
- [Connector management writes](#stamp-writes)
- [ModelTask outcomes and attachments](#model-task)
- [Plan Documents and public planning results](#planning-wire)
- [Parameter values and bound template](#bound-template-wire)
- [Compilation identity envelopes](#compilation-identities)
- [Diagnostic documents](#diagnostic-documents)
- [Author-choice repairs](#behavioral-repairs)
- [Diagnostic compatibility profiles](#diagnostic-profiles)
- [Ranked candidate acquisition contract](#ranked-search-contract)
- [SourceView transformation profiles](#sourceview-transformations)
- [Machine contracts](#machine-contracts)
<!-- page-contents:end -->

<a id="contracts-terms"></a>

## Terms

- **Check Environment** — the content-addressed evidence supplied to checking,
  including schema snapshots, Connector and Mapping Contracts, and Host policy
  ([Check Environment and source evidence](#check-environment)).
- **Compiled Plan** — the compilation identity envelope binding the bound
  Invocation Template, Executable Plan, fragment identities, and governing
  contracts; distinct from the executable graph itself ([Canonical identities](../language.md#canonical-identities)).
- **Plan Document** — the private artifact wrapping one bound Executable Plan
  with its Authoring Context ([Typed barriers and Plan Documents](../language.md#plan-documents)).

<a id="authoring-context-wire"></a>

### Authoring Context sidecar

The compiler extracts every allowed `meta` object before semantic checking and
publishes one closed sidecar:

<!-- requirement-block: authoring-context-wire.actql-authoring-context -->
<!-- normative-code: grammar -->
```text
actql-authoring-context/0.1 := {
  program_definition_cid: Cid,
  annotations: [{
    target: {
      kind: program | stage | input | parameter | binding | step | result | effect,
      source_path: JsonPath,
      name?: NonEmptyString
    },
    meta: Meta
  }, ...],
  authoring_context_cid: Cid
}
```

The compiler supplies source paths and names; authors do not declare annotation
IDs. Annotation order is canonical. The sidecar CID changes when metadata
changes, while the semantic Program and Executable Plan remain byte-identical.

<a id="check-environment"></a>

### Check Environment and source evidence

Optimization statistics are separate from the Check Environment. Their update
alone does not change semantic identities. A measured fact used as proof must
instead bind its verification and exact snapshot/content identity in the
governing evidence; an estimate cannot discharge a proof obligation.

<!-- requirement-block: check-environment.compilation-must-not-fetch-this-evidence-import-code-or-access check-environment.two-compilers-using-different-evidence-must-produce-different-check-environment -->
Compilation receives a canonical non-executable `actql-check-environment/0.1`
envelope containing schema snapshots, connector capability evidence, mapping
contracts, and a host-policy profile. It is content-addressed as
`evidence_bundle_cid`; `check_environment_cid` is a reference to that same CID,
not a second envelope. Compilation MUST NOT fetch this evidence, import code,
or access a connector. Two compilers using different evidence MUST produce
different Check Environment and Compiled Plan identities even when the
evidence-independent Program CID is unchanged.

<!-- requirement-block: check-environment.envelope-shape -->
The Check Environment wire envelope MUST contain exactly `version`,
`schema_snapshots`, `connector_capabilities`, `mapping_contracts`, `source_views`,
`command_contracts`, `model_task_contracts`, `contract_registry`,
`connector_catalogs`, `host_policy_profile`, and `evidence_bundle_cid`.
The version is `actql-check-environment/0.1`; all eight evidence sections are
arrays of objects, including explicit empty arrays, and `host_policy_profile`
is an object. There are no omitted-section defaults or extra top-level members.

<!-- requirement-block: check-environment.envelope-preimage -->
The `evidence_bundle_cid` MUST equal SHA-256 over the canonical JSON UTF-8 of
the entire envelope excluding only that root member. A same-named nested
member is ordinary data and remains in the preimage. `check_environment_cid`
is not an additional member or independently hashed envelope. Canonical-byte
admission rejects noncanonical encodings rather than repairing them.

<!-- requirement-block: check-environment.envelope-array-order -->
Each evidence array MUST be ordered by ascending full canonical body CID of
its members. Ordering never removes a repeated schema-snapshot selector:
those repetitions fail as specified below, even for identical bodies.
Byte-identical Contract Envelopes are deduplicated before canonical envelope
construction, as required by the Catalog closure rules. Sorting other evidence
does not itself authorize deduplication, infer selector uniqueness or validate
the evidence's meaning.

The envelope schema intentionally checks only the closed outer shape. Hash and
array-order integrity do not validate Catalog authority, derived-array equality,
snapshot correspondence, capability/mapping contracts, policy components or
runtime claims. Their governing checks remain mandatory before the environment
can be used as admitted checking evidence. An implementation that only reads an
integrity-checked envelope must not label it an admitted Check Environment.

<!-- requirement-block: check-environment.admission-must-recompute-every-catalog-sourceview-command-modeltask-and-contractenvelope check-environment.a-sourceview-output-must-reference-one-closed-data-policy-contract check-environment.each-connector-derived-schema-snapshot-must-bind-that-exact-policy-cid check-environment.a-local-input-schema-snapshot-must-bind-its-input-source-reference -->
Connector Catalogs are the sole authority for SourceView, Command, and
referenced ContractEnvelope bodies inside a Check Environment. Admission MUST
recompute every Catalog, SourceView, Command, ModelTask, and ContractEnvelope
self-CID; reject duplicate or conflicting contract identities and dangling or
wrong-kind references; and require the derived `source_views`,
`command_contracts`, and `contract_registry` arrays to equal the validated
Catalog closure exactly. These arrays provide no independent contract
authority. A SourceView output MUST reference one closed
`data_policy` contract. Each Connector-derived schema snapshot MUST bind that
exact policy CID, source identity, classification, output Carrier, and
SourceView CID. A local-input schema snapshot MUST bind its input source
reference, Carrier, and schema contract; it requires no SourceView CID.
Rehashing only the aggregate Check Environment after changing an inner body is invalid.

<!-- requirement-block: check-environment.source-data-policy-body -->
Each `data_policy` Contract Envelope body MUST be a closed object containing
exactly `version: "actql-source-data-policy/0.1"`, a nonempty string `source_ref`,
and `classification`, one of `public`, `internal`, `confidential`, `restricted`,
or `unknown`. All supplied data-policy bodies are validated, including unused
ones. Unknown classification remains unknown; no public default is inferred.
The referenced policy CID identifies its complete Contract Envelope preimage,
not the body alone. Validation retains the exact SourceView output reference
and policy source identity; it does not authenticate the publisher or authorize
publication or model egress. Snapshot correspondence and effective Host policy
remain separate required checks.

<!-- requirement-block: check-environment.protocol-value-contract-bodies -->
Each `request_schema`, `command_input`, `command_output`, `idempotency_key`,
`checkpoint`, `lookup_request_key`, `lookup_batch_request` and
`lookup_response_key` Contract Envelope body MUST satisfy the canonical checked
value-contract grammar, including unused supplied envelopes. Author-form
defaults and arbitrary JSON Schema bodies are not substituted for that grammar.
The Check Environment contract pins the exact governing schema. `carrier_schema`
and behavioral roles use their own body contracts, not this value grammar.
Validation retains the original Envelope and its exact environment membership;
equal bare-body hashes do not substitute for role or ownership. This validates
type declarations, not actual values, Ref issuers or execution authority.

<!-- requirement-block: check-environment.carrier-schema-bodies -->
Each supplied `carrier_schema` body MUST use exactly one of the following closed
forms, including unused envelopes. Relation uses the non-null canonical checked
object value contract, including `fields: {}`. Graph uses the existing
`actql-graph-contract/0.1` structural body in [Carriers](../language.md#carriers).
Events uses `{version: "actql-events-contract/0.1", records, id, time}`; Vectors
uses `{version: "actql-vectors-contract/0.1", records, ids, components}`.
`records` is a complete non-null checked object contract. All role names are
canonical ordinary field names resolving exactly to fields in that record.
Event `id` is non-null KeyComparable, and `time` is a non-null number or timestamp
with the existing UTC-millisecond interpretation. Vector `ids` is a nonempty
ordered list of distinct non-null KeyComparable fields; `components` is a
different field with a non-null vector contract, which supplies dimensions.
Array order is retained, not sorted or deduplicated. The Check Environment
contract contains the shape schema; field resolution, comparability, clock and
component types, Graph completeness and sorted labels are additional semantic
checks. No role is inferred from a field name, observed data, primary-key facts
or an AoA physical layout.

<!-- requirement-block: check-environment.carrier-schema-correspondence -->
A SourceView's `output.carrier` MUST match its resolved carrier-schema body.
Admission retains the exact output reference, Contract Envelope and environment.
The Envelope CID and bare structural body CID are different identities; no
self-CID is added to a structural body. These declarations do not prove runtime
value validity, event or vector identity uniqueness, graph membership, stable
order, capacity, publisher authority or backend support. Those obligations remain
separate. A backend unable to represent a declared semantic ID rejects execution;
it does not stringify or replace that ID. Absence of type evidence elsewhere in
the language is not represented by a malformed supplied schema or by a `json`
placeholder. Empty datasets retain their declared structural contracts.

<!-- requirement-block: check-environment.within-one-admitted-check-environment-every-author-visible-selector-must-resolve -->
Within one admitted Check Environment, every author-visible selector MUST
resolve exactly once: Connector ID, SourceView `(connector, resource, view)`,
Command ID, ModelTask task ID, and schema-snapshot source ref are unique.
Repeated byte-identical Contract Envelopes are canonically deduplicated, while
the same selector naming different contract CIDs is rejected.

Runtime source evidence and drift validation are specified in [Runtime source evidence](run.md#runtime-source-evidence).

<a id="local-input-source-reference"></a>

#### Local input source references

<!-- requirement-block: check-environment.local-input-selector check-environment.local-input-selector-canonical -->
A local-input schema snapshot source reference MUST use
`source:local/<stage-token>/<input-token>` within the selected staged Program.
The tokens encode the authored stage ID and local input name, not array indices
or generated step handles: replace each `~` with `~0`, then each `/` with `~1`.
Both decoded names MUST be nonempty, well-formed NFC-plus-LF text, without
normalization repair, percent decoding or a second escape pass. No other escape,
extra path component, or legacy `source:local.<name>` spelling is admitted.

<!-- requirement-block: check-environment.local-input-selector-resolution check-environment.local-input-selector-unique check-environment.local-input-selector-ownership -->
Admission MUST resolve both names exactly against the selected Program and
require a local input, not a Connector declaration or Result/receipt import;
it MUST reject unknown stages, unknown inputs and repeated snapshot selectors,
including identical duplicates. An input with the same name in a different
stage is a different selector. The selector alone does not identify a Program,
authenticate the Host, prove materialization or discharge any input obligation.
Check Environment admission and subsequent compiler assembly MUST retain the
selected Program ownership; a selector from another Program is not transferable
merely because its text or schema matches.

The pinned local-source-reference schema checks string syntax only. Canonical
Unicode, exact Program resolution, snapshot Carrier/type correspondence and
evidence authority require separate semantic checks. This definition applies
to all local Carrier selectors, without defining their snapshot body formats.
Schema evidence alone is not evidence that input rows already exist: static
checking does not implicitly acquire, materialize or authorize data.

<a id="local-relation-snapshot"></a>

#### Local Relation schema snapshots

<!-- requirement-block: check-environment.local-relation-snapshot-shape -->
A local Relation schema snapshot MUST contain exactly the required members
`version: "actql-local-input-schema/0.1"`, `source_ref`,
`output_carrier: "relation"`, and `schema`, plus only the optional members
`input_cid`, `completeness`, and `integration_binding_cid`. `schema` is a complete
checked non-nullable object contract, including explicit `additional_properties:
false`; empty `fields` is allowed. It is not an author-form declaration or a
bare field map. Other local Carriers require their corresponding snapshot
contracts; this Relation contract does not restrict their language support.

<!-- requirement-block: check-environment.local-relation-snapshot-materialization -->
`input_cid` and `completeness` MUST occur together, with completeness either
`complete` or `partial`; `integration_binding_cid` is optional but requires that
pair. Their absence denotes static schema evidence only, not zero rows, complete
data or an implicitly acquired materialization. An ordinary local input need not
have a Collection IntegrationBinding. When supplied, these identity/provenance
claims remain bound in the snapshot and need validation against their governing
materialization and integration contracts; schema agreement alone verifies none
of those claims.

<!-- requirement-block: check-environment.local-relation-snapshot-integrity check-environment.local-relation-snapshot-correspondence -->
The snapshot identity MUST hash the entire canonical JSON body as UTF-8 with
SHA-256, including all supplied optional claims; no self-CID field is part of
that body. Admission MUST verify its exact source selector in the selected
Program, Relation Carrier, recursive supplied-to-authored schema assignability,
explicit input assertions and membership in the selected Check Environment.
Canonical-byte admission rejects noncanonical bytes rather than repairing them.
An independently recomputed content CID establishes integrity, not Host authority,
runtime row validity, uniqueness, completeness or permission to execute.

<a id="capacity-law-registry"></a>

### Capacity witness law registry

<!-- requirement-block: capacity-law-registry.closed-identifiers -->
A bound witness MUST name a law in the pinned
`actql-bound-law-registry/0.1`. Its `law_ids` is a nonempty, unique, ascending
ASCII list. Registry membership identifies an admitted law name; it does not
validate the witness's role, source, unit, derivation, applicable consumer or
enforcement. Those checks remain mandatory under the governing source and
operation contracts. A registered name without a validated application does not
produce a runnable capacity fact. The Host entries are exactly the IDs in the
pinned capacity policy's `host_witness_laws` table. Other law names retain their
separate source/application obligations rather than accepting arbitrary witness
claims by name alone.

<!-- requirement-block: capacity-law-registry.author-guard-sources capacity-law-registry.author-guard-occurrence capacity-law-registry.author-guard-value -->
The registry's `author_guard_laws` table fixes the source field, quantity unit
and governing law for each listed checked-operation guard scope. These source
witnesses MUST have role `author_guard`, source kind `author_guard`, source
derivation and the owning Program Definition CID as their sole dependency.
Their source path MUST address the actual authored guard occurrence, and their
value MUST equal its bound positive safe-integer value. Omitted guards create
no witness; Parameter guards require binding, not default inference by the
witness reader. Repeated occurrences and currently non-binding guards remain
distinct. A matching unit or number does not allow one occurrence to govern
another consumer.

The join-output law applies separately to `join`, `cross_join` and
`interval_join` output guards; the owning occurrence determines the operation
and protected output. The nested-array-items law restricts each matched
parent's nested array, not total input rows. String-aggregate guards restrict
UTF-8 output bytes; array-aggregate guards restrict array items. Sequence
per-key match and total-output scopes remain distinct. Components, traversal
and shortest-path guards restrict their operation's output rows, not input
nodes or path length. These restrictions do not establish measured bounds
before enforcement. The operation contract still determines the enforcement
boundary; the table does not grant truncation, selection, or execution authority.

The Program law `actql.bound.text-rank` identifies the lexical ranking output
bound from [Language's text_rank](../language.md#text-rank): query count times
the smaller of k and corpus count. A query-only upper bound may use k directly.
These are output-row upper bounds, not exact counts or bounds on corpus scoring
work. A corpus-dependent reduction retains the corpus count dependency in
addition to the query dependency; a scalar factor alone is not evidence of
the corpus size. This law is separate from the nearest output law.

Input-free Program count laws distinguish their evidence. `actql.bound.values`
uses the authored row occurrence count, without discharging cell binding.
`actql.bound.time-series` uses the admitted UTC endpoint interval and positive
integer-millisecond step, including resolved typed Parameter values when needed.
`actql.bound.calendar-series` uses the Calendar generator's conservative civil
domain upper bound for its selected unit and profile, not a claim that all
possible boundaries occur in the requested interval. Binding, range, profile
and resource obligations remain distinct from these output-row bounds.

<!-- requirement-block: capacity-law-registry.values-body -->
An application of `actql.bound.values` MUST satisfy the separately pinned
`actql-bound-values-law/0.1` body. That body fixes the row-count derivation and
its operation ownership; the law-name registry alone is not its semantic body.
It is a law contract, not a cell-admission schema or a backend registration.

<!-- requirement-block: capacity-law-registry.values-machine-contract -->
<!-- normative-code: law -->
```text
../../../spec/contracts/actql-bound-values-law.json# sha256:0e0f9b4b6585ab7b17bafe484e82f44cd8f3acc9eec5ef9329cea200237a7971
```

<!-- requirement-block: capacity-law-registry.relation-count-body capacity-law-registry.relation-count-machine -->
The pinned `actql-bound-relation-laws/0.1` body governs common Relation
row-upper-bound preservation, global-group, take/top_k, append, unpivot and
unnest derivations. Applications MUST retain actual input occurrences, quantity
units and source dependencies, and reject unsafe arithmetic. Its selection
does not replace Carrier-specific laws or discharge the owning operation's
validation, ordering, resource enforcement or runtime obligations. A law-name
registry or transfer classification alone is not this semantic body.

<!-- normative-code: law -->
```text
../../../spec/contracts/actql-bound-relation-laws.json# sha256:163a0d75d56310803ac755d5f4f02069f442651711209037d6e3f512954c97ab
```

<!-- requirement-block: capacity-law-registry.machine-contract -->
<!-- normative-code: law -->
```text
../../../spec/contracts/actql-bound-law-registry.json# sha256:45f824fa077ac7eb6fecda6e25fa954834f1854c512f99f6803ad2ab84dd899a
```

<a id="capacity-host-policy"></a>

### Host capacity policy evidence

<!-- requirement-block: capacity-host-policy.canonical-source -->
A Host capacity policy used as bound-witness source evidence MUST be an exact
canonical `actql-capacity-host-policy/0.1` body conforming to the pinned
capacity-policy contract. Its 17 named limits are required positive safe
integers; unknown fields, missing limits, noncanonical bytes and implicit
defaults are rejected. The Check Environment selects the expected policy CID
independently of the supplied body. Validation checks that CID against the
complete canonical body, without removing a field or repairing the encoding.

<!-- requirement-block: capacity-host-policy.environment-component -->
The capacity policy component, when supplied, MUST be the complete body at
`/host_policy_profile/capacity` in the Check Environment. Its selected CID is
the hash of that complete canonical component, not the profile or environment
CID. Absence leaves capacity policy unresolved and supplies no implicit default;
explicit null is not absence. Every supplied capacity component is validated
even if no operation consumes a capacity ceiling. Compiler assembly retains
the exact environment association and compares the selected policy CID against
this validated component. This component check does not admit other profile
members, the whole environment or Host authority.

<!-- requirement-block: check-environment.text-time-component -->
The text-time policy component, when supplied, MUST be the complete
`actql-text-time-host-policy/0.1` body at
`/host_policy_profile/text_time_evaluation`, conforming to the existing
expression-fragment request `text_time_policy` schema. Absence leaves selection
unresolved without defaults; null is not absence. Every supplied component is
validated even when unused. Its full canonical body CID, not the aggregate
profile or environment CID, is the `host_policy_profile_cid` in text-time
envelopes. Compiler assembly retains its exact environment association.
Component admission does not prove argument bounds, complete static obligations,
enforce runtime limits or grant Host authority.

<!-- requirement-block: check-environment.text-rank-selection check-environment.text-rank-association -->
The lexical text-ranking profile selection, when supplied, MUST be the closed
object `{version: "actql-text-rank-selection/0.1", profile_bytes_cid}` at
`/host_policy_profile/text_rank`. Both members are required; unknown members,
null, unsupported versions and CIDs other than `sha256:` followed by 64 lowercase
hexadecimal digits are rejected. Absence leaves the profile unresolved and
does not select a default. Every supplied selection is validated even when
unused. Its entire body participates in Check Environment identity; its
`profile_bytes_cid` is the independently selected hash of the original profile
bytes, not the selection component CID or an identity computed after repair.
Compiler assembly MUST retain the exact environment association, compare the
admitted lexical profile to that selected byte CID, and require verification of
all source/vector dependency pins defined by the
[text-ranking profile](../language.md#text-rank). A matching profile supplied for
another environment does not establish that association. This selection does
not prove provenance, evaluator conformance, scoring limits or execution permission.

<!-- requirement-block: check-environment.calendar-selection check-environment.calendar-association -->
The Calendar selection, when supplied, MUST be the closed object
`{version: "actql-calendar-selection/0.1", table_bytes_cid, tzdb_version,
conversion_law: "actql-calendar-boundaries/0.1"}` at
`/host_policy_profile/calendar`. All four members are required. Unknown fields,
null, unsupported versions/laws, empty external release names and CIDs other
than `sha256:` followed by 64 lowercase hexadecimal digits are rejected.
Absence leaves Calendar selection unresolved without defaults; every supplied
selection is validated even when unused. Its entire body participates in
Check Environment identity. Compiler assembly MUST retain that exact environment
association and compare the admitted transition table to both the independently
selected original-byte CID and external `tzdb_version`, under the fixed
[Calendar conversion law](../language.md#calendar). The external release name
is not rewritten to an ActQL-owned version. Selection does not prove IANA
provenance, boundary evaluation, resource enforcement or execution permission.

<!-- requirement-block: capacity-host-policy.ceiling-provenance -->
A policy ceiling MUST retain the exact policy CID, field name and value.
Policy admission establishes integrity and structural validity relative to the
selected CID, not Host authorization, an observed data upper bound, or completed
enforcement. The governing witness law separately determines the field's unit,
scope and consumer; numeric equality cannot substitute one field for another.
Resolving and enforcing the resulting capacity remains required before a
runnable Plan can rely on it. Policy selection and deployment remain Host
responsibilities rather than author-level source defaults.

<!-- requirement-block: capacity-host-policy.host-source-witness -->
A Host policy source witness MUST use the exact field/unit/law triple in the
pinned `host_witness_laws` table, with role `host_ceiling`, derivation
`{op: source}`, and source `{kind: host_policy, policy_cid, field}`. Its value
equals that admitted policy field and its dependencies are the singleton policy
CID. Its `witness_cid` hashes the complete canonical witness body excluding only
the `witness_cid` member itself. The emitted wire body includes that member.
Field scope is retained when matching a consumer: equal values and equal units
do not make different policy fields interchangeable. Fields without a table
entry remain policy facts for their separate consumer envelopes; they cannot
be recast into one of the current bound-witness units.

<!-- requirement-block: capacity-host-policy.machine-contract -->
<!-- normative-code: law -->
```text
../../../spec/contracts/actql-capacity-host-policy.json# sha256:4150c63cf455b675d428479fcbf486d17b5421901eb35f65285cf96769c250bd
```

<a id="catalog-and-lock"></a>

### Connector Catalog and lock

<!-- requirement-block: catalog-and-lock.a-connector-must-publish-at-least-one-sourceview-for-each catalog-and-lock.a-sourceview-derived-during-catalog-construction-including-from-a-resource -->
A Connector MUST publish at least one SourceView for each Resource exposed
for reading. A SourceView derived during Catalog construction, including from a
resource configuration with no explicit SourceViews, MUST be published as an
ordinary contract with a name, classification, and contract CID. Such
construction is not compiler completion ([Connector SourceViews](../language.md#sourceviews)).

<!-- requirement-block: catalog-and-lock.every-referenced-request-schema-facts-pushdown-checkpoint-command-reconciliation-contract-is-a-id-version-cid catalog-and-lock.each-reference-must-also-resolve-to-the-contract-kind-required -->
Each Connector publishes one canonical `actql.connector_catalog/0.1` containing
its ResourceKinds, SourceView contracts, typed command contracts, carrier and
schema/fact contracts, identities, authorities, read modes, checkpoints,
delivery, pushdown, permissions, atomicity, and async outcomes. The complete
catalog is content-addressed. Every referenced request/schema/facts/pushdown/
checkpoint/command/reconciliation contract is a `{id, version, cid}` and MUST
resolve to exactly one canonical Contract Envelope contained by the Catalog.
Each reference MUST also resolve to the contract kind required by its role:
for example `request_schema` cannot refer to a `carrier_schema`, and `poll`
cannot refer to `reconciliation`. Catalog creation rejects dangling references,
role mismatches, CID/body mismatches, duplicate
id/version pairs with different CIDs, and Connector ownership/version mismatch.
Therefore changing any transitive contract body necessarily changes the Catalog
CID and invalidates an old lock. `actql.lock` binds the ActQL Grammar,
Connector Catalog, SourceView, Command, and AoA semantic contract identities.
Implementation-package pinning belongs to Host deployment and supply-chain
verification, not the portable program lock. Runtime schema snapshots and
Resource observations belong to plan and receipt evidence, not the program lock.

<!-- requirement-block: catalog-and-lock.canonical-preimage -->
The Catalog self-CID MUST hash the complete canonical Catalog excluding only its
root `catalog_cid`. SourceView and Command self-CIDs exclude only their root
`contract_cid`; Contract Envelope self-CIDs exclude only their root `cid`.
Nested members with these names remain ordinary data in every preimage.

<!-- requirement-block: catalog-and-lock.member-order -->
Within a canonical Catalog, `source_views` and `commands` MUST be strictly ordered
by their `contract_cid`, and `contracts` by their `cid`. Duplicate entries and
unsorted arrays are rejected without repair. The Check Environment's derived
arrays instead use their existing full-body-CID order; identical Contract
Envelopes shared across Catalogs appear once in the derived registry, while each
Catalog's references still resolve within that Catalog's own contract set.

<!-- requirement-block: catalog-and-lock.when-a-lock-is-supplied-to-planning-or-execution-the -->
When a lock is supplied to planning or execution, the host MUST compare the complete canonical lock against
the current Grammar, AoA, Connector Catalog, SourceView, and Command
identities and reject any mismatch before compilation or provider access.
Status, Checkpoint resolution, and cancellation operate on a durable Run that
already binds that checked environment; they do not accept a replacement lock.
Lock verification performs the same comparison without executing a Program.

#### Discovery and publication

<!-- requirement-block: catalog-and-lock.refreshing-a-catalog-from-a-provider-requires-separate-authorized-publication -->
Discovery is an explicit Host service over published language and contract
artifacts, not a Program operation or an implicit checking/planning step.
Discovery access grants no SourceView, ModelTask, Effect, or Result access.
Refreshing a Catalog from a provider requires separate authorized publication
work; discovery MUST NOT hide business-data sampling or model invocation.

<!-- requirement-block: catalog-and-lock.search-results-and-scoped-paginated-or-redacted-summaries-must-not catalog-and-lock.a-projection-has-its-own-identity-and-must-not-claim -->
Search results and scoped, paginated, or redacted summaries MUST NOT establish
candidate-set completeness for sole-view completion. Resolution uses the
complete domain of the admitted Catalog ([Connector SourceViews](../language.md#sourceviews)). A projection has its own
identity and MUST NOT claim the original artifact's CID. CID integrity does
not establish issuer trust or current authorization. If the complete Check
Environment cannot be disclosed, the Host checker uses the authorized original,
not a reconstructed summary.

The shared Host Discovery protocol is defined in [Host Discovery protocol](discovery.md#discovery).

<a id="source-pushdown-contract"></a>

#### SourceView pushdown contract

<!-- requirement-block: source-pushdown-contract.body -->
The core pushdown body is either the empty object `{}`, denoting no pushdown
operations, or exactly `{version: "actql-source-view-pushdown/0.1", carrier,
operations}`. The versioned body's `carrier` is `relation`, `graph`, `events` or
`vectors`. Its `operations` is a duplicate-free array drawn from `projection`,
`filter`, `order_by`, `limit` and `assert_unique_by`; non-Relation bodies have
an empty array. Other body versions or vocabularies require a separately
registered interpretation and MUST NOT be silently treated as this contract.

<!-- requirement-block: source-pushdown-contract.agreement -->
Every SourceView referencing this body MUST declare the same operation set, and
the same Carrier when the body names one. An empty body requires an empty
SourceView operation list. Array order is not capability precedence; neither
array is reordered, deduplicated or replaced for identity computation. The
complete Contract Envelope and SourceView keep their existing preimage rules.

<!-- requirement-block: source-pushdown-contract.preservation -->
Advertisement is not evidence of implementation, semantic equivalence or
execution authority. A selected pushdown MUST preserve the operation's values,
types, null behavior, multiplicity, required ordering, eager evaluation and
failure behavior, and applicable bounds. A residual predicate is evaluated with
the same canonical semantics or rejected. In particular, advertising `limit`
does not establish a deterministic selection order, and advertising `filter`
does not permit suppressing an eagerly evaluated failure.

<!-- requirement-block: source-pushdown-contract.dependencies -->
The interpreted body depends on its governing Check Environment contract;
nonempty operation lists additionally depend on the pinned RelA primitive laws,
and `filter` additionally depends on the pinned expression contract. Those pins
are recorded in `pushdown_contract_bodies.semantic_dependencies` of the Check
Environment machine contract. This body grammar has no ContractRef positions.
These direct dependencies do not replace transitive closure or provider
equivalence checks, which MUST be validated at their respective boundaries.

<a id="connector-manifest"></a>

### Connector manifest and authorization boundary

<!-- requirement-block: connector-manifest.unknown-keys-must-fail-before-a-connector-is-instantiated connector-manifest.the-spi-separates-static-describeviews-side-effect-free-planread-and-executeread -->
The portable local manifest version is `actql-connectors/0.1`. It is a closed
envelope containing `version` and `connectors`; each connector entry is also a
closed object. Unknown keys MUST fail before a connector is instantiated.
The SPI separates static `describeViews`, side-effect
free `planRead`, and `executeRead`; one opaque callback MUST NOT hide contract
resolution and network execution in the same phase.

<!-- requirement-block: connector-manifest.a-connector-must-reject-absolute-drive-qualified-unc-parent-segment-and-intermediate-symlink -->
Every filesystem-backed Connector path declared by this portable local
manifest is a relative path confined to the manifest directory. A Connector
MUST reject absolute, drive-qualified,
UNC, parent-segment, and intermediate-symlink paths before reading or writing
bytes. This confinement applies to manifest-declared paths, not to Cloud
storage or inputs separately authorized and bound by the Host. Those remain
subject to their own access and input contracts.

<!-- requirement-block: connector-manifest.raw-tokens-passwords-api-keys-private-keys-bearer-values-and connector-manifest.raw-authorization-secrets-must-not-enter-actql-source-program-cid -->
Authorization secrets are Host state, not ActQL data. A manifest MAY contain
a non-secret `auth_binding` with the lexical form
`auth://<host-binding-name>`. Raw tokens, passwords, API keys, private keys,
bearer values, and other secret material MUST be rejected wherever they appear
in a connector manifest. The host resolves `auth_binding` outside compilation.
Raw authorization secrets MUST NOT enter ActQL source, Program
CID, connector-manifest identity, source evidence, diagnostics, Results,
delivery,
preview, or receipts. The non-secret reference itself is bound by the source
contract so changing the host binding invalidates checked source evidence.

<a id="mapping-contracts"></a>

#### Mapping contracts

<!-- requirement-block: mapping-contracts.host-admission-must-validate-the-inline-mapping-against-the-resolved -->
The author-facing `mapping` field identifies a connector-owned static Mapping
Contract with a typed-qualified reference such as
`mapping:crm.opportunity.v1`. The source and canonical protocol artifacts use
the same spelling. In YAML such as
`mapping: mapping:crm.opportunity.v1`, the first `mapping` is the ActQL field
name and the second is the contract namespace. The resolved contract defines
target schema/version, primary identity, writable
target fields, target types, permitted conversions, and required permissions.
Inline `match` and `set` do not redefine that contract: they select which
named-result columns are used by this program for identity and values. Host
admission MUST validate the inline mapping against the resolved static contract.

<!-- requirement-block: mapping-contracts.the-program-and-preview-must-bind-both-the-authored-mapping -->
The program and preview MUST bind both the authored mapping reference and the
complete resolved mapping evidence as
`resolved_mapping_contract_cid`. The canonical resolved contract contains its
version, mapping and target references, connector-manifest and resource
identity, target-schema identity, complete target schema and nullability,
primary identity, writable fields, conversions, permission rules, required
permissions, and mapping minimum approval. When no external schema reference exists,
`target_schema_identity` is the canonical CID of the complete resolved target
field contract. Changing any member changes the CID and therefore the effect
preview identity.

<!-- requirement-block: mapping-contracts.the-resolved-mapping-contract-must-derive-exactly-one-non-empty-permission mapping-contracts.preview-and-apply-must-reject-a-mapping-unless-exactly-one mapping-generation.product-c4d159e6b70f mapping-generation.product-9c63aad3384b classification-inheritance.product-340f5cf73a23 -->
The resolved mapping contract MUST derive exactly one non-empty permission set
for the effect kind, selector class, and exact write-field set. A resource-wide permission list is evidence
only and is not an executable permission rule: it cannot distinguish effect
kind, selector class, or write scope. Preview and apply MUST reject a mapping
unless exactly one `permission_rules` entry matches all three dimensions.
Neither compiler nor author may broaden that exact rule.

The resolved mapping contract owns a complete target row mapping for
`create` and `store` from a named result. It specifies every target field
as one explicit result field or literal, null behavior, writable/required
fields, types, and conversions. Extra result fields are ignored only because
the mapping does not reference them; missing required target values, implicit
same-name copy, undeclared defaults, or incompatible null/type values fail.
Inline `set` remains the program-specific row mapping for update/upsert within
the writable/type constraints of that same contract.

<a id="mapping-generation"></a>

### Deterministic Catalog generation

Catalog publication may generate contracts from a canonical provider-schema
snapshot, Connector/Resource identity, versioned type mapping, writable/required/
identity rules, operation/permission/preview/recovery capabilities and generator
law. Equal complete inputs MUST produce equal bytes and CIDs, independently of
enumeration, timestamps, secrets and Host paths. Generation is explicit
authorized preparation/publication, never an implicit checker schema fetch.
OpenAPI alone does not prove idempotency, natural-key uniqueness or permission.
Missing capabilities restrict the affected operation, not unrelated valid reads.

Read-only/system/formula fields remain readable but are excluded from writable
mappings. Explicit Program write selection narrows a generated Mapping; no
implicit all-writable copy or invented business default is allowed. Missing
required writes are diagnosed. The explicit Mapping reference remains required;
resolved mapping and capability evidence are sealed in Plan and Preview.
Mapping target identity remains a single primary-key field.

Response normalization MUST convert missing declared optional properties to
typed null under a nullable recursive contract. Required missing or wrong-type
values fail. Null parents stay null; unknown properties require admitted
projection or are schema drift. Failed acquisition is not a null record. This
rule never runs backwards on writes: unselected means omitted, explicit null
means a contract-admitted clear, provider default is separate. Presence evidence
requires an explicit declared field. Regeneration changes affected Contract/
Catalog CIDs and detects lock mismatch; automatic compatible-lock renewal is
deferred. Secret rotation alone does not change the static Catalog.

<a id="classification-inheritance"></a>

### Capture classification inheritance

Observation kind (projection/capture/extraction), data confidentiality and
private evidence storage are distinct. Connector publication binds trusted
provider/parent label mappings and applicable instance/Resource/SourceView
default/minimum policies into generation inputs and Contract CIDs. Capture
resolves those policies before Artifact issuance, not at model dispatch.

Effective policy combines authoritative source/container and existing Artifact
policy, trusted labels and all minima. Classification takes the stronger bound;
region/destination constraints intersect. Incompatible constraints fail. An
absent provider label may use an applicable published default with policy_default
origin evidence. Unknown labels, missing mappings, invalid signatures, conflicts
or absent policy MUST NOT be repaired with that default. Ref, issuer and capture
evidence bind the same resolved policy; receiving/egress cannot relabel sealed
Artifacts. Existing high classification never falls to a local default.

Authors may strengthen a declared minimum, not self-declare a lower class. MIME
does not determine confidentiality. No model call may classify content before
its own egress is admitted. ModelTask/Host still check destination, account,
region, training/retention, scope and media limits; known classification is not
permission. Reference Local mail capture proposes confidential only as an
explicit connection preset, not a language-wide constant or live-provider claim.

<a id="command-contracts"></a>

#### Command contracts

A command resolves to a canonical `actql.command_contract/0.1` containing:

```text
command_id, version, connector_id,
target {resource_kind, cardinality, max_items},
input_schema and closed input_contract, output_schema, permissions,
minimum_approval, idempotency {support, key_schema, retention}, preview strength,
reversibility, atomicity, outcome, reconciliation, cancellation, contract_cid
```

<!-- requirement-block: command-contracts.permissions-must-be-derived-from-this-contract command-contracts.they-must-not-be-authored-or-broadened-by-the-program command-item-contract.product-7dc55ab8c349 stamp-writes.product-de5edfbb89aa stamp-writes.product-54385477c89e model-task.product-e2cfca5b7129 planning-wire.product-a854b55d6c3e -->
The complete resolved contract, not only its authored reference, is bound as
`resolved_command_contract_cid`. Permissions MUST be derived from this
contract. They MUST NOT be authored or broadened by the Program.
`preview: none|schema_only` produces a blind, non-applicable preview. A command
URL, HTTP method, raw provider payload, or command not owned by the selected
Connector is invalid.

<a id="command-item-contract"></a>

### Command item and recovery contract

A Command item is the CID of `{command_contract_cid, target_identity,
canonical_payload_cid}`. Limits count items, not distinct targets. Canonical
item order is target identity then payload CID; contract identity precedes
these when combining namespaces. Exact duplicate mutation identities MUST fail
across a stage even under different Effect IDs. Same-channel different-message
items may be independent under an append capability, but enable/disable payload
differences prove no independence. Intentional resend uses a new logical
request. Commands do not inherit create-row occurrence exemptions.

Recovery contracts declare native, atomic stamped, proved natural_key or
unavailable, with exact-request reconciliation, scope, retention horizon and
finite attempts/cost/deadline. Stamp fields participate in permission and
footprints. Receipt contracts fix item/input-key correlation, typed result,
Ref issuer, and availability at acceptance or completion, never batch-return
order. Data row conflicts are row-level even for disjoint writable fields;
create/update coexistence requires proved key nonintersection.

<a id="stamp-writes"></a>

### Connector management writes

Stamped recovery capabilities MUST declare field/path and type, target scope,
native mapping, fixed insertion recipe/law, same-commit atomicity with business
mutation, write/read permissions, footprint, readback/correlation, retention
horizon and provisioning prerequisites. Field creation is a separate explicit
administrative operation, not implicit schema modification during execution.

Preview displays business writes separately from Connector bookkeeping writes,
including field, purpose, recipe and readback. It binds the recipe, not the future
dispatch-key value. Required permission is their union; a selected business field
does not authorize stamp writes. Check rejects supplied evidence proving missing
permission/schema; otherwise it retains an obligation. Current pre-dispatch
admission MUST validate actor/delegation without silently using a stronger service
identity. Rejection performs neither business nor stamp mutation.

Readonly/formula/system stamp fields, undeclared business overwrite, collisions,
unknown preexisting meaning and non-atomic follow-up stamps are inadmissible.
Changing recovery capability requires a new contract/Preview, not fallback. An
overwritten last_stamp cannot prove a former unknown was not applied: declared
history/horizon evidence must support exact reconciliation. A mechanism name
alone does not prove exactly-once.

<a id="model-task"></a>

### ModelTask outcomes and attachments

ModelTask contracts MUST fix finite retry classification and ceilings, immutable
slot request/model/prompt/generation/output contracts, data handling and typed
attachment roles. Outcome classes and strict publication are defined by
Language's infer. The Host produces outcome tags, not the model. Attempts retain
private raw evidence, usage/reservations and adopted-attempt identity; public
failure rows do not expose arbitrary provider errors. Media contracts specify
MIME, full/truncated requirement, byte/page/frame/array limits, token and cost
worst-case reservation, transfer plan, issuer/scope and current egress.
The adapter binds exact content bytes and full Ref identity independently.
Media reservations are not fabricated exact text-token counts. ResourceRef,
hidden tools/retrieval and cross-Run model cache remain outside this contract.

<a id="planning-wire"></a>

### Plan Documents and public planning results

The machine planning result is one closed `actql-plan-result/0.1` union:
`invalid`, `needs_bindings`, `pending_predecessor`, `ready`, `unsupported`, or integrity-only
`stored`. Invalid source still returns the `invalid` variant when machine output
was requested. `needs_bindings` is a successful template proof, but combining
it with an artifact output request fails and writes no Plan Document.

`invalid` rejects the checking request: a language diagnostic identifies a
language violation, whereas `ACTQL_E_PROFILE_UNSUPPORTED` identifies a profile
the checker does not claim. In the latter case the Program may be valid;
complete type checking is not required and validity is not established.
`needs_bindings` reports a valid template lacking execution values. `ready`
reports a fully checked bound Plan supported by the Host; `unsupported` reports
a fully checked bound Plan that the Host cannot execute. These
validated bound/template variants and `pending_predecessor` carry `semantic_status: valid`; `unsupported` additionally
carries `runtime_support: unsupported`. `stored` reports artifact integrity,
not a fresh validity or execution-admission judgment. No rejected or unbound
result authorizes execution.

For the staged target, `pending_predecessor` is the closed variant registered in
the stage contract's schemas.pending_predecessor. It requires version,
status, semantic_status, runtime_support, execution_admission,
checked_template_cid, node_id, pending_control and pending_imports. The fixed
values are status/execution_admission `pending_predecessor` and semantic_status
`valid`; runtime_support is `supported` or `unsupported` as independently checked.
At least one pending-control or pending-import entry MUST remain. Missing caller
values take precedence as needs_bindings; no future producer value is a caller
hole. Once prerequisites become available, concretization returns ready or
unsupported under fresh admission, not by mutating this template into a Run.
No Invocation, bound Plan Document or authority is fabricated while waiting.
The planning response validates this variant against its registered schema
and stage dependency evidence before admission.

<!-- requirement-block: planning-wire.every-emitted-machine-plan-result-must-remain-valid-after-json planning-wire.every-object-nested-within-that-public-protocol-must-reject-unknown -->
Every emitted machine Plan Result MUST remain valid after JSON serialization
under both the published JSON Schema and the runtime assertion. Every object
nested within that public protocol MUST reject unknown fields rather than
exposing future compiler state by accident.

A compiler-emitted bound Executable Plan carries the metadata-stripped semantic
Program; the names and content CIDs of parameters and opaque bindings; and the
Program Definition, Invocation Template, Check Environment, Grammar, barrier,
AoA, Result Plan, and Effect Plan identities. Because AoA lowering follows
parameter binding, the bound graph MAY contain parameter-derived literals and
other sensitive derived planning material. A saved Plan is therefore wrapped
with its nonsemantic Authoring Context as a private
`actql-plan-document/0.1`. Changing only that context preserves Executable Plan
identity but changes Plan Document and review-projection identity.

<!-- requirement-block: planning-wire.the-public-actql-plan-result-0-2-projection-must-not-expose-bound-scalar-or planning-wire.a-plan-document-must-be-stored-as-private-execution-material -->
The public `actql-plan-result/0.1` projection MUST NOT expose bound scalar or
opaque values, resolved bound requests, or the complete Executable Plan. It
reports declaration names, types, constraints, bound state, identities, and a
redacted structural summary. A Plan Document MUST be stored as private
execution material.

<!-- requirement-block: planning-wire.a-public-planning-diagnostic-must-restore-parameter-derived-and-opaque-binding-derived planning-wire.a-public-planning-diagnostic-must-not-expose-a-bound-scalar -->
A public planning diagnostic MUST restore parameter-derived and opaque-binding-
derived values to their authored symbolic references, or omit a repair payload
when that restoration cannot be proven. A public planning diagnostic MUST NOT
expose a bound scalar, provider identity, private locator, or other opaque value
through a message, replacement, candidate, current shape, available Result, or
operation signature.

<!-- requirement-block: planning-wire.a-runtime-accepting-a-saved-bound-executable-plan-must-replan -->
A runtime accepting a saved bound Executable Plan MUST replan its embedded
semantic Program with the exact supplied values and current Check Environment,
and reject any identity mismatch before provider access or Run creation.

<!-- requirement-block: planning-wire.an-internal-graph-without-bound-execution-material-is-not-an -->
An internal graph without bound execution material is not an Executable Plan
artifact and MUST NOT pass the public Plan Document boundary.

<a id="bound-template-wire"></a>

### Parameter values and bound template

The parameter and bound-template artifacts are respectively:

Values are the effective typed map after applying missing-only literal defaults
once. Nullable explicit null is a value; absent without default remains missing.
Recursive objects are complete, without deep merge. Origin is separate evidence
and does not change equal values' CID. Bound-template wire applies to a concrete
stage; the whole Program checked template carries typed future ports instead of
inventing their values. Contract identity and runtime support are separate:
implementations declare support for exact pinned contracts.

The bound-template envelope below is a common compilation component, not a
complete local Invocation identity. The node-plan binding additionally binds
the local Unit Definition, used parameter values, local contract closure and
concrete import artifacts. Graph membership and activation evidence bind the
whole checked Program separately; they are not ancestors of the local plan CID.
Reusing this component does not permit one unit's imports or authorization to be
substituted for another's.

For extracted units, program_definition_cid identifies the local Unit Definition;
parameter/check-environment identities are the normative used-value/contract
projections. Whole Program values and lock stay authenticated graph membership
evidence. Localizing hashes does not waive whole-lock admission or permit
cross-scope substitution. Map derive uses unordered, input-row expressions;
its array binding evidence requires the registered shared row-kernel extension.

<!-- requirement-block: bound-template-wire.actql-parameter-values -->
<!-- normative-code: envelope -->
```text
{version:"actql-parameter-values/0.1", values, parameter_values_cid}
{version:"actql-bound-invocation-template/0.1",
 program_definition_cid, parameter_values_cid, check_environment_cid,
 source_evidence:"unbound", bound_invocation_template_cid}
```

<a id="parameter-value-projection"></a>

#### Parameter value identity projection

The `values` member is a map from Parameter names to projected, admitted values,
not an untyped copy of supplied JSON. The canonical hash preimage is exactly
`{version:"actql-parameter-values/0.1", values}`; the outer
`parameter_values_cid` member is not included. Empty maps are permitted for a
Program with no Parameters. Program and local used-value projections select
their required names before constructing this envelope; this definition does
not authorize dropping required names.

<!-- requirement-block: bound-template-wire.parameter-projection -->
Parameter Values identity MUST use the following recursive projection of a
complete bound set and its admitted Parameter types. Null projects to null.
Ordinary booleans, numbers and normalized strings retain their JSON values;
date and timestamp retain their canonical wire strings. Arrays project their
elements in order. Object values project their fields in normalized UTF-16
code-unit order. Neither null nor an empty collection receives a declaration
type wrapper. Admission-only constraints (`nullable`, `integer`, numeric bounds,
array length and `max_items`), default declarations, supplied/default origin and
annotation metadata are not value-preimage members. Their exclusion from this
value identity does not remove the Program's declaration or evidence obligations.

Decimal projects to the following value, using the exact coefficient and the
declared precision and scale:

```json
{"$actql_value":["decimal",{"version":"aoa-decimal-value/0.1","precision":4,"scale":2,"coefficient":"1990"}]}
```

The second array member is the AoA decimal value identity preimage with its
version, precision, scale and coefficient, not its display string or a binary64
conversion. A non-null string constrained by `format: duration` projects to
`{"$actql_value":["duration", milliseconds]}`, where milliseconds is the positive
safe integer defined by the Language duration rule. Thus `1s`, `1S`, `01s` and
`1000ms` share a projection; unconstrained strings with those spellings do not
undergo duration conversion. These rules also apply to object fields and array
items. No tag is inferred by inspecting business data.

<!-- requirement-block: bound-template-wire.parameter-object-escape -->
A business object containing the exact normalized key `$actql_value` MUST
project to `{"$actql_value":["object", pairs]}`, where `pairs` contains every
field as `[name, projectedValue]` in strictly increasing UTF-16 name order.
The pair list has unique names and includes `$actql_value` exactly once. Its
arrays are structural containers, not recursively re-escaped objects; each
field value is recursively projected under its declared type. Objects without
that key remain ordinary projected objects. This escape does not reserve an
authored field name or alter the admitted business value. In particular,
business data resembling a decimal, duration or object tag cannot impersonate
that tag in the preimage.

<!-- requirement-block: bound-template-wire.parameter-projection-canonical -->
The complete preimage MUST be serialized by the canonical JSON rules and hashed
over its UTF-8 bytes. The schema fixes projected shapes; canonical normalization,
numeric admission, sorted unique escaped field pairs and agreement with the
admitted declarations remain semantic validation requirements. Invalid or
incomplete bindings do not produce a Parameter Values CID. Hashing the raw
binding strings, stripping arbitrary metadata-shaped business fields, or
interpreting supplied tags as proof of admission is not an alternative.

<a id="compilation-identities"></a>

### Compilation identity envelopes

**Compiled Plan** denotes the compilation identity envelope, while
**Executable Plan** denotes the complete checked execution graph it references.
The Compiled Plan's hash preimage is:

<!-- requirement-block: compilation-identities.actql-compiled-plan -->
<!-- normative-code: envelope -->
```text
{version: "actql-compiled-plan/0.1",
 invocation_template_cid, grammar_manifest_cid, required_profile_contracts,
 barrier_contract_manifest_cid, aoa_logical_cid, executable_plan_cid,
 result_plan_logical_cids, effect_plan_logical_cids, aoa_contract_cid}
```

Result/Effect logical CID maps are keyed by their declared names. The Executable
Plan's `execution_material` binds Program Definition, bound Invocation Template,
Check Environment, parameter/binding value CIDs, Grammar and barrier manifests,
AoA contract, and Result/Effect plan maps; its graph binds nodes, typed edges,
root Results, facts, limits and enforcement references. These are transitive
dependencies, not optional audit metadata. Neither envelope contains its own
CID or a later receipt CID. [Machine contracts](#machine-contracts) pins this owner's
closed wire schemas; the [family contract index](../conformance.md#contract-index)
is informative navigation to other owners.

<a id="diagnostic-documents"></a>

### Diagnostic documents

The canonical diagnostic document is versioned independently as
`actql-diagnostics/0.1`:

<!-- requirement-block: diagnostic-documents.diagnosticdocument -->
<!-- normative-code: grammar -->
```text
DiagnosticDocument := {
  version: "actql-diagnostics/0.1",
  diagnostic_semantic_profile_version: "actql-diagnostic-semantic-profile/0.1",
  diagnostic_semantic_profile_cid: Cid,
  diagnostic_catalog_version: NonEmptyVersionIdentifier,
  diagnostic_catalog_cid: Cid,
  ok: false,
  issues: [DiagnosticIssue, ...],
  diagnostic_cid: Cid
}
```

<!-- requirement-block: diagnostic-documents.each-issue-must-have-a-code-matching-actql-e-a-z0-9-an-absolute diagnostic-documents.a-unique-repair-must-use-replacement-without-also-emitting-a diagnostic-documents.an-ambiguous-repair-must-use-two-or-more-complete-candidates diagnostic-documents.an-ambiguous-repair-must-use-two-or-more-complete-candidates.second -->
Each issue MUST have a code matching `ACTQL_E_[A-Z0-9_]+`, an absolute `$`
path, and a non-empty stable message. `replacement` and `candidates` are
mutually exclusive. A unique repair MUST use `replacement` without also
emitting a one-item candidate list. An ambiguous repair MUST use two or more
complete candidates and MUST NOT emit a preferred replacement.

<!-- requirement-block: diagnostic-documents.before-serialization-issues-must-be-ordered-by-path-code-then diagnostic-documents.allowed-keys-must-be-lexically-sorted diagnostic-documents.available-results-must-be-sorted-by-result-name diagnostic-documents.candidates-must-be-sorted-by-canonical-replacement-bytes-and-then diagnostic-documents.with-the-same-actql-source-compiler-version-capability-profile-and -->
Before serialization, issues MUST be ordered by path, code, then canonical
issue bytes. `allowed_keys` MUST be lexically sorted. `available_results` MUST
be sorted by result name. Candidates MUST be sorted by canonical replacement
bytes and then their stable meaning. With the same ActQL source, compiler
version, capability profile, and schema evidence, the canonical diagnostic
document and `diagnostic_cid` MUST be byte-identical across runs.

<!-- requirement-block: diagnostic-documents.summary-and-verbose-human-renderings-may-differ-but-must-be -->
Canonical diagnostic serialization and CID computation use the AoA Kernel
canonical JSON and SHA-256 contract. Summary and verbose human renderings MAY
differ, but MUST be projections of the same canonical structured facts.

<!-- requirement-block: diagnostic-documents.within-actql-diagnostics-0-1-a-diagnostic-code-s-semantic-condition-and-required-payload behavioral-repairs.product-ba296803a920 -->
Within `actql-diagnostics/0.1`, a diagnostic code's semantic condition and
required payload MUST NOT change. The diagnostic document envelope can carry a
newer separately versioned catalog without changing its own envelope version;
however, adding or removing a catalog code changes the catalog CID and requires
a new catalog version. Changing the meaning of a code, weakening a required
payload, or changing canonical ordering rules requires a new diagnostic
contract version. The compiler error-code catalog is specified below.

<a id="behavioral-repairs"></a>

### Author-choice repairs

A meaning-preserving unique repair remains distinct from a behavioral repair.
Conversion failures MUST offer the corresponding registered `try_*` replacement
when one exists, tagged `changes_semantics: true`, `requires_author_choice: true`
and a reason explaining failure-to-null behavior. A guard-reduction `top_k`
candidate similarly changes selected scope and requires author choice; no
business order is invented. Neither candidate can be auto-applied as a safe
normalization or silently weaken a protected operation. Public diagnostics
redact private bindings; authorized inspection is a separate Run protocol.

<a id="diagnostic-profiles"></a>

### Diagnostic compatibility profiles

Portable language-semantic conformance is defined by
`actql-diagnostic-semantic-profile/0.1`, identified by
`ACTQL_DIAGNOSTIC_SEMANTIC_PROFILE_CID`. It requires the structured envelope,
stable semantic category, absolute path, message, repair-versus-candidate
contract, and canonical candidate order. It intentionally does not require an
independent compiler to claim an exact diagnostic catalog.
Every diagnostic document nevertheless identifies the version and CID of the
catalog it actually uses. The optional claim is equality with the official
catalog, not omission of catalog identity. A different catalog uses its own
versioned identifier and preserves the shared semantic categories and envelope.

The exact agent-authoring diagnostic catalog version is
`actql-diagnostic-catalog/0.1`. Its machine-readable representation is published as
`ACTQL_DIAGNOSTIC_CATALOG`; each entry contains `code`, `phases`, `condition`,
and `required_payload`. Its canonical envelope is
`{version, entries}` and its SHA-256 content identity is published as
`ACTQL_DIAGNOSTIC_CATALOG_CID`. Catalog entries are lexically ordered, unique
codes covering ActQL checking and direct AoA-validation phases. The entry count
is derived from the exact catalog body, not fixed independently in prose.

<!-- requirement-block: diagnostic-profiles.a-compiler-claiming-this-catalog-must-not-emit-an-uncataloged diagnostic-profiles.a-catalog-code-must-not-be-reassigned-to-a-different diagnostic-profiles.tests-must-verify-that-every-diagnostic-code-literal-reachable-from diagnostic-profiles.successful-and-failed-planning-output-and-every-conformance-report-must diagnostic-profiles.an-implementation-claiming-exact-catalog-compatibility-must-match-the-official -->
A compiler claiming this catalog MUST NOT emit an uncataloged `ACTQL_E_*` code. Every
cataloged check diagnostic requires `code`, absolute `path`, and non-empty
`message`; ambiguity entries additionally require `candidates`. A catalog code
MUST NOT be reassigned to a different semantic condition. Adding or removing a
code or required payload, or changing an existing condition, requires a new catalog
version. Tests MUST verify that every diagnostic code literal reachable from
the compiler is registered, that the catalog is sorted and duplicate-free, and
that its CID equals the exact catalog identity bound by the released
specification's conformance manifest. Successful and
failed planning output and every conformance report MUST include the semantic
profile version and CID and the actual catalog version and CID. An implementation
claiming exact catalog compatibility MUST match the official catalog identity;
different CIDs are not exact diagnostic-surface compatible,
but do not alone defeat ActQL semantic conformance.

Concrete preview, admission, apply, serialization, and receipt failures occur
after compiler planning and are not members of this compiler diagnostic catalog.
They use the separately versioned `actql-runtime-error/0.1` artifact and stable
phase-specific error names rather than weakening the check diagnostic
meta-contract.

<!-- requirement-block: diagnostic-profiles.a-published-checked-plan-summary-must-report -->
A published checked Plan summary MUST report:

- the diagnostic semantic-profile version and CID, and the actual catalog
  version and CID;
- normative target modules required by the concrete program;
- complete modules claimed by the implementation, separately;
- any required but unclaimed profiles, distinguishing semantic validation
  from execution support under [Conformance profiles](../conformance.md#conformance-profiles);
- the normalization journal CID and entry count;
- each SourceView's selector and contract CID, acquisition kind, authority,
  observation classification, output Carrier, modes, and any extraction
  contract;
- every named Result's Carrier, statically known fields, field-set
  completeness, identity fields, schema-evidence strength, and stable-order
  status;
- every Result's effective data and retention policy, including whether Effect
  consumption strengthens it to authority-evidence retention;
- the public acquisition scope and logical item bound for every typed external
  boundary; and
- statically required, contract-required, and policy-dependent Checkpoint
  reasons.

<!-- requirement-block: diagnostic-profiles.for-each-named-effect-set-member-it-must-additionally-report -->
For each named Effect Set member, it MUST additionally report its name,
`effect_kind`, resolved
target, whether authority was resolved or deferred to preview, write fields,
exact required permissions when known, the effective item limit, any author
guard and its binding status, the resolved-limit CID, contract minimum,
resolved approval policy, and `executed: false`. The effective limit is not an
inferred author guard ([Author guards, resolved limits, and Plan facts](../language.md#resolved-limits)). Mapping and Connector contract bodies,
bound requests, idempotency material, and private parameter-derived literals
remain in the private Plan Document. This public summary is a normative
authoring contract, not permission to apply the Effect.

<!-- requirement-block: diagnostic-profiles.compact-and-verbose-presentations-may-differ-but-their-structured-facts -->
Diagnostics are not part of AoA IR. Compact and verbose presentations MAY
differ, but their structured facts MUST agree.

<a id="ranked-search-contract"></a>

### Ranked candidate acquisition contract

A SourceView admitted for `search_candidates` publishes a closed ranked-search
capability: dynamic request roles, response candidate identity, ordered-prefix
law, optional finite score contract, completion scope, exactness, pagination
termination, per-query capacities and native batch support. The ordinary
request/response schemas remain authoritative; this capability does not
create another untyped request envelope. ANN additionally binds index and
embedding-model/search-configuration identities. Request values cannot select
a different Connector, Resource, SourceView, ranking law or pagination protocol.

The search barrier has version `actql-search-barrier/0.1` and exactly these
members: `version`, `source_view_contract_cid`, `profile_contract_cid`,
`query_input`, `query_id_field`, `request_fragment_cid`, `static_request_cid`,
`k`, `fields`, `output_contracts`, `resolved_limits`, `barrier_cid`.
Query_input is the ordinary checked input port; fields is the normalized
projection list. Output_contracts is the closed map candidates/coverage of
complete checked Relation contracts. Resolved_limits is the canonical list
of limit bindings for request evaluation, dispatch, response and publication.
Request_fragment binds the dynamic role expressions, their parameter values,
source evidence, output schema and demand under the common expression
contract. Static_request binds remaining request roles including opaque
bindings. Barrier identity hashes the canonical body without barrier_cid.
Public diagnostics reference/redact this private execution material rather
than exposing resolved requests.

<!-- requirement-block: ranked-search-contract.admission -->
Barrier admission MUST reconstruct the request roles, source/profile identities,
complete output contracts, projection and limit bindings from the checked
Program and Check Environment. A valid self-CID alone is insufficient.
Execution verifies each query's response candidate uniqueness, ranking evidence,
prefix length and completion scope before publishing either output. Capture
evidence retains request/response and pagination identities, even for no hits;
coverage is an authenticated projection of that evidence, not an author-made
claim. Physical deduplication requires identical admitted requests and authority
context under the SourceView law and preserves all logical query bindings.

Search response completeness and exactness are independent: exact ranking of
a prefix does not prove that the prefix contains every external match. Partial
input provenance follows the Language rules through local computations; it is
not silently promoted by a complete serialization or successful delivery.

<a id="sourceview-transformations"></a>

### SourceView transformation profiles

<!-- requirement-block: sourceview-transformations.a-connector-catalog-or-host-local-registration-must-not-extend-this -->
This section is the normative registry for `observation.transform` ([Connector SourceViews](../language.md#sourceviews)).
The registered set in this revision is empty; no extraction contract is
admitted. Registration requires a specification revision identifying the
profile ID, version, exact contract CID, input/output contracts, deterministic
transformation and bound laws, failure behavior, and independent conformance
vectors. A Connector Catalog or Host-local registration MUST NOT extend this
set. A profile claim by itself does not authorize provider access.

<a id="machine-contracts"></a>

## Machine contracts

These exact schema/law references are owned here. Their identities do not include this document or another owner's aggregate contract.

<!-- requirement-block: machine-contracts.exact-artifacts -->
<!-- normative-code: law -->
```text
../../../spec/contracts/actql-check-environment.json# sha256:8d080aae1651270777521cb49534bb0b758ce3c5aecc16cc9159c74b77249204
../../../spec/contracts/actql-local-relation-snapshot.json# sha256:60e8136aea733421e75fa3dcef4934c87ce98959b36f8a56da93ccfbf03d81b2
../../../spec/contracts/actql-local-source-reference.json# sha256:9be664306a6a91a8e5bfca53d579e6dac77baf4567eb241ceeedc3216ffe47d9
../../../spec/contracts/actql-protocol-schemas.json#/schemas/model_task sha256:19408a610dbc52552bff3a7f97f25a120a66688e7db4f41383c91c9298f02dd2
../../../spec/contracts/actql-consumer-capacity.json# sha256:7d59718b965451d8a19ccf7095b92777ba0cdd8c3bb71f437ab387801fe7271f
../../../spec/contracts/actql-consumer-capacity.json#/laws sha256:a799f82a4a06d6b2402c434142dd6e13a265bef160f4143160de1770f0e52853
../../../spec/contracts/actql-protocol-schemas.json#/schemas/contract_ref sha256:a149fa3216f6e15bfaca58a886f7a3e6a269b0109fe7b9ccca1c402c1a103e94
../../../spec/contracts/actql-protocol-schemas.json#/schemas/contract_envelope sha256:12b59aa2fd993c1d540f8cc80f658760f17ee9f179d8d12cb5f037127b8ae6fe
../../../spec/contracts/actql-protocol-schemas.json#/schemas/source_view sha256:d6952a589192f22a335237629da2babd794b3b7f9a0c51d674d05146a5ea8d74
../../../spec/contracts/actql-protocol-schemas.json#/schemas/command_contract sha256:1d4f0afc13fe2fb73b193d377cf7f42729f80f8438076f31bcb80f951c8eff01
../../../spec/contracts/actql-protocol-schemas.json#/schemas/connector_catalog sha256:877f1571d0ec91367c8ea53f39e9692a6b34fa788334a748f9f878bcefc004a3
../../../spec/contracts/actql-protocol-schemas.json#/schemas/lock sha256:02e3693c855d6137ac1fee89705a2a11824cf6607ea593b3ee7786263f49bdd4
../../../spec/contracts/actql-protocol-schemas.json#/artifact_schemas/authoring_context sha256:930efa0eff6819f19378cc397c0f268de71d9fcbb5f1543aa0ac4be30f676398
../../../spec/contracts/actql-protocol-schemas.json#/artifact_schemas/parameter_values sha256:6376d9cbe27f40771a0e47ed84128364c218f7403ed3734612ab719b722da6a3
../../../spec/contracts/actql-protocol-schemas.json#/artifact_schemas/bound_invocation_template sha256:d7ba95795c14fc1145fb430f3311d38139a834f15a3dc636bb881ecde9f1cbb7
../../../spec/contracts/actql-protocol-schemas.json#/artifact_schemas/executable_plan sha256:361b003c48ac989d0052a68092cee310235e4817eed2064237bdc619b7c652f9
../../../spec/contracts/actql-protocol-schemas.json#/artifact_schemas/normalization_journal sha256:485ccc0d3215dfc0d9f13101dbc7bc0d4a72b8eb28a346ab8122cafd635ae6f0
../../../spec/contracts/actql-protocol-schemas.json#/artifact_schemas/plan_document sha256:a32fec3b8af1c3b0f6848e3f516fe9f2311f55d07f57b46aa5441f2e717b4404
../../../spec/contracts/actql-protocol-schemas.json#/artifact_schemas/plan_result sha256:dd6343496e0673405ab47bcafe0cf38b2812601f6d84e95fd0232cc1f0320ec7
../../../spec/contracts/actql-production-profile-schemas.json#/schemas/lookup_source sha256:6730fdb00f7b0f21ae796bd55f686fb984cddac5b8da5325cec2114b82a37e1c
../../../spec/contracts/actql-production-profile-schemas.json#/schemas/lookup_barrier sha256:587bfea69fbab0d23d200ac65ffc20c373142c4843820d37db6e0c617f10206a
../../../spec/contracts/actql-production-profile-schemas.json#/schemas/text_time_evaluation_envelope sha256:168fa3b40dd267423f0cbf0b350e9fbab589f094afb400f9f83a2dad22171ba9
../../../spec/contracts/actql-production-profile-schemas.json#/schemas/text_time_evaluation_barrier sha256:291c96a7206b05aeee3512d1232e399bf3be179b7a1c160030ebd0728b903237
```

<!-- stage-contract-pins:start -->
```text
../../../spec/contracts/actql-stage-contracts.json#/schemas/checked_program sha256:9cd57d2b8868b343f5e03afc14e9c890401093052628b5b6aab0d8e12aec29d4
../../../spec/contracts/actql-stage-contracts.json#/schemas/node_plan sha256:b7e43d91097f0424671e001123a1e71752065a7cdfb63fda8298e85d7e302001
../../../spec/contracts/actql-stage-contracts.json#/schemas/catalog_generation sha256:9b53ba0d40b1795ed953f33e2cbc7b5e2c649bea8992712e3a6df0de73e47c52
../../../spec/contracts/actql-stage-contracts.json#/schemas/input_normalization sha256:288bdc94b5c45567c71b8b7129303d5358ba5418e6219bdbb9a2e96ca1d2690b
../../../spec/contracts/actql-stage-contracts.json#/schemas/effective_parameters sha256:04939dfe6b67c50916bd2dad281a2ecc4e89d21c27607a86157f2d918f063fdd
../../../spec/contracts/actql-stage-contracts.json#/schemas/model_execution_contract sha256:c940f10b2c6c9dac5aa4b9451361445bb25dfd6620f5e5be0f08ad67d54750a5
../../../spec/contracts/actql-stage-contracts.json#/schemas/inference_plan sha256:aad4fcf3d6c9a4117c00e141e1abc6b640bb0ef1a6dbae5c54a475eaac8093d1
../../../spec/contracts/actql-stage-contracts.json#/schemas/behavioral_repair sha256:9571db73c3ba7869603bc3e9ba15054172e05a79f056348d5f74b1638e9fdc45
../../../spec/contracts/actql-stage-contracts.json#/schemas/classification_derivation sha256:6820601d432bcc0fb61250cd021e140446ea33e9b4a1b4c0c90c839ae0a687a6
../../../spec/contracts/actql-stage-contracts.json#/schemas/stamp_capability sha256:53a6aa36eb0bfd9fa6df153fff563893435d56a7d5aad7d7adbd7cf8a90dbd03
../../../spec/contracts/actql-stage-contracts.json#/schemas/risk_facts sha256:df89b3058a2410355a01ecf90cf90756424fc3d7028f64ee825a60cf966961ec
../../../spec/contracts/actql-stage-contracts.json#/schemas/pending_predecessor sha256:106477c9d966e26f10aa733e1a4bc91c0c112a1d43b262060a85bd4534b85147
```
<!-- stage-contract-pins:end -->
