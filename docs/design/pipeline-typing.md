# Pipeline type checking

`pipeline_typing` connects an ordered array of steps using the
[pipeline naming rules](../spec/language.md#pipeline-references). Dispatch covers
the 48 operations listed in [Pure operation checking](pure-operation-checking.md)
and the existing Relation operations: derive/filter/projection, ordering and
deduplication, assertions, reshaping, join, append, nest, aggregates, pivot,
analytic and top-k. Carrier-specific checkers own their source/type rules;
the pipeline owns naming, connections, shared budgets and evidence propagation.
Unsupported operation names fail; no step is skipped or treated as an opaque
successful operation. Dispatch coverage alone does not complete the shared
evidence or executable-profile work in that implementation contract.

## Inputs and scope

Nest uses the current/step-selected parent and resolves its child `with` through
the same input/prior-`as` namespace. It has no `left` override. The retained
`Nest` variant includes the child target, payload projection sequence, authored
ordering and guard, and unresolved order/capacity/validation obligations. It
accepts qualified schemas on either side; child payload names must be explicitly
flat. Assertions and unpivot remain unary operations. An `assert_rows.unique_by`
operation can produce a conditional key witness retaining its validation
obligation; successful checking does not prove observed uniqueness or grant
permission to publish. Nest retains the parent row-count summary, not a
general output-key proof.

Append uses the current/step-selected Relation as its left input and resolves
`with` through the same input/prior-`as` namespace as join. It does not inherit
join's explicit `left` selector. `CheckedOperation::Append` retains the right
target and checked recursive schema alignment, including when both operands
are the same target. Registration of `as` occurs after checking, so forward
and self references remain invalid. Append's work, text and node usage is
debited from the shared pipeline budget; it consumes no expression tokens.

The caller supplies an owned, source-normalized steps cursor, named materialized
inputs, optional Parameter declarations, an optional cursor for stage-level
`from`, and limits. `check` accepts complete [Relation schemas](relation-schema.md);
`check_carriers` accepts structural Carriers; `check_with_evidence` additionally
accepts admitted key/ranking inputs. Calendar operations require the supplied
admitted Calendar profile. Expected Graph Delta contracts can be supplied through
the `delta_contracts` option and are validated even for unused bindings.
Input names must already be NFC/LF and well-formed Unicode, with nonempty
contents. They are dataflow names, not field names or Parameter identifiers.
Input order only defines the returned `Input(index)` coordinates; it never
selects an ambiguous current input. The input list is copied.

`check` adapts complete Relation schemas to the common `check_carriers` entry.
Inputs and outputs use [structural Carrier contracts](carrier-contracts.md).
Open or partially typed Relations and opaque Graph/Events/Vectors are retained
without inventing field or type evidence. Each operation applies its own
required knowledge: for example Graph normalization accepts an opaque Graph,
while ordinary Relation operations may require a complete schema. Wrong Carrier
and missing schema/type evidence are distinct failures. There is no global
conversion of unknown fields into JSON or of an open field set into an empty one.
`relation_schema.from_object` adapts an already checked non-null
object contract. Qualified schemas are also accepted and preflighted even when
unused. The unary operation checks use `relation_typing` with this same
schema representation. No dotted names are added to ordinary object contracts.
Only join operands must be flat: qualified output needs explicit projection
before another join. This applies to both the left and right input.

The package owns shared naming, connection, budget and diagnostic rules; its
current checked steps have one output. Main input and final current are optional
in the representation. `CheckedOperation` has typed variants for Relation,
Graph, temporal, Calendar, vector and lexical operations, including binary
operands, graph selectors and independent ranking queries.
`input_occurrences` returns detached, ordered, role-tagged edges, preserving two
occurrences even when operands resolve to the same target. General multi-output
ports remain outside this pure-operation scope. `values`, `time_series` and
`calendar_series` are input-free generators. Explicit Graph construction and
`mean_graphs` have named operands but no implicit current operand. Generator
steps require `as`, reject step `from` and establish current. Concise Graph
construction instead consumes the selected Relation.

SourceView acquisition, Catalog/authority checks, Carrier resolution, search
template classification and stage imports belong to callers. Search templates
must not appear in this materialized-input list. Complete-schema requirements
belong to individual implemented operation boundaries, not a general restriction
on ActQL derive.

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
Empty steps preserve the selected input unchanged or retain no current when
none was selected. Zero-input empty pipelines and no-current publication-only
pipelines are admitted. A consuming operation still fails with `MissingCurrent`
unless a selector establishes its operand; no input is chosen by list order.

Step objects are closed to one supported operation key plus `from`, `as` and
`meta`. Explicit null selectors/aliases are invalid. Metadata is a nonempty
object with arbitrary source JSON contents, except top-level `actql_` keys.
It is retained without influencing names or types. Nested reserved-looking
keys are ordinary data. Metadata traversal is iterative and budgeted.

## Retained result and diagnostics

The opaque result retains source, the optional authored stage selector,
input Carriers, Parameter declarations,
checked steps, the optional final current target and output Carrier. A step retains its
source, explicit binding name, metadata cursor, checked operation and exact
`Input(index)` or `Step(index)` edges and its output Carrier. These indices are local storage coordinates,
not generated names, stable semantic identities or an AoA graph. `lookup`
resolves authored dataflow names without rescanning steps.

`carrier_at` retrieves an input or step by bounds-checked target without copying
the input list. `schema_at`, `step_schema` and `output_schema` return a schema
only for a complete Relation; absence is not an empty schema.
[Result definition checking](relation-results.md) explicitly checks the Carrier
kind at this boundary and retains the originating pipeline.

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

## Retained expression slots

`collect_expression_slots` enumerates the typed Expression roots retained by all
local checked steps, including unused `as` branches. It retains the exact
CheckedPipeline owner and returns indexed immutable handles with their step
coordinates. Relation bindings include aggregate/analytic arguments and filters;
Sequence includes every pattern predicate. Graph coverage includes match
predicates, subgraph node/edge predicates, traverse start and per-hop edge/node
predicates, and shortest-path endpoint predicates. The operation match is
exhaustive: forms without general Expression roots are listed explicitly.

Every slot also retains an explicit `ExpressionConsumer`: named derive output
(and an ordinal for ordered derive), row filter/assertion, aggregate or analytic
argument/filter, sequence pattern, or the particular Graph selector/hop/endpoint.
These are semantic uses, not executable registry names or inferred lowering
signatures. In particular an ordered derive slot is not silently treated as an
independent snapshot-based derive operation.

An aggregate expression argument additionally retains its own `ExpressionFilter`
when present: the earlier slot coordinate and exact typed filter from the same
CheckedOperation. Evaluation of the argument requires that filter to be true;
the filter itself has no self-demand. Analytic aggregate filters obey the same
dependency within their window-row scope. Navigation calls have no invented
filter, and field shorthand/count-star arguments are not expanded into new
Expression roots. Equal filter texts on different aggregates remain separate
occurrences. Relation binding coverage is checked rather than silently leaving
a newly retained binding unclassified.

Slot coordinates identify this local collection only. They are not the sorted
`roots` index of an expression Fragment, a semantic step ID, or persistent
identity. The final root collector must apply the normative consumer-specific
binding and ordering before rebasing both local demand and the filter edge.
Sketch `87dc7144`'s fragment builder confirms that aggregate filters are separate
roots and are prepended as true tests only to their own arguments. Its canonical
root sorting must not be confused with this filter-before-argument intake order.

This pass charges one work unit per step, aggregate/analytic descriptor and
inspected expression candidate, including absent optional Graph predicates.
`max_slots` bounds retained roots, not the
number of Parameter occurrences inside them. Equality is accepted and failure
returns no partial collection. Expression trees are not copied, re-normalized,
evaluated or substituted. Their original source ownership and location sidecars
remain available through the typed Expression handles. Producer pipelines retain
their own slots and require their own traversal.

These slots feed the [Parameter reference index](parameter-references.md) after
bounded occurrence discovery. The integration test retains root-source pointers
through derive/filter checking, including an unused branch. This is not a
complete Program reference enumeration: the complementary non-expression pass
below handles local value operands, while input requests, Results, effects and
opaque binding references still require their grammar-specific paths. No checked schema expansion or
evidence-dependent operation completion becomes the authored semantic body.

## Non-expression Parameter slots

`collect_parameter_slots` separately enumerates currently admitted direct
Parameter operands from every local checked step. Each immutable record retains
the step, name and original singleton `{$param: name}` source cursor; the result
retains the exact pipeline. The operation dispatch is exhaustive, with explicit
non-operand cases, and does not recursively search JSON for `$param`.

It covers take/count/offset and top-k counts, lag offsets, row-watermark values,
window size/step/offset (including authored fixed-window step), session gaps,
sequence periods and guards, time-series/calendar endpoints, applicable Graph
counts and path guards, join/nest guards, as-of tolerance, vector query Parameters,
aggregate fraction/item/byte options, analytic navigation/frame bounds, pivot
fill and typed values cells. It visits only named grammar fields or checked cell
records. Plain literal cells, wrapped literal payloads, business objects,
annotations and general Expression children are not recursively inspected.
Literal-only options in a checked operation do not become Parameter slots.

Work counts local steps, inspected immediate fields and repeated container items
(rows/cells, aggregate calls and frame boundaries); `max_slots` bounds retained
Parameter occurrences. Equality is accepted and exhaustion returns no partial
collection. It shares the slot-limit issue vocabulary with expression discovery.
It neither resolves effective values nor discharges the operands' binding and
execution obligations. Repeated names and semantically unused but authored
options are preserved as separate source occurrences.

These direct nodes have the same closed syntax as a structured Parameter
Expression, so bounded common admission can connect them to the existing
[reference index](parameter-references.md) without parsing expression text or
interpreting surrounding data. The integration test checks their original
locations and declaration association. Collection and any subsequent admission,
occurrence/index passes retain independent limits until the combined Program
boundary accounts for them together. Producer pipelines, input requests,
Results, effects and opaque binding references still require enclosing traversal;
the local collections alone do not certify complete Program usage.

## Conditional evidence

The retained pipeline keeps distinct evidence axes, not a universal checked flag:

| Accessor | Meaning and retained dependencies |
| --- | --- |
| `candidate_keys` | Conditional input or producer key witnesses, with all surviving component aliases; `candidate_key` only returns a sole witness |
| `join_evidence` | Whole-key coverage on each actual join operand, combined with but not replacing authored cardinality assertions |
| `window_evidence` / `window_aliases` | Surviving start/end roles from a checked window producer; not arbitrary matching column names |
| `ranking_evidence` | Producer-bound ranking identity/score annotations and admitted score declarations; not a claim that runtime ranks passed validation |
| `expected_delta_contract` | The expected typed Delta contract, not proof of a valid Delta row |
| `row_count` / `graph_count` | Conditional successful-output counts or upper bounds; graph node and edge extents stay separate |

Input key and ranking evidence can be combined only through the validated
same-Relation boundary, preserving both sets of obligations. Transfer follows
the operation-specific rules in [Relation evidence](relation-evidence.md) and
[conditional counts](row-count-evidence.md); unimplemented transfers drop the
fact, not the operation. General logical-order proofs, additional cross-family
key transfers and dependency-closed Plan witnesses are still required work.
Successful checks do not imply these missing proofs are available.

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
Evidence selection, transfer and count derivation also debit the shared counters;
their scans do not receive a fresh budget. `usage` reports these logical counters,
not heap bytes or CPU instructions.
Collection views, maps and retained source/contracts have separate memory costs.

No evaluation, optimizer, operation elimination, Effect checking,
lowering, authority proofs, general logical-order proofs, envelope completion or
Program/Plan CID calculation is implemented here. Result definitions use the
separate `relation_results` checker and retain this pipeline. Conditional key
and count derivation is implemented as described above; it is not runtime proof
discharge. Success is conditional type consistency, not a checked Plan or
permission to execute. Empty-operation AoA adapter compatibility remains the
lowering work described in the relation checker guide.

The [fixed corpus](../../portability/corpus/actql-relation-pipeline-v0.1.json)
contains independently specified edges and output contracts. Tests also cover
branch reuse, cumulative limits, retained metadata, exact diagnostics and long
chains. They are not runtime conformance evidence.
