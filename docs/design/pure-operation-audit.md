# Pure operation completion audit

This is an open audit of [the agreed scope](pure-operation-checking.md), not a
completion certificate. The inspected implementation baseline is `7734e65`.
The local regression baseline is 1,710 tests per target (JS, Wasm, native), plus
format, API, documentation and metadata checks. Linux CI and runtime execution
conformance are not established by these checks.

## Dispatch inventory

All 48 scoped spellings have concrete routes in
`src/pipeline_typing/check.mbt`; none is admitted as an opaque successful step.
The inventory below identifies route groups, not proof that every acceptance
condition or overloaded Carrier alternative has sufficient tests. In particular,
a passing package suite is not a substitute for the remaining schema/vector/
consumer audit.

| Scoped operations | Actual checking route |
| --- | --- |
| values | early `values` generator branch |
| except, intersect | Relation binary branch, `relation_set` |
| cross_join | Relation binary branch, `relation_join` |
| row_window, window_events | Carrier-specific window branch, `temporal_window` |
| window_group | unary Group dispatch with required retained window prefix |
| lag, watermark_rows | unary `relation_typing` dispatch |
| watermark_events, session, to_events, dedupe_events | `event_typing` branch |
| time_series | early input-free `time_series` branch |
| interval_join, asof_join | distinct two-input temporal join branches |
| sequence | `event_typing` sequence branch |
| calendar_bucket, calendar_series | early Calendar branch, with admitted profile |
| events, vectors, node_rows, edge_rows | explicit `carrier_projection` branch |
| graph | early construction branch with explicit input occurrences |
| normalize_graph, components, graph_bounds, degree | unary Graph branch |
| match_nodes, match_edges | property-match branch |
| traverse, subgraph | selector branch retaining resolved auxiliary input |
| shortest_path | endpoint-selector branch |
| reach | concise reach branch |
| graphs_equal, graph_diff, graft_graph, union_graphs, subtract_graphs, apply_graph_delta | typed binary Graph/Delta branches |
| mean_graphs | early sample-list branch retaining repeated operands |
| to_vectors, normalize_vectors, score_vectors | unary Vector branch |
| nearest | query/candidate branch |
| pool_vectors | pooling branch |
| merge_rankings | ranking-list branch |
| text_rank | corpus/query branch with optional admitted lexical profile |

## Shared-boundary findings

| Requirement | Inspected evidence | Audit finding |
| --- | --- | --- |
| Typed Carrier and explicit connections | `pipeline_typing/types.mbt`, dispatch branches | Present; exhaustive alternative/consumer tests still need inventory-level review. |
| Input evidence bound to immutable records | `pipeline_typing/input_evidence.mbt`, `InputContract` | Keys and ranking can be combined only on matching handles. No external count/order witness variant is admitted. |
| Candidate-key transfer | `pipeline_typing/keys.mbt::sync_keys` | Handles unary/window_group, Calendar, time grids, nest, except/intersect, Relation windows and Graph/Vector projections. Sliding windows retain composite membership witnesses, not the original key alone. The default branch still returns None for other operations; this is incomplete transfer, not a language rule. |
| Nest parent keys | `language.md#nest`, `sync_keys`, `relation_evidence/nest.mbt`, `pipeline_typing/nest_keys_test.mbt` | The baseline gap is now closed by exact-parent-bound witness transfer. Alias survival, child-key noninterference, budget boundaries and mismatched-contract rejection are tested. Child-order and capacity obligations remain independent. |
| External order and counts | `logical_order.mbt::logical_order`, `row_counts.mbt` input cases | Inputs return None. Validated external facts still need a boundary; provider enumeration and caller booleans cannot fill it. |
| Conditional operation order | `logical_order.mbt` | Implemented origin/dependency graph; inspected separately from keys and counts. It is not an execution certificate. |
| Contextual order consumers | `aggregate_order.mbt`, `analytic_order.mbt`, `nest_order.mbt`, `input_order.mbt`, `sort_completion.mbt`, `relation_results/publication_order.mbt` | Group, analytic, nest, prefix watermark/pivot, lag, sort/top-k/take and Results have explicit resolutions. A whole-pipeline discharge boundary has not been demonstrated. |
| Conditional cardinality | `row_counts.mbt`, `join_evidence.mbt` | Implemented transfer and join refinement; exactness and upper bounds stay distinct. No dependency-closed resolved-limit artifact follows from a numeric summary alone. |
| Runnable capacity facts | `language.md#resolved-limits`, public pipeline API, retained checker obligations | No completed public boundary producing and validating canonical bound-witness/resolved-limit dependency closure was found. This remains required shared work, not permission to pass arbitrary ceilings as facts. |
| Profile facts | Calendar and text-rank profile APIs, pipeline check signatures | Admitted profile boundaries exist. Numerical/tokenization fixture checks are not evaluator conformance. Cross-family use and outstanding profile obligations remain audit subjects. |
| Atomic success and cumulative limits | operation/pipeline Budget implementations, dedicated boundary tests | Individual checks and several resolvers are bounded and atomic. Independent resolver success does not prove all required checks were invoked together. |
| Normative/schema/vector coverage | scoped operation list versus machine contracts and fixed corpora | Full per-operation acceptance mapping remains unverified; regenerated CIDs only establish consistency with selected bodies. |

## Remaining implementation and verification

1. Close the remaining semantically required key transfers; the demonstrated
   nest parent-key loss has been addressed. Audit windows and Carrier bridges independently: row
   preservation, repeated membership and semantic identity uniqueness are not
   interchangeable rules. Preserve original key producers and validation debts.
2. Define validated external evidence and resolved-capacity boundaries using
   the existing normative witness domains, governing laws and dependency checks.
   Shared [capacity arithmetic](capacity-arithmetic.md) is implemented and used
   by count propagation; arithmetic validation does not close this requirement.
   [Derivation consistency](capacity-derivation.md) checks bounded numerical
   dependency graphs, including cycles and units. Canonical wire/source/law
   verification remains open; a closed bound-law registry body was not found in
   the inspected repository and still needs an authoritative owner.
   The separate [operation transfer registry](bound-transfer-registry.md) now
   covers all 72 public spellings and is pinned by the language owner. Coverage
   classification does not replace individual witness-law/source validation.
   [Host capacity policy admission](capacity-policy.md) now binds canonical
   policy bodies and opaque field ceilings to an expected CID. Host authority,
   complete witness laws and consumer enforcement are separate unfinished work.
   Do not add public proof flags, treat policy ceilings as observations, or
   expand into acquisition, an evaluator or Host dispatch.
3. Connect contextual resolutions into a complete static checking/discharge
   boundary. It must not let callers omit a difficult step or local aggregate,
   reset shared budgets per resolver, or turn unresolved mandatory facts into
   execution permission. Runtime/binding obligations remain explicitly separate.
4. Finish the 48-operation audit against source bodies, schemas, fixed accepted
   and rejected vectors, overloaded Carrier alternatives, bounds and downstream
   consumers. The dispatch table above is only the navigation index for this
   audit. Record missing evidence as unverified rather than complete.
5. Run the full agreed gates on the resulting tree and inspect the remaining
   scope requirements individually before claiming completion.

These are remaining parts of the original scope, not a replacement objective.
Existing operation compatibility, nonrecursive bounded checking, exact diagnostics,
immutable results and Relation-only publication stay in the acceptance contract.
