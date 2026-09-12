# Finite Relation construction checking

`relation_values.check` checks the source-normalized
[`values`](../spec/language.md#values) body `{schema, rows}`. The schema is a
nonempty closed author field-contract map. Every finite row has exactly these
fields; nullable fields still cannot be omitted. An empty row list retains the
declared type. Constructor eligibility recursively excludes opaque JSON and
reference types, including when the row list is empty; it does not fabricate
reference evidence or infer a missing type.

Cells use exactly the specified whole-value grammar. An exact singleton
`{$param: name}` is always a hole, even when its name is malformed or unknown.
An exact singleton `{literal: value}` quotes its payload once. Everything else
is literal data; nested `$param` and `literal` members are not interpreted.
The checked `Cell` variants are the canonical literal/Parameter distinction;
both plain and quoted literals produce `Literal`. Source locations remain
available separately. Printing, identity emission and actual substitution are
not implemented by this checker.

Literal cells pass typed value admission without implicit casts. Decimal cells
use the declared fixed-scale strings. Whole Parameter holes require known,
assignable declared recursive types; defaults are not substituted and each
occurrence retains its binding obligation. Unknown, incompatible or malformed
holes fail rather than falling back to business data. Nested literal and schema
errors retain their exact source paths and spans.

The opaque result retains the schema and every authored row occurrence in order.
Cells are in the schema's canonical field order; returned arrays are detached.
`pending_binding_cell_at` resolves a binding obligation directly to its row,
canonical column index, checked cell and target contract without rescanning rows
or copying arrays. Repeated uses of one Parameter remain separate occurrences.
The cell retains the Parameter's declared contract, while the target is the
column contract; neither is replaced with the other. The occurrence index is
created under the shared work budget and does not itself discharge binding or
publication obligations.
An occurrence count is not proof of unique projected field values, acquisition
completeness, a published CID or an admitted physical resource envelope.

The pipeline requires `as`, rejects step-level `from`, records no input edges,
and establishes this step as current. Existing current is not consumed. Generated
Relations can feed subsequent operations and named Results, including typed empty
Relations. All independently supplied pipeline inputs remain preflighted even
when the generator does not use them.

Work, source nodes and text are shared across the complete body, schema reads,
Parameter contracts, cell compatibility and literal admission. Bounded preflight
measures and reserves an additional traversal envelope before invoking a reader;
limits are not reset per row. `max_rows` bounds the finite list independently.
Nested source/contracts are traversed iteratively. These logical limits do not
claim a process-wide heap or publication byte bound.

The embedded Program schemas preserve recursive author contracts, decimal
precision/scale conditions, constructibility, disjoint cell alternatives and
generator envelope requirements. Schema-to-row compatibility and binding are
semantic checker responsibilities, not cross-field JSON Schema inference.
`check:values` verifies generated contracts and artifact pins. Product tests cover
empty/repeated rows, quoting, null versus missing, decimal admission, whole-value
holes, recursive failures, exact budgets and pipeline/Result composition across
three targets; they are not evaluator conformance evidence.
