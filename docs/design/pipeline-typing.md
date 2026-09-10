# Pipeline type checking

`pipeline_typing.check` connects an ordered array of steps using the
[pipeline naming rules](../spec/language.md#pipeline-references) and the
[single-operation checker](relation-typing.md). It supports only `derive`,
`filter`, `select`, `rename`, `drop`, [ordering and deduplication](relation-ordering.md)
(`sort`, `take`, `distinct`, `dedupe_rows`), row assertions (`assert_rows`), typed
reshaping (`json_pick`, `unnest`, `unpivot`), [local join](relation-join.md),
[append](relation-append.md), [nest](relation-nest.md), and
[group aggregates](relation-aggregates.md). Other operation names are explicitly
unsupported; no step is skipped or treated as an opaque successful operation.

## Inputs and scope

Nest uses the current/step-selected parent and resolves its child `with` through
the same input/prior-`as` namespace. It has no `left` override. The retained
`Nest` variant includes the child target, payload projection sequence, authored
ordering and guard, and unresolved order/capacity/validation obligations. It
accepts qualified schemas on either side; child payload names must be explicitly
flat. Assertions and unpivot remain unary operations. Neither nesting nor row
assertions produce proven keys or permission to publish during this check.

Append uses the current/step-selected Relation as its left input and resolves
`with` through the same input/prior-`as` namespace as join. It does not inherit
join's explicit `left` selector. `CheckedOperation::Append` retains the right
target and checked recursive schema alignment, including when both operands
are the same target. Registration of `as` occurs after checking, so forward
and self references remain invalid. Append's work, text and node usage is
debited from the shared pipeline budget; it consumes no expression tokens.

The caller supplies an owned, source-normalized steps cursor, a list of
materialized input names and complete [Relation schemas](relation-schema.md), optional
Parameter declarations, an optional cursor for stage-level `from`, and limits.
Input names must already be NFC/LF and well-formed Unicode, with nonempty
contents. They are dataflow names, not field names or Parameter identifiers.
Input order only defines the returned `Input(index)` coordinates; it never
selects an ambiguous current input. The input list is copied.

Inputs and outputs use `relation_schema.Schema`, not ordinary object value
contracts. `relation_schema.from_object` adapts an already checked non-null
object contract. Qualified schemas are also accepted and preflighted even when
unused. The unary operation checks use `relation_typing` with this same
schema representation. No dotted names are added to ordinary object contracts.
Only join operands must be flat: qualified output needs explicit projection
before another join. This applies to both the left and right input.

The package owns shared naming, connection, budget and diagnostic rules; its
current checked steps have a main input and one output and require a final
current. `CheckedOperation` distinguishes `Unary`, `Join`, `Append`, and `Nest`; all
binary variants retain an additional right-input target and their checked operation. General multi-output
ports, generators and non-Relation Carriers are not implemented.

SourceView acquisition, Catalog/authority checks, Carrier resolution, search
template classification and stage imports belong to callers. Search templates
must not appear in this materialized-input list. Complete schemas are a scope
restriction of this API, not a general restriction on ActQL derive.

Stage-level `from` resolves only against inputs. Without it, exactly one input
becomes current; zero or multiple inputs leave current unset. An explicit step
`from` resolves against inputs and preceding `as` bindings and can establish
current. Otherwise a consuming step requires current. Each successful step
becomes current, whether or not it has `as`; generated names are not exposed.
Inputs and `as` share a unique namespace. Forward and self references fail.
Join's `with` resolves the right input in that namespace; optional `join.left`
replaces the selected main input and can establish it when no current exists.
Step `from` and `join.left` may coexist: `from` selects first and `left` wins,
but both explicit selectors are validated. The retained main input edge names
the final left operand, not the overridden binding. Resolving both sides to the same
existing input is legal, unlike referencing the current step's own `as`.
Empty steps return the selected input unchanged; this Relation pipeline API
requires a selected final current even when empty. It does not admit the
zero-input/generator or no-current publication-only stage cases.

Step objects are closed to one supported operation key plus `from`, `as` and
`meta`. Explicit null selectors/aliases are invalid. Metadata is a nonempty
object with arbitrary source JSON contents, except top-level `actql_` keys.
It is retained without influencing names or types. Nested reserved-looking
keys are ordinary data. Metadata traversal is iterative and budgeted.

## Retained result and diagnostics

The opaque result retains source, the optional authored stage selector,
input schemas, Parameter declarations,
checked steps, the final current target and output schema. A step retains its
source, explicit binding name, metadata cursor, checked operation and exact
`Input(index)` or `Step(index)` edge and its output schema. These indices are local storage coordinates,
not generated names, stable semantic identities or an AoA graph. `lookup`
resolves authored dataflow names without rescanning steps.

`schema_at` retrieves an input or step schema by bounds-checked target without
copying the input list. [Result definition checking](relation-results.md) uses
this boundary after pipeline checking and retains the originating pipeline.

Each checked operation preserves typed expressions, projection order and
pending profile/pattern/Host obligations. Callers access them through
`step_at`, the operation variant and the relation/join/expression APIs; obligations are not copied
into a second aggregate list. A later projection does not delete earlier
bindings or their failures and pending validations. Returned input lists and
the operation's array accessors are detached; contracts and cursors are opaque.

Pipeline shape and selector failures retain the relevant source path/span.
Operation failures preserve their original path/span and decoded-text range,
including nested mixed expressions. Input-contract failures use the supplied
steps cursor as context because independently supplied contracts have no source
cursor here. Errors return no partial pipeline.

## Shared limits

`max_steps` bounds the authored array. Work/text/nodes/tokens are cumulative
over the entire call, never reset at a step boundary. `max_depth` independently
bounds nested contract, metadata and expression traversals, not linear step count.
Contract preflight counts edges from the root contract at depth zero, matching
the operation checker. Metadata counts enclosing containers, matching owned
JSON admission: a root object consumes one level and scalar leaves add none.
Thus an empty root object needs depth zero for contract preflight but depth one
for metadata traversal (an empty metadata object is separately invalid).
The owned input source tree is admitted before this API and has separate limits.

Work charges input registration, whole-contract preflight, step envelopes,
names, metadata and each operation's reported work. Text charges processed
names, contract text, metadata text and operation text. Nodes charge step
envelopes, metadata values and operation syntax/type nodes. Tokens charge
embedded expression lexing. Join body traversal consumes nodes but no text-parser
tokens; its work/text/nodes are deducted from the same remaining counters.
Input and Parameter contracts are preflighted even
if unused or the steps array is empty. Operations currently preflight their
own input and Parameter contracts again; repeated work is charged, not hidden.
`usage` reports these logical counters, not heap bytes or CPU instructions.
Collection views, maps and retained source/contracts have separate memory costs.

No evaluation, optimizer, operation elimination, Result/Effect checking,
lowering, policy/key/order proofs, envelope completion or CID calculation is
implemented. Success is conditional type consistency, not a checked Plan or
permission to execute. Empty-operation AoA adapter compatibility remains the
lowering work described in the relation checker guide.

The [fixed corpus](../../portability/corpus/actql-relation-pipeline-v0.1.json)
contains independently specified edges and output contracts. Tests also cover
branch reuse, cumulative limits, retained metadata, exact diagnostics and long
chains. They are not runtime conformance evidence.
