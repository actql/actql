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
| Candidate-key transfer | `pipeline_typing/keys.mbt::sync_keys` | Handles unary/window_group, ordinary/cross/interval joins, Calendar, time grids, nest, except/intersect, windows, Event record bridges and Graph/Vector projections. Joins retain role-tagged parent/key/cardinality dependencies; null extension does not fabricate non-null keys. Interval matching alone does not prove uniqueness; cross-join left-key preservation retains its checked singleton assertion. The default branch still returns None for other operations; this is incomplete transfer, not a language rule. |
| Nest parent keys | `language.md#nest`, `sync_keys`, `relation_evidence/nest.mbt`, `pipeline_typing/nest_keys_test.mbt` | The baseline gap is now closed by exact-parent-bound witness transfer. Alias survival, child-key noninterference, budget boundaries and mismatched-contract rejection are tested. Child-order and capacity obligations remain independent. |
| External order and counts | `logical_order.mbt::logical_order`, `row_counts.mbt` input cases | Ordinary inputs return None. Producer-bound inputs retain conditional counts and scoped order origins from their immutable source pipeline; external snapshot facts still need a verified source boundary. Provider enumeration and caller booleans cannot fill it. |
| Conditional operation order | `logical_order.mbt` | Implemented origin/dependency graph; inspected separately from keys and counts. It is not an execution certificate. |
| Contextual order consumers | `contextual_orders.mbt`, `aggregate_order.mbt`, `analytic_order.mbt`, `nest_order.mbt`, `input_order.mbt`, `sort_completion.mbt`, `relation_results/publication_order.mbt` | Whole-pipeline contextual order resolution now visits every step atomically under cumulative budgets, including unused branches. Results retain their separate whole-collection resolver. Combined all-obligation discharge and external input evidence admission remain unfinished. |
| Conditional cardinality | `row_counts.mbt`, `join_evidence.mbt` | Implemented transfer and join refinement; exactness and upper bounds stay distinct. No dependency-closed resolved-limit artifact follows from a numeric summary alone. |
| Runnable capacity facts | `language.md#resolved-limits`, public pipeline API, retained checker obligations | No completed public boundary producing and validating canonical bound-witness/resolved-limit dependency closure was found. This remains required shared work, not permission to pass arbitrary ceilings as facts. |
| Profile facts | Calendar and text-rank profile APIs, pipeline check signatures | Admitted profile boundaries exist. Numerical/tokenization fixture checks are not evaluator conformance. Cross-family use and outstanding profile obligations remain audit subjects. |
| Atomic success and cumulative limits | operation/pipeline Budget implementations, dedicated boundary tests | Individual checks and several resolvers are bounded and atomic. Independent resolver success does not prove all required checks were invoked together. |
| Normative/schema/vector coverage | scoped operation list versus machine contracts and fixed corpora | Full per-operation acceptance mapping remains unverified; regenerated CIDs only establish consistency with selected bodies. |

## Remaining implementation and verification

1. Close the remaining semantically required key transfers; the demonstrated
   Graph query gap now retains exposed node/edge identities and the actual
   selection units of traversal, shortest paths and diagnostic reports. Checked
   query producers retain original input contracts and obligations through
   aliases and Result publication. Path endpoints alone do not identify all
   enumerated paths. The demonstrated
   sequence gap now establishes each independent label identity for disallowed
   overlap and retains the checked matching producer through aliases, contextual
   sorting/take and Result publication. Allowed overlap does not gain a key.
   The demonstrated
   as-of gap now retains projected left keys and checked identity, including
   Events identity and multiple aliases, with the actual producer obligations.
   This does not complete the cross-operation key audit. The demonstrated
   nest parent-key loss has been addressed. The Relation/Event window and Events
   projection paths have now been inspected against `transfer_window_keys`,
   `transfer_event_keys` and `transfer_events_projection_keys`. The regression
   `event_membership_audit_test.mbt` adds external typed Events inputs and both
   orders of multiple start aliases: retaining one alias preserves the composite
   key and its original declaration debt; deleting all aliases loses that key
   and its sort-completion evidence. Bare Event roles supply no row key, whether
   the window is fixed or sliding. Existing `event_keys_test.mbt` and
   `window_membership_keys_test.mbt` cover declared and absent keys through
   `to_events`, fixed/sliding windows, watermark and row projection. This closes
   these transfer cases, not external evidence admission or all Carrier bridges.
   Row preservation, repeated membership and semantic identity uniqueness remain
   distinct; producer validation debts are retained, not discharged.
   Nearest now retains its original Carrier or key collection independently of
   completed vector roles, including explicit-ID inputs that do not select a
   supplied key. Ranking provenance can recover both original sides without
   reconstructing them from output fields. Nearest now produces its query plus
   candidate key, retaining positional identity domains through exact aliases
   and Result order completion. Opaque input roles do not manufacture keys, and
   ordinary objects do not acquire comparison semantics. Ranking fusion now
   retains its distinct by fields plus candidate key, ordered input occurrences
   and positional domains across successive fusions and aliases. Lexical ranking
   retains the query/candidate key with its corpus/query inputs and profile.
   Distinct set operations now add producer-backed whole-row uniqueness without
   requiring an input key, alongside preserved left keys. ALL modes do not
   manufacture uniqueness. Nullable/structural key-use restrictions and empty-row
   cardinality remain separate from tuple provenance.
   Empty-schema distinct now retains its zero-or-one count; set multiplicities
   use the single possible empty-row value when both counts are exact, with
   exhaustive bounded-multiplicity checks. This remains conditional count
   propagation, not admission of external count witnesses.
   These are conditional producer-backed keys, not discharged row-validation,
   arithmetic or resource obligations; the cross-operation audit remains open.
   The nearest checker now lives in `relation_evidence`, with shared vector
   checking support below both packages and the original `vector_typing` facade
   retained. Dependency tests enforce the direction. This removes the ownership
   cycle for nearest and ranking key producers, with unchanged facade entry points.
2. Define validated external evidence and resolved-capacity boundaries using
   the existing normative witness domains, governing laws and dependency checks.
   [Producer-bound input evidence](produced-input-evidence.md) now retains the
   original pipeline/target and conditional record/node/edge facts through
   input forwarding. Repeated operands and existing key/ranking owners remain
   intact. Imported order now uses a local input origin with an explicit
   upstream owner, preserving repeated dependencies without reinterpreting
   foreign step indices. Input consumers and Result publication are tested;
   this is not external snapshot verification or complete validation of the
   producer dependency graph.
   Shared [capacity arithmetic](capacity-arithmetic.md) is implemented and used
   by count propagation; arithmetic validation does not close this requirement.
   [Derivation consistency](capacity-derivation.md) checks bounded numerical
   dependency graphs, including cycles and units. Candidate minimum selection
   is preceded, for CID-addressed descriptions, by complete bounded reference
   linking; missing dependencies cannot skip arithmetic checks. Reference
   spelling and closure are not content/source authentication. Candidate selection
   now retains all numeric candidates and computes strict author-guard binding;
   supplied roles and applicability are not authenticated by that arithmetic.
   [Common wire admission](capacity-witness-wire.md) checks closed shapes,
   role/source pairs, declared references, canonical bytes and preimage identity;
   its wire collection is linked to complete numeric operand checks, including
   unused inconsistent claims. It remains a claim until source/application and
   complete source closure validation; enforced-limit inputs fail explicitly
   until that boundary is implemented. Non-Host
   source/law verification remains open. The [closed law-name registry](capacity-law-registry.md)
   now has a normative owner, pinned body and exact-membership API; individual
   law applications and non-Host sources remain unvalidated by that membership.
   The separate [operation transfer registry](bound-transfer-registry.md) now
   covers all 72 public spellings and is pinned by the language owner. Coverage
   classification does not replace individual witness-law/source validation.
   [Host capacity policy admission](capacity-policy.md) now binds canonical
   policy bodies and opaque field ceilings to an expected CID. Host authority,
   complete witness laws and consumer enforcement are separate unfinished work.
   [Host source witnesses](host-capacity-witness.md) now fix the supported
   field/unit/law combinations and canonical identity while retaining the
   admitted policy. Program/Contract/author/language sources and complete
   consumer resolution remain unfinished.
   Canonical Host-source wire admission now reconstructs the full witness from
   the admitted policy and checks both expected CID and full byte identity;
   even a self-consistent wrong-unit witness is rejected. This closes that
   source branch, not the remaining mixed-source dependency closure.
   Program proof body binding now checks the two fixed-reference body forms,
   canonical identity, matching assertions and exact declared dependency sets.
   It preserves repeated proof inputs but does not validate Program subjects,
   governing-law applications or the truth of source bounds. Enforced ceilings
   still require the separate resolved-limit owner.
   Program-input closure now requires one bound proof for every Program claim,
   resolves every proof input within the arithmetic witness collection, checks
   operand occurrences and rejects cycles including source-proof dependencies.
   This closes the input-reference gap, not external source bodies or semantic
   applicability; no pipeline execution evidence is produced by this result.
   Do not add public proof flags, treat policy ceilings as observations, or
   mistake a `LimitClaim` for runnable evidence. Resolved-limit wire admission
   now binds every embedded candidate to the arithmetic collection, recomputes
   the minimum and guard binding, and verifies canonical body identity. Candidate
   completeness, source/law applicability and consumer enforcement remain open.
   Mixed witness/limit closure now binds preflight ceilings by exact source
   dependency, unit and value, and rejects cycles across limit candidates and
   witness operands under cumulative artifact/reference budgets. Program-proof
   inputs now join that same graph, with one body for each ordinary Program
   witness and retained limits for preflight claims. Synthetic tests detect a
   cycle introduced only by a Program input edge. Consumer/source/application
   validation remains open; this does not discharge enforcement or produce
   input counts.
   Collection-wide Host source binding now resolves every Host witness against
   admitted policy bodies, including unused claims, and retains the original
   Program/mixed owner. Exact field/unit/law/value/source identity is checked;
   non-Host entries remain explicitly unvalidated. Policy selection authority
   and consumer applicability are not supplied by this catalog lookup.
   [Graph input preflight binding](graph-input-preflight.md) now associates
   Host-backed node/edge limits with the actual immutable pipeline inputs and
   selected policy, including opaque and unused Graph inputs. Other consumer
   families, non-Host candidate applicability and actual enforcement remain open.
   Do not
   expand into acquisition, an evaluator or Host dispatch.
3. Connect contextual resolutions into a complete static checking/discharge
   boundary. [Combined order checking](combined-order-checking.md) now resolves
   all steps and named Results with one shared budget and one pipeline owner.
   Capacity and other mandatory obligations still require the final combined
   boundary. It must not let callers omit a difficult step or local aggregate,
   reset shared budgets per resolver, or turn unresolved mandatory facts into
   execution permission. Runtime/binding obligations remain explicitly separate.
4. The demonstrated traversal/report count gaps now retain
   node-pair bounds and bounded diagnostic rows, with path multiplicity and
   resource guards explicitly kept separate. Finish the remaining 48-operation
   audit against source bodies, schemas, fixed accepted
   and rejected vectors, overloaded Carrier alternatives, bounds and downstream
   consumers. The dispatch table above is only the navigation index for this
   audit. Record missing evidence as unverified rather than complete.
5. Run the full agreed gates on the resulting tree and inspect the remaining
   scope requirements individually before claiming completion.

These are remaining parts of the original scope, not a replacement objective.
Existing operation compatibility, nonrecursive bounded checking, exact diagnostics,
immutable results and Relation-only publication stay in the acceptance contract.
