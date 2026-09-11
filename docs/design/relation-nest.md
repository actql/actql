# Nest type checking

`relation_nest.check` checks the closed body against parent and child Relation
schemas and optional Parameter declarations. The caller resolves `with`;
`pipeline_typing` retains both input edges and ordinary from/as/current scope.
The normative owner is [nest](../spec/language.md#nest), including its newer
qualified-input and projection rules. Older adapter restrictions do not narrow
source acceptance.

The result owns detached key, projection, order and obligation arrays and shares
opaque admitted contracts. Parent qualification is preserved. Child payloads
have flat authored names and recursively constructible types: opaque JSON and
references cannot be hidden inside arrays or objects. Reference correlation
keys remain valid without being projected. Nullable payload fields are retained
inside a non-null array of non-null objects. Omitted and explicit order remain
distinct; explicit empty order fails. Repeated correlation pairs are retained
without multiplying rows or implying stronger evidence.

Success is not an executable Plan. `ResolveTotalOrder` retains the distinction
between explicit ordering (which needs a key or stable total witness for ties)
and omitted ordering (which may use the eligible full projection in authored
sequence). No candidate key or witness is invented. `ResolveItemLimit` and
`BindGuard` require actual bound values and capacity validation. A supplied guard
does not become an unconditional array bound in the output type.

`pipeline_typing.resolve_nest_order` supplies bounded contextual resolution of
child order, retaining the exact checked nest and resolved child target. Omitted
order first reuses the child's conditional sequence, then selects a canonical
whole candidate key, then uses the complete eligible projection in its authored
sequence. Explicit terms remain unchanged and require key completion or stable
sorting with an existing child sequence to settle ties; projected-field fallback
cannot rescue explicit ties. Alias coverage is qualification-aware and hidden
identity components remain available before projection. Parent order is never
used as child evidence. An unresolved order fails with its nest/projection source
location and no partial result. Indexed metadata and returned terms avoid array
copies before budget checks; work and field text use caller-supplied cumulative
limits within each resolution, with consumed usage returned for larger callers.
The checked operation's generic obligations remain intact: resolving order does
not validate item limits, sibling capacities, policy, complete acquisition or
values, nor emit a Plan. Fixed Sketch `87dc7144` uses the same priority and stable
explicit-tie fallback in its nest compiler; newer projection syntax and typed
opaque witnesses follow current Language rather than its legacy column objects
and public ordering flag.

`ResolveNestedEnvelope` requires Host nested byte/depth ceilings, overflow-safe
parent-count × per-parent-limit accounting, sibling byte addition, and logical
copies for repeated parent rows. A child-total bound only tightens expansion
when the parent correlation keys themselves are proven unique.
`ValidateOutputsBeforeConsumers` requires atomic validation after aggregation
and attachment, even when a later step drops the payload.
`PropagatePolicyAndCompleteness` retains dependencies through correlation,
membership, ordering and counts; an empty array does not prove global absence.

Input/output contracts and source trees are traversed iteratively with shared
work, text, node and depth budgets. These are checker resource limits, not Host
execution ceilings. Unknown references retain their source path and span.
This package performs no row acquisition, execution, AoA lowering, ordering
proof construction or publication. The existing canonical nest lowering corpus
remains a separate specification oracle, not evidence of execution support.
