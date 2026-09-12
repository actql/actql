# Local Relation join type checking

`relation_join.check` checks a normalized, owned join body against two complete
`relation_schema.Schema` operands and optional Parameter declarations. It does
not resolve dataflow names or accept SourceView acquisition templates. The
[pipeline checker](pipeline-typing.md) resolves the main input, optional `left`
override and required `with` target before calling it. Source and exact operand
schemas remain in the opaque `CheckedJoin`; its array accessors return copies.

The authority is the Language's [join](../spec/language.md#join),
[field paths](../spec/language.md#field-paths),
[value contracts](../spec/language.md#value-contracts) and
[resolved limits](../spec/language.md#resolved-limits). This is type checking,
not execution, lowering or complete Plan admission.

## Admission and output

The closed body accepts `with`, `left`, `kind`, `on`, `cardinality`, `null_key`,
`select` and `max_output_rows`. Kinds are `inner`, `left`, `full`, `semi`, `anti`.
`on` accepts a flat input field name, `{left: name, right: name}`, or a nonempty
array of these equalities. Nested arrays and arbitrary predicate trees fail.
Every pair is checked using `KeyComparable`: nullable business keys, Ref keys
and decimal keys with different P/S are not rejected merely for those features.
There is no coercion. Repeated pairs and repeated components are retained in
authored order; a repeated component with a different peer is another equality.

Both operands must be flat. A raw qualified output cannot be rejoined on either
side without an explicit flat projection. With no `select`, all left fields
become `Qualified(Left, name)` and all exposed right fields become
`Qualified(Right, name)`. Semi/anti expose only qualified left fields. Left join
adds nullability only to right fields; full adds it to both sides. Existing
child structure and nullability are otherwise unchanged. Null extension is not
evidence for uniqueness, and an unqualified name never chooses a side implicitly.

An explicit `select` is a nonempty map from authored flat output names to exact
qualified input references. It produces flat fields in canonical UTF-16
output-name order. Multiple aliases of one source retain all mappings and the
same type/nullability. Empty projection is not a no-op and is rejected. An
unprojected join's fields can instead pass through derive/filter/select/rename/
drop and into Results, retaining qualification until explicitly renamed.

## Unfinished obligations

| Retained obligation | Required later work |
| --- | --- |
| `ResolveCardinality` | Inspect candidate-key evidence; omission may remain unproven. Never infer many-to-many or turn an assertion into an established proof. |
| `ValidateCardinality` | Enforce the authored one-to-one/many-to-one/one-to-many uniqueness assertion before accepting output. |
| `ResolveOutputLimit` | Derive the finite resolved output limit from actual input witnesses, Host policy and any author guard, with checked arithmetic and fail-on-breach. |
| `PreserveRowOrder` | Retain and enforce the join-kind-specific row-order contract and its input evidence. |
| `StableIdentity(Left/Right)` | Establish both required stable identities for full join during complete Check, not after execution starts. |
| `RejectNullKeys` | For `null_key: fail`, reject null components on either input before publication. |
| `BindGuard(name)` | Require the bound value to be a non-null positive safe integer; never silently omit or clamp an invalid guard. |

The default null policy is `NoMatch`; explicit `no_match` has the same semantic
policy while the original source remains available. An output guard literal
must already be a positive safe integer. A parameter guard requires a declared
number type but is not substituted or resolved here, including when it has a
default. A nullable number declaration remains usable for its non-null values;
`BindGuard` must reject null. Declaration constraints and defaults are not
evidence that a particular invocation has supplied a valid guard.

Pending obligations survive branch changes, projection and hidden keys because
the pipeline retains every checked step. A successful `CheckedJoin` is not a
runnable Plan, proven cardinality, resolved capacity, stable row identity or
permission to publish. Candidate-key propagation under multiple aliases is
not implemented; retaining a mapping does not establish a key.

## Bounds, diagnostics and verification

### Program requirement binding

`link_program_join_requirements` consumes the owning pipeline's cached
cardinality selection and the exact producer visit's capacity application.
An unproven cardinality remains unproven; a finite output limit is not a
uniqueness proof. An authored cardinality assertion and null-key rejection
remain separate obligations.

`JoinOutputLimit` retains the selected limit, policy and capacity dependency.
`JoinRowOrder` retains the checked join, both operand targets and their optional
logical-order witnesses, together with the already-derived output witness.
It requires execution to preserve the join-kind-specific occurrence order
before accepting output. It does not manufacture total order from physical
enumeration, and does not require a total witness merely to retain occurrence
order. Later order-dependent consumers still require their own valid evidence.

Both execution bindings are future obligations, not backend support or execution
receipts. Linking charges the copied inventory and scan against cumulative work,
bounds the number of links, and leaves the original inventory unchanged on
failure. Closing the inventory still rejects every unrelated unresolved entry.

Source traversal is iterative and consumes work, text and nodes for the entire
body, including fields later rejected. Full operand and Parameter contracts
are preflighted before output projection. Contract depth counts edges from the
row root at zero; source depth counts containers with the body at one. Names,
key pairs, output construction and projection consume additional work/text.
Each successful call reports usage so pipeline checking deducts it from shared
counters. Limits equal to consumption are accepted. No counter is a physical
heap or elapsed-time limit. Maps, schema fields and the already owned source
have their own memory costs; no Relation rows are materialized by this checker.

Errors retain the responsible cursor's path/span, and no partial join is returned.
Downstream expression references additionally retain decoded-text ranges,
including qualified and quoted field aliases. Key/type/projection failures are
not deferred to runtime just because later execution may reject the same input.

The [fixed corpus](../../portability/corpus/actql-relation-join-v0.1.json) specifies
output reference names, nullability, key counts and rejection categories without
using the product to generate expectations. `check:relation-join` verifies
generated-test freshness and generator failures. Additional tests exercise
parameter guards, exact budgets, deep unused contracts, long repeated-key lists,
ownership and join-to-unary-to-Result composition on all supported targets.

AoA's Relation AST already distinguishes left/right operands; its common
pipeline uses ordered input references, so future lowering maps main/right to
the registered input order. Neither representation forces string-only schema
typing here. The existing Cloud keyed-merge adapter namespaces only conflicts
and merges some equal-name keys, which is not ActQL raw join provenance. It
must not determine this layer's output schema. Backend integration and the
existing empty-operation AoA compatibility gaps remain separate work.
