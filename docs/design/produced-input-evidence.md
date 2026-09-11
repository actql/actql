# Producer-bound input evidence

`pipeline_typing.produced_input` selects a valid target in an immutable checked
pipeline. `InputContract.ProducedInput` makes that target available as an input
to another check, retaining the original pipeline and target rather than
accepting an independently supplied count, Carrier or proof flag.

This represents conditional successful output from the retained producer. It
is not a SourceView snapshot, a published Result import, a measured data fact or
an execution certificate. Producer obligations, Parameter bindings and source
validation remain necessary. The normative distinction between estimates and
verified source facts remains in
[Check Environment](../spec/protocols/contracts.md#check-environment); this API
does not bypass that admission boundary.

## Retained axes

The handle captures the actual Carrier, existing key and ranking owners, and
the producer's conditional counts. Relation/Event/Vector record counts and
Graph node/edge extents remain distinct. Counts retain exact versus upper-bound
status. Unknown remains unknown, even when an identically typed input elsewhere
has a finite count. An ordinary `CarrierInput` never borrows the count of a
structurally equal producer.

The shared count pass reads both retained input facts and earlier step facts.
Consequently unary and binary consumers, graph construction/projection,
selector relations and ranking operand occurrences use the same arithmetic
rules regardless of whether a count originates locally or from a retained
producer. Repeated targets remain repeated operands; forwarding does not
deduplicate rows or strengthen an upper bound into an exact count.

`input_producer`, `producer_pipeline` and `producer_target` expose the provenance
owner for subsequent complete checking. Key and ranking ownership is retained,
not reconstructed from field names. Numeric facts are cached in each handle,
so forwarding an input through many checked pipelines does not recursively
traverse its ancestry. The ancestry itself remains available; the API does not
silently discharge an earlier producer's obligations.

Input admission continues to charge Carrier/key processing. Count-table
construction additionally charges two input visits before allocating its row
and graph tables. Exact shared budgets pass and insufficient budgets fail
without exposing a partial pipeline.

## Order ownership

Logical-order origins and dependency targets are pipeline-local coordinates.
An imported order has `Input(i)` as its receiving-pipeline origin, no local step
producer and no copied foreign dependency targets. `order_input_producer`
returns the retained input owner; `producer_order` yields its upstream order in
`producer_pipeline`'s coordinates. That order retains the actual generator or
operation, repeated dependency occurrences and validation obligations.

Accordingly, `order_producer` returns an optional local `CheckedStep`. A caller
must distinguish a step origin from an imported input origin rather than
interpreting an upstream `Step(0)` as the receiving pipeline's `Step(0)`.
Preserving steps keep this input origin and record local predecessor targets.
An operation that establishes a new order has a local producer and local input
dependencies, which may themselves resolve to imported owners.

The order table charges one additional input visit per entry before allocation.
Each produced input caches its order handle; forwarding and ordinary lookup are
non-recursive. Provenance can be followed explicitly and iteratively. Unknown
order stays unknown. Merely giving an ordinary Carrier the same field types,
or importing its unknown order through another owner, cannot establish order.
`take`, existing-input-order consumers, binary order transfer and Result
publication use this boundary through the shared logical-order lookup.

## Remaining boundaries

Window-role and typed Delta evidence still need their own cross-pipeline
bindings; their absence is not a new language restriction.
The final combined checker must traverse producer dependencies with shared
budgets and reject any unresolved mandatory obligations. This handle alone
does not prove that the producer was fully discharged or actually executed.

External snapshot verification, Check Environment authority, named Result
projection/publication and runtime input-to-content binding remain separate
work. Consumers must not interpret this internal producer reference as
permission to attach arbitrary external rows to the producer's counts.
