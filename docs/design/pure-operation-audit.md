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
| graphs_equal, graph_diff, graft_graph, subtract_graphs, apply_graph_delta | typed binary Graph/Delta branches |
| union_graphs | binary or ordered nonempty-list Graph branch retaining each left fold |
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

## Watermark Carrier acceptance audit

Language's `relational-temporal.watermark-source-and-output` and
`event-bridges.watermark-labels` were compared with `relation_typing/check.mbt`,
`relation_typing/watermark.mbt`, `event_typing/check.mbt` and pipeline dispatch.
The embedded Program shapes are checked by `window-schema.test.mjs` and
`event-schema.test.mjs`. The fixed Sketch `87dc7144` semantic checker likewise
separates `watermark_rows` and `watermark_events`; their different option names
and threshold forms must not be collapsed into a shared permissive body.

`pipeline_typing/watermark_carrier_audit_test.mbt` adds 64 combinations of
Relation/Event paths, number/timestamp clocks, declared/absent input keys,
mark/drop policy and negative fractional, zero, positive and large finite
thresholds. The Event path explicitly passes through `to_events` and `events`.
Both paths preserve the clock contract and emit the correct distinct generated
field names with non-null types, then feed an ordinary select. Existing keys
survive; no input key, count or order is invented. Exact work/node/text budgets
and one-less failures are checked for each combination. Ten rejection cases
cover wrong Carriers, exchanged policy names, Events role overrides and
Parameter/skew thresholds, invalid policy and ambiguous/missing Relation sources.

Existing `relation_typing/watermark_test.mbt` separately fixes Parameter domains,
positive skew, generated-column collisions and bad clock contracts.
`pipeline_typing/carrier_counts_test.mbt` covers exact counts for mark versus
upper bounds for drop on zero/nonzero Event inputs, while Event/window key tests
cover preservation of membership evidence. Prefix-skew order requirements are
not replaced by fixed-threshold tests. This is static admission and transfer
evidence, not execution of late-row comparisons, prefix arithmetic or publication.

## Row set acceptance audit

Language `row-set-operations` and its multiplicity block were traced through
`relation_set/check.mbt`, the shared `relation_append.align_schemas`, pipeline
Set dispatch, count/order transfer and `set_keys_test.mbt`. The two embedded
Program bodies are fixed by `set-schema.mjs` and `set-schema.test.mjs`: exact
`with`/`duplicates` members and required lowercase `distinct|all`, without
Parameter mode selection. Schema alignment uses typed field names, not column
position, joins recursive nullability/extents and rejects incompatible domains
or provenance. The package tests cover closed bodies, located invalid modes,
empty schemas, detached alignments and work/text/node/depth boundaries.

`pipeline_typing/set_acceptance_audit_test.mbt` adds 64 cases across both
operators, both duplicate modes and left/right literal input lengths zero
through three. Each fixture contains unique integer rows; an independent
complete-row comparison counts survivors. At both the operation and downstream
select, the retained bound covers those survivors, never exceeds the left
bound, and cannot claim an incorrect exact count. The exact left/right producer
edges and inherited left order are checked, as are cumulative work/node/text
budgets and retained comparison/resource obligations. This does not evaluate
the set operation in MoonBit or establish arbitrary row-equivalence execution.

Duplicate-class multiplicities and empty schemas are separately covered by
`row_counts_wbtest.mbt`, which enumerates actual m/n values under exact and
upper-bound inputs. `set_keys_test.mbt` covers left-key transfer, nullability
widening, distinct whole-row identity, structured/nullable fields that cannot
serve as scalar or ordering keys, and foreign left-schema rejection. Existing
`set_test.mbt` covers repeated input occurrences and forward-reference errors.
These close the inspected static admission and transfer cases; external
comparison evidence, memory ceilings and the final combined consumer boundary
remain independent obligations.

## Input-free generator acceptance audit

The `values.admission` generator rules and the time/Calendar sections were
compared with the early generator branches in `pipeline_typing/check.mbt`,
`relation_values`, `time_series` and `calendar_typing`. These three operations
require `as`, reject step `from`, and establish current without consuming it.
`mean_graphs` is not covered by this input-free argument: it retains its explicit
graph-list operands and has a separate acceptance boundary.

`pipeline_typing/generator_acceptance_audit_test.mbt` adds 36 cases: three
generators, empty/nonempty ranges or literal rows, and six input arrangements
(none, typed Relation, opaque Graph/Events/Vectors, and multiple inputs).
Every generator has no input occurrence; downstream select and take consume
its result rather than an unrelated prior current. Literal values and time-grid
counts are exact; a nonempty Calendar bound is not asserted to be an exact
number of buckets. All empty cases retain exact zero. Generated order survives
selection and satisfies take's contextual check. Each case fixes exact shared
work/node/text budgets and one-less rejection.

Existing generator pipeline tests cover missing aliases and explicit `from`;
time-series tests cover producer-backed keys through Calendar aliases and
as-of completion. `time_series/count_test.mbt` and `resolved_count_test.mbt`
keep unbound Parameters separate from defaults and validate bound endpoint/step
domains even for empty intervals. Calendar admission tests require an admitted
profile and retain located zone/clock errors. The values schema and its corpus
separately constrain cell grammar and typed literal admission.

The opaque unused inputs in this matrix are not certified snapshots. The test
does not waive their source, producer-closure or Graph-input preflight checks,
and does not execute time grids, Calendar transitions or Result publication.

## Graph mean sample acceptance audit

Language `graph-mean.closed-source` and its numeric law were compared with
`graph_typing/mean.mbt`, the early pipeline mean branch and `graph-schema.mjs`.
`mean_graphs` has no implicit current input but does retain every declared
sample occurrence. Closed compatible Graph property/identity domains are
checked before zero-weight contribution filtering. Property strategies cover
every non-identity property; numeric means become nullable because an excluded
denominator can be zero. Arbitrary input order does not choose row-role aliases.

`graph_typing/mean_test.mbt` covers complete strategy maps, compatible recursive
domains, zero-weight incompatibility, nonempty aligned weight lists, positive
total weight, support bounds and finite weights whose ordinary binary64 sum
would overflow. Those static checks do not calculate the weighted mean.
`pipeline_typing/mean_acceptance_audit_test.mbt` adds zero-weight samples at both
ends of the list, explicit sample roles/targets, preserved weights and names,
an unrelated prior input, the `node_rows` consumer and exact work/node/text
budgets. Twelve invalid zero-weight cases reject incomplete Graphs, other
Carriers and incompatible identity/property information; zero does not waive
input validation.

Existing `graph_test.mbt` covers repeated names, missing `as` and forbidden
step `from`. `mean_counts_test.mbt` verifies repeated positive samples are
counted repeatedly, zero-weight samples do not contribute count bounds, an
unknown positive contributor keeps bounds unknown, and empty constructed
Graphs have exact zero extents. These tests do not validate actual support,
label agreement, rational accumulation or graph-mean runtime execution.

## Unary Graph acceptance audit

The degree, components and structural-graph sections were traced through
`graph_typing/check.mbt` and the pipeline Graph branch. Normalization retains
the original Graph knowledge; the other three operations return Relations with
fixed roles. `graph_bounds` thresholds select diagnostics and are not execution
ceilings. Its node-ID output is nullable for whole-graph violations, unlike
degree and component membership identity fields.

`pipeline_typing/graph_unary_audit_test.mbt` checks 65 cases: normalization,
three degree directions, both component kinds and seven nonempty combinations
of zero bounds, each on typed Graph, opaque Graph and three wrong Carriers.
Typed Graph output preserves its exact decimal identity contract, including
the bounds report's nullable form, and feeds ordinary select. Opaque Graph
retains unknown identity evidence and cannot pass complete-schema selection.
Normalization retains its original input handle. Every accepted case checks
its input edge, graph-data/resource obligations and exact work/node/text budgets
with one-less rejection. Wrong Carriers never become successful opaque steps.

Existing `graph_typing/check_test.mbt` covers closed bodies, invalid counts,
Parameter guards and normalization without invented data evidence.
`graph_counts_test.mbt`, `graph_report_counts_test.mbt` and
`graph_query_keys_test.mbt` cover node/report bounds, semantic identity keys and
downstream ordering. This audit does not execute degree counting, SCC discovery,
normalization or diagnostic-row generation, and does not discharge Graph input
preflights or output resource obligations.

## Empty Graph selector Relation audit

The traverse and shortest-path sections explicitly allow an empty selected
Relation, unlike an empty authored `ids` list. `graph_typing/selector.mbt`
checks the selected column's identity domain without requiring a data row;
membership remains a separate obligation. Existing selector tests cover
closed selector forms, literal occurrences and reference identity contracts.

`pipeline_typing/graph_empty_selector_audit_test.mbt` fixes 15 pipeline cases:
three directions across both traversal emit modes and all three shortest-path
selection modes. An input-free, empty typed `values` Relation supplies the
selector while an explicit `from` retains the Graph operand. Both shortest-path
selector occurrences remain separate edges even when they share that Relation.
The fixed-role output feeds select, and exact zero output evidence survives
projection. Exact work/node/text budgets accept and one-less budgets reject.
This is static evidence propagation, not traversal execution or a substitute
for Graph membership, preflight and search-resource validation.

## Pooling Carrier acceptance audit

Language's `pool-vectors.closed-source`, `typed-output` and
`member-key-selection` blocks were compared with `vector_typing/pool.mbt`, the
shared pipeline route and `vector-schema.test.mjs`. The schema gate fixes the
closed body, nonempty distinct grouping fields, three explicit methods and
single-group restriction on `output_id`. The fixed Sketch `87dc7144`
`semantic_check` likewise requires a candidate key for Relation pooling, but
its physical `id`/`vector` output reconstruction is not the current semantic
Carrier contract and is not reused as the expected output.

`pipeline_typing/pool_carrier_audit_test.mbt` adds 96 combinations of Relation
and Vectors, string/numeric member identities, string/number/decimal/ResourceRef
group identities, mean/sum/max and original/aliased output identity. Every path
continues through `vectors`, projection and `take`, retaining the group contract,
component dimensions and pooling's logical-order origin. The aliased path reuses
the dropped member-ID field name without confusing its old type with the new
group identity. Other input payload and hidden component columns do not leak
into the selected output.

The matrix distinguishes direct string member identity from Relation numeric
key encoding, preserves declared-key ownership, and retains global member-ID
validation, quantization and resource obligations. Every accepted case checks
exact work/node/text budgets and one-less rejection. Sixteen rejection cases
cover both Carriers with empty/repeated grouping fields, invalid method or
component role, reserved member-ID override, output collision, tuple alias and
nullable grouping identity. Existing pooling suites separately cover composite
member-key selection, open field knowledge and key-alias transfer.

This closes the inspected static alternative/consumer matrix. It does not
execute quantization or deterministic folds, prove runtime identity uniqueness,
or resolve the separate profile and capacity obligations.

## Nearest mixed-Carrier acceptance audit

Language's `nearest` source, role-consistency and semantic-ID blocks were
compared with the shared pair/output checking and `vector-schema.test.mjs`.
The schema fixes the closed source, literal safe-integer k and absence of a
second corpus or authored exactness option. Sketch `87dc7144`'s semantic checker
has the four Carrier paths but restricts Relation IDs and public outputs to
strings. The current specification instead retains each side's semantic ID
type, so that old restriction is not an acceptance oracle.

`pipeline_typing/nearest_carrier_audit_test.mbt` covers 192 combinations of
Relation/Vectors on each side, independent string/number/decimal/ResourceRef
IDs and cosine/dot/l2. Each uses explicit side roles, preserving the current
corpus and separate query operand. The output continues through two aliases
of candidate ID, deletion of the first alias, and take. Query and candidate
contracts stay distinct, the two-component key retains its actual nearest
producer, and logical order remains rooted at that operation. Exact
work/node/text budgets and one-less failures are tested for every combination.

Twenty-four negative cases cover known dimension mismatch across all four
Carrier pairs, zero/fractional/unsafe k, Parameter-shaped k and an invalid
metric. Dimension failures preserve the query-vector source path. Existing
nearest suites separately exercise positional composite identities, unknown
roles, repeated operand edges, completion paths and alias invalidation.

The tests retain global identity uniqueness, exact scoring and contiguous rank
assignment as obligations. They do not compute scores or certify f32 numerical
conformance, actual identity uniqueness or capacity enforcement.

## Binary structural Graph acceptance audit

The structural-graph property-domain and subtraction laws were compared with
`graph_typing/structural` checking, shared dispatch and count transfer. Sketch
`87dc7144` only checks availability/merge shape before retaining the left shape;
the current implementation additionally joins both compatible property contracts
as required by the current specification.

`pipeline_typing/graph_structural_audit_test.mbt` adds 27 combinations of graft,
binary union and subtraction with independently produced empty/nonempty inputs.
Both node and edge upper bounds are checked through their respective row bridges.
Subtraction retains the left upper bound; graft/union use the sum. Nonzero bounds
do not become exact observed counts. Every case checks original producer owners,
ordered operand coordinates and exact/one-less work/node/text limits.

A further 24 combinations check joined nullable property domains on both node
and edge records, canonical label union and reversed operand order through both
bridges. Twelve field-set mismatch cases reject rather than filling a missing
property with null. Existing structural suites separately test authored numeric
and set strategies, endpoint-closure obligations and repeated binary operands.
These are static type/count checks, not evaluation of merge or subtraction laws.

The audit found and prompted correction of a source omission: Language's explicit
`union_graphs.with` nonempty-list rule and `operation-binding` left-fold rule.
`graph_typing/union_test.mbt` and `pipeline_typing/union_list_test.mbt` now exercise
ordered repeated operands, sequential property-bound widening, retained fold
obligations, ownership, late-reference diagnostics and shared budget boundaries.
The pipeline keeps one authored step and transfers node/edge count bounds to
both row bridges. Grammar and machine schema distinguish union's nonempty list
from binary graft/subtraction. These are static acceptance and propagation
checks; merge evaluation and canonical binary lowering remain outside this work.

`capacity_program_step/graph_union_test.mbt` checks the separate capacity boundary
for scalar, singleton and repeated-list union and both row bridges. Conditional
node/edge bounds propagate, but integrity-valid union Program claims (including
the same numeric bound) reject without their required checked Graph dependencies.
Row bridges likewise require their corresponding measure applications. Registry
membership, source hashing and conditional counts cannot replace those owners.

`capacity_program_step/graph_measure_test.mbt` separately checks explicit Graph
construction across empty/nonempty node and edge inputs, concise endpoint
completion, both row bridges and subsequent selection. Applications validate
actual input roles, unit conversion, source-law arithmetic and exact dependency
owners; same-valued foreign inputs and swapped node/edge/row measures reject.
Collection coverage retains all node/edge applications and their row sources.
Imported Graph measures preserve original producer ownership under exact/one-less
traversal budgets. `capacity_graph_preflight/input_bounds_test.mbt` additionally
connects validated external preflight node/edge bounds to both row bridges and
repeated structural union operands. Bounds retain the original input, pipeline,
policy and source-collection owner; equal CIDs from detached collections and
wrong measures are rejected. Imported Graph inputs follow their real producers
under cumulative traversal limits. This closes preflight-to-measure application
linkage, not enclosing Program identity or execution of the retained preflight.

`capacity_program_step/graph_structural_test.mbt` adds node and edge proof
applications for graft, scalar/list union and subtraction across empty/nonempty
inputs. Every case checks actual left/right owners, repeated occurrences,
collection closure, row-bridge consumption and exact/one-less operand budgets.
Subtraction uses only its left capacity bound without losing its right data
dependency. A 33-occurrence union checks retained duplicates and safe-integer
overflow rejection; matching conditional summaries do not bypass application
checks. This closes local structural count-law application, not graph value
admission, resource enforcement or complete source authority.

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
   Dedicated generator applications now bind values row occurrences, literal
   or bound time-series counts and Calendar civil-domain upper bounds to their
   actual input-free steps. Timestamp and step resolution retain the exact
   binding owner; empty intervals do not bypass step checks. Calendar bounds
   retain the selected profile and do not claim exact generated row counts.
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
   intermediate obligations. Transport now also covers set/nest/as-of left
   paths, semi/anti joins, asserted singleton cross joins, selections,
   non-expanding known factors, fixed windows, pooling on both input Carriers
   and calendar buckets. Expansion and generators still stop the walk; right
   resources, child-array sizes, singleton and key/profile validation remain
   separate. Parameter selection
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
   obligations remain separate. Lexical text_rank applications now apply its
   registered output law with query-only or corpus-dependent bounds, preserving
   both actual dependencies when the corpus reduces the factor. Score-zero
   filtering does not create an exact-count claim; profile, corpus, numeric and
   work/byte obligations remain. Ranking fusion applications now include all
   ordered input bounds, retaining RRF repetition and checking source/add laws.
   Global grouping clamps to k without an overflowing intermediate sum; grouped
   sums reject overflow. Indexed connections and explicit cumulative operand
   budgets bound the variable-arity work before allocation. Complete input and
   ranking validation obligations are retained. Join, cross-join and interval
   applications now retain both count dependencies and recompute kind-specific
   successful-output upper bounds, including empty sides and unmatched rows.
   They reject owner substitution and arithmetic overflow. A separate ordinary
   join refinement entry now uses the exact retained per-side candidate keys
   and authored cardinality, with conditional count arithmetic and empty-side
   precedence. Its application retains the key owners and assertion separately;
   key-producer validation and author-assertion enforcement are not discharged
   by the count calculation. Generic two-count proofs do not implicitly acquire
   these assumptions. Collection
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
   [Source-bound stage Result wiring](stage-results.md) now binds actual
   Program/stage Result definitions to their published projections and order
   origins, checks exact imported-input attachment and assembles every stage
   plus root exports. Foreign source maps, substituted producer publications,
   omitted stages and aggregate budget overruns reject. Root exports retain the
   exact named port without another projection. This closes static Result-edge
   ownership within that assembly, not ordinary/receipt Input admission,
   enclosing semantic identity, capacity or runtime publication evidence.
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
   [Sequence capacity consumers](sequence-capacity.md) now bind the Host-only
   per-key and total-output limits to an actual step, preserving distinct units,
   policy fields, candidate occurrences and enforcement obligations. Authored
   guards explicitly prevent using this incomplete source branch; they are not
   discarded when Host limits are tighter. The sequence collection entry now
   checks every local sequence, including unused branches, with exact owner
   matching and an isolated limit-consumption ledger. Dedicated collection
   completeness rejects unused limits. Complete source identity, upstream
   coverage and mixed consumer consumption remain required.
   Combined Graph/sequence consumer coverage now rejects unused mixed limits
   across those two supported families, requiring exact pipeline/source owners
   and selected policy identity. It preserves each scope's original bindings;
   remaining operation families and upstream closure are not certified by it.
   Join-family output limit consumers now match selected Host fields and all
   available registered local Program bounds to the exact checked join, cross
   join or interval join. Tighter Host limits cannot hide omitted proofs or
   authored guards. Author-source identity remains open; local limit application
   does not discharge execution obligations.
   Join application collections now cover every local join-family branch with
   one source/proof owner, reject omissions and duplicate applications, and
   retain exact consumption indices. The mixed consumer scan now joins that
   ledger with Graph and sequence, rejecting leftovers even after all three
   families are supplied. Other consumers and complete upstream/source closure
   remain required.
   Components now has separate input-node and output-row limit applications,
   an all-step ledger and integration into the same mixed consumer scan. An
   absent components ledger is rejected even when both limit artifacts are
   omitted or the operation is on an unused branch. Traversal node-pair and
   shortest-path selection bounds now have owned Program candidate applications;
   Traversal path/output limit consumers now bind the selected Host fields and
   all applicable registered node-output candidates, with an all-step ledger
   integrated into mixed consumption. Both emission modes and unused branches
   are covered. Join, components, traversal and sequence output applications now resolve
   atomically with downstream bounds: a private dependency-ordered table is
   sealed only after complete claim coverage and final candidate revalidation.
   Output proofs retain exact limit owners; candidate-dependent limits reject
   reconstructed tables. Sequence retains its two Host-only scopes without a
   Program-table dependency. Runtime enforcement is retained, not claimed as executed. Other output
   families and author-source identity remain open.
   Combined supported application coverage now runs source and consumer scans
   under one budget and requires the exact same Program application table for
   join candidates and source completeness. Unsupported sources and late
   consumer failures cannot produce a partial combined result. This composition
   does not establish external authority or enclosing Program/Invocation identity.
   An omitted join ledger now requires a budgeted all-step scan proving the
   absence of join-family operations. An empty limit collection is not proof
   that no operation requires a limit; regressions cover all three join families.
   Supported capacity application coverage now pairs every contextual producer
   visit with an exact-owner local result, including unused and repeated input
   occurrences. Its cumulative capacity work and detached result are tested on
   long forwarding chains. This closes occurrence coverage for that subset,
   not remaining source authority, unsupported consumers, Invocation binding
   consistency or the final all-obligation boundary.
   The occurrence closure now requires one independently selected admitted Host
   policy and checks every local policy CID against it, including empty limit
   collections and unused producers. Equal numeric ceilings do not hide policy
   drift. This closes selection consistency within that boundary, not Host
   authorization or enclosing semantic identity.
   Program application tables can now be checked against one bound guard
   context, requiring the exact retained Parameter collection for local
   binding-dependent proofs. Foreign producer entries are explicitly outside
   that local result. The capacity occurrence closure now requires the exact
   bound guard closure and performs each local comparison under its shared
   budget, including repeated and unused visits. Nonlocal proof-table entries
   now require validated producer coordinates, exact pipeline ownership and
   matching bound values in the same closure. Missing/foreign registrations and
   binding substitutions fail under a shared linear scan budget.
   Graph input dependencies now also resolve to the exact registered preflight
   owner, automatically for proof-local roots or through checked contextual
   coordinates for imported roots. Missing, duplicate and detached preflight
   registrations fail; repeated tables and dependency occurrences are charged.
   This preserves pending preflight enforcement rather than claiming execution.
   Enclosing
   Program/Invocation semantic identity remains unfinished; closure membership
   and owner-relative coordinates are not substitutes for that identity.
   Do not
   expand into acquisition, an evaluator or Host dispatch.
3. Connect contextual resolutions into a complete static checking/discharge
   boundary on main, as required by the
   [main/lowering ownership contract](pure-operation-checking.md#main-and-lowering-ownership).
   Lowering must consume this boundary rather than substitute its own integration.
   Completion requires an opaque validated Program result tying Program/stages,
   input roles, bound Parameters, contracts/policy, type/order/capacity decisions
   and producer dependencies together. Runtime obligations retain targets,
   application locations and dependencies; they are not static success flags.
   Persistent Program/stage/Invocation identities must come from their normative
   semantic projections, independently of internal ownership handles.
   This boundary remains unimplemented; documenting the division is not evidence
   that a formal Program compiler entry is ready.
   An [integrated pipeline context](pipeline-check-context.md) now runs order
   resolution, per-visit guard binding and supported capacity closure in one
   constructor with cumulative budgets and a shared internally created closure.
   It rejects foreign or missing late producer entries without exposing partial
   results. This closes manual assembly for that subset, not staged semantic
   identity, source authority or remaining static/profile/runtime obligations.
   The context now explicitly inventories static expression profile, pattern
   and Host-envelope requirements across every producer visit, including unused
   steps and unselected expression branches. Exact expression/node ownership
   and cumulative collection work are retained. Inventory is not discharge;
   operation-level obligations and validated resolutions remain required.
   Reference indexes can now bind exact declaration-owned Parameter values and
   emit the selected-name typed value preimage without a second projection tree.
   Repeated references and opaque literals retain their existing interpretation.
   This closes the local reference-to-value owner link, not completeness of all
   staged source slots or assembly of Program/stage/Invocation envelopes.
   Contextual Parameter binding now collects every local operation reference
   across producer visits and binds it using the values already owned by the
   context's guard closure. Expression-only and values-cell holes cannot escape
   because no guard requested their values. Cumulative work includes the earlier
   context, and late missing bindings expose no partial success. Local source
   coordinates remain distinct from whole staged Program collection.
   The existing source-bound all-stage operation collector now attaches one
   complete declaration-owned binding set to both stage-local and combined
   Program-coordinate indexes, under a cap including prior collection work.
   This prevents per-stage binding substitution in that collection; joining it
   with checking contexts and the remaining non-operation slots is still required.
   Stage-context attachment now requires the exact all-stage operation and
   Result owners, one checked context per stage, common selected value ownership
   through all producer visits and a common verified policy CID. Shared prior
   operation collection is charged once, alongside Result/context costs. This
   joins these results without certifying input/import contracts, static
   discharge or the still-missing complete Program semantic envelope.
   Incremental construction can now reuse resolved-order owners in pipeline
   contexts and retain previously checked Results in source-bound stage
   collections. Producer ports can therefore be prepared before consumer
   checking without reissuing either owner for later assembly. Both reuse
   paths validate source/closure correspondence and include prior costs; the
   final wiring-to-context attachment now requires the same prepared source and
   each stage's exact published order owner. It retains validated Result imports
   and root exports with stage contexts, charging shared prior order costs once.
   Stage source attachment also checks the exact input-name set, including
   unused inputs, without requiring source map enumeration order. It rejects
   omitted or invented names under the shared collection work cap; Carrier and
   input evidence semantics still need the corresponding admission boundary.
   [Local Relation input declarations](local-relation-input.md) now read explicit
   source schema, open expected-column assertions, conditional primary keys and
   duplicate-policy terms without inventing complete types or runtime proof.
   Source-slot attachment now reads all local Relation declarations of an actual
   stage and requires their exact Carrier/key registration owners in its checked
   pipeline. Result/receipt imports stay separate, and unsupported local forms
   reject rather than vanish. Host assertion reconciliation, duplicate total-order
   resolution and other Input families remain unfinished. Source-only local
   attachments now join WiredStages with exact all-stage collection owners,
   shared-cost accounting and aggregate local source limits. A real local input
   followed by a Result-importing stage exercises this path, without claiming
   Host/receipt admission, static discharge or final Program readiness.
   Local schema assertion comparison now preserves a supplied stronger complete
   checked schema after recursive assignability, expected-column and newly known
   key/order-type checks. It is not snapshot source/CID/Host admission and is not
   accepted by the source-only registration path as if it were such evidence.
   Stage-local schema reconciliation now checks partial supplied sets against
   exact prepared declarations with shared budgets, retaining absent evidence
   explicitly and rejecting unknown/duplicate selectors. Its opaque result is
   still type-assertion evidence, not external snapshot admission or a stronger
   input registration accepted by the Program assembly.
   [Staged local source references](local-source-reference.md) now have a pinned
   canonical selector grammar and bounded codec with independent fixed vectors.
   Source resolution now indexes one actual staged Program and resolves batches
   to immutable source slots, preserving original diagnostics and rejecting
   unknown/nonlocal/duplicate selectors with shared work/text budgets. Snapshot
   body/environment admission remains necessary; a resolved source location is
   not an authenticated input owner or a stronger pipeline registration.
   A two-stage actual Result import tests final publication ownership, foreign
   reissued orders and exact/short cumulative budgets. Ordinary/receipt inputs,
   static discharge and complete semantic Program identity remain incomplete.
   [Combined order checking](combined-order-checking.md) now resolves
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
