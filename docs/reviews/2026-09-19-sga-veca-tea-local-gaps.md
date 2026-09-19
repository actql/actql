# SGA, VecA, and TEA Local execution gaps

Baseline: `0886df5ab75ff77edcd68291470f487346fc1cc4`.

This is a live implementation ledger, not a completion claim. The machine
readable coverage manifest is authoritative for individual operation status.

## Shared blockers

| Area | Baseline state | Required closure |
|---|---|---|
| Canonical AoA | Closed: the selected registry contains the complete fixed family set and typed variable-arity contracts | Preserve the selected registry, AoA profile, CIDs, pins, and independent vectors during implementation |
| Lowering | All seventeen SGA operations, both record-producing Bridges, vector normalization and scoring, and event watermarking reach typed canonical occurrences; the remaining TEA, VecA, Bridge, and VecA expression forms remain unimplemented | Produce complete checked typed AoA without frontend rediscovery |
| DAG inputs | Closed: the common captured DAG, managed request, dispatch, cancellation, and cleanup paths retain ordered input positions without a two-input ceiling | Preserve edge position, producer port, binding, ownership, and accounting as family execution is connected |
| Completion | Common lifecycle and exact producer reads now own typed Relation, Graph, Events, and Vectors generations; Graph and record construction install retention before accepting values | Join every Carrier to physical task completion |
| Runtime material | Bounded immutable Graph storage enforces graph laws, and common finite-record storage preserves typed Events and Vectors with semantic identity uniqueness and pre-allocation admission; normalize uses Graph storage and checked Events and Vectors use record storage through managed completion, but no standard Host Carrier provider is connected yet | Connect the typed storage to registered providers without forced copies |
| Progress | The portable MoonBit session core enforces bounded work reports, fresh step tokens, stop confirmation, and separately retryable cleanup; normalize is the first connected kernel, but environment yield is not connected yet | Move every remaining potentially long kernel into bounded steps and add real environment yield between steps |
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
All seventeen SGA operations now have typed canonical lowering: `normalize_graph`,
`match_nodes`, `match_edges`, `components`, `graph_bounds`, `degree`,
`graph_diff`, `graft_graph`, `union_graphs`, `subtract_graphs`, `graphs_equal`,
`apply_graph_delta`, `mean_graphs`, `reach`, `subgraph`, `traverse`, and
`shortest_path`. Match lowering retains checked
predicate field bindings and authored projection order without frontend rediscovery.
Reach retains its typed start identity, direction, and finite depth.
Subgraph retains explicit, predicate, and Relation selectors as distinct typed
forms and preserves its optional edge predicate.
Traverse retains homogeneous and patterned hops, selector form, predicates,
emission mode, bounds, and the resolved output guard.
Shortest path retains scalar and selected endpoints, repeated selector input
positions, selection policy, direction, bounds, labels, weight, and guard.
Union and mean preserve their ordered finite input lists,
including repeated positions, as one operation occurrence. Structural
operations retain checked property laws. Basic operations preserve direction,
component policy, resolved guards, and bounds. Delta application retains its
exact produced input and selected field. Normalize now copies an exact managed
Graph input into an independently retained managed Graph generation through
bounded work units. Graft consumes two exact positioned inputs, preserves a
repeated material occurrence, collapses an equal declaration, and rejects a
conflicting payload atomically. Their portable tests cover pre-allocation
limits, kernel cancellation observation, and managed Graph generations on JS,
Wasm, and native. Standard Host selection, actual downstream computations,
environment cancellation delivery, independent consumer release, and
publication remain open. The other SGA operations still lack portable Local
kernels. Graph projection already defines evidence laws; execution must
consume rather than recreate them.

### VecA

Normalization now executes as a portable bounded-step kernel over exact managed
Vectors input. It applies binary32 input and output quantization, preserves the
specified dimension-order binary64 norm fold, rejects zero vectors, admits
record workspace before temporary construction, and publishes a distinct
managed generation. Its tests cover cancellation observation and two exact
downstream producer reads on JS, Wasm, and native. Environment cancellation
delivery, independent consumer release, and standard Host selection remain
open, so normalization is not complete. Checked typed lowering also emits
`VEC.score_sort`, including bound query values, without reading frontend syntax
again. The other four VecA operations still lack portable Local kernels.
`vector_score` and `vector_concat` are accepted by expression typing but still
rejected by shared expression lowering and have no evaluator implementation.
Common immutable record storage preserves composite vector identities,
admitted dimensions, exact UTF-8 value usage, work, and workspace bounds.

### TEA

All eight operations lack portable Local execution. Checked typed lowering now
emits `TEA.watermark.label`, while the other TEA forms remain unimplemented in
shared lowering. Runtime work must preserve finite event-time observation
semantics across transport page splits and bind checkpoint advancement to the
existing successful commit boundary. No long-lived streaming state is required
by TEA 0.1. Common immutable record storage preserves typed event roles, open
payload evidence, semantic identity uniqueness, and bounded allocation. Events
now pass through the common managed generation and exact producer-read
lifecycle on all three targets; TEA kernels and standard Host integration
remain open.

### Bridges

`to_events` and `to_vectors` now lower their checked semantic roles to
`BRIDGE.rows.to_events` and `BRIDGE.rows.to_vectors`. Their runtime conversions
and the other five Bridge operations remain open. Bridge implementations must
retain their source and target Carrier contracts and create an independently
managed generation; a Relation-shaped buffer alone is not evidence of a
completed conversion.

## Current verification boundary

The baseline passed Linux CI run `35414883771`. That proves the accepted RelA
baseline only. It is not evidence for any missing family execution path.

Each entry moves from missing to partial to complete only when its manifest
evidence names existing fixtures, suites, targets, and recorded results. A
passing inventory count alone cannot complete a layer.
