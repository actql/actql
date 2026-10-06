# Graph structural contract identity

The current implementation target is the definition-keyed Graph
profile described below. Its model and law body are owned in ActQL, with no
dependency on `smoothhq/aoa` or its PR #2. Historical law and snapshot records
remain immutable evidence, not a compatibility or fallback requirement.

## Contract admission and bounds

The Graph contract codec admits only complete, definition-scoped metadata.
Unknown carriers, open or untyped property schemas and inconsistent labels,
keys or endpoints are rejected by the existing Carrier and value owners.
Contract admission does not certify row admission, execution authority,
retention or cleanup completion.

CID emission uses the bounded canonical hashing writer without constructing
a second contract tree, serialized String or full UTF-8 byte array. Indexed
definition and property access avoids collection copies. Nodes, depth and
encoded bytes are bounded and returned to the enclosing owner for accounting.
These bounds are not a total-heap theorem. Text emission uses the same codec
with its own bounded sink. Delta admission separately validates contract,
base and target identities and complete records.

## Definition-keyed Graph profile

The separate `actql-graph-contract/0.1` profile retains its definition
domain, ordered non-null key contracts and key-column/component correspondence,
complete definition-local property
contracts, static label sets and each label's exposed property subset. Edge
definitions bind their source and target node definitions. The distinct
Graph law manifest binds its identity and value laws. Neither a new
profile tag nor a self-CID authorizes a received constructor domain: the
checking context must establish definition provenance independently.

The new profile does not reinterpret historical contract or snapshot bytes.
Their laws and CIDs stay unchanged as evidence, but old-format admission and
compatibility readers are not required. Existing consumers move to the keyed
contract. An operation without a checked keyed implementation explicitly
rejects it rather than falling back to endpoint-tuple identity.

The current schema reader shares the existing checked value and Carrier
validators. Structural JSON nodes/text/depth and type/label comparison work
have separate bounds. `read_graph_cursor_usage` returns consumed
comparison work to the enclosing admission owner, which debits it once across
all schemas, including unused definitions. No second schema or Graph validator
is introduced. Successful schema admission is not row or snapshot admission.

### Construction quantities and checker selection

The installed checker declares the Graph profile separately from legacy
SGA support. Old SGA declarations alone do not admit the new constructor. This
declaration is not execution authority or an assertion of backend availability.
The existing operation and resource owners retain the exact checked definition.

`actql-bound-graph-construction-laws/0.1` sums the row premises of each node or edge
definition through the existing capacity-application owner. Repeated producer
uses remain separate data-edge occurrences. An empty family has bound zero;
unknown premises are not zero. Premises retain their quantity, target and
pipeline owner, with exact safe-integer arithmetic and overflow rejection.
Definition-local MATCH transfers the applicable graph extent to a row bound.
Neither calculation authenticates data or discharges resource checks.
Historical Graph count bodies remain frozen; current declared-node bounds
never invent nodes from endpoint values.

### Snapshot preimage and custody

The new canonical preimage is
`["actql-graph-snapshot/0.1", graph_contract_cid, graph_contract, nodes, edges]`.
The embedded complete contract must hash to `graph_contract_cid` and match the
consumer's independently expected contract. It preserves labels and typing for
empty graphs without inferring a schema from data. A received contract is not
permission to relabel an existing managed read or mint a new identity domain.

Nodes use complete closed records `{id, key, props}`. Edges use complete closed
records `{dst, id, key, props, src}`. `id` is the full definition-scoped semantic
identity, and `key` retains the original admitted key components in their typed
wire representation. The source and destination are full node identities, not
physical indexes. Static labels and property exposure come from the embedded
definition contract, not from property names or arbitrary record labels.
Properties contain exactly the complete definition-local field set, including
nullable fields. Reload must revalidate key evidence, identity, property types
and endpoint membership; it must not infer capability-bearing key evidence from
the projected identity or silently omit malformed records.

Each kind is strictly sorted by its full canonical identity token, independently
of input enumeration and endpoint equality. Independently keyed parallel edges
therefore retain separate records. Changing a property, label or endpoint changes
the snapshot contents, not the identity of the same definition-scoped typed key.
Historical snapshot preimages retain their original identity order as evidence;
they are not accepted or converted into this framing.

Emission shares the existing bounded snapshot sort, phase and encoding owners.
The opt-in API drains provisional canonical bytes from the same hashing writer;
a final digest is available only after complete emission. Byte, value-node,
depth and workspace ceilings apply before completion. Cancellation releases the
snapshot's private sort/output state without reclaiming its borrowed Graph.
The consumer's existing storage/publication owner must confirm all writes and
finalization before publishing. A prefix, a drain, or a matching digest alone is
not a completed stored snapshot. Save/reload does not add execution authority,
a second Graph engine or a separate retention owner.

Reload uses the existing RowsToGraph bounded session, Graph OutputBuilder and
retention owner. The expected contract comes from the caller's checked owner
and target binding, not from the snapshot. Closed framing and contract admission
precede record admission. Keys, complete properties, strict identity order and
endpoint membership are checked through the existing value and storage owners.
Snapshot admission rejects NULL keys and missing endpoints; the constructor's
exclusion rules must not repair a stored snapshot. Capability-bearing keys need
the caller's current Host reference issuer or reissuer. Semantic identity JSON
cannot grant reference authority.

Completed material remains private while the existing snapshot encoder verifies
the expected content CID. Only a full match permits downstream handoff. Failure,
capacity exhaustion, input loss or cancellation retains cleanup for both private
material and hashing state, and cannot expose a prefix as a Graph. Successful
handoff preserves the existing downstream custody; cleaning the completed reload
session must not reclaim that Graph. Parsing a decoded snapshot and verifying its
canonical content identity do not prove that the original transport bytes were
canonical, authenticated or durably stored.
