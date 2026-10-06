# Public language migration

The adopted target is GoogleSQL/Pipe with the selected GQL, VecA and TEA
surfaces and explicit ActQL acquisition, Result and Effect boundaries. The
September 30 revised Pipe target and adoption review supersede older structural
text requirements. This migration does not claim whole-standard compatibility.
The [vocabulary rules](semantic-decisions.md#vocabulary-across-representations)
govern names and semantic correspondence across source, Program and AoA.

## Separate completion units

1. Withdraw the public AQL/PROGRAM/STAGE envelope, STEP/OP, its parser routing
   and Program-to-structural formatter. Preserve public JSON/YAML machine
   input, the common Program, admission, checker, planner and Host.
2. Implement the adopted replacement text paths and execute their complete
   examples through the installed Local/HTTP Client. Keeping machine Programs
   or historical decoding tests is not completion of this second unit.

The first unit does not add all target syntax. Public acceptance of a replacement
form requires its common checked and execution owners; parser availability alone
does not make that form executable. A common INFER owner and real ModelTask
execution must arrive through its owner's formal handoff; source construction
or test replay cannot substitute for that acceptance. Delivery evidence belongs
in the [migration checkpoint](../reviews/2026-10-03-frontend-migration-checkpoint.md),
separately from these architectural obligations.

## Public input responsibilities

| Input | Public route | Meaning |
| --- | --- | --- |
| `json`, `aql-json` | Ordinary Program admission | Supported machine input |
| `yaml`, `aql-yaml` | Ordinary Program admission | Supported machine input |
| `sql` | Common SQL query parser/lowerer | Adopted SQL query heads and allowed Pipe composition; unsupported forms are typed refusals |
| `aql-text` | Common query parser/lowerer | Adopted SQL/Pipe and domain surfaces; Graph admission requires the unified Graph owner |
| AQL/PROGRAM/STAGE, STEP/OP | Typed input rejection | No legacy fallback, alternate public entry or public formatter |

Source errors precede durable Run acceptance and provider I/O. Neither SDK
nor CLI contains the parser; they retain explicit format selection and ordinary
request identity, transport-unknown, approval, cancellation and Result rules.
JSON/YAML still carry metadata, stable IDs, bindings, explicit steps and Effect
structures through the same common owners. This is not an internal-only input.

## Lost text paths and replacement obligations

These are concrete migration obligations, not new language restrictions.
The independent [SGA fixtures](../../spec/frontend/fixtures/sga-surface/) retain
the prior source and expected Program separately. Every named fixture previously
used OP for its Values/Graph inputs or Relation egress, so withdrawing the
envelope withdraws its *text path*, not the common Graph operation.

| Prior example | Adopted new expression / meaning | Boundary obligation | Completion evidence required |
| --- | --- | --- | --- |
| `client-values.structural.aql`: OP values | A source-free Relation with the same declared schema/rows; no fabricated external source | Source-free SELECT and UNION ALL lower to existing Values; named Results require explicit declarations | `SELECT 1 AS id UNION ALL SELECT 2 AS id ORDER BY id` versus independent `packages/sdk/fixtures/values.json`, then Local/HTTP Result |
| `orders.structural.aql`: filter/group/sort | SQL/Pipe WHERE, AGGREGATE, ORDER BY; explicit RESULT where requested | Exact authored IDs, metadata and Result envelope are not represented automatically by query sugar | Preserve the independent machine Program; compare the complete modern source through Local/HTTP |
| Named SGA examples: OP graph plus named calls | Existing producer references, named typed arguments and Graph-to-Graph or Graph-to-Relation operations | DATA/SGA syntax and lowering must connect to unified Graph admission, adapted consumers and explicit Results | All nodes, edges, types, order, multiplicity and Delta compared through public text Local/HTTP |
| Metadata, bindings, unused steps and explicit no-ops | Program machine input retains these authored facts | No automatic equivalent text spelling is claimed; some facts belong to source context rather than query operators | Independent lossless machine input tests; any proposed text context must bind exact facts |
| Old EFFECT maps and AFTER envelopes | Explicit terminal EFFECT, BRANCH, statement sequencing, AFTER ACCEPTED, RESULT(name)/RECEIPT(name) | Surface productions and owner bindings are separate; Effect-only export needs its explicitly adopted contract | Existing Effect owners and durable acceptance; no Effect-free recheck or second scheduler |
| INFER/NEAREST KEEP and AS | KEEP plus one result STRUCT forms a new output scope | Source lowering and execution are separate; preserve common ModelTask and key/evidence ownership | Values/types/nullability, keys, replay and no-redispatch through packed Local/HTTP |
| VecA/TEA OP forms | Their adopted domain vocabulary and existing logical operators | Surface productions and lowering must preserve the selected common contracts | Independent Program/result cases; never approximate with SQL scalar functions |

Source-free Relation examples use the adopted FROM-optional SELECT and set
syntax. The adopted [Graph mapping](frontend-standard-profiles.md#graph-mapping-and-element-identity)
uses NODE TABLES, EDGE TABLES, independent KEYs, REFERENCES and static label
sets inside an explicit pure ActQL constructor. It requires a coordinated
common Graph representation and independently authored expected Programs;
the historical simple-Graph operation cannot faithfully represent it. Do not
preserve OP while that implementation is unfinished. An installed Graph source
and a source-free constructed Graph are distinct input obligations.

## Named SGA migration inventory

The following producer-level expressions record already-adopted operation names,
argument roles and required connections; they do not establish runtime support.
The complete examples also require the construction and Result surfaces above.
DATA references existing producers; it must not force another
acquisition, materialization, task or local placement.

| Retained independent example | Adopted logical expression / Carrier transition | Required text connection |
| --- | --- | --- |
| components | `FROM g \|> components(kind: "weak")`: Graph → Relation | Named call then ordinary Relation SELECT |
| reach-subgraph | `FROM g \|> reach(...)`, then `FROM g \|> subgraph(nodes: {from: reached, ...})`: Graph → Relation → Graph | Reuse the same g and reached producers |
| diff-apply | `FROM base \|> graph_diff(with: target)`, then `FROM base \|> apply_graph_delta(with: changes, field: "delta")`: Graph → Delta Relation → Graph | Exact base Graph and retained Delta reference |
| mean-graphs | `mean_graphs(with: [first, second], ...)`: explicit Graph list → Graph | No implicit current-input sample |
| graphs-equal | `FROM first \|> graphs_equal(with: second)`: Graph pair → Relation | Preserve pair identity and comparison semantics |
| normalize-rows | normalize_graph then node_rows/edge_rows | Keep Graph until explicit row extraction |
| degree-rows | degree | Graph → Relation |
| shortest-path | shortest_path | Existing bounded path Relation |
| reach-selector | reach with Relation selector | Same retained selector producer |
| reach-selector-duplicates | reach with repeated selected IDs | Preserve common selector deduplication law |
| reach-selector-empty | reach with empty selector | Empty output, retained schema |
| reach-selector-nullable | reach with nullable ID column | Common runtime ID admission, not fabricated evidence |
| graph-bounds | graph_bounds | Complete existing bounds output |
| traverse-paths | traverse | Explicit traversal mode and bounds |
| union-graphs | union_graphs | Graph → Graph, explicit peer |
| graft-graphs | graft_graph | Graph → Graph, existing conflicts/identity |
| subtract-graphs | subtract_graphs | Graph → Graph, preserve nonempty remainder |
| match-projections | match_nodes/match_edges | Distinct from the GQL-derived MATCH surface |

References and literal/column values are chosen by argument role, never guessed
from strings. `with: target` refers to a producer; `start: "A"` is an ID value;
`field: "delta"` is a field designation. Named Results and order declarations
are explicit; none is synthesized merely by adding DATA. Frontend placement
independence remains separate from actual provider pushdown support.

## Evidence classification

Historical `.aql` parsing/formatting is internal fixture evidence. Independent
JSON/YAML Program execution proves retained common capability. New query source
execution proves that specific text path only. A machine-input SGA success must
not be recorded as migrated named SGA text success. The frozen imported 140-case
index is historical and is never bulk-marked executed by these checks.
