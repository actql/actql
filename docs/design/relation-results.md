# Relation Result definition checking

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
