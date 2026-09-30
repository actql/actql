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
`traverse-paths.named.aql` uses a Relation selector for a bounded one-hop
Graph path. The independent Program keeps the seed as one producer, and the
Result fixture expects the semantic string IDs, node sequence, and closed
`{src, dst, rel}` edge identity with an explicit null label. It declares no
extra sort or materialization.
`shortest-path.named.aql` asks for the shortest A-to-D path in a diamond
Graph. A-to-B-to-D and A-to-C-to-D have equal unit cost and hop count; the
normative node-identity tie break selects B. Its independently authored
Program preserves both explicit endpoints, the hop and output bounds, and one
Named Result. Its Result fixture checks total cost, hop count, ordered node
IDs, and both closed edge identities. The additional fourteen-case and native
CLI evidence is recorded separately below.
`union-graphs.named.aql` composes two Graph producers with a one-element
ordered `with` list, then declares separate node and edge Results. The second
Graph shares B with the first, adds C and B-to-C, and the expected union keeps
exactly A, B, C and both distinct directed edges. Both Results declare their
order; the DATA binding itself adds no Result or sort.
`graft-graphs.named.aql` uses the same distinct A-to-B and B-to-C edge
identities with add-only graft semantics. B has the same complete payload in
both inputs, so the independent expected Graph contains A, B, C and both
edges. Its explicit node and edge Results test the Graph output without
creating an implicit Result or ordering boundary.
`subtract-graphs.named.aql` removes C and D from a four-node base Graph.
The independent expectation retains A and B and the A-to-B edge; the
B-to-C edge disappears by endpoint closure even though it is absent from the
removal Graph. Both Results have authored order.
`match-projections.named.aql` uses duplicate authored node IDs to select
A and C once each, and separately projects the two original edges. Its
independent rows follow the semantic node and edge identity orders rather
than the input Values order. It declares two Results without authored sorts.
`degree-rows.named.aql` computes out-degree from a Graph with two edges from A.
The authored sort fixes A, B, C order; the independent Result fixture expects
degrees 2, 0, 0 and keeps the `node`/`degree` schema from the existing contract.
`graph-bounds.named.aql` declares two Results from one Graph. The first reports
the node-count violation before A's degree violation; the second is empty at
inclusive limits. The independently authored expectations include a nullable
`node_id` for whole-graph violations. Neither DATA expression adds a sort or
Result order declaration.
At `0601a0f02f99e23cb38b908f2d0955a96339b50f`, the standard clean packed
installation passed `normalize-rows`, `mean-graphs`, `traverse-paths`,
`union-graphs`, `graft-graphs`, `subtract-graphs`, `degree-rows`, `components`,
`graph-bounds`, `match-projections`, `reach-subgraph`, `graphs-equal` and
`diff-apply` through both Embedded Local and HTTP.
The same source passed the Node-free native CLI's
representative SGA Result. The driver checked independently authored rows and
stream termination; the public Result API does not expose schema type,
nullability or column order.
All original eight cases now pass packed Embedded Local and HTTP. The five
additional cases above also pass, for thirteen standard named-source cases.
The earlier failed probes and their repaired provider boundaries are recorded
in `docs/reviews/2026-09-29-sga-packed-run-handoff.md`.
The distribution Client job runs `scripts/sga-surface-checker.test.mjs`
against common preparation. It admits all thirteen source-free Graph fixtures,
checks typed Graph/Delta task edges and Result roots, and rejects a Relation
passed to a Graph-only operation and a bounds call without a threshold.
Source authorization and independent positive, rejection and boundary
fixtures for other Graph operations remain separate work.

At `5835d644410e702223c0b77250a9a154abfcabea`, all fourteen fixtures,
including `shortest-path`, passed through clean packed Embedded Local and
HTTP. The targeted native CLI shortest-path run also matched the independent
path, cost, hop count and edge identities. Invalid `max_hops: 0` was rejected
before Run acceptance through both SDK transports. The fixture driver checks
accepted Run counts and actual source I/O; no extra Run or read was introduced
by that refusal. See the
[additional acceptance record](../../../../docs/reviews/2026-09-30-sga-shortest-acceptance.md)
for source inputs, package digests and verification limits.

These results use the prior Graph provider, not the newer PR #92 semantics.
The separate #92 integration still rejects authored edge Result order in
`diff-apply` and `mean-graphs`; its successful `graphs-equal` result does not
close that regression. The original eight-case milestone remains incomplete
on that newer integration until the order witness is corrected.

The zero-argument node_rows/edge_rows syntax emits boolean `true` in
the existing Program. An empty object is not the registered operation body.
