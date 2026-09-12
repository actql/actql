# Operation obligation reads

Typed-operation owners expose count and indexed reads alongside their existing
copied obligation-array APIs. Collectors can check a retained-entry budget before
allocating an aggregate inventory. Indices preserve the same order, repetitions,
parameter names and original source handles. Negative and out-of-range indices
return `None`; mutation of a copied array cannot alter the checked operation.

Retained arrays use direct length/index access. Fixed and conditional obligation
lists share one bounded enumeration rule between copied and indexed reads, with
no intermediate obligation array for count or element access. Their number of
branches is independent of row counts, property counts and graph size. Graph
structural operations summarize the at-most-two strategy validation families
during checked construction, preserving their first occurrence order. That
single strategy scan is charged to the construction work budget; subsequent
obligation reads do not rescan arbitrary-length property strategy lists.

Public facade APIs retain the same indexed access, including join and vector
evidence owners. An API coverage check requires a matching typed count/index
pair for every obligation-array accessor in these operation packages. This
check prevents interface omissions, not incorrect semantic classification.
Shared enumeration and operation tests separately validate the returned contents.

These are outstanding requirements, not proof of completion. In particular, an
inventory must not treat a static requirement as discharged simply because it
was listed, or treat runtime value/identity validation as already executed.
Graph union retains ordered checked binary folds: consumers visit each fold's
structural obligations rather than inventing a flattened, unbudgeted array.
The owning Program/producer and resolved static or runtime implementation
responsibility must still be attached by the integration boundary.
