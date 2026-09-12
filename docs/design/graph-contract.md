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
