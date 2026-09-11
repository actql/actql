# Expression-normalized pipeline source

`pipeline_source.prepare` consumes one complete `pipeline_parameters.Collected`,
retaining its exact pipeline and source owner. It indexes every checked
expression root by its original source location, verifies membership and unique
nonoverlapping replacement, and retains the corresponding immutable normalized
Expression. A caller cannot supply replacement expressions, a selected subset
of slots, or a separate source tree.

`emit` writes the source steps array into a caller-owned canonical writer.
Whole grammar-owned expression slots use `expression_syntax.emit_source`;
other structural fields and direct Parameter operands remain source values.
Only metadata values at Step.meta are excluded. The exclusion never descends
into literal business values, so fields named meta, literal and $param survive.
Source normalization is not parameter substitution: references stay unbound.

Map versus array derive remains distinct, including authored array slot order
and shadowing. Empty no-ops, explicit from/as, selected fields and authored
assertions are retained. No schema-dependent expansion, candidate-key completion,
default insertion, macro lowering, expression deletion or normalization journal
entry is fabricated. Grammar decoding is separate from Plan completion under
the language's completion and canonical identity rules.

Preparation scans the retained structural source with an additional work cap;
previous collection/type-checking charges remain the caller's responsibility.
Normalized expressions are already admitted. Retained non-expression strings
and keys are checked for canonical NFC/LF; nonfinite numbers and negative zero
are rejected rather than repaired. Step metadata has already been admitted by
the owning pipeline and is not reinterpreted as execution data. Preparation
returns no partial result on failure.

Emission is iterative and shares the enclosing writer's output byte/node/depth
limits. Per-object key sorting uses the previously bounded input; max_bytes is
not a whole-heap bound. Text, measurement and hash sinks consume the same
canonical events, without constructing a second normalized steps tree.

This is the steps component consumed by [stage local bodies](stage-source.md),
not a complete stage or Program identity. Inputs, Results, Effects, binding
declarations, their used references and enclosing membership still require full
semantic admission. No Fragment root index, semantic step ID, executable node or backend
capability is assigned here. The original checked pipeline and reference index
remain attached for that integration.

Tests fix text/structured equivalence, Parameter and owner retention, precise
metadata exclusion, ordered shadowing, no-op retention, empty steps, preparation
caps, canonical output, an independent digest and enclosing sink boundaries.
