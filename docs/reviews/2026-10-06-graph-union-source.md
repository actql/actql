# Graph union public source connection

## Problem and existing contract

Integration baseline: `eed8644b449d2936c84160975a55b32996cdb8a4`, a normal
merge of B's statistical aggregate/package repair
`7ffe39f4862ae2f6424a4ebd5ee89727e773f2b7` and main
`24ed33b8f6a5d9834d67edf349455dd029ddf381`.

The adopted named SGA parser, common new-Property-Graph union checker and
provider already accept `union_graphs`. Public script lowering omits this
connection. A pre-repair focused test first checked an independently authored
complete Program, then failed compiling its source equivalent (`run-WCCGVs`).
This is a Frontend connection repair, not a new union semantic profile.

The existing `docs/spec/language.md` structural-union contract defines one
primary Graph followed by a scalar peer or nonempty peer list, in authored
order with repeated occurrences preserved. Merge strategies, compatibility,
typed identities, parallel edges, nullability, failures and operation-wide
capacity belong to the common checker/owner. The Frontend passes them through
without evaluating union, changing ceilings or converting to legacy Graphs.

## Implementation and independent examples

`graph_union_program.mbt` resolves bare/backtick peers through the existing
DATA Graph namespace and emits one ordinary `union_graphs` step. A STRING is
a value, never a producer reference. Both Graph-preserving DATA and the direct
Graph-to-Relation chain call that module. The `compile_query_script` change is
only the Graph producer-table argument; CTE, predicates, assert and Effects
are unchanged. Compatible definition names support subsequent rows lowering;
actual property types and presence remain common-checker decisions.

The complete simple expected Program is handwritten and checked before the
generated Program is compared. The public JSON control is independently
authored, checked through the ordinary checker, and uses ordered composite
keys plus two parallel self-loop edges. Public expectations are independently
computed:

- Original node property 7 and edge properties 2/5, summed with peers `[g,g]`:
  node 21, edges 6/15. This is three occurrences, not two.
- With a doubled Graph, `number_mean` folds `[doubled,g]` to node 8.75 and
  edges 2.5/6.25; `[g,doubled]` gives node 10.5 and edges 3/7.5. Reordering
  or deduplicating peers changes the result.
- A direct union-to-edge_rows chain retains its definition selection,
  predicate, SELECT column order, ORDER BY and LIMIT: edge 11 with weight 15.

The existing packed public-query corpus includes all seven normal cases,
nine preparation refusals and one execution conflict. The narrow
`--graph-union-only` flag selects the same cases, driver, default capacity and
installed Host. Rows and Result.describe check exact columns/types/labels;
same-request resubmission, attach/reread and provider-I/O counts are retained.
Preparation refusals require no Run admission/provider I/O. An unspecified
merge policy with conflicting values fails without publishing either Result.

## Local evidence and identities

- Repaired initial lowering tests: 4/4 (`run-6m5hLv`).
- Expanded JS selection: 32/33 (`run-ViFMTu`). The only failure was a caller
  fixture reserving an unrelated Source name while expecting source-free
  physical slot names. After removing that unused Source from its context,
  the affected caller passed 1/1 (`run-aIZg2w`). The earlier failure is retained.
- Independent Node vectors, manifests and corpus registration: 11/11
  (`run-aIZg2w`). Tests use the pinned toolchain and bounded/nonzero wrappers.

Only the normative query-text rules change the grammar manifest from
`cfb9547ce2d09997b65f3dc9496985e80c9e51210333b8dc7d5d911a0c3bb29d`
to `8cef04355f736983a0fcb4ce73551596ce04f370be0ab9c1d4400f81263842ae`.
The fixed Values Run CID becomes
`6b74c71135148ba3f6eff9ee0cc6e6ec786658242c1dc9cf874dc5cb66f3bd3f`,
from the independent canonical preimage/vector. Historical expectations remain
intact. Unit/Result Plan, operation registry, schemas, expression laws and union
semantics are unchanged. Dependent metadata and generated manifest/canonical
vectors follow the authoritative inputs.

## Delivery and incomplete coverage

This unit is stacked on the statistical aggregate/package repair PR #586;
the eventual merge target is main. Its packaging dependency fixes a real nested
SDK import in installed adapters. It is not a union runtime workaround.

The submitted PR body records the exact source SHA, ordinary five-package
manifest/digests and actual Local/HTTPS receipt. Until that receipt passes,
source/checker success is not public execution acceptance. Full Core,
Wasm/native, Cloud, proof and performance suites are not run locally. Wider
Graph operators, external providers and the overall Frontend migration remain
separate unfinished work. No PR merge or manual CI rerun is performed.
