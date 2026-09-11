# Checked author-guard occurrences

`pipeline_typing.collect_author_guards` enumerates authored capacity guards
from an immutable checked pipeline. Every occurrence retains that exact
pipeline, local step index, operation-specific scope, original guard cursor,
and the checked literal-or-Parameter value. A caller cannot construct an
occurrence from an independent number, source path or proof flag.

## Coverage and distinctions

The collector visits every local step, including unused branches, and every
group/window-group aggregate. It retains join, cross-join and interval-join
output guards; nest item guards; array/string aggregate item/byte guards;
sequence per-key and output guards; and components, traversal and shortest-path
output guards. Aggregate scopes include the checked aggregate index, so equal
values in different aggregates cannot collapse into one occurrence.

An absent guard contributes no occurrence. A Parameter guard contributes an
unresolved occurrence, even if its declaration has a default. Enumeration does
not bind values, apply defaults or remove guards that may be non-binding under
a tighter Host/Contract/Program candidate. Repeated guards remain repeated,
in local step order; aggregate guards follow checked aggregate order.

Selection counts (`take`, `top_k`), hop limits, window size/step and diagnostic
`graph_bounds` thresholds do not become author guards. In particular, Graph
bound reports admit zero and describe violations; that is not the positive
fail-closed author-guard contract. Operation-specific scope remains distinct
even when numeric values or units coincide.

## Budgets and ownership

The collection charges one work unit per step, one per visited aggregate and
one per emitted guard. Text budget counts each emitted guard's fixed field name
and any referenced Parameter name. The source lookup opens only the operation's
already-checked closed option object, never an arbitrary payload or the whole
Program. Insufficient budgets fail atomically without exposing a partial list.
Original source paths and spans remain available from the retained cursor;
getters do not expose the mutable collection array.

Upstream producer pipelines have their own local step coordinates and guards.
This API enumerates one owner only; the final combined checker must visit
producer occurrences under shared budgets, as contextual order closure already
does. An imported guard must not be reassigned to a coincidentally numbered
local step.

## Remaining source binding

This result is an authored occurrence, not a numeric bound witness, verified
source artifact, resolved limit or permission to execute. Subsequent binding
must verify the actual Parameter value and governing law/unit/enforcement,
retain Program Definition identity from its owner, and include every applicable
candidate. Missing Parameter values are not absent guards or zero. Wire identity
and source/application verification remain separate, as recorded in the
[capacity source audit](capacity-source-audit.md).

Regression tests cover every emitted scope, exact source slots, repeated/unused
steps, unresolved Parameters, omission, equal-valued different quantities,
Graph diagnostic exclusion, owner identity and exact/insufficient budgets.
