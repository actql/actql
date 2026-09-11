# Relation operation type checking

`relation_typing.check` checks one `derive`, `filter`, `select`, `rename`, `drop`,
`sort`, `take`, `distinct`, `dedupe_rows`, `json_pick`, `unnest`, `unpivot`,
`assert_rows`, [group](relation-aggregates.md), [pivot](relation-pivot.md),
[analytic](relation-analytic.md), or [top-k](relation-top-k.md) body against a supplied complete
`relation_schema.Schema` and optional
Parameter declarations. The operation kind is a closed enum; the body is an
owned `decode_core.Cursor`. It is not a parser for the step envelope:
`from`, `as`, `meta`, stage naming and input acquisition belong to the caller.
The source cursor must already satisfy the source normalization boundary.

The authority is the Language's [derive](../spec/language.md#derive),
[filter](../spec/language.md#filter), [select](../spec/language.md#select), and
[common expression](../spec/language.md#expressions) contracts.
Open input schemas are outside this implementation's scope, not prohibited by
ActQL. Candidate-key proofs, row-order witnesses, policy/provenance, cardinality
and execution envelopes are not supplied to or established by this API.

## Inputs, scopes and outputs

`unpivot` retains `Reshape::Unpivot` with detached authored column and keep
arrays. It permits repeated columns but rejects repeated kept names and actual
output collisions. Omitted keep retains no input fields. Recursive `TypeEqual`,
including nullability and bounds, is charged against the shared work budget;
neither a common supertype nor scalar-only restriction is substituted. Qualified
kept fields retain provenance and generated names are flat. `ExpansionEnvelope`
must use the column count including repetitions; this checker constructs no
candidate-key or order proof. `ValidateReshapeRows` remains required before
execution consumers. No rows are materialized by this static API.

`assert_rows` retains either a typed boolean predicate (`AssertWhere`, with one
binding) or an ordered, duplicate-free `KeyComparable` key list (`AssertUnique`).
Nullable booleans and nullable scalar or reference keys are admitted statically.
The input schema is unchanged: neither nullability narrowing nor a
candidate-key proof is produced. `AtomicRowAssertion` requires physical validation
before publication or any proof consumer; `AssertionConsumption` requires later
planning to reject unconsumed assertion branches. These obligations survive a
subsequent projection through the retained pipeline step. This is not a filter:
false and unknown predicates fail the eventual assertion rather than discard rows.
The current boundary does not execute `REL.assert_all` or `REL.assert_unique`.

The [ordering and deduplication guide](relation-ordering.md) describes the four
row operations, their retained `row_operation` details and `pending_validations`.
They do not use expression syntax or consume expression tokens. The existing
expression/projection forms remain distinct from `Form::RowOperation`.

The result retains the input and output Relation schemas, original body, original
operation kind and Parameter declarations. `binding_at` returns each typed RHS
and its retained source location. `references` reports ordinary and qualified field
occurrences, including template substitutions, as `InputField(FieldName)` or
`PriorSlot(index)`. Literal JSON and escaped template braces do not introduce
field references. Reference coordinates retain the syntax layer's source-slot
path/span and optional expression-text range; they do not claim a fabricated
byte mapping through source escapes or YAML folding.

The visible field index is built once. Each RHS receives only its referenced
field contracts, partitioned into ordinary, left and right expression scopes,
avoiding a copy of the entire growing schema at every slot.
Consequently the environment retained by each `TypedExpression` is that
projection, while `CheckedOperation` retains the original complete input and
the preceding bindings. Entire input contracts are preflighted even if a
projection removes them or a later slot shadows them. Parameters remain
declarations: defaults are not substituted, nullable types are not narrowed,
and missing invocation bindings do not block type checking.

- Derive maps read only the operation-start input, reject input collisions,
  and record bindings in canonical UTF-16 name order. An empty map is a no-op,
  including on an empty schema; input-contract and budget checks still run.
  The operation is retained, without deletion or CID equivalence to omission.
- Derive arrays are nonempty singleton-map lists. A prior slot wins over input;
  otherwise input remains visible even if a later slot uses that name. The
  current slot cannot refer to itself unless the input already has that name.
  Duplicate slot names are rejected. A shadow replaces the old type without
  joining or coercion. All slots remain in the result even if a later operation
  drops their outputs.
- Filter requires a boolean result, including nullable boolean, and preserves
  the input schema. This layer does not evaluate the predicate or select rows.
  A bare unresolved NULL is not given an arbitrary expected type; an explicit
  `CAST(NULL AS BOOLEAN)` is typed and accepted.
- Select accepts a nonempty array of field names or singleton
  `{output_name: input_name}` maps. Unknown inputs and duplicate output names
  fail. Several distinct output aliases may refer to the same input.
  A string selection preserves the input's typed qualification; an explicit
  alias must be an authored flat name. Derived names and rename targets are
  also flat. Rename/drop leave qualification on retained fields intact.
  Unqualified references never choose one side of a raw join by precedence.
- Rename is simultaneous, so swapping two names is valid. Drop uses a set of
  input names; repeated removal of an existing name is not a duplicate output.
  Unknown fields and removing every input field fail.
  Empty rename/drop bodies are identity projections, including on an empty
  input schema. This is an explicit clarification of the language contract;
  the earlier reference implementation rejected those bodies. The original
  operation remains retained: no operation deletion or CID equivalence is
  inferred from its being a no-op. Empty select remains rejected.

`projection` separately preserves select's authored order; it is not recovered
from the output Relation schema, whose reference names are canonically sorted.
Rename/drop expand in canonical input-name order because this API receives no
independent physical or publication column-order witness. They do not infer
Result publication order. A caller can pass the output schema to another
single-operation check, but that is not whole-pipeline admission or proof
propagation.
The [pipeline checker](pipeline-typing.md) composes these checks and local joins
with step naming and cumulative limits. `nodes_used` and `tokens_used` expose
the operation's consumed syntax/type nodes and expression tokens alongside
the existing work/text counters; retained source trees have separate costs.

The existing AoA adapter rejects empty `REL.derive.exprs` and empty
`REL.select.columns`. Lowering must resolve these compatibility gaps before it
can implement the admitted empty derive/rename/drop cases; this checker does
not lower operations. The complete-schema restriction belongs to this API's
current scope, not to the language's general derive contract.

## Typed reshaping

`Form::Reshape` retains detached `reshape` details for
[json_pick and unnest](../spec/language.md#reshaping). Both preserve existing
columns and their typed qualification. The source column may be `left.payload`;
new output names are flat authored names and cannot overwrite existing fields.

`json_pick` follows exact keys through closed object contracts, combining
parent and leaf nullability. Binary search reads each opaque field set without
copying it. A final `json` leaf is retained; traversing an opaque `json` fails
with `ShapeEvidenceRequired`. This is an unsupported evidence boundary, not a
language-wide ban on object-valued JSON. No Host shape-evidence API is added.

`unnest` retains the declared item type for normal expansion, even when the
array container is nullable. Outer expansion makes the element and exposed
index nullable. Omitted index, `true`, and an explicit name remain distinct in
the retained source; `true` resolves to `<as>_index`. `max_items` in the details
is the original array bound; it is not an output-row or key proof.

`ValidateReshapeRows` records missing/nonconforming row validation, and
`ExpansionEnvelope` records unnest's pending output/byte/Host bounds. Execution,
source-plus-index identity (including the distinct outer sentinel), candidate
keys, order and completeness evidence are not established by this checker.
Non-outer expansion uses the array bound; outer expansion uses its maximum with
one when known. The existing AoA unnest adapter neither implements outer rows
nor rejects every missing/non-array input; lowering must close that gap before
claiming execution support. No whole-data tree or evaluator is introduced.

Both operations preflight their entire body and input/output schemas with
shared work, text and node budgets; they consume no expression tokens. Source
locations identify the failing column, path segment or option. Returned path
arrays are copies. Their fixed corpus is type-checking evidence, not executed
row conformance. The operation bodies have no dedicated existing machine
schema to regenerate; normative grammar, requirements and fixtures are updated.

## Budgets and immutability

Limits apply to a complete call, never reset for each derive slot:

- `max_work` charges contract visits, field/slot processing, syntax admission's
  reported node work and the expression type checker's reported work. It also
  bounds preflight of the final retained output schema.
- `max_text_bytes` cumulatively charges names, imported contract text, syntax
  text and type-checking text. Repeated processing is charged again.
- `max_nodes` cumulatively charges syntax admission and typed expression nodes.
  Temporary expression-owned trees also have bounded admission.
- `max_tokens` is shared across all embedded expression-text parses.
- `max_depth` bounds each syntax/type traversal, input preflight and final
  output contract depth; it is not summed across sibling slots.

Negative limits fail before checking. `work_used` and `text_bytes_used` report
successful-call accounting, not physical time or heap usage. The already owned
source tree and retained immutable contracts consume memory independently.
Sorts and map hashing are not metered as CPU instructions. Parameter contracts
are currently imported by each RHS type check and that work is charged; this
does not claim a once-only prepared Parameter type index.

Traversal is iterative. The visible-field map is updated in place internally,
but never exposed. Results and child contracts are read-only; exported arrays
are detached copies; references retain shared read-only source handles and expand
one path only when requested. A failure exposes no partial result.
Syntax issues retain syntax diagnostics; type issues resolve the failing
normalized node through its original origin sidecar before propagation.
Operation-level shape/name errors identify the relevant body or declaration.
Diagnostics expose `path`, `span` and optional expression-text `range`;
`source` retains the enclosing checking context and is not a substitute for
those coordinates. Unknown expression fields preserve their reference
occurrence, including a nested structured node or the original scalar slot
and range of an embedded expression string.

## Type evidence is not execution admission

Profile, pattern and Host-envelope obligations remain on each typed expression,
including expressions in undemanded branches. Success is not a checked Plan,
a complete checked row-binding wire contract, or permission to execute.
Runtime demand paths, row-major failure scopes, input/retained-output resource
envelopes and key/policy proofs remain later work. No row evaluator, lowering,
constant folding, CID calculation or external lookup is added here.

[Fixed vectors](../../portability/corpus/actql-relation-typing-v0.1.json) declare
expected schemas, projection order and rejection categories independently of
the implementation. The generator only copies these expectations into tests.
`check:relation-typing` verifies freshness and generator behavior. Product tests
exercise those vectors on each backend and separately cover exact slot
references, shadowing, pending obligations, ownership, cumulative budgets,
wide schemas and deep expressions. These are type-checking tests, not runtime
or whole-ActQL conformance evidence.

## Derive evidence cardinality

The existing `actql-stage-contracts.json#/schemas/derive_binding` now admits an
empty `bindings` list only for `snapshot_map`; `ordered_array` still requires
at least one binding. This repairs the evidence schema's mismatch with the
already-admitted empty map, without changing source acceptance or map AoA nodes.
Input/output contracts, limits, node identity, passthrough and failure scope
remain required even for the no-op. An empty body does not waive input validation
or authorize operation removal. The schema change updates its pin; it does not
reinterpret artifacts pinned to the earlier schema.

`scripts/derive-binding-schema.mjs --write` updates the conditional constraint
and schema CID. Its tests fix both modes at zero and nonzero cardinality and
reject missing evidence, null lists and malformed entries. These tests verify
shape only; hashes and checked-owner correspondence require semantic admission.
The executable ordered row-kernel and its resource-context binding remain
separate work, not an execution capability conferred by this schema correction.
