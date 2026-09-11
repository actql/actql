# Checked author-guard occurrences

`pipeline_typing.collect_author_guards` enumerates authored capacity guards
from an immutable checked pipeline. Every occurrence retains that exact
pipeline, local step index, operation-specific scope, original guard cursor,
and the checked literal-or-Parameter value. A caller cannot construct an
occurrence from an independent number, source path or proof flag.

## Coverage and distinctions

The collector visits every local step, including unused branches, and every
group/window-group aggregate and analytic call. It retains join, cross-join and interval-join
output guards; nest item guards; array/string aggregate item/byte guards;
sequence per-key and output guards; and components, traversal and shortest-path
output guards. Analytic aggregate guards use the same array-item/UTF-8-byte
laws, with the frame result as their operation-defined scope. Aggregate scopes
include the checked aggregate index (the full call index for analytic), so equal
values in different aggregates cannot collapse into one occurrence.

An absent guard contributes no occurrence. A Parameter guard contributes an
unresolved occurrence, even if its declaration has a default. Enumeration does
not bind values, apply defaults or remove guards that may be non-binding under
a tighter Host/Contract/Program candidate. Repeated guards remain repeated,
in local step order; aggregate guards follow checked aggregate/call order.

Selection counts (`take`, `top_k`), hop limits, window size/step and diagnostic
`graph_bounds` thresholds do not become author guards. In particular, Graph
bound reports admit zero and describe violations; that is not the positive
fail-closed author-guard contract. Operation-specific scope remains distinct
even when numeric values or units coincide.

## Budgets and ownership

The collection charges one work unit per step, one per visited aggregate or analytic call and
one per emitted guard. Text budget counts each emitted guard's fixed field name
and any referenced Parameter name. The source lookup opens only the operation's
already-checked closed option object, never an arbitrary payload or the whole
Program. Insufficient budgets fail atomically without exposing a partial list.
Analytic calls use count/index accessors so traversal does not copy the complete
call array before charging it. Ranking/navigation calls and frame extents do
not generate guards; missing aggregate guards remain absent.
Original source paths and spans remain available from the retained cursor;
getters do not expose the mutable collection array.

Upstream producer pipelines have their own local step coordinates and guards.
This API enumerates one owner only; the final combined checker must visit
producer occurrences under shared budgets, as contextual order closure already
does. An imported guard must not be reassigned to a coincidentally numbered
local step.

## Numeric binding and declaration ownership

`bind_author_guards` accepts an occurrence collection and optional opaque
`parameter_binding.BoundValues`. BoundValues now retains the exact Declarations
owner used by `bind`; a supplied collection must have the same owner as the
checked pipeline, including when its guards happen to be literals. Equal names,
equal types or byte-identical separately admitted declarations do not substitute
for that internal owner. This prevents mixing defaults or constraints from
another check; it does not change the language's semantic identity rules.

Parameter guards must resolve to positive safe-integer numbers. Missing bindings,
null, zero, negative, fractional and out-of-range values fail at the original
guard cursor. Defaults are applied only by Parameter binding, never by this
resolver. Literal-only guards may resolve without a binding collection. A
successful result retains the original occurrences and bindings and exposes
quantities by occurrence index, preserving repeats and supplied/default origin.

The binding budget counts every supplied Parameter entry and every guard, plus
Parameter-name bytes for the map and each guard lookup. It builds one name map
using indexed immutable access rather than copying arrays per lookup. It does
not scan unrelated Parameter value trees; those remain owned by their completed
admission. A later invalid guard returns no partial collection. Enumeration and
binding budgets are explicit separate costs for a future combined caller to
accumulate, not implicit execution-policy limits.

## Remaining source binding

The pinned registry now fixes field/unit/law mappings for every collected scope.
`author_guard_field`, `author_guard_unit` and `author_guard_law` derive these
from the occurrence. The collector also checks that its actual source field
matches the table. This fixes source-law selection without permitting caller
overrides; it does not bind Program identity or select an enforcement boundary.

Neither an occurrence nor its bound quantity is a numeric bound witness,
verified source artifact, resolved limit or permission to execute. Subsequent
source/application validation must verify governing law/unit/enforcement,
retain Program Definition identity from its owner, and include every applicable
candidate. Missing Parameter values are not absent guards or zero. Wire identity
and source/application verification remain separate, as recorded in the
[capacity source audit](capacity-source-audit.md).

Regression tests cover every emitted scope, exact source slots, repeated/unused
steps, unresolved Parameters, omission, equal-valued different quantities,
Graph diagnostic exclusion, owner identity and exact/insufficient budgets.
Analytic regression cases mix ranking, guarded aggregates and navigation,
verify original function indices and guard paths, resolve and reject Parameter
values at that path, and keep absent guards distinct from frame-size bounds.
