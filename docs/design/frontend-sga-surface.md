> Public migration status: the legacy structural envelope, STEP and OP are
> withdrawn. Named-call examples below record the adopted logical mapping;
> their historical decoder is an internal fixture tool. They are not currently
> executable public source. See [migration mapping](frontend-language-migration.md).

# SGA surface syntax over the existing Program

This is the accepted logical design for the SGA Frontend increment. Named
Graph calls previously lowered inside structural DATA; that public envelope
is withdrawn. The standalone adopted surface still needs the migration
connections listed above. The contract baseline remains 0.1. Public SDK/CLI
source routing and packed Local/HTTP execution are required for text migration
acceptance. Graph execution support is measured per operation and profile.

## Meaning and placement

Use existing operation names with named arguments, checked by the ordinary
Program checker. Do not require redundant type annotations, create operation
synonyms, or treat graph operations as SQL scalar functions. GQL-derived MATCH
and ActQL-specific SGA operations are distinct surfaces over the same Program.
The authority for operation meaning is [Graph operations](../spec/language.md#graph-operations-sga).

DATA binds a logical producer. Existing lowering emits ordinary steps with
`as`/`from`; a bare DATA alias reuses its producer without emitting a step.
Adding the surface must not introduce per-binding acquisition, materialization,
publication or physical tasks. Preserve authored step occurrences, shared
producer references and explicit Stage, acquisition, approval, Effect and
Result boundaries. Never expand a shared source into separate acquisitions.

Lower to placement-independent operations, not Local kernels or provider
procedures. Planner/Connector capability matching retains type, identity,
ordering, multiplicity, failure, snapshot and resource obligations. A matching
operation name is insufficient for pushdown. Pure graph computation cannot be
replaced by a provider write. Moving computation to Local still requires
input access, movement permission and bounded capacity; an unsupported
pushdown is not permission to fetch the entire graph.

Frontend placement independence and actual Graph pushdown are separate
acceptance items. This design does not implement a graph-service connector,
prove provider fusion, or remove existing physical execution constraints.

## Argument roles and names

Each argument position obtains its role from the existing operation contract:

- `with: target` is a producer reference; graph lists retain their authored
  order and repeated references.
- `start: "A"` in reach is a typed ID value, never a guessed producer name.
  `start: {from: seeds, id: "id"}` instead names a Relation producer in the
  selector's `from` field; its `id` field designates a column.
- `field: "delta"` is a column designation, not a value or producer reference.
- `nodes: {from: reached, id: "node_id"}` contains a producer reference and a
  column designation at their respective existing selector positions.

Never infer these roles from string contents. Reference positions admit the
existing DATA name syntax, including quoted names; value positions use their
existing literal/expression contract. Column positions retain exact admitted
column names, including names requiring quoting. SQL expressions continue to
use their established identifier and alias rules. Do not rewrite a literal
merely because it equals a DATA name. Detailed lexical admission and diagnostics
must be tested when the productions are added.

Within a Stage, reuse the input/step/port producer namespace and existing DATA
visibility. Reject duplicate producer definitions, forward references and
cycles. SQL column aliases occupy query scopes and do not replace producer
bindings. Cross-Stage references use explicit Result exports/imports, not
temporary DATA names. Any necessary change to existing DATA semantics must be
reported explicitly rather than hidden in lowering.

For consuming operations, the Pipe left operand supplies the existing current
input, represented by step `from` or its ordinary sequential equivalent.
Other inputs remain explicit named arguments. Reject a second specification
of the same primary input. This does not prohibit legally using the same
producer at two different operand positions, or repeated mean samples.
Generators have no Pipe left operand. In particular, mean_graphs uses only
its declared list, and is rejected after `FROM` or another Pipe operation.

## Complete Graph operation inventory

All rows have machine Program operation keys and historical internal STEP/OP
fixtures. The operation key equals the name in the first column. Adopted named
calls cover the 19 rows other than Graph construction; they remain subject to ordinary checked
operation contracts. MATCH is separate: fixed patterns lower through
Graph-to-Relation bridges and relational steps; bounded patterns also use
traverse. MATCH coverage does not imply natural syntax for every SGA operation.

The [Local operation inventory](../reviews/2026-09-19-sga-veca-tea-local-coverage.json)
records operation-level Host/kernel evidence. In the last column, Host refers
to [standard-host.test.mjs](../../adapters/connectors/duckdb/node/test/standard-host.test.mjs)
and integration to [local_carrier_graph_wbtest.mbt](../../src/query_integration/local_carrier_graph_wbtest.mbt).
This is evidence for existing operations, not packed execution of the new
named source.

| Program operation | Pipe/current input | Other inputs | Output | Adopted named DATA | Local evidence |
| --- | --- | --- | --- | --- | --- |
| graph, concise form | Relation | Existing graph field mapping | Graph | Text construction pending | Host |
| graph, explicit form | None | Node Relation and edge Relation | Graph | Text construction pending | Host |
| normalize_graph | Graph | None | Graph | `normalize_graph()` | Host |
| match_nodes | Graph | Predicate/projection arguments | Relation | `match_nodes(...)` | Host |
| match_edges | Graph | Predicate/projection arguments | Relation | `match_edges(...)` | Host |
| reach | Graph | ID, Relation or predicate start selector | Relation | `reach(...)` | Host |
| traverse | Graph | Start selector, optionally a Relation | Relation | `traverse(...)` | Host |
| shortest_path | Graph | Source/target selectors, optionally Relations | Relation | `shortest_path(...)` | integration |
| components | Graph | Kind | Relation | `components(...)` | Host |
| degree | Graph | Direction | Relation | `degree(...)` | integration |
| graph_bounds | Graph | Existing bounds | Diagnostic Relation | `graph_bounds(...)` | integration |
| subgraph | Graph | Node selector, optionally a Relation | Graph | `subgraph(...)` | integration |
| graft_graph | Graph | Graph | Graph | `graft_graph(...)` | Host |
| union_graphs | Graph | Graph or ordered Graph list | Graph | `union_graphs(...)` | integration |
| subtract_graphs | Graph | Graph | Graph | `subtract_graphs(...)` | integration |
| graphs_equal | Graph | Graph | One-row boolean Relation | `graphs_equal(...)` | Host |
| graph_diff | Base Graph | Target Graph | One-row typed Delta Relation | `graph_diff(...)` | integration |
| apply_graph_delta | Base Graph | Delta Relation and field | Graph | `apply_graph_delta(...)` | integration |
| mean_graphs | None | Explicit Graph list, weights and strategies | Graph | `mean_graphs(...)` | integration |
| node_rows | Graph | None | Relation | `node_rows()` | Host |
| edge_rows | Graph | None | Relation | `edge_rows()` | Host |

The 17 SGA operations in the adopted profile exclude graph construction and
the two Carrier bridges; the table includes all of them. Delta remains typed
Relation data, not another Carrier, a permission token or an external Effect.
Graph-returning operations stay Graph until an explicit bridge or a
Relation-returning operation. Reject incompatible chaining without conversion.

## Concrete lowering examples

These combine admitted named SGA calls with planned SQL/Pipe sugar and show
corresponding Stage step fragments. They are not complete Programs or executed
fixtures. `g`, `base`, `target`, `g1` and `g2`
denote existing Graph producers. No example invents a source, grant or schema.

```text
DATA groups = FROM g
  |> components(kind: "weak")
  |> SELECT node_id, component_id, component_size;
```

Existing steps: `from: g, components: {kind: weak}`, then
`select: [node_id, component_id, component_size], as: groups`.
The first operation changes the current Carrier to Relation.

```text
DATA reached = FROM g
  |> reach(start: "A", direction: "out", max_depth: 2);
DATA neighborhood = FROM g
  |> subgraph(nodes: {from: reached, id: "node_id"});
DATA rows = FROM neighborhood |> node_rows() |> SELECT id;
```

Existing steps: `from: g, reach: {start: A, direction: out, max_depth: 2},
as: reached`; `from: g, subgraph: {nodes: {from: reached, id: node_id}},
as: neighborhood`; `from: neighborhood, node_rows: true`; then
`select: [id], as: rows`. Both uses of g reference the same producer. There
is no direct Relation-to-subgraph coercion.

```text
DATA changes = FROM base |> graph_diff(with: target);
DATA restored = FROM base
  |> apply_graph_delta(with: changes, field: "delta");
DATA rows = FROM restored |> node_rows() |> SELECT id;
```

Existing steps: `from: base, graph_diff: {with: target}, as: changes`;
`from: base, apply_graph_delta: {with: changes, field: delta}, as: restored`;
`from: restored, node_rows: true`; then `select: [id], as: rows`.
Keep the checked Delta evidence and exact base/target snapshot validation.
A shape-compatible arbitrary JSON object does not replace this evidence.

```text
DATA average = mean_graphs(
  with: [g1, g2], weights: [1, 1],
  support: {nodes: 0.5, edges: 0.5},
  properties: {nodes: {}, edges: {}}
);
DATA rows = FROM average |> node_rows() |> SELECT id;
```

Existing steps: `mean_graphs: {with: [g1, g2], weights: [1, 1],
support: {nodes: 0.5, edges: 0.5}, properties: {nodes: {}, edges: {}}},
as: average`; `from: average, node_rows: true`; then
`select: [id], as: rows`. Empty property maps require empty closed property
domains; this example is not valid for arbitrary graph schemas.

The zero-argument `node_rows()` surface maps to the existing boolean
`node_rows: true`, not an empty object. The same applies to `edge_rows()`.

Each example needs a separately authored Result declaration to publish a
Named Result. For example, `from: rows, fields: [id], order_by: [{id: asc}]`
is an explicit Result body. DATA does not synthesize `results.answer`, sort,
a retention boundary, or additional Results. An explicit sort or Result order
is compared as part of the authored Program, not added to make a test pass.

## Independent acceptance and implementation boundaries

Pair each new source with independently authored STEP/OP and Program fixtures
using the same inputs, IDs, explicit declarations and applicable contracts.
Run normal admission/checker and compare canonical Program structure,
producer references, explicit steps, Result definitions and relevant identities.
Do not generate expected Programs with the new lowerer. Origin maps may differ
with source spelling; generated nodes retain the originating source spans.

Derive expected results from existing normative laws, including:

- reach includes its start at depth zero, retains the semantic ID type and
  required aliases, and obeys membership and finite exploration limits;
- components uses the canonically least semantic node ID as component ID,
  with exact member counts and component/node output order;
- subgraph preserves selected nodes and precisely the admitted induced edges;
- diff/apply verifies complete typed Delta records, action ordering, exact
  before records, base/target CIDs and final edges as well as nodes;
- mean uses exact support boundary comparisons, retained list multiplicity,
  zero/repeated weights and existing property-mean laws, including rejection.

Include quoted DATA/column names, value strings matching producer names,
wrong Carrier chains, duplicate primary inputs, scope/cycle rejection and
wrong-base Delta. Test Result absence/order without silently repairing them.
Then execute the public source from clean packed Local and HTTP installations,
compare independent Named Result schema/rows/order, and observe that shared
references do not reacquire sources. Maintain typed pre-admission rejection
and existing authorization, cancellation and failure ownership.

Existing evidence must retain its layer: the
[SGA coverage inventory](../reviews/2026-09-19-sga-veca-tea-local-coverage.json)
records operation-level Host/kernel evidence with shared limitations. The
[resource audit](../reviews/2026-09-23-local-resource-accounting-audit.json)
tracks additional resource boundaries. Graph tests in
`scripts/test-node-client-package.mjs` execute generated Program JSON from
packed Local/HTTP packages; they do not prove public ingestion of the named
surface. Each named operation needs separate public-source acceptance for the
claimed Host profile and Result contract.

Report underlying operation gaps to the Compute owner; do not implement a
second Graph runtime or approximate the meaning in Frontend. The grammar,
manifest and dependent pin remain on version 0.1.
