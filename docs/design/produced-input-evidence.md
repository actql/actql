# Producer-bound input counts

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

## Remaining boundaries

Logical-order origins and dependency targets are pipeline-local coordinates.
This increment deliberately does not copy those coordinates into another
pipeline. Order import needs a separately retained origin boundary, as do window
role and typed Delta evidence; their absence is not a new language restriction.
The final combined checker must traverse producer dependencies with shared
budgets and reject any unresolved mandatory obligations. This handle alone
does not prove that the producer was fully discharged or actually executed.

External snapshot verification, Check Environment authority, named Result
projection/publication and runtime input-to-content binding remain separate
work. Consumers must not interpret this internal producer reference as
permission to attach arbitrary external rows to the producer's counts.
