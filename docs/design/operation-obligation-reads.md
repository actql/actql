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
responsibility are separate integration concerns.

## Pipeline groups

`operation_obligation_group_count/at` exhaustively dispatches the checked
pipeline vocabulary into opaque groups. Each group exposes typed count/index
reads and a local scope. Sequence retains both its row validations and sequence
semantics. Graph union exposes each ordered binary fold, including repeated
operands. Subgraph and traversal retain their node/start selector groups;
shortest-path selection retains source and target selector groups independently.
Single endpoints do not acquire selector obligations. A body group can be empty.

Group count and access do not flatten an arbitrary number of folds. A collector
charges each group before reading its size, then charges its entries before
retaining them. The group preserves the original checked owner; wrapping an
obligation does not alter its source handles, parameter names or dependencies.
Expression obligations inside predicates remain the expression collector's
responsibility. These groups do not duplicate embedded key requirements as
independently attachable proofs.
