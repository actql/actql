# Ordering, limiting and duplicate elimination

`relation_typing.check` admits `sort`, `take`, `distinct` and `dedupe_rows`
against a complete `relation_schema.Schema`. They compose as ordinary unary
operations in `pipeline_typing`, including after raw joins and before Results.
The authority is Language [sort](../spec/language.md#sort),
[take](../spec/language.md#take), [distinct and dedupe](../spec/language.md#distinct-and-dedupe),
and the [ordering classifications](../spec/language.md#ordering).
The [semantic decision criteria](semantic-decisions.md) explain the boundary
decisions; reference limitations do not override those adopted requirements.

## Retained operations

`row_operation` returns detached `RowOperation` details. Sort terms and equality
keys retain typed field identities and original cursors; their arrays are copied.
Count/offset are `Literal(Int64)` or `Parameter(String)`. The original operation
body is retained independently of completed fixed defaults. No invocation values,
row data, physical ordering or candidate-key evidence enter this API.

| Operation | Shape and output |
| --- | --- |
| Sort | Array of OrderKey; retains term order and repetitions. Empty array is an identity. The schema is unchanged. |
| Take | Positive safe-integer count or `{count, offset?}`; both positions admit an exact `{$param: name}`. Offset is nonnegative and defaults to literal zero. Schema is unchanged. |
| Whole-row distinct | Exactly `true`; retains the complete schema, including structural and reference fields. |
| Keyed distinct | Nonempty duplicate-free field list; projects only these fields, retaining authored projection order. |
| Dedupe rows | Closed `{by, order_by}`; by may be empty or repeated, order_by is nonempty. Preserves the complete schema. Keep-first and fail-on-top-tie are not authored options. |

Keyed distinct and dedupe partition keys require `KeyComparable` domains:
scalar or reference types, with nullable keys allowed. Object/array/json/vector
keys fail. The restriction does not apply to whole-row distinct. Ordering keys
require `AuthorOrderable` and therefore exclude references as well as structural
types. This layer validates domains, not runtime equality or reference evidence.

Qualified references resolve exactly; no side fallback, nested-property parsing,
implicit flattening or alteration of nullability occurs. Keyed distinct records
the projected references in `projection`; unprojected operations leave that
accessor empty rather than manufacturing an explicit projection. Output schema
storage order is canonical and distinct from authored term/projection order.

The shared `order_key` reader checks shorthand and closed explicit forms. It
does not infer fields or order proofs. Shorthand completes nulls to last;
explicit form requires first/last, independent of direction. A field named
`field`, `dir` or `nulls` remains usable as the single shorthand map key. The
reader reports shape work for the caller to charge; callers preflight the whole
owned source first and resolve fields in their own schema index.

## Deferred obligations, not proof claims

`pending_validations` returns a detached array retaining the relevant cursor:

| Kind | Obligation |
| --- | --- |
| SortOrderCompletion | For nonempty sort, resolve the required ordering/tie-break evidence later. Authored keys alone are not a proven total order. |
| StableInputOrder | For take, establish admitted stable input order using the language's permitted evidence and journaled completions. |
| FailOnTopTie | For dedupe, enforce the top-candidate tie failure before accepting output. No implicit identity or physical-order tie-break. |
| BoundInteger | Require the named bound value to be non-null, integral, at least the retained minimum (1 for count, 0 for offset), and at most 9007199254740991. |

Empty sort adds no order obligation or evidence of its own. Its retained empty
operation conveys identity behavior; it neither destroys prior evidence nor
discharges a later take obligation. Global dedupe retains FailOnTopTie even
with no by keys. Repeated keys do not strengthen proofs, and no operation or
preimage is deduplicated. Pending obligations remain on every retained pipeline
step even if a later step switches branches or removes a relevant field.

Parameter references must resolve to number declarations. Nullable declarations
are allowed because their non-null bound values may satisfy the consumer.
Defaults and min/max/integer declaration constraints are not substituted or
treated as proof that the current invocation supplies a valid value. Literal
count/offset are checked immediately, including rejecting negative zero.
The two values are checked independently without an artificial safe-integer
limit on their sum. Missing, null, string and coerced values are not defaults.

No runtime deduplication, ordering, row limiting, lowering, identity/key derivation
or order-witness propagation is implemented. Result publication remains subject
to its own TotalDeterministicOrder obligation. Full-row value equality and Ref
identity validation remain the responsibilities of execution/admission boundaries.
Existing AoA empty-order/global-dedupe and offset adapter gaps remain unresolved;
successful type checking is not a runnable Plan or a claim of backend support.

## Resources and verification

The row-operation body is preflighted iteratively, including values in invalid
or unknown members. Source containers count from depth one; contract roots count
from zero. Entire input and Parameter contracts, even unused fields, are checked
against the depth/work/text allowance. Names, keys, parameter indexing, output
construction and OrderKey parsing consume additional logical work/text. These
operations consume source nodes but no expression tokens. Pipeline counters are
shared across all steps, not reset for each operation; exact limits are admitted.

This is logical work accounting, not a physical heap or instruction limit.
No row arrays are materialized. Iterative traversal supports deep unused contracts,
and field/parameter maps are reused across lists instead of rebuilt per key.
Immutable schemas are shared; exposed detail arrays cannot mutate checked state.
Failures retain path/span and expose no partial operation or fabricated text range.

The [fixed Relation corpus](../../portability/corpus/actql-relation-typing-v0.1.json)
includes explicit input/output contracts and rejection expectations; its generator
does not compute expected schemas from product output. Additional tests cover
symbolic parameters, independent count/offset boundaries, all key domains, deep
and wide inputs, detached accessors, qualified join composition, Results and exact
budget shortages. Run `check:relation-typing`, `check:pipeline-typing`,
`check:relation-results` and the three-target MoonBit checks. These tests do not
execute row-level semantics or discharge pending proof/runtime obligations.
