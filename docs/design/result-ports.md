# Named Result port preparation

`relation_results.prepare_ports` prepares every named Result from one opaque
`CheckedOrders`. That owner already binds the checked Result definitions,
their pipelines, contextual producer-order closure and publication strategies.
No separate caller-supplied order or projection can be paired with a definition.

Each `ResultPort` retains its exact definition index and `CheckedOrders`, the
existing `PublicationOrder`, and a producer projection derived from the original
`fields` cursor. The projection is checked as Select against the exact source
schema and uses the existing producer evidence-transfer implementation. This
adds no authored step and does not rewrite the Result source or Program identity.
Qualified fields and their nullability remain qualified, not flattened.

The publication strategy is not recomputed: the owning Result checker uses the
[shared order policy](publication-order-policy.md) for authored order, inherited order,
candidate-key completion and projected-field fallback use the existing resolver.
Two Results with the same producer and selected fields can therefore retain
different authored orders. An order can refer to a source column hidden by the
Result projection. The checked Result's execution obligations remain retained.

## Budgets

`max_results` bounds the full port collection; preparation cannot omit unused
definitions. Work and text allowances include the prior `CheckedOrders` usage,
one registration per Result, Select checking and producer-projection transfer.
Each phase receives the remaining allowance. Depth and additional value-node
limits apply to those projection phases; selecting already admitted fields may
need no new value nodes. Parsing and earlier Result type admission are not
retroactively charged here. Exact limits pass and failure returns no partial
port collection. Projection and transfer issues retain the Result index and
their original diagnostics.

## Consumer boundary

This prepares conditional static port evidence; it does not execute publication
or authorize a captured Result import. Accessors expose the actual Result,
publication order and projected schema. There is deliberately no conversion to
ordinary `ProducedInput`: that type's cached order still describes the original
producer, not the Result's publication transformation. Exposing the projected
input as if it were publication-complete would recreate the
[raw-producer mismatch](relation-results.md#named-results-versus-raw-producers).

The remaining consumer connection must represent publication as an explicit
order/evidence origin, bind the named port to the enclosing stage/Program source,
and preserve all upstream obligations while transferring the Result schema.
It must not invent a public `ordered` flag, flatten qualified fields or accept
schema equality as proof of the referenced Result. Capacity, identity, binding,
input evidence and runtime checks remain separate from this preparation.

Tests cover opposite authored orders on equal projections, inherited hidden-field
order, qualified full-join outputs, exact owner retention, collection bounds and
aggregate work/text limits including earlier order resolution.
