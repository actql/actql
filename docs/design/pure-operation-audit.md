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

The [acceptance evidence inventory](pure-operation-test-inventory.md) now maps
all 48 spellings to operation/pipeline tests and schema owners. Its integrity
gate checks exact scope coverage, real evidence paths and presence in both
embedded Program schemas. This closes the missing navigation/index mapping,
not the assertion-by-assertion normative review or consumer completion below.

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

## Explicit row-bridge acceptance audit

The four row bridges have been traced through their normative sections,
`carrier_projection`, pipeline dispatch and existing downstream tests. The
fixed Sketch `87dc7144` compiler has the same four algebra bridges; its authored
`event_rows`/`vector_rows` spellings and older physical-column assumptions are
not imported into the current `events`/`vectors` contract.

| Operation | Source/schema owner | Evidence and consumers inspected |
| --- | --- | --- |
| events | Language `event-bridges`; `carrier-projection-schema.mjs` requires `true` in both embedded Programs | `carrier_projection/projection_test.mbt` retains typed, untyped and open payload evidence; `pipeline_typing/projection_test.mbt`, Event membership tests and `relation_results/projection_test.mbt` cover window roles, aliases and explicit Relation publication. |
| vectors | Language `vector-bridges`; same schema gate | Projection tests retain composite identity and dimensions without invented physical aliases. Pipeline vector projection/key tests cover lost identity components, multiple aliases and nearest; carrier count tests cover normalization/scoring/row projection. |
| node_rows | Language `graph-rows`; `graph-schema.mjs` requires `true` | Graph projection tests retain typed identities, properties and authored aliases, reject output collisions, and retain runtime collision/admission debts for incomplete inputs. Pipeline Graph projection-key and Result Graph tests cover downstream identity use. |
| edge_rows | Language `graph-rows`; same Graph schema gate | Tests preserve the source/destination/nullable-label tuple, distinguish missing key components from a whole identity, and reject using nullable labels as non-null order evidence. Graph projection alone does not establish logical order. |

`pipeline_typing/bridge_audit_test.mbt` adds the full four-operation by
four-Carrier by typed/opaque matrix at the shared dispatch boundary (32 cases),
24 invalid-body cases, absent/ambiguous current rejection and explicit source
selection. Accepted routes produce one Relation output with the original input
edge and no invented row count. Opaque inputs do not become complete schemas.
Each accepted matrix case has exact work/node/text and one-less budget tests;
wrong-Carrier and invalid-body failures retain the operation's source slot.

This verifies these source/Carrier/connection boundaries alongside the listed
consumer regressions. It does not discharge runtime admission, external count
or order evidence, capacity sources, or the remaining operation audit.

## Session Carrier acceptance audit

Language's `session.closed-body` and `session.by-and-positive-gap-are-required`
blocks match the two branches of `event_typing/check_session`: Relation requires
explicit id/time; Events takes intrinsic roles and rejects overrides. Both keep
the input Carrier, repeated/global partition keys and source roles, add fresh
non-null numeric boundaries/string session IDs, and retain arithmetic/identity
and Parameter-gap validation obligations. Existing session unit tests cover
partial payload knowledge and bound gaps without reading defaults; pipeline
tests cover window-role preservation through Events projection/window_group.

`pipeline_typing/session_carrier_audit_test.mbt` adds 32 cases across both
Carriers, number/timestamp clocks and eight identity types (including exact
decimal and both Ref domains). The consumer chain explicitly projects Events
to Relation, selects original roles/session fields and resolves take's contextual
order. Identity and clock contracts remain unchanged, and session arithmetic
and identity obligations remain attached to the original producer. Every
accepted case tests exact work/node/text limits and one-less rejection. Four
negative cases reject missing Relation roles and Events role overrides.

This closes that static Carrier/role/consumer matrix, not execution of session
membership, gap-boundary arithmetic, reference identity comparison or stable
session-ID generation. Those runtime laws remain separate from type/order
checking and from the remaining TEA/window/sequence acceptance audit.

## Session-to-sequence acceptance audit

The sequence source/generated-output/clock requirement blocks were compared
with `relation_typing/sequence.mbt` and the shared pipeline dispatch. Unlike
session, sequence has an explicit numeric-only clock restriction on Events;
Relation clocks also admit timestamp conversion. That normative distinction
must not be removed merely because Events retain a timestamp intrinsic role.
Explicit `id` still matches intrinsic Events identity. Both Carrier inputs
produce a Relation, with repeated grouping references retained in the source but
one output column per distinct group and each label ID retaining its full type.

`pipeline_typing/session_sequence_audit_test.mbt` adds 48 combinations of
string/number/decimal identity, two original clocks, both Carriers and both
overlap/contiguity modes. It partitions explicitly on `session_id` rather than
assuming session labels implicitly prevent cross-session matching. Timestamp
Events explicitly select numeric `session_start_ms` for the sequence clock;
the unchanged timestamp field is rejected at the sequence `time` source slot.
Relation timestamp conversion remains recorded only where required.

The output feeds take through contextual order resolution. Disallowed overlap
retains two producer-backed label keys; allowed overlap acquires none. Unique
event-identity and atomic match-limit obligations remain present. Each accepted
case has exact work/node/text/token and one-less budget checks. Existing
sequence tests separately cover predicate diagnostic ranges, label aliases and
Result publication. These are static connection tests, not evaluation of the
matching automaton or proof that session-boundary values have been computed.

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
   The [source applicability audit](capacity-source-audit.md) distinguishes
   registered names from actual source authority, records the extension-local
   fragment law boundary, and identifies checked-operation author-guard binding
   as the next in-scope source connection. It does not add a generic trusted
   Contract/Program/Language witness constructor or expand into acquisition.
   Its Program application review also distinguishes semantic references from
   authored names and capacity operands from data inputs. The
   [checked step bound application](program-step-bounds.md) now binds local
   input-independent global-group and literal take/top-k proofs to their actual
   operation, using owner-relative step references and checking law/unit/value
   and derivation. Input-dependent append, literal clamps and known unpivot/
   unnest expansion now retain checked child applications from actual same-owner
   producer edges, preserving repeated operands and checking arithmetic.
   As-of applications now check the existing left-row-bound law for both kinds
   and every direction, rejecting right-side substitution and retaining both
   data edges without treating the right scan as capacity-free. The right proof,
   if present in the claim collection, still requires its own application.
   Retained
   `ProducedInput` links also connect exact upstream owners through forwarding
   inputs under cumulative iterative-traversal budgets.
   Non-expanding step transport now also follows the actual input edges of
   Relation preservation/reduction and Events/Vectors transformations back to
   the original bound owner. Repeated paths share the same cumulative budget;
   expansion, global aggregation and unrelated inputs cannot substitute a bound.
   This transports conditional upper bounds, not exact counts or discharged
   intermediate obligations. Parameter selection
   counts now resolve through budgeted lookups retaining exact declaration,
   pipeline and bound-value owners, without implicit defaults.
   Window applications now validate literal/bound size, step and offset on both
   Relation and Events inputs and derive exact fixed/sliding membership factors.
   Duration lookup parses once under an explicit text budget; fixed unused step
   remains validated and overflow fails. Profile, time-value and endpoint checks
   remain obligations. Nearest applications now distinguish query-only bounds
   from candidate-dependent bounds, retaining both actual operand owners when
   the candidate count reduces the factor. Application checks reject swapped
   operands and hidden factor dependencies, preserve zero candidate bounds and
   fail on checked multiplication overflow. Search-work and value/score/profile
   obligations remain separate. Ranking fusion applications now include all
   ordered input bounds, retaining RRF repetition and checking source/add laws.
   Global grouping clamps to k without an overflowing intermediate sum; grouped
   sums reject overflow. Indexed connections and explicit cumulative operand
   budgets bound the variable-arity work before allocation. Complete input and
   ranking validation obligations are retained. Collection
   application coverage now rejects missing unused Program applications and
   substituted child handles under cumulative work limits, while retaining
   other source branches as unresolved. Graph preflight source coverage can now
   join Host and ordinary Program application checks for the same exact claim
   collection, rejecting unsupported source branches without implying full
   limit consumption or source authority. Plain external
   input applications, general imported semantic subjects and enclosing Program
   identity remain open; arithmetic closure or matching an
   `as` name cannot substitute for those boundaries.
   [Checked author-guard occurrences](author-guard-occurrences.md) now retain
   actual local step/aggregate owners, exact guard slots and unresolved
   Parameter references under cumulative enumeration budgets. Numeric binding
   now checks positive safe-integer values against BoundValues from the exact
   declaration owner and retains default/supplied provenance, with source-local
   rejection and separate cumulative work/text costs. Program identity,
   governing source laws and consumer enforcement remain required; bound guard
   quantities are not capacity witnesses.
   The pinned author-guard table now fixes every collected scope's source field,
   unit and law, with generated product accessors and independent mapping tests.
   Three newly named laws cover nest items, string-aggregate bytes and
   shortest-path output. Source identity and enforcement still require binding.
   The consumer audit found and closed an analytic-aggregate enumeration gap:
   array/string aggregate guards inside analytic now retain full call indices,
   exact source slots and the existing item/byte laws. Non-aggregate calls and
   frame extents do not create guard occurrences; binding and budget regressions
   cover the added route. Contextual producer closure now collects guards for
   every visit, including unused branches and repeated owners, under its shared
   budgets. Result order checking retains these collections with their original
   source owners. Closure-wide numeric binding now validates one optional
   declaration-owned BoundValues per visit under cumulative budgets, preserving
   repeated occurrences and reporting late failures atomically. Reusable
   pipeline ownership is not Invocation identity: consistency of bindings within
   a Program/Invocation, source identity binding and consumer enforcement remain
   required.
   [Producer-bound input evidence](produced-input-evidence.md) now retains the
   original pipeline/target and conditional record/node/edge facts through
   input forwarding. Repeated operands and existing key/ranking owners remain
   intact. Imported order now uses a local input origin with an explicit
   upstream owner, preserving repeated dependencies without reinterpreting
   foreign step indices. Input consumers and Result publication are tested;
   the combined order checker now resolves all producer occurrences, including
   unused inputs and branches, with shared step/work/text limits and original
   owner diagnostics. This is not external snapshot verification or complete
   non-order validation of the producer dependency graph.
   Window-role evidence now crosses this boundary through the retained opaque
   producer handle, including multiple aliases and Events row projection.
   Identically typed ordinary inputs remain insufficient. Overwrite and alias
   removal retain the existing invalidation rules; long forwarding chains use
   cached lookup rather than recursive ancestry traversal. Typed Delta
   expectations now also cross this boundary, retaining original Graph-contract
   handles and isolated, budgeted receiver maps. Aliases, overwrite, duplicate
   bindings and application obligations are covered by producer-input tests.
   These expected contracts do not prove actual Delta admission; complete
   non-order producer validation remains unfinished.
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
   selected policy, including opaque and unused Graph inputs. It now reports
   unconsumed limits, and its collection-complete entry rejects valid limits
   that have no Graph input consumer. This is complete consumption only for
   that dedicated collection, not whole-pipeline readiness. Other consumer
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
