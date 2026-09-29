# SGA surface baseline fixtures

These independently authored fixtures prepare the existing Program side of
future SGA syntax acceptance. No new syntax is implemented here.

`reach-subgraph.op.aql` uses today's structural DATA/OP syntax.
`reach-subgraph.expected-program.json` is a separately authored Program, not
new-lowerer output. Both explicitly declare two Results and their order.
The test checks ordinary source admission and exact Program equality,
including shared producer references. It is included by `aql-text.test.mjs`.

`reach-subgraph.expected-results.json` records independent expected schema and
rows from the normative reach and induced-subgraph laws: A is included at
zero hops, B is reached, C is excluded, and precisely the A-to-B edge remains.
These expectations have not yet been checked against runtime output. Full
checker, execution, source authorization/capacity and packed public-input
acceptance remain required. Other planned operations still need their own
independent positive, rejection and boundary fixtures.

The new zero-argument node_rows/edge_rows syntax must emit boolean `true` in
the existing Program. An empty object is not the registered operation body.
