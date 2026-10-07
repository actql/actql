# Preparation Array custody and conditional storage

The existing Native diagnostic additionally samples one populated, unfinished
producer-read cursor and one completed transfer of the same input occurrence.
It does not start another parent or create a production owner. The fixture
independently fixes one receiving input port and one receiving schema field.
Typed borrowed roots bind the observations to actual preparation records.

`selected` begins empty and grows once per resolved receiving port; `columns`
begins empty and grows once per resolved receiving schema field. The source
review checks these construction/growth sites, the metadata entry admission,
and the publication of the same columns Array into `ProducerRead`. These are
reviewed source premises, not a general control-flow or heap analysis.

The pinned Native Array owner requests 24 bytes, and the fixed buffer has an
8-byte header plus 8 bytes per reference slot or 4 bytes per Int slot. With
`C(h) = max(8, 2*h)` for positive high water and `C(0) = 0`, the conditional
component envelope is:

```text
80 + 16*C(receiving ports) + 8*C(receiving fields)
```

The 80 comprises two owners and up to two buffer headers per Array. The slot
terms include old/new growth overlap. Cardinality bounds, the pinned ABI/growth
implementation and at most two live growth buffers without escaped views are
premises. This expression is 272 bytes for the fixed one-port/one-field case;
it is not a measured peak or a whole-parent reservation. Empty static buffers
are reported separately from dynamically requested storage.

`PreparationArrays.lean` checks the conditional component arithmetic and uses
the existing allocation-identity charge model to show that transferring the
same columns Array does not charge it twice. Expected proposition types and
the existing axiom audit remain mandatory. The two propositions do not prove
source dependency completeness or physical collection.

An unfinished cursor's cancellation clears columns; cancellation of an already
completed cursor preserves the published columns. The pinned `Array.clear`
changes the visible length, retaining capacity/backing and previously
initialized slots. In particular, clearing selected still retains its first
initialized input reference while that Array is held. The observer reads only
that known initialized prefix, never arbitrary uninitialized capacity. It
keeps explicit cursor/read references, so it cannot establish GC destruction.

The final consumer independently recomputes point storage, sharing, and
retention from the archived execution log. Source/overlay/compiled marker and
executed binary correspondence remain required. Missing, changed or detached
preparation facts are rejected. No historical receipt is rewritten as a new
execution.

Remaining obligations include the selected input wrapper and ProducerRead
binding/output referents, shared schema/payload, escaped views and arbitrary
external holders, allocator overhead, complete lifetime unions, Ledger
generations and reservation retirement. These require separate correspondence;
clear or disappearance from the parent state alone cannot discharge them.
