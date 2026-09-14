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
and whole retained candidate-key completion are connected through the shared
key boundary; actual uniqueness and first-place tie checks remain obligations.
The [sequence checker](sequence-typing.md) shares predicate budgets across pattern
slots and retains typed event identities in its match-output contract.
The [Calendar boundary](calendar-checking.md) admits source options and binds
validated transition tables to selected byte/release pins with exact zone lookup.
Its real selected-zone release fixture is pinned and reproducible. Calendar
operation/pipeline checking requires that admitted profile. Independent boundary
vectors are fixed and checked against a separate table-inversion oracle.
Logical-order and resolved resource proofs belong to the shared pipeline and
capacity boundaries; admitting a Calendar profile alone establishes neither.

Use a typed Carrier sum with Relation, Graph, Events and Vectors variants, not a
Carrier string attached to an otherwise untyped object. Retain recursive value
contracts and semantic roles: graph node identity, node/edge property domains
and labels; event identity/time/payload; vector identity/components/dimensions;
Relation field provenance. Carrier transformations follow the explicit bridges
and the semantic macros permitted by Language, never an implicit reinterpretation.

Keep field knowledge, field-set completeness, recursive type evidence, candidate
keys, logical order, window roles, score contracts and resource facts separate.
The [Relation key boundary](relation-evidence.md) retains declared input identity
with its admission obligations; it does not replace runtime validation with a flag.
Its validated combined-input boundary retains keys and ranking annotations on
the same immutable Relation contract without conflating their obligations.
The [conditional row-count pass](row-count-evidence.md) connects known generator
counts to implemented unary and binary Relation laws, keeping exact counts,
upper bounds and unresolved execution obligations distinct.
The [conditional logical-order pass](logical-order.md) retains ordered generator
origins and supported preserving edges independently of candidate keys.
The [contextual order resolver](contextual-orders.md) checks all pipeline steps
atomically, sharing budgets across aggregate and nest resolutions and rejecting
unresolved static consumers even in unused branches. External evidence admission
and combined order/capacity/publication discharge remain required.
The [Result publication-order resolver](result-publication-order.md) now applies
the declared priority to inherited order, eligible keys and projected-field
fallback while retaining execution obligations and unresolved authored ties.
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

## Main and lowering ownership

The pre-lowering Program integration boundary is a completion condition of
**main**, not work delegated to the lowering branch. Main must construct one
consistent static result for the authored Program and stages: inputs, Parameter
bindings, selected contracts and policy, types, order strategies, capacity
applications and their producer dependencies. The result must be opaque and
constructible only through validation; a public aggregate of checker results or
`validated: true` does not satisfy this boundary. The public
`program_check.check` constructor returns the opaque `CheckedProgram`; consumers
use its read-only interfaces rather than assembling or sealing component results.

The [Checked Program construction contract](checked-program.md) fixes the entry,
success conditions, exhaustive obligation coverage and lowering reads. Integration
proceeds through small complete Programs under that contract; additional partial
checked types are not a substitute for exercising the final entrance.

Static unresolved requirements must prevent successful construction. Runtime
obligations remain explicit, with their protected target, application location
and required dependencies attached. Actual uniqueness, observed row counts,
acquired-value validation and limit enforcement can remain runtime checks;
that does not permit deferring static input, type, order-strategy, bound-source
or binding inconsistencies. Nor does inability to observe runtime data at Check
justify rejecting an otherwise admitted operation.

Program, stage and Invocation semantic identities must be separate from process
object identity and owner-relative `checked-step:<index>` handles. Main must
bind the actual semantic projections and envelopes, not substitute a fixture
identity or a hash of a local pipeline. Internal ownership remains useful for
preventing mismatched checker results, but is not persistent identity.

Lowering consumes this completed boundary through read-only APIs. It translates
the selected semantics and runtime obligations to execution nodes and explicit
checks/failure behavior, verifies representability under the selected registry
and backend, and validates the generated Plan's structure and identity. It must
not re-infer keys/order, combine unrelated checker results, or independently
implement the Program integration boundary. Unsupported obligations or
operations prevent creation of an executable Plan.

During parallel development, lowering may test node construction and limited
operation lowering with existing checked-operation APIs. Such entry points are
internal, not the formal Program compilation interface. Lowering requests any
missing read-only APIs; formal integration waits for the main boundary. Final
Plan integration is a separate downstream check, not evidence that main's
static boundary has already been completed. This division does not add actual
lowering, evaluation, acquisition or Host dispatch to main's current scope.

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
The pre-lowering review must also verify that a lowerer consuming the integrated
result need not guess or re-decide ActQL semantics, and that it can locate every
retained runtime obligation and dependency without reconstructing checker
ownership or inventing identities. Static readiness is neither execution nor
authorization to execute.
The [historical audit](../reviews/pure-operation-audit.md) preserves earlier
findings. Its implementation-status notes are not a current support matrix or
completion certificate; completion requires the current-state checks above.
