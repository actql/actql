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

`reach-selector.named.aql` and `reach-selector.op.aql` exercise a Relation
selector for Reach. `seeds` aliases the existing `nodes` producer without
adding a step. The independently authored expected Program therefore binds
`reach.start.from` to `nodes`; it also records that named and OP syntax have
the same Program meaning.

`reach-subgraph.expected-results.json` records independent expected schema and
rows from the normative reach and induced-subgraph laws: A is included at
zero hops, B is reached, C is excluded, and precisely the A-to-B edge remains.
`components.named.aql` adds Graph-to-Relation components and an explicit
SELECT; its separate Program and Result fixtures require A and B in the
component identified by A, while C is its own component.
`diff-apply.named.aql` keeps the base Graph, target Graph and typed Delta
producer distinct; its expected final Graph has one added node and edge.
`mean-graphs.named.aql` repeats the first Graph in an explicit three-sample
list. With equal weights and half-support thresholds, A and B and their edge
remain while C and its edge do not.
`graphs-equal.named.aql` compares a Graph producer with itself. Its separate
Program and Result fixtures expect one `equal: true` row and no implicit sort.
`normalize-rows.named.aql` normalizes a Graph, converts it to Relation rows,
and explicitly sorts the rows before declaring an ordered Named Result. Its
independently authored input lists B before A, while the expected Result is A,
B. This checks that Frontend lowering adds no extra Program step and does not
make Result ordering implicit. Physical task boundaries require separate
planner and packed execution evidence.
`degree-rows.named.aql` computes out-degree from a Graph with two edges from A.
The authored sort fixes A, B, C order; the independent Result fixture expects
degrees 2, 0, 0 and keeps the `node`/`degree` schema from the existing contract.
`graph-bounds.named.aql` declares two Results from one Graph. The first reports
the node-count violation before A's degree violation; the second is empty at
inclusive limits. The independently authored expectations include a nullable
`node_id` for whole-graph violations. Neither DATA expression adds a sort or
Result order declaration.
These expectations have not yet been checked against runtime output from the
named source. Separate small source cases have passed the common checker for
reach/subgraph, diff/apply and mean. The exact fixtures here still need
checker and execution acceptance; components needs its ordinary capacity
evidence. The normalize-rows, degree-rows and graph-bounds fixtures pass
Program admission and common preparation with the Local Check Environment,
but their current task compilation requires the existing Result transformation
to be connected by the Host.
The distribution Client job runs `scripts/sga-surface-checker.test.mjs`
against common preparation. It admits the four source-free Graph fixtures that
currently prepare and rejects a Relation passed to a Graph-only operation and
a bounds call without a threshold. This is checker evidence, not packed
runtime or publication evidence.
Source authorization, packed public-input acceptance and independent
positive, rejection and boundary fixtures for other operations remain required.

The zero-argument node_rows/edge_rows syntax emits boolean `true` in
the existing Program. An empty object is not the registered operation body.
