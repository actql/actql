# Graph structural contract identity

`graph_contract` builds the closed preimage specified by
[Carriers](../spec/language.md#carriers) from a complete `carrier_contract.Graph`.
It rejects unknown carriers, open property sets and untyped properties. The
opaque result retains the immutable Graph contract and its computed CID; it is
not a snapshot, a validated Delta, or proof of any data's admission.

Property contracts include their complete checked nullability and extents.
Property names and closed label domains use canonical UTF-16 order. Unknown
labels (`null`) and a known empty domain (`[]`) remain different. Source aliases,
enumeration order and observations are not members of this preimage.

## Law binding decision

The existing language contract required exact identity and value law CIDs, but
the pinned AoA contract only supplied the SGA structural-field law body. The
new `aoa-sga-identity-laws/0.1` body fixes both graph laws in one manifest and
both CID members resolve that same body. This completes the normative binding;
it does not add string-only identity restrictions from the reference adapter.
The manifest states contract requirements, not execution-conformance evidence.
Its addition changes the admitted AoA contract CID and dependent pins.

The pinned AoA reference uses string IDs and optional/partial graph records.
Those representations are not substituted for ActQL's complete typed contract
or complete Delta records. The compatibility gap remains at lowering.

## Allocation and bounds

`read_cursor` consumes the same closed normative body and returns the existing
opaque CheckedContract. It reuses checked value-contract admission and Carrier
constructors rather than inferring types from graph values. Both law members
must match the selected SGA law. A supplied label array is already strictly
UTF-16 sorted and unique; the reader rejects noncanonical arrays rather than
relying on the constructor to repair them. Null and empty label domains retain
their distinct meanings. Property maps are complete and never contain unknown
types or provenance-qualified source fields.

Reader construction shares a cumulative node/text budget across the identity,
properties and labels; child type traversal is nonrecursive. The existing
canonical emitter then enforces the complete body's serialized byte, node and
depth limits. Admission of a decoded cursor does not prove that the original
wire bytes were canonical, authenticate a Contract Envelope, or admit graph
contents. Those boundaries retain their own checks.

CID emission uses the bounded canonical hashing writer, without building a
second contract tree, serialized String or full UTF-8 byte array. Indexed
property/label access avoids collection copies. Nodes, container depth and
serialized UTF-8 bytes are bounded by the writer; these are not total heap
limits. The text API uses the same emitter with an independently bounded sink.
Successful hashing retains the emitted byte and value-node counts for consumers
to debit shared budgets, without measuring or serializing the contract again.

Tests fix an independently calculated canonical CID, label-domain distinctions,
incomplete-evidence rejection and output budget boundaries. These check contract
identity, not Graph execution. Delta checking must separately bind the expected
contract, base and target identities and verify snapshot admission; a payload
or matching self-CID cannot manufacture those proofs.

## Definition-keyed Property Graph profile

The separate `actql-property-graph-contract/0.1` profile retains its definition
domain, ordered non-null key contracts, complete definition-local property
contracts, static label sets and each label's exposed property subset. Edge
definitions bind their source and target node definitions. The distinct
Property Graph law manifest binds its identity and value laws. Neither a new
profile tag nor a self-CID authorizes a received constructor domain: the
checking context must establish definition provenance independently.

The new profile does not reinterpret the legacy contract or snapshot. Legacy
inputs, laws and CIDs retain their meaning; neither reader performs an implicit
conversion. An operation without a checked new-profile implementation rejects
the new profile rather than applying endpoint-tuple identity rules to it.

### Construction quantities and checker selection

The installed checker declares the Property Graph profile separately from legacy
SGA support. Old SGA declarations alone do not admit the new constructor. This
declaration is not execution authority or an assertion of backend availability.
The existing operation and resource owners retain the exact checked definition.

`actql-bound-property-graph-laws/0.1` sums the row premises of each node or edge
definition through the existing capacity-application owner. Repeated producer
uses remain separate data-edge occurrences. An empty family has bound zero;
unknown premises are not zero. Premises retain their quantity, target and
pipeline owner, with exact safe-integer arithmetic and overflow rejection.
Definition-local MATCH transfers the applicable graph extent to a row bound.
Neither calculation authenticates data or discharges resource checks. Legacy
Graph count bodies and endpoint-derived construction remain unchanged.

### Snapshot preimage and custody

The new canonical preimage is
`["actql-property-graph-snapshot/0.1", graph_contract_cid, graph_contract, nodes, edges]`.
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
The legacy snapshot keeps its original typed node and endpoint/label order.

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
