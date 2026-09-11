# Local pipeline Parameter collection

`pipeline_parameters.collect` composes the checked pipeline's expression-slot
and direct-Parameter-operand collectors with
[canonical reference indexing](parameter-references.md). It derives the slots
from the retained pipeline, rather than accepting a caller-selected subset.
Unused branches still contribute references; metadata and literal payloads do
not become references merely because they contain `$param` keys.

Typed expression roots retain their existing admitted expressions. Direct
operands are already checked singleton `{$param: name}` objects; the collector
admits those two-node objects through the common expression boundary. It does
not reparse expression text, expand defaults or substitute bound values.

The chosen pointer root must be an ancestor of the pipeline source in the exact
same admitted arena. This is checked even for an empty pipeline. References
resolve against the pipeline's retained declaration owner; a pipeline without
one uses an empty declaration set. The opaque result retains the pipeline,
both slot collections and the resulting immutable reference index.

## Shared limits

`max_slots` covers expression roots and direct operands together.
`max_references` covers all occurrences, including repeated names.
`max_direct_text_bytes` is shared by common admission of all direct operands;
already admitted typed expressions are not charged again as direct text.
`max_pointer_units` limits aggregate escaped RFC 6901 pointer UTF-16 units.

`max_work` covers source-root path segments, both collectors' reported work,
two retained nodes per direct operand plus its common admission node usage,
occurrence-discovery work, slot and reference registration, and pointer units.
Each component receives the remaining allowance. Exact limits pass; negative
limits and exhaustion reject without returning a partial collection. Nested
failures retain their slot, syntax or reference-index classification.

This is a logical-work budget, not a wall-clock or heap quota. Sorting and
declaration lookup comparisons are bounded by collection sizes and previously
admitted declarations, not individually charged. Paths are materialized from
previously bounded source and expression trees. Output Writers retain their
independent byte, node and depth budgets.

## Remaining semantic boundary

Completeness here concerns currently admitted operations in one local pipeline.
It does not discover Program input, Result, Effect or binding slots, traverse
producer pipelines, reject globally unused declarations or prove that the
declaration owner came from the enclosing Program source. Choosing a document
root controls pointer coordinates; it does not validate that document's grammar.

The [source-bound stage collector](stage-parameters.md) binds declarations, steps
and initial `from` to a structurally admitted Program before calling this layer.
The complete stage/Program semantic envelope, Invocation identity and capacity
applicability still require those enclosing checks. A local reference index
must not be presented as a completed Program semantic owner.

Tests cover mixed expression/direct references, retained declaration ownership,
unused branches, metadata opacity, document/local pointer roots, empty and
foreign roots, all exact-limit boundaries and shared direct-operand text usage.
