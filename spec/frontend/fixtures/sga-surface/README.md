# SGA surface baseline fixtures

These independently authored fixtures compare named SGA calls with the
existing Program side of syntax acceptance.

`reach-subgraph.op.aql` uses today's structural DATA/OP syntax.
`reach-subgraph.named.aql` uses the direct named calls for reach, subgraph,
node_rows and edge_rows. Both source forms must match the same Program.
`reach-subgraph.expected-program.json` is a separately authored Program, not
new-lowerer output. Both explicitly declare two Results and their order.
The test checks ordinary source admission and exact Program equality,
including shared producer references. It is included by `aql-text.test.mjs`.

`reach-subgraph.expected-results.json` records independent expected schema and
rows from the normative reach and induced-subgraph laws: A is included at
zero hops, B is reached, C is excluded, and precisely the A-to-B edge remains.
These expectations have not yet been checked against runtime output from the
named source. Full checker, execution, source authorization/capacity and packed
public-input acceptance remain required. Other operations still need their own
independent positive, rejection and boundary fixtures.

The zero-argument node_rows/edge_rows syntax emits boolean `true` in
the existing Program. An empty object is not the registered operation body.
