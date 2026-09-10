# Pure operation checking

This implementation contract covers all remaining provider-independent operation
checking. The normative owner is [Language](../spec/language.md); this document
records implementation boundaries and acceptance, not a competing language.

## Scope

The work comprises the shared Carrier/evidence model and these 48 operations:

| Family | Operations |
| --- | --- |
| Relation | `values`, `except`, `intersect`, `cross_join`, `row_window`, `window_group`, `lag`, `watermark_rows` |
| TEA and Calendar | `window_events`, `watermark_events`, `session`, `time_series`, `interval_join`, `dedupe_events`, `asof_join`, `sequence`, `calendar_bucket`, `calendar_series`, `to_events`, `events` |
| Graph | `graph`, `node_rows`, `edge_rows`, `normalize_graph`, `match_nodes`, `match_edges`, `traverse`, `shortest_path`, `components`, `reach`, `graph_bounds`, `graph_diff`, `graft_graph`, `union_graphs`, `subtract_graphs`, `subgraph`, `graphs_equal`, `apply_graph_delta`, `mean_graphs`, `degree` |
| Vector and lexical ranking | `to_vectors`, `vectors`, `normalize_vectors`, `score_vectors`, `nearest`, `pool_vectors`, `merge_rankings`, `text_rank` |

Existing operation checking remains supported and is tested through the same
pipeline. Both Carrier alternatives of an overloaded operation are in scope;
supporting just its Relation alternative is not completion.

No evaluator, algebra lowering, acquisition, `infer`, `search_candidates`,
`serialize`, Effect/Run engine, provider dispatch, Host adapter or deployment is
part of this work. Fixed numerical vectors document the admitted law; generating
or checking them does not prove that a MoonBit evaluator implements that law.

## Shared representation

The [structural Carrier contracts](carrier-contracts.md) implement the type
representation independently of pipeline evidence propagation.
The [explicit Carrier projections](carrier-projection.md) connect retained
Events/Vectors record knowledge to Relation consumers.
The [Graph operation checker](graph-typing.md) preserves typed identity and
partial property evidence for each supported Graph operation.
The [Vector operation checker](vector-typing.md) retains dimensions and semantic
identity across normalization and scoring before the explicit Relation bridge.
The [Event operation checker](event-typing.md) retains semantic roles and window
evidence across watermark labeling and filtering.
The [time-series checker](time-series.md) admits input-free timestamp grids with
explicit binding and execution-bound obligations.
The [interval-join checker](interval-join.md) validates temporal roles and retains
independent output/search-work obligations on two Relation inputs.
The [as-of contract decisions](asof-join.md) distinguish typed temporal roles,
whole identity tuples and validated tie evidence. Typed Relation/Events admission
is connected; retained candidate-key completion still requires the shared proof boundary.
The [sequence checker](sequence-typing.md) shares predicate budgets across pattern
slots and retains typed event identities in its match-output contract.

Use a typed Carrier sum with Relation, Graph, Events and Vectors variants, not a
Carrier string attached to an otherwise untyped object. Retain recursive value
contracts and semantic roles: graph node identity, node/edge property domains
and labels; event identity/time/payload; vector identity/components/dimensions;
Relation field provenance. Carrier transformations follow the explicit bridges
and the semantic macros permitted by Language, never an implicit reinterpretation.

Keep field knowledge, field-set completeness, recursive type evidence, candidate
keys, logical order, window roles, score contracts and resource facts separate.
Support typed, columns-only and unknown inputs where the operation's existing
rules allow them. Unknown information is neither an empty closed schema nor
`json`. Missing mandatory static evidence fails; only already admitted deferrals
become pending obligations. Pending obligations are not evidence or execution
permission. Supplied facts enter through validated boundaries, not public
booleans that allow callers to invent a proof.

Each checked operation retains ordered, role-tagged input occurrences. Shared
targets are not deduplicated. Generator steps have no implicit current operand;
`mean_graphs` still has its explicit graph-list operands. The pipeline can have
no current target. Its consuming steps require one unless an explicit selection
establishes it; generators require `as`, reject step `from`, and set current.
All pure operations in this scope have one output. General multi-output
acquisition is deferred rather than represented as a successful opaque step.

Only Relations become named Results. Graph/Events/Vectors require a specified
bridge before publication. Result imports preserve the resulting Relation
contract; they do not import an arbitrary stage-local Carrier or `as` binding.

## Implementation units

1. Normative rules, pinned laws and independent boundary vectors.
2. Carrier contracts, incomplete evidence, role-tagged connections and Result integration.
3. Relation generators, set operations and cross join.
4. Relation/Event time operations and Calendar checking.
5. Graph construction, projections, selectors and query checking.
6. Graph structural operations and typed Delta checking.
7. Vector carriers, exact-ranking contracts and lexical ranking checking.
8. Cross-family regression and complete scope audit.

Commits group coherent functionality, its interfaces, tests and applicable
schema/pin changes. This sequence is not authorization to omit a family.

## Acceptance

For every operation, verify its closed source body, required input roles,
Carrier compatibility, literal/Parameter boundaries, result contract and
mandatory versus deferred checks. Fix independent accepted, rejected, empty,
duplicate, nullable and limit-boundary cases where those distinctions apply.
No-op or repeated-input acceptance never authorizes operation deletion or CID
equivalence unless a specific normalization law says so.

Budget work/text/nodes/tokens cumulatively across input admission and operations;
bound recursive work without recursive host stacks. Retain exact source paths,
spans and embedded-expression ranges. Returned contracts/collections remain
opaque or detached and failed checks expose no partial successful pipeline.

Cross-family tests must cover bridge output into later operations, wrong Carrier
rejection, generators with no current, repeated ordered input roles, branches,
partially known inputs, empty typed collections, and Result publication requiring
a Relation. Existing join provenance and all previously supported operations
must survive the shared-model change.

Each completed implementation unit passes JS, Wasm and native checks/tests with
warnings denied, formatting, public-interface comparison, documentation checks,
metadata checks and whitespace checks. Spec/schema changes regenerate dependent
CIDs and independent identity tests together. Runtime profile conformance and
Linux CI success require their own evidence and are not implied by local checks.

The final audit compares the complete operation list above against actual
dispatch, per-operation tests, schemas and consumers. This design document is
not completion evidence by itself.
