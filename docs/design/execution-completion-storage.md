# Completion and physical Relation storage

Execution success and physical layout have separate responsibilities. The
opaque completed sequence retains the exact prepared owner, selected contracts,
Parameter binding and upstream completion anchors. Its private store retains
ordinary row tables, numeric-column tables or admitted-value tables. Neither storage
construction nor equal values establish successful execution.

These representations enter the same ordered driver and final success
constructor. A failure clears invocation-local retained outputs; no completed
handle is returned. Completion and producer admission contain no expression
frame, continuation or scheduling API. Changing synchronous expression
scheduling does not change this boundary.

## Producer admission

Binding checks the producer pipeline, bound preparation and target. Receiver
admission checks selected contracts and input obligations before importing data.
Logical input charging reads every row before projection, regardless of buffer
sharing. The adopted physical view has receiver-owned metadata while its
completion anchor retains the actual producer and original buffers.

An integration can narrow a successful output's future admission through
`bind_live_completed_input`. This shares the original storage and metadata and
combines the original completion predicate with an additional synchronous live
condition. It cannot create success from rows or replace the original condition.
Observation adapters install exact issuer/attempt/observation verification here.
An existing binding or producer read does not freeze that condition: new read
preparation, import and consumer execution still check it. Independently
completed consumers retain their own successful results after upstream revocation.

Each successful producer binding has a private immutable process-local identity.
Fixed-input completions record those identities by receiving port, separately
from their physical storage anchors. `completed_output_matches_inputs` checks
the exact bound owner, all receiving ports and those binding identities; equal
rows, schemas or CIDs cannot substitute for a different binding. Rebuilding a
read view of the same binding preserves that identity. The identities themselves
hold no row buffers or upstream liveness callbacks.

Local execution records the admitted producer bindings. A trusted external
Compute port receives its exact fixed inputs at preparation and snapshots only
their identities; its installed verifier remains responsible for the actual
input/attempt/transport relationship and live admission before completion.
Acquisition ports do not claim fixed-input provenance. Checking an independently
completed result's input affinity does not require its upstream to remain live;
the result's own liveness and retention still apply. No identity wire domain or
logical charging rule is changed by these private references.

Row storage remains the default. A typed producer selects the mixed-storage
adapter before execution. This is representation dispatch, not error recovery:
neither exhausted budgets nor expression failures retry a different strategy.

## Numeric columns and conversion

The private typed representation retains numeric and validity buffers, names,
an explicit row count and optional composed selection indices. Zero columns
do not imply zero rows. No mutable buffer accessor or public disposal operation
is exposed. Public cell observation returns the existing immutable Value form.

Projection uses the existing checked row-body evaluator and a numeric-column
sink. A temporary projected row may exist, but no complete output row matrix
is retained. Index operations use the existing comparison and selection kernels;
their physical adapter composes indices against shared buffers. This does not
introduce ordering inference or change tie handling.

Admitted-value tables use a separate projection sink, not the numeric sink.
The same checked evaluator establishes column selection, aliases, logical
charging and failure order. The sink retains the selected immutable admitted
values by reference, reserving the destination reference arrays before their
construction. It does not re-admit values or convert text, decimal or temporal
payloads to numbers. Empty inputs retain their checked output names. These
tables already contain row reference arrays; preserving them is not a claim of
columnar execution or allocation-free projection.

Non-projection expression bodies use the existing bounded row output builder.
This is the explicit conversion boundary for consumers without a typed output
builder: the input remains readable in its current representation, and only
the output becomes row storage. The shared evaluator charges construction,
retention and values; there is no speculative conversion followed by fallback.

## Lifetime and resource accounting

An opaque `ProducerRead` can expose the immutable receiving schema and cells of
an exactly bound completed producer to a physical input adapter. Preparation
checks the receiver by reference identity, resolves the already checked input
projection to retained source columns, and bounds column/name traversal before
building the index map. It retains the bound upstream output and does not copy
rows, reconstruct ownership, or expose mutable storage. Such a view is not
receiving admission, a successful Compute, or a logical accounting credit;
execution and transfer still enforce their own applicable budgets.

Temporary numeric buffers and index copies are reserved before allocation and
charged to operation work. Common table reservations remain in force. Mixed
stores additionally reserve the full numeric/validity backing capacity and
selection indices, even if the visible selection is small. This is conservative
per-handle accounting; sharing does not reduce logical occurrences or silently
discount a receiver's retention ceiling.

Container/element limits, logical value bytes and process RSS are different
quantities. References keep necessary buffers alive; dropping a user handle
does not promise immediate allocator or GC release. Multiple consumers have
independent invocation budgets and cannot invalidate an upstream completion.

This boundary is not whole-Program admission, Result publication, Arrow support,
general vectorization or a change to the default physical layout.
