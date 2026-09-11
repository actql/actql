# Relation Result definition checking

The shared pipeline may have no current target; Results always resolve their
explicit named source. Non-Relation Carriers fail with `WrongCarrier` and require
an explicit bridge before publication. This checker currently requires complete
Relation type evidence (`IncompleteSchema` otherwise); partial-column publication
and its permitted deferred ordering checks remain in the pure-operation scope.

`relation_results.check` consumes a retained
[`pipeline_typing.CheckedPipeline`](pipeline-typing.md), a normalized owned
cursor for a nonempty stage-local `results` map and limits. It checks names,
projection and authored ordering types under
[Named Results](../spec/language.md#results-and-delivery) and
[Lexical and ordering rules](../spec/language.md#ordering).
It does **not** establish that a Result can be published or executed.

## Source and type boundary

A definition is closed to required `from` and `fields`, optional `order_by`
and `meta`. `from` names an input or explicit step `as` in the completed
pipeline; it never defaults to current, resolves another Result, or exposes a
generated step coordinate as an authored name. Result names occupy a separate
namespace and may equal dataflow names. Definitions retain source-map order
for indexing; this is not a semantic identity or publication-order rule.
Names are nonempty, source-normalized strings, not Parameter identifiers.

`fields` is a nonempty list of distinct existing field names, not select alias
maps. Its order is retained independently of the canonical ordering of the
output Relation schema. The exact selected field contracts and nullability are
preserved. Whole-Program root exports are outside this API.

The public output is `relation_schema.Schema`. Preflight and projection work on
its typed fields directly, including raw join output. A `fields` entry such as
`left.id` preserves that qualification in the output schema, independently of
the requested column order. Flat aliases must be established by an earlier
operation; Results do not introduce an alias-map syntax. `order_by` resolves
exact qualified names against the source before projection. No qualified names
are silently flattened or admitted as authored object field names.
This retention also governs published column names. A downstream consumer
requiring flat fields needs an explicit upstream projection or rename, not an
implicit conversion at the Result or consumption boundary.

Optional `order_by` is nonempty. Each key follows the closed grammar:
`{Field: asc|desc}` or `{field, dir, nulls}`. The explicit form requires
`nulls: first|last`; shorthand records `last` independently of direction.
The `order_key` leaf reader and its `AuthorOrderable` classification are shared
with sort and dedupe type checking. Direction and null-placement types are
re-exported from that package; Result diagnostics retain their existing paths.
The result retains whether null placement was explicit and keeps the original
key cursor. Repeated order terms are retained, not silently simplified.
Each authored key must be string, number, decimal, boolean, date or timestamp;
nullable forms are allowed with null placement. References are not author-
orderable, even though later canonical completion may use their identities.
Object, array, JSON and vector order keys are rejected statically.
Sorting precedes projection: a key may exist in the input schema without
appearing in `fields`.

Metadata is retained as a cursor. It must be a nonempty object and rejects
top-level `actql_` keys; nested keys remain ordinary data. Source traversal
accounts for all metadata, but metadata does not affect reference resolution,
output types or ordering choices.

## Retained evidence and unfinished obligations

The opaque checked collection retains its pipeline and definitions. Each opaque
definition exposes its name, source, input/step target, output contract,
ordered field list, optional authored order terms and metadata. Targets are
coordinates in that originating pipeline, not independently reusable identity
or authority evidence. Returned arrays are detached copies.
`pipeline.schema_at` obtains a target's schema with bounds checking without
copying the entire input list.

Every definition exposes `TotalDeterministicOrder` as a **pending obligation**,
including definitions with authored order keys or only scalar projected fields.
An order clause alone does not prove unique ties. This layer neither invents
candidate keys nor claims an inherited stable witness; it does not select the
all-projected-fields fallback ahead of higher-priority evidence. A later
publication checker must apply the normative priority and reject Results whose
required proof cannot be established. It must also discharge applicable
pipeline expression/profile/Host and policy obligations. No success here is
an executable Plan, Result identity, delivery authorization or proof of data
policy compliance. No key completion, evaluation, lowering, Effect checking,
serialization, delivery or CID computation is included.

## Named Results versus raw producers

`pipeline_typing.produced_input(p, target)` describes the entire input or step
output at that coordinate. It is not a named Result port. Passing a Result's
`target` to that function retains the pre-projection Carrier and its original
order evidence; it does not apply the Result's `fields` or publication order.

`producer_boundary_test.mbt` fixes two concrete counterexamples. A five-column
producer published as an `id`-only Result still has five columns when passed
through the raw producer API. An authored `score desc` Result ordering is also
absent from that raw producer. Separately, two Results with the same producer
target and projected fields can specify opposite publication orders. Matching
pipeline/target or schema alone cannot identify the Result port.

The eventual cross-stage import adapter must therefore bind the exact checked
Result collection and named definition, its source Program/stage, projected
schema (including qualification), publication-order resolution and remaining
producer obligations. Raw pipeline producer traversal remains useful for those
dependencies, but cannot replace the Result transformation boundary. A type-only
Carrier supplied to the consumer is likewise not evidence of that port origin.

This is not permission to drop order evidence when its original sort fields are
projected away: Language explicitly preserves a total stable ordering witness
through such projection. Candidate-key, window-role, ranking, delta and capacity
evidence must each follow their governing transfer rules, not be copied wholesale
from the raw source or discarded merely to simplify the adapter. Result ordering
and projection belong to the declared Result semantics, not extra authored steps
or a new Program identity.

The current source-bound stage Result pass does not implement this adapter.
The tests establish the distinction and prevent treating existing raw-producer
support as proof of cross-stage Result-import completion; they do not execute
publication, imports or lower the Result.

## Budgets and diagnostics

`max_results` bounds the map. `max_work`, `max_nodes` and `max_text_bytes` are
shared across all definitions. The complete Result source is traversed once,
including metadata: each value consumes a node and work; field keys and string
values consume UTF-8 text allowance. Shape, projection, indexing and order
processing consume additional work; output field-name construction consumes
additional text allowance. Counts measure logical work, not physical heap or
elapsed time. The already owned input source has separate admission limits.

Referenced source contracts are preflighted and indexed once per distinct
input/step target, including unprojected fields; the cache is shared across
Results. Pipeline checking is not rerun and its past usage is not charged here.
Contract traversal consumes work/text, not source nodes. Like the existing
checkers, source depth counts containers (root object is one), whereas contract
depth counts edges (root contract is zero). Limits equal to consumption are
accepted. No partial collection is returned after any failure.

Errors retain path and span from the source cursor, including nested fields,
selectors, order terms and metadata keys. These definitions contain no embedded
expression text, so no fabricated expression range is added.

The [fixed corpus](../../portability/corpus/actql-relation-results-v0.1.json)
specifies expected projections, order terms and failures. Generator tests check
freshness and malformed fixtures; MoonBit tests check the declared expectations
on JS, Wasm and native. These are definition/type tests, not publication or
runtime conformance evidence.
