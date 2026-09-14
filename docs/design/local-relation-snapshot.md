# Local Relation schema snapshot integrity

## Input score assertions

The optional `score_contracts` map supplies field-scoped input semantics for
score fusion without changing row value contracts. This is an extension of the
closed snapshot envelope, not a reinterpretation of authoring metadata. The map
uses the same closed ScoreContract schema as max/weighted-sum options. Its
cross-field existence/type checks and ordered finite endpoints are semantic
admission checks; JSON Schema alone does not establish them.

Admission retains indexed immutable declarations and their source cursors.
Those declarations remain assertions requiring authentication against captured
input evidence. The distinction prevents an authored range from relabeling raw
BM25 or cosine scores as a common normalization. Empty data does not remove
the requirement. Row-type projection stays independent: a consumer that uses
score semantics needs the selected declaration and source correspondence in
its static identity as well as the row type, not the full observed snapshot.

Snapshots without this optional member preserve their existing canonical bytes
and identities. Consumers pinned to the older closed envelope cannot admit the
new member; updating the interpretation contract does not establish backend
support or permission to execute.

Environment reconciliation constructs each typed input registration once and
retains it by declaration index. A score-bearing input combines its declared
candidate key with the ranking assertion through the existing Relation evidence
boundary; score admission neither drops the key nor proves its uniqueness.
Repeated readers return the stored handles. Attachment checks exact registered
owners and rejects independently rebuilt same-content evidence.

Static contract collection selects a separate `StageLocalInputScores` root for
each Local input with nonempty declarations. Its score projection uses the
existing snapshot shape without materialization claims, keeping the entire
selected input's score map and row schema. This is distinct from the unchanged
row-type-only projection. Import consumers refer to their producer, rather than
copying the producer's Local assertion into their own direct contract set.

The normative owner is [local Relation schema snapshots](../spec/protocols/contracts.md#local-relation-snapshot).
`spec/contracts/actql-local-relation-snapshot.json` pins the envelope schema,
checked-type/selector dependencies and semantic requirements. Extract `schema`
as a standalone schema resource for its local `$defs` references.

This closes an unspecified wire boundary rather than copying the reference's
internal representation. Sketch `87dc7144:src/actql-collection-integration.ts`
uses bare field maps and flat local selectors for already captured integrations.
The staged contract uses a complete checked non-nullable object contract and
the separately pinned staged selector. Empty fields remain a known empty schema,
not an unknown schema. A full checked contract avoids author defaulting during
evidence admission and reuses the existing validated type reader and emitter.

Static schema evidence does not require an existing materialization. The optional
`input_cid`/`completeness` pair retains a claimed capture; an IntegrationBinding
CID is optional because ordinary local inputs need not arise from Collection.
These are explicit choices extending beyond the reference's captured-only path.
No absent claim is synthesized, and no claimed completeness becomes verified
by schema agreement. Other Carrier snapshot bodies remain separate work.

`local_relation_snapshot.read` requires canonical UTF-8 bytes and an external
expected CID. It bounds input bytes before hashing, uses bounded nonrecursive
JSON and checked-type admission, and reconstructs the entire body into the
bounded hash sink. Both hashes must equal the expected identity. This rejects
normalization repair, whitespace, alternate key/number spelling, unknown members
and malformed types without materializing a second serialized body. Each pass
has the supplied node/depth/byte caps; returned usage describes the canonical
body, not total CPU work or heap usage. Callers still budget batches globally.

JSON Schema checks closed shape, checked type syntax and optional-member pairing.
Canonical bytes, Unicode, schema semantics, identity, Program correspondence and
evidence authority remain separate checks. The fixed corpus is independently
authored; Node fixes canonical bytes/CIDs, and MoonBit checks the expected body
acceptance. This is not a claim of generic JSON Schema validator conformance.

The opaque `Snapshot` establishes content integrity and envelope/type validity
only. It retains unverified materialization claims without executing I/O.
`stage_local_inputs.reconcile_snapshots` now binds resolved local source slots
and authored assertions to the exact snapshot and prepared Program/stage owners
under cumulative budgets. Subsequent admission must still bind the selected
Check Environment and governing provenance/authority. The snapshot cannot be
passed to the source-only pipeline assembly as authenticated Host evidence.

`read_member` now accepts only an opaque SchemaSnapshots member of an
integrity-checked Check Environment. It derives the expected snapshot CID from
that member, validates the complete body and retains both in `EnvironmentSnapshot`.
An identical body in another section is not applicable. Membership is scoped to
the exact wire environment owner, not inferred from a caller-supplied CID string.
Full environment/policy admission and connection to the resolved Program inputs
are still separate requirements.
