# Completion and physical Relation storage

Execution success and physical layout have separate responsibilities. The
opaque completed sequence retains the exact prepared owner, selected contracts,
Parameter binding and upstream completion anchors. Its private store retains
either ordinary row tables or mixed row/numeric-column tables. Neither storage
construction nor equal values establish successful execution.

Both representations enter the same ordered driver and final success
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
