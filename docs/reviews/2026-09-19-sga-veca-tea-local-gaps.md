# SGA, VecA, and TEA Local execution gaps

Baseline: `0886df5ab75ff77edcd68291470f487346fc1cc4`.

This is a live implementation ledger, not a completion claim. The machine
readable coverage manifest is authoritative for individual operation status.

## Shared blockers

| Area | Baseline state | Required closure |
|---|---|---|
| Canonical AoA | Closed: the selected registry contains the complete fixed family set and typed variable-arity contracts | Preserve the selected registry, AoA profile, CIDs, pins, and independent vectors during implementation |
| Lowering | Thirteen SGA operations now reach typed canonical occurrences; the remaining family operations are rejected as unimplemented | Produce complete checked typed AoA without frontend rediscovery |
| DAG inputs | Closed: the common captured DAG, managed request, dispatch, cancellation, and cleanup paths retain ordered input positions without a two-input ceiling | Preserve edge position, producer port, binding, ownership, and accounting as family execution is connected |
| Completion | Managed output is Relation-shaped | One Carrier-aware lifecycle with typed Carrier views |
| Runtime material | Only relation sequences and tables are accepted | Add managed Carrier views and registered providers without forced copies |
| Progress | Local kernels are synchronous | Add bounded MoonBit start/resume state and real environment yield |
| Cancellation | Pre-start and surrounding asynchronous cancellation exist, but synchronous kernels cannot receive cancellation | Connect delivery, polling, stop confirmation, and cleanup |
| Packaging | Local execution kernels are assembled together | Produce and inspect family-selective artifacts |
| Publication | Existing Effect-free path accepts ordered Relations | Connect every new Relation result and Carrier projection through that path |

## Closed normative contract mismatches

The selected pipeline registry now contains the five previously absent
canonical operations:

- `SGA.subgraph`
- `SGA.equal`
- `SGA.mean_structural`
- `TEA.time_series`
- `TEA.join.interval`

The selected registry now represents the following source shapes without
forcing an incompatible fixed arity:

- graph traversal with an optional selector Relation
- shortest path with up to two selector Relations
- reciprocal-rank fusion with a nonempty finite Relation list

Canonical `union_graphs` retains the authored finite list as one typed
occurrence. A physical fold remains an implementation choice only when it
preserves the registered order, failure, numeric, identity, and accounting
laws. Independent vectors retain repeated input positions and reject a
canonical binary fold tree.

## Family execution gaps

### SGA

All 17 author-visible operations are accepted by frontend typing.
Thirteen SGA operations now have typed canonical lowering: `normalize_graph`,
`match_nodes`, `match_edges`, `components`, `graph_bounds`, `degree`,
`graph_diff`, `graft_graph`, `union_graphs`, `subtract_graphs`, `graphs_equal`,
`apply_graph_delta`, and `mean_graphs`. Match lowering retains checked predicate
field bindings and authored projection order without frontend rediscovery.
Union and mean preserve their ordered finite input lists,
including repeated positions, as one operation occurrence. Structural
operations retain checked property laws. Basic operations preserve direction,
component policy, resolved guards, and bounds. Delta application retains its
exact produced input and selected field. They still lack their Carrier
provider, managed execution, two-consumer connection, and publication
connection. The other SGA operations still lack portable Local lowering as
well. Graph projection already defines evidence laws; execution must consume
rather than recreate them.

### VecA

All five operations lack portable Local execution. `vector_score` and
`vector_concat` are accepted by expression typing but rejected by shared
lowering and have no evaluator implementation. The prescribed binary32 and
binary64 operation sequence needs a portable conforming kernel and independent
vectors before optimized implementations can be selected.

### TEA

All eight operations lack portable Local execution. Runtime work must preserve
finite event-time observation semantics across transport page splits and bind
checkpoint advancement to the existing successful commit boundary. No
long-lived streaming state is required by TEA 0.1.

## Current verification boundary

The baseline passed Linux CI run `35414883771`. That proves the accepted RelA
baseline only. It is not evidence for any missing family execution path.

Each entry moves from missing to partial to complete only when its manifest
evidence names existing fixtures, suites, targets, and recorded results. A
passing inventory count alone cannot complete a layer.
