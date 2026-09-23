# SGA, VecA, and TEA Local execution gaps

Baseline: `0886df5ab75ff77edcd68291470f487346fc1cc4`.

This is a live implementation ledger, not a completion claim. The machine
readable coverage manifest is authoritative for individual operation status.

## Shared blockers

| Area | Baseline state | Required closure |
|---|---|---|
| Canonical AoA | Closed: the selected registry contains the complete fixed family set and typed variable-arity contracts | Preserve the selected registry, AoA profile, CIDs, pins, and independent vectors during implementation |
| Lowering | Closed for inventory coverage: all 39 normative entries have contract, checker, and typed canonical lowering evidence | Preserve checked meaning and reject unsupported runtime variants before execution without frontend rediscovery |
| DAG inputs | Closed: the common captured DAG, managed request, dispatch, cancellation, and cleanup paths retain ordered input positions without a two-input ceiling | Preserve edge position, producer port, binding, ownership, and accounting as family execution is connected |
| Completion | Closed for operation coverage: all 39 entries use the shared Carrier-aware lifecycle with registered lifetime evidence | Preserve exact owner, generation, view, and independent release rules while closing the shared release gates |
| Runtime material | Closed for operation coverage: all 39 entries retain their Carrier laws through bounded immutable or managed shared storage | Preserve storage meaning, admission, holding, and reclamation while closing the shared release gates |
| Progress | Long principal paths use bounded sessions and each operation has a checked production route | Prove operation-specific boundary evidence and the remaining common cancellation boundary |
| Cancellation | Closed for the 39 operation entries; in-flight RelA execution after a mixed Carrier/Relation split remains a shared gap | Preserve stop/reclaim separation while closing the common evaluator boundary |
| Packaging | Closed: the RelA-only artifact and each family provider have verified transitive imports and generated artifacts | Preserve the artifact gate whenever runtime or provider imports change |
| Publication | Closed for operation coverage: every applicable Effect-free Relation result and Carrier projection uses the formal publication path | Preserve publication preflight, exact identity, custody, retrieval, and failure behavior |
| Differential conformance | Closed: all 29 RelA operations are classified and the six registered overlapping Local/DuckDB scopes require same-program execution, canonical comparison, and independent expectations | Preserve the operation-indexed manifest and extend it whenever a second registered implementation gains formal scope |
| Resource accounting audit | Incomplete: all 68 operations are bound to profiles and checked production routes, but operation-specific exact/one-short/cancel/cleanup evidence is not yet complete | Bind executable boundary fixtures to every production route |

## Current cross-operation review gaps

- Mixed Carrier/Relation stages: selected and fused-prefix Graph, Events, and
  Vectors paths now connect to a Relation filter and two actual consumers in
  the standard Host. The fused prefix retains one checked owner and an exact
  terminal output step. Selected derive bindings now use a bounded session;
  a multi-step checked sequence can stop during binding evaluation without
  publishing partial rows. Filter, select, and take still use synchronous
  selected evaluation. Environment-delivered cancellation across this split
  and cross-task failure/cleanup combinations remain unverified. These are
  connection gaps, not new normative operations.
- Resource accounting: the 68-operation gate now checks each production
  dispatch marker and entrypoint symbol as well as the family profile. It does
  not yet prove each operation's own exact, one-short, cancellation, and
  cleanup evidence. A passing route gate alone is not completion evidence.

## Local family correction branch

The following fixes are committed after the `8cae50b6` common baseline. They
close specific correctness and cleanup findings, not the shared blockers above.

| Commit | Corrected boundary | Product evidence |
|---|---|---|
| `4ad05dca8` | Exact structural pairwise mean, rounded once | Independent midpoint vectors and three-target SGA tests |
| `d1b7bb9ac` | Typed Relation and Events grouping order | Three-target grouping and Carrier regressions |
| `8ab36b721` | Minimum eligible simple path after hop and predicate checks | Three-target SGA and Graph standard-Host regressions |
| `f0cbb4ebd` | Both VecA nearest inputs admitted before pairing, including an empty opposite side | Three-target VecA and Relation/Vector input regressions |
| `1d1714058` | Exact window membership with separately checked output boundary | Independent boundary vectors and three-target Relation/Events regressions |
| `7c16ee15b` | Q1–Q4 language, machine contract, dependency pins, and independent vector wiring | Local contract and documentation gates |
| `46ef37b72` | Graph mean skips properties of edges whose endpoints are not retained | Retained-versus-excluded edge regression and three-target Graph integration |
| `82d505432` | Session validates global event identity before grouping and rejects empty input | Relation-input duplicate/empty regressions and three-target Events integration |
| `1098d32bf` | Graft retains terminal nested-set cleanup responsibility | Terminal nested failure regression and three-target Graph integration |
| `3880522c8` | Common DAG retains a fused Carrier prefix and selects later Relation steps | Typed physical split and generated-prefix boundary tests |
| `9317ec2bb` | Graph, Events, and Vectors fused prefixes reach row consumers | Standard Host value, identity, two-consumer, and reclamation regressions |

At source HEAD `1098d32bf`, the scoped SGA/Graph suite passed 140 tests per
target and the TEA/Events suite passed 31 tests per target on JS, Wasm, and
native. `check:docs`, the generated public API gate, and
`check:local-family-coverage` also passed locally at that HEAD. These results
do not establish Linux CI, all 68 route-specific resource boundaries, or the
remaining mixed-stage cancellation boundary.

At source HEAD `9317ec2bb`, query integration plus the generated-sequence
boundary tests passed 554/554 on each of JS, Wasm, and native. The public API
gate also passed locally. The new fused-prefix fixtures establish the named
Relation identity but do not replace publication retrieval or in-flight
cancellation evidence. No Linux CI result is claimed for this HEAD.

The following snapshot is generated from the authoritative manifest. It is
checked by `check:local-family-coverage`; do not edit its counts by hand.

<!-- local-family-coverage-summary:start -->
| Coverage state | Count |
|---|---:|
| `contract` | 39/39 |
| `checker` | 39/39 |
| `lowering` | 39/39 |
| `kernel` | 39/39 |
| `managed` | 39/39 |
| `standard_host` | 39/39 |
| `consumer_lifetime` | 39/39 |
| `resources` | 39/39 |
| `cancellation` | 39/39 |
| `publication` | 39/39 |
| `three_targets` | 39/39 |
| complete operations | 39/39 |
| open operations | 0/39 |
<!-- local-family-coverage-summary:end -->

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

## Review findings closed after `bc391b3e`

Commits `3c381d6e0`, `8672bbd7a`, `f337ee951`, and `1b317fe90`
close the four concrete execution-boundary findings.

- Interval join charges each explored pair exactly once before key or temporal
  evaluation. Exact and one-short work limits remain invariant under
  single-work resume quanta.
- Sliding windows reject a binary64 backward grid step that does not decrease
  the current coordinate. Fixed and sliding cases around `2^53` and `2^54`,
  with positive and negative clocks and steps 1, 2, and 4, terminate under
  single-work resume quanta on every portable target.
- Sequence predicate-cache rows and cells are initialized only inside bounded
  resume phases. Cancellation can arrive before or during initialization, and
  cleanup clears predicate cells and every retained partial or completed match
  position.
- Shortest-path node and edge identity arrays preflight their structural value
  node lower bound, construct one element per bounded step, and retain the
  recursive runtime-value check. An insufficient value limit rejects the path
  before any identity element is constructed.

The operation-indexed RelA differential gate covers its registered overlap.
The resource-accounting route gate remains useful but needs operation-specific
boundary evidence before it closes the broader release check.

## Closed focused Local and DuckDB semantic review

Commits `4c0dbff79`, `1fc115323`, `985ed20f5`, and `9902dbead`
close the concrete placement-parity findings from the focused review.

- Managed sort and take run the same null placement, descending, offset,
  ordinal-tie, and UTF-16 corpus through Local and real DuckDB execution.
- Filter comparison covers `=`, `<>`, `<=`, and `>=` over nullable numbers,
  including a bound NULL parameter, from one checked owner.
- Decimal join covers scale equality, precision 38 boundaries, negative zero,
  large values, and empty input on Local and DuckDB.
- Group keys cover compound text, NULL, ASCII case, supplementary Unicode,
  and BMP/private-use boundaries while the DuckDB session uses a hostile
  `nocase` collation. Generated SQL groups text by encoded bytes and orders
  results with the ActQL UTF-16 comparator.
- `null_key: fail` returns the same typed failure for Local memory input and
  the retained DuckDB import path.
- Join SQL orders by explicit imported ordinals. Retained row wires without
  that physical column re-enter the checked parameter importer, which appends
  the admitted row ordinal. Resident views expose their immutable stored rowid
  as that ordinal and never derive it with `row_number() OVER ()`.
- The managed retained Host checks the exact join and downstream count CIDs at
  the formal custody boundary. Internal completions that have no identity
  requirement keep their specified delayed-identity state.

The focused corpus passes on JS, Wasm, and native, and the real DuckDB Node
tests cover the corresponding SQL paths. This closes E1 through E6 from the
review.

## Closed operation-indexed RelA differential gate

The release manifest
`docs/reviews/2026-09-23-rela-differential-coverage.json` classifies every one
of the 29 normative RelA operations. The registered overlapping scopes are
`filter`, `select`, `sort`, `take`, `join`, and `group`. Each names its exact
supported scope, Local and real DuckDB fixtures, an independently authored
expectation, and the observations it covers. A projection or expression used
only inside another admitted physical plan is not misreported as a complete
second implementation of its author-visible operation.

`check:rela-differential-coverage` derives the operation inventory from the
fixed RelA manifest, rejects missing classifications and missing independent
oracles, verifies every fixture remains connected to source, and requires
coverage for values, order, NULL, text identity, decimal, duplicates, empty
input, failures, exact resource boundaries, and Named Result identity. The
focused real DuckDB run executes all ten registered Node comparisons.

## Resource-accounting route gate and remaining boundary evidence

The release manifest
`docs/reviews/2026-09-23-local-resource-accounting-audit.json` binds every one
of the 29 RelA and 39 family operations to a reviewed implementation profile.
Each profile records its work unit, cumulative ceiling, temporary, retained,
and peak scopes, maximum noninterruptible step, stop observation point, and
cleanup owner. It separately inventories prepare, resume, ordering or hashing,
value construction, finalization, cancellation, and cleanup. Fixture evidence
is required for admission before allocation, charged bounded work, finite stop
observation, overlapping lifetime and peak accounting, and cleanup ownership.

`check:local-resource-accounting` derives both operation inventories from the
authoritative manifests, rejects missing or duplicate bindings, verifies every
source and fixture, checks 68 dispatch-to-entrypoint routes, and requires every
accounting facet for every profile. It
also requires operation-specific RelA performance evidence and the resources
and cancellation layers for every SGA, TEA, VecA, Bridge, and VecA-expression
entry. The negative suite proves that omitted operations or routes, missing
facets, disconnected profile fixtures, and unknown profiles fail. It rejects a
missing entrypoint or dispatch marker. The gate does not yet prove that a
boundary fixture exercises every operation's exact and one-short limits,
cancellation, and cleanup.

## Closed review findings after `15d759ac`

Commits `8da406996`, `30b18fa67`, `5dcc77be4`, `b97b7f3a7`, and
`5b91dc2c7` close the fixed review findings without changing the Local
milestone boundary.

- The graft and mean fixtures use valid typed row sources. Workers and Node
  Host generated fixtures are synchronized from their pinned generators.
- DuckDB logical cell accounting excludes its owned physical ordinal, retained
  diagnostics distinguish semantic file validation from physical inserts, and
  count-group transport uses collision-free physical aliases while preserving
  case-distinct logical names.
- Path traversal validates its exact Graph operation edge before storage
  access and readmits Relation selector values under the Graph identity
  contract. Nullable non-NULL identities therefore match required identities,
  while NULL and missing identities fail before traversal.
- Paths are emitted by canonical start identity, then hop count, node identity
  sequence, and edge identity sequence. The regression covers every ordering
  of the review graph's three relevant edges and quanta 1, 2, 32, and 256.
- Start selection, simple-path membership, path copying, path comparison, and
  node/edge value construction are resumable charged phases. Frontier transfer
  is an owned pointer swap with explicit slot accounting. Structural row and
  array bounds are checked before builders allocate or append rejected items.
- Cleanup cancels nested predicate execution and clears every private selector,
  frontier, pending path, row, and value-builder owner. The diagnostic reaches
  zero while an independently accepted output remains outside private state.

The complete Graph integration file passes 86 tests on each of JS, Wasm, and
native at `5b91dc2c7`. These focused results do not replace the final same-SHA
Linux CI or close the broader resource-accounting release gate.

## Closed review findings after `4f84dec2`

Commit `6d9affad` closes both ownership findings from the fixed review.

- A failed Graph or record append closes further writes without discarding
  cleanup custody. Cancellation still clears every private array and map,
  releases live workspace and retained-value usage, and remains retry-safe.
- A bounded session retains an unaccepted completed result when a later stop,
  invalid report, or counter overflow rejects the step. Cleanup disposes that
  result before its private state, and a disposal failure remains visible and
  retryable. A result accepted by the caller transfers custody exactly once.

The regressions cover duplicate, malformed, value, work, and workspace
failures; repeated cancellation; post-step cancellation; invalid reports;
counter overflow; disposal retry; and accepted handoff. Related tests pass on
JS, Wasm, and native. Full JS passed 5,061 tests at that commit.

Commit `2fc8defe` connects the type-erased Carrier completion occurrence to
the common physical graph. It verifies exact ordered producer edges, retains
the admitted output allocation, and revokes graph references with the common
output lifetime. This does not by itself complete standard Host Carrier
selection or environment yielding.

Commits `8a05ec82`, `f32279b2`, and `efa68e75` add the next shared dispatch
boundary.
Graph, Events, and Vectors producer reads expose read-only structural views
bound to the exact use-site reference without exporting family storage
handles. Local providers can opt into one ordered input array containing
Relation reads and Carrier views; existing providers remain Relation-only and
reject Carrier substitution before start. The common runtime imports no
family kernel package, so this does not weaken artifact isolation. A
family-neutral material retains exact typed storage custody, issues an
independent view for each checked consumer edge, and delegates final
reclamation to the owning family runtime without exposing its storage handle.

The view/runtime suites pass 18 tests and the existing providers plus query
integration pass 394 tests on each of JS, Wasm, and native. Later common and
Node dispatch plumbing accepts retained Carrier completions and mixed ordered
inputs. No product standard-Host fixture yet carries one Carrier completion
across a physical task boundary into its checked consumer, so that end-to-end
path remains open.

Commits `adfcfede` and `ce088605` connect the first provider through the common
configuration and standard Host. Provider cleanup must confirm reclamation
before common task cleanup proceeds; a false result remains retryable. The
Node adapter yields through the environment event loop between bounded steps,
then requests cancellation, observes stop, and retries cleanup separately.
The exact rows-to-Events, watermark, and Events-to-rows sequence reaches two
real downstream Relation computations and final ledger reclamation. These
commits do not complete other sequences, standalone Carrier outputs, or formal
publication.

## Closed review findings after `505a21e4`

Commit `26951d0e` closes both lifecycle findings from the fixed review.

- SGA normalize and graft, plus VecA normalize and score, now match every
  input read against the exact checked consumer step, edge position, and
  resolved producer target before allocating output state.
- Unpublished completed Graph and record payloads remain under owner-bound
  cleanup after read availability is revoked. A failed disposal remains
  retryable, while successful reclamation occurs exactly once.

The regressions include an operation whose exact external source is Input 1,
reordered binary Graph inputs, unavailable completed payloads, disposal retry,
and prior internal-step matching. The affected lifecycle and kernel suites pass
52 tests on each of JS, Wasm, and native.

Commit `c17589cc` bounds the two-site Host failure diagnostic before any opaque
execution graph is formatted and refreshes the generated Workers fixture from
the canonical helpers. The real two-site DuckDB Host test passes, and the
Workers adapter passes all 24 tests. These focused results do not replace final
same-SHA Linux CI.

## Closed review findings after `550a7f3a`

Commit `d3080fa9` closes both explicit Graph construction findings from the
fixed review.

- The canonical expansion projects the selected node and edge branches,
  performs deterministic source and target endpoint closure against the
  explicit node universe, and only then invokes `BRIDGE.rows.to_graph`.
  The Local bridge applies the same closure law instead of hiding a different
  interpretation in its kernel.
- One typed expansion descriptor now drives preparation accounting, canonical
  occurrence enumeration, and encoding. Preparation admits the additional
  nodes, references, names, and work before emission while retaining repeated
  logical input occurrences.

The regressions cover absent and present endpoints, selected properties,
repeated node and edge roles, exact and one-short limits, re-admission, and
agreement between canonical expansion and Local execution on JS, Wasm, and
native. Commit `b7e1df7e` records that evidence in the coverage manifest.
Commit `f37b3714` also prepares stable node and edge projection descriptors.
Each branch emits a shared physical field once while preserving distinct
source, target, label, and input-position roles. Self-loop construction and
the revised exact budget boundaries pass on all three targets.
Concise endpoint-derived construction, formal publication, and environment
cancellation delivery remain separate open requirements.

## Closed review findings after `d49191b9`

Commits `f37b3714`, `2bf2499d`, and `c62ce4f2` close the three fixed
review findings without expanding the Local milestone.

- Explicit Graph construction deduplicates each physical projection branch
  while retaining distinct logical Graph roles and repeated input positions.
- Session identity construction is resumable, bounded by the admitted value
  ceiling, and clears partial buffers during cancellation cleanup.
- Delayed identity issuance marks the exact requirement as establishing
  before invoking Host code. Same-requirement reentry is rejected, failed
  transitions are cleared, and established CIDs remain monotonic.

Focused JS, Wasm, and native suites pass for Graph lowering, Local TEA, and
managed completion. Full same-SHA acceptance and Linux CI remain pending.

## Closed review findings after `b460132b`

Commit `2924d72b` closes the as-of provisional-tie finding. Candidate rows are
not allowed to fail an equal-ranked tie while a later row can still become the
unique better candidate. The final selected class alone is checked for an
unresolved tie. All candidate permutations and the standard Host
counterexample preserve the registered result and failure order on JS, Wasm,
and native.

Commit `047d0bd1` moves retained-output admission, Result view preparation,
stable ordering, and logical identity scans into resumable finalization. The
Node Host yields between bounded steps, so cancellation can be delivered
during finalization. Cancellation closes unfinished admission, view, and
identity state without publishing a completion; stop confirmation and
resource reclamation remain distinct.

Commit `01bb5876` exercises the compiled Node Host with two Named Result
aliases. It delivers cancellation after the first identity has completed and
while the second Result view is still being finalized, then observes stop and
complete reclamation without accepting a partial completion. The test records
delivery and stop times without imposing a universal wall-clock threshold.

The finalization regressions cover output re-admission, cancellation from a
real timer, unchanged ordered Result identity, no completion publication after
cancellation, and final ledger reclamation. The affected execution and
query-integration suites pass 1,100 tests on each of JS, Wasm, and native. The
retained boundary passes 232 tests, the Workers adapter passes 24 tests, and
tracked public interfaces agree across targets. These focused results do not
replace final same-SHA Linux CI.

## Closed review findings after `241fad7b`

Commits `a786e1b0` and `248307a4` regenerate the Workers conformance package
from its current query-integration sources, including the finalization
boundary fixtures added while closing this review. The freshness check and all
24 Workers tests pass, including the workerd execution cases.

Commit `7022c6f5` makes every managed finalization phase respect the caller's
work quantum. Retention, identity export, issuer construction, completion,
identity establishment, and deadline checks now retain explicit progress.
Cancellation revokes a completed generation that has not been published. The
Node adapter validates continuation and terminal reports before acting on the
completion flag.

The finalization fixtures cover zero-row output, 31-row output, and quanta 1,
2, 31, 32, and 33. Invalid terminal reports cover over-limit and negative
work, negative progress, Number work at a BigInt boundary, and missing
progress. Query integration passes 396 tests on each of JS, Wasm, and native;
the Node adapter suite passes 14 tests.

Commit `249decd8` rechecks the completed source at every resumable Named Result
view boundary. Loss during projection mapping, row-map construction, merge
sorting, or after stream preparation closes only the private preparation and
returns unavailable before more bounded work is charged. The execution
relation suite passes 709 tests on each portable target.

These fixes close the three findings in the fixed review. They do not change
the family layer counts above or replace final same-SHA Linux CI.

## Closed review findings after `7143be63`

The literal selector membership finding was already closed after the reviewed
SHA by `e48f65f6`. Literal and Relation selectors retain their typed values,
mark every matched identity, and fail the operation if any requested identity
is absent. This check finishes before edge selection or output completion.

Commit `c26b567b` keeps each raw Graph producer read beside its immutable
storage during graft, exact union, and structural subtraction. Every bounded
resume, including the final handoff, rechecks all exact reads before touching
storage. A successful copy owns an independent output generation and does not
retain a permanent dependency on its inputs.

Commit `d4a42cd2` constructs subgraph output in declared-node mode regardless
of the source construction representation. A valid derived-endpoint Graph can
therefore retain a selected isolated node even when no selected edge remains.
The focused Local SGA tests pass 22 tests and the affected provider and query
integration selection passes 445 tests on each of JS, Wasm, and native.

The stale Workers finding is also closed by canonical regeneration in
`2a2f385f`; the read-only generator checks and all 24 Workers tests pass. These
focused results do not replace final same-SHA Linux CI.

## Family execution gaps

### SGA

All 17 author-visible operations are accepted by frontend typing.
All seventeen SGA operations now have typed canonical lowering: `normalize_graph`,
`match_nodes`, `match_edges`, `components`, `graph_bounds`, `degree`,
`graph_diff`, `graft_graph`, `union_graphs`, `subtract_graphs`, `graphs_equal`,
`apply_graph_delta`, `mean_graphs`, `reach`, `subgraph`, `traverse`, and
`shortest_path`. Match lowering retains checked
predicate field bindings and authored projection order without frontend rediscovery.

Commits `16573673c`, `83df880a5`, `8d730cf95`, and `050469b0b`
close `graph_diff`. Canonical snapshot construction, tuple sorting, equality,
action materialization, and cleanup advance under bounded work and admitted
workspace. The standard Host fixture exercises nonempty node and edge add,
remove, and update sets through two overlapping consumers on JS, Wasm, and
native. The same path establishes the independently derived Named Result
identity. Cancellation after partial snapshot work confirms stop separately
from cleanup and reclaims the unpublished output without revoking either
input.

Commits `7e608333e`, `b5cd1a0d2`, and `098f29445` add the atomic
`apply_graph_delta` kernel and its managed provider path. Lowering retains the
typed delta field and Graph contract identity. The kernel verifies the exact
base snapshot CID, Graph contract CID, ordered unique actions, before-value
preconditions, and target snapshot CID before exposing a completed Graph.
Empty and nonempty node, edge, and property changes run with single-work
quanta on JS, Wasm, and native; cancellation stops independently of cleanup.

Commit `d3877af58` closes the standard Host boundary without adding a hidden
provider-local Relation channel. One formal task completes `graph_diff` as an
exact retained Relation; the following task rebuilds the base Graph from its
typed Relation input and consumes that exact delta as its second input. The
applied Graph reaches two overlapping downstream Relation consumers and the
formal Named Result publication path on JS, Wasm, and native. Independent
release and retryable cleanup return execution, retention, and held-byte
ledgers to zero. `apply_graph_delta` is complete.
Reach retains its typed start identity, direction, and finite depth.
Subgraph retains explicit, predicate, and Relation selectors as distinct typed
forms and preserves its optional edge predicate.
Traverse retains homogeneous and patterned hops, selector form, predicates,
emission mode, bounds, and the resolved output guard.
Shortest path retains scalar and selected endpoints, repeated selector input
positions, selection policy, direction, bounds, labels, weight, and guard.
At `757705ba`, the scalar, unweighted `each_pair` path executes as a bounded
kernel through the standard Host. The portable tests cover exact managed Graph
input binding, pre-allocation workspace rejection, cancellation observation,
cleanup, two overlapping Relation consumers, and final reclamation on JS,
Wasm, and native. The capacity fixture now includes the exact shortest-path
program candidate instead of relying only on the Host ceiling. At that
revision, selected endpoints, `nearest_per_source`, `nearest_pair`, edge-type
filtering, weighted costs, and canonical equal-cost tie resolution were open.

At `457e1886`, every admitted adjacency segment is sorted by semantic node
and edge identity before the bounded breadth-first search. Equal-hop choices
therefore no longer depend on physical edge enumeration. Merge scratch and
path reconstruction arrays are included in pre-allocation workspace admission;
exact and one-short boundaries pass on JS, Wasm, and native. At `77a0bed4`,
omitted, explicitly empty, and finite `edge_types` are distinct. Degree and
CSR phases compare one authored label per bounded step. Match, later-list
match, miss, and empty cases reach the standard Host, two consumers, and
three portable targets; the matching case also establishes and retrieves its
formal publication identity. At `8023b17d`, incoming, outgoing, bidirectional,
and source-equals-target zero-hop paths reach the standard Host and overlapping
consumers on all three portable targets. The incoming case also establishes
and retrieves its formal publication identity. At `43b173aa`, explicit
nonempty identity sets are resolved before search, deduplicated, and sorted by
semantic identity. Their Cartesian endpoint pairs run through one bounded
managed session. Missing identities fail before search; exact workspace
admission, two overlapping consumers, formal publication, and JS, Wasm, and
native execution are covered. At `c23d7db5`, Relation-backed source and target
selectors retain their distinct ordered input edges even when both positions
refer to the same material. Repeated rows resolve to one canonical endpoint.
Checked node predicates use bounded expression execution over typed Graph
bindings. Both forms reach the standard Host, formal publication, two
overlapping consumers, final reclamation, and all three portable targets.
At `b69cfba4`, the unweighted kernel also executes `nearest_per_source` and
`nearest_pair`. Canonically ordered endpoint iteration resolves cross-pair
ties after hop count, and retained best-path storage is admitted before
allocation. Empty predicate selections complete with zero rows and zero
physical output capacity. Exact workspace rejection, bounded execution,
standard Host consumers, formal publication, and all three portable targets
are covered. At `5060af20`, weighted execution validates every admitted edge
before search and enumerates simple paths within the authored hop bound. It
folds costs in path order, keeps overrange internal and absorbing, and selects
by cost, hops, then canonical node and edge identity. Selected overrange paths
fail atomically, while a nonselected overrange candidate does not fail a finite
selection. Equal-cost paths, all selection policies, zero-hop paths, exact
workspace admission, cancellation, standard Host consumers, formal
publication, and JS, Wasm, and native execution are covered. `shortest_path`
is complete for the fixed inventory.
Union and mean preserve their ordered finite input lists,
including repeated positions, as one operation occurrence. Structural
operations retain checked property laws. Basic operations preserve direction,
component policy, resolved guards, and bounds. Delta application retains its
exact produced input and selected field. Normalize now copies an exact managed
Graph input into an independently retained managed Graph generation through
bounded work units. The registered Graph provider now runs that generation
through the formal Graph-to-Relation Bridge, two Relation consumers, and final
reclamation on all three portable targets. A real environment timer also
delivers cancellation during normalization, observes stop, and completes
cleanup without exposing a partial generation. The standard Host now keeps one
normalized Graph generation live across a second bounded normalization and a
formal Graph-to-Relation Bridge. The same-Carrier consumer finishes and releases
its independent output while the bridge's earlier read authority remains valid;
the resulting Relation then reaches two independent consumers and the formal
Named Result publication path on JS, Wasm, and native. `normalize_graph` is
complete.
Graft consumes two exact positioned inputs, preserves a
repeated material occurrence, collapses an equal declaration, and rejects a
conflicting payload atomically. Their portable tests cover pre-allocation
limits, kernel cancellation observation, and managed Graph generations on JS,
Wasm, and native. The registered provider now accepts two common read-only
Graph Carrier views, preserves their exact operation-edge bindings, and runs
the bounded graft output through the formal Graph-to-Relation Bridge. The
provider now also executes two ordered Graph construction steps before graft,
keeps both exact source generations until the graft output takes custody, and
then reclaims them independently. The portable standard Host carries the
grafted Graph through the formal Relation Bridge, overlapping consumers, and
Named Result publication and retrieval on JS, Wasm, and native. The Node Host
delivers timer cancellation during graft, confirms stop, completes cleanup,
and returns the ledger to zero. At `867489fb`, the affected portable suites
pass 412 tests per target, the real Node Host passes, all 24 Workers tests pass,
and the generated Workers fixture is current. This closes `graft_graph`.

At `5dd60e2d`, the no-merge `union_graphs` variant executes its authored
finite input list as one bounded occurrence. The provider resolves every
ordered operation edge from its exact managed Carrier input, including
repeated positions, without inventing external inputs or a binary fold tree.
Portable tests cover successful singleton and repeated-list inputs, atomic
payload conflict, and early rejection of explicit property strategies on JS,
Wasm, and native. At `c533f7a0`, the repeated list also passes through the
standard Host, formal Relation Bridge, overlapping consumers, Named Result
publication, and final reclamation. The Node environment delivers cancellation
during the bounded union and confirms stop before cleanup returns the ledger to
zero. The finite-list kernel also rejects one node below the required output
capacity and completes at the exact node limit while retaining all four input
occurrences in logical accounting. Explicit `exact_equal` uses the same
bounded fold and rejects a conflicting shared identity atomically at
`c282a9f0`. At `385be7a3`, numeric strategies preserve authored fold order,
and canonical set union produces complete-value order without duplicates.
The maximum non-interruptible value traversal includes every field and fold,
rejects arithmetic overflow before output allocation, and is checked on all
three targets. The numeric and set paths also run through the standard Host,
overlapping consumers, publication, cancellation, and final reclaim. At
`def46cc0`, canonical set ordering runs as bounded merge-sort steps. Its child
session retains exact workspace custody, reports byte and node bounds, receives
cancellation, and is reclaimed before the Graph builder. The portable kernel
and query integration suites pass on all three targets, and the real Node
standard Host passes. This closes `union_graphs`.

At `9a995650`, `mean_graphs` executes its ordered finite sample list as one
bounded occurrence. Exact dyadic folds compare weighted support without a
rounded quotient and compute weighted number properties with one final
nearest-ties-to-even binary64 rounding. The kernel preserves repeated sample
positions, canonical node and edge order, retained-endpoint closure,
`exact_equal`, and every missing and null policy. At `5ff6996a`, stable
bottom-up merge steps replaced quadratic ordering; temporary buffers are
admitted before construction and released at their actual lifetime boundary.
The portable kernel suites pass 34 tests per target, including exact and
one-short workspace bounds and subquadratic scaling evidence. At `39d718ca`,
the standard Host carries an internal Graph construction through the mean and
the formal Graph-to-Relation Bridge to two overlapping consumers and formal
Effect-free publication. At `309d5111`, a real Node timer delivers
cancellation during mean work and verifies kernel observation, stop,
cleanup, and a zero final ledger. This closes `mean_graphs`.

At `1b7dbec3`, `subtract_graphs` executes the property-free structural
variant over two immutable internal Graph generations. The bounded kernel
removes shared node identities, discards remaining edges whose endpoints were
removed, observes cancellation between records, and admits output capacity
before construction. The portable standard Host carries the result through
the formal Graph-to-Relation Bridge, two overlapping Relation consumers,
Named Result publication and retrieval, and final reclamation on JS, Wasm,
and native. Direct Carrier inputs preserve the same exact operation-edge
bindings as managed storage inputs.

At `9c0cf275`, an explicit `exact_equal` map retains shared subtraction
entities instead of treating the strategy as a removal instruction. The
kernel validates the complete duplicate payload, so unlisted properties keep
their equality requirement. Conflicts fail atomically, right-only entities do
not enter the result, and node and edge strategy maps remain independent.
Property-bearing entity kinds without a complete executable map are rejected
before output allocation. The portable kernel tests pass on JS, Wasm, and
native. At `00063427`, the exact-equality path also runs through the standard
Host, two overlapping consumers, Named Result publication and retrieval, and
final reclamation on all three targets. At `385be7a3`, numeric and canonical
set difference retain explicitly mapped shared entities, keep right-only
entities out, and admit temporary set indexes before allocation. At
`053005b9`, the real Node Host also delivers cancellation during the bounded
kernel, observes stop separately from cleanup, and returns all ledger holdings
and reservations to zero. At `def46cc0`, the shared canonical set-key sort is
resumable, accounts its workspace before allocation, and cleans an active child
session after cancellation. Its portable and standard Host regressions close
`subtract_graphs`.

Node Graph equality now compares two exact positioned immutable Graph inputs by
typed node and edge identity, optional edge label, and complete payload. The
kernel advances through bounded work units and emits one admitted boolean
Relation row without depending on Graph enumeration order. The portable
standard Host carries the result through two consumers, independent release,
formal Named Result publication, retrieval, and final ledger reclamation on
JS, Wasm, and native. The real Node Host publication path and generated
Workers fixture are current at `738d19da`. An environment timer now delivers
cancellation after both Graph operands are constructed; the bounded equality
kernel observes stop, reports it separately from cleanup, and returns the
ledger to zero at `092cc87b`. Distinct managed Relation inputs now cover both
unequal edge cardinality and equal-cardinality node payload mismatch through
the standard Host and two consumers on all portable targets at `5b3bb4e5`.
This closes `graphs_equal`.

Node identity-list matching now resolves every checked
identity through the admitted immutable Graph index before output, sorts by
semantic identity with bounded merge passes, collapses repeated authored
identities, and preserves the checked projection schema. A missing identity
fails before any Relation is published. The standard Host selects the
registered provider and connects graph construction to matching, common
managed completion, and two independent downstream Relation computations on
JS, Wasm, and native. Releasing either consumer does not invalidate the other
consumer or producer, and final cleanup returns the ledger to zero. A checked
Named Result occurrence also reaches the match output, establishes its fixed
Logical Relation CID, publishes it, and retrieves the stored rows. The
standard Host re-admits the exact managed Relation generation in MoonBit
before the existing publication contract runs. The output remains retained
through publication even when an unrelated later task completes. Literal
true and false predicates now execute through the bounded node scan and the
standard Host with two downstream consumers on all three targets. Checked
node-property predicates use the same resumable expression evaluator as row
execution, with bounded binding preparation and workspace admission. The real
environment timer covers predicate cancellation, stop observation, and final
reclamation, while the formal path publishes the exact filtered result.
`match_nodes` is complete. Edge matching now executes absent, empty, and
repeated type filters plus literal predicates through a bounded scan and
stable canonical edge ordering. Workspace is admitted before the sort arrays,
empty selection remains a valid completed Relation, and cancellation cleanup
releases private state. The registered standard Host reaches two independent
downstream Relation computations and final reclamation on JS, Wasm, and
native. The formal Named Result path publishes and retrieves the exact edge
Relation with its fixed logical CID. A real environment timer cancels edge
matching, observes stop, and completes retryable cleanup without publishing a
partial result. Checked edge-property predicates now use the common resumable
expression evaluator rather than a graph-specific interpretation. Predicate
bindings are prepared one field at a time, expression workspace is admitted
before use, unknown properties retain their typed source diagnostic, and the
same standard Host path covers predicate publication and cancellation.
`match_edges` is complete. Bounded
Graph diagnostics now emit strict node, edge, and total-degree violations in
canonical identity order. Their output is atomic under row limits, structural
workspace is admitted before allocation, and the registered standard Host
reaches two independent downstream Relation computations and final reclaim on
all three targets. The Effect-free Named Result path publishes and retrieves
the retained diagnostics through the formal Store. A real environment timer
now cancels bounded diagnostic work, observes kernel stop, prevents completion,
and releases all holdings and reservations. `graph_bounds` is complete.
Directional degree metrics now count
incoming, outgoing, and total incidences in canonical node order, including
two total incidences for a self-loop. The shared bounded kernel admits its
workspace before allocation, emits its Relation atomically, and reaches two
independent downstream computations and final reclaim through the registered
standard Host on all three targets. The Effect-free Named Result path also
publishes and retrieves the retained total-degree result. The same environment
cancellation path stops degree work before completion and completes retryable
cleanup without leaking reservations. `degree` is complete. Weak and
strong components now use admitted outgoing and incoming CSR indices and
bounded iterative graph walks. Strong components use two graph passes; weak
components traverse both directions. Component identity is the least semantic
node identity, and output is ordered by component identity and then node
identity. Exact authored output guards and structural workspace are admitted
before allocation. Both variants reach two independent downstream Relation
computations and final reclaim through the registered standard Host on JS,
Wasm, and native. The Effect-free Named Result path publishes and retrieves
both component variants through the formal Store while preserving canonical
row order. A real timer delivers cancellation during strong-component work;
the bounded kernel reports stop, no component result is completed, and retry
cleanup releases all holdings and reservations. Direct portable tests cover
the same cancellation boundary for weak and strong execution. `components`
is complete. Commit `235f8b41` connects the first bounded `traverse` variant:
a literal singleton start, one homogeneous directional hop rule, node output,
finite minimum and maximum hop counts, and the resolved output guard. The
registered provider rejects other variants before execution. The implemented
path consumes a typed traversal bound proof and reaches the standard Host,
formal publication, two downstream computations, independent release, and
final reclamation on JS, Wasm, and native. Direct portable tests also cover
kernel cancellation. Relation and predicate selectors, repeated starts, edge
types and predicates, patterned hops, and path output remain open, so
`traverse` remains partial. The remaining SGA operations still lack portable
Local kernels.

At `d08a946c`, the standard Host fixture also exercises inbound and
bidirectional traversal. Both directions preserve the same managed lifetime,
two-consumer, publication, and three-target guarantees as the original
outbound fixture. Direction is no longer an untested formal branch. Selector
relations and predicates, repeated starts, typed or predicate-constrained
hops, hop patterns, and path output remain open.

At `77cb1ff2`, the bounded traversal kernel accepts one authored edge type.
The standard Host fixtures distinguish a matching label from an existing but
nonmatching label, and retain two consumers, publication, resource admission,
and JS, Wasm, and native execution. Multiple edge types, edge and node
predicates, selector relations and predicates, repeated starts, hop patterns,
and path output remain open.

At `e528eda0`, an explicitly empty edge type list is preserved as a filter
that admits no edges; it is not collapsed into the omitted, unrestricted
form. The same standard Host fixture verifies the empty result on all three
portable targets.

At `ccc3d25b`, any finite authored edge type list is matched through bounded,
resumable degree and adjacency phases. The standard Host fixtures prove both
a later-list match and a complete miss on JS, Wasm, and native. Type-list
length no longer creates one hidden synchronous comparison loop. Edge and
node predicates, selector relations and predicates, repeated starts, hop
patterns, and path output remain open.

At `4a72ee83`, the real Node standard Host delivers cancellation while the
bounded homogeneous traversal is active. The fixture supplies the authored
traversal proof instead of reusing reach evidence, observes kernel stop, and
verifies retryable cleanup and a zero final ledger. The direct JS, Wasm, and
native tests continue to cover the same kernel boundary. This closes the
environment-cancellation layer for the implemented variant; the classified
selector, patterned-hop, and path-output variants remain open.

At `20a3d337`, homogeneous traversal reads a checked Relation-backed start
selector through its exact ordered input edge and selected field. Typed cells
are resolved through the managed Graph identity index, repeated identities
are deduplicated, and start nodes retain canonical semantic order. Direct
managed tests cover the binding, input evidence, and output order on JS,
Wasm, and native. At `b066dad6`, the same bounded start-selection state
machine evaluates a checked node predicate with shared typed Graph bindings.
Binding and expression work use the existing workspace and logical-work
limits, and no partial traversal output is exposed on evaluation failure.
Direct tests select a node through a typed property predicate on all three
targets. At `ff2a6410`, predicate selection also reaches the registered
standard Host with its correct capacity proof, two overlapping downstream
computations, independent release, and final cleanup on JS, Wasm, and native.
At `bf33b6e8`, Relation-backed selection reaches that same standard Host path.
Its traversal proof includes the exact upstream selector bound, while repeated
selector rows still resolve to canonical unique Graph identities at runtime.
Three-target tests cover two consumers and final cleanup, and the real Node
Host smoke passes. At `a4392c06`, the distinct authored `hops` source form with
one predicate-free hop executes through the bounded kernel and the same Host,
consumer, and cleanup path on all portable targets. At `7e4c2f06`, one-hop
patterns evaluate typed edge and reached-node predicates in authored order.
Edge-only, node-only, combined, and empty selections run as bounded expression
steps without exposing partial output. At `987327f3`, node-emitting patterns
advance through every authored hop as distinct bounded frontier layers. Each
layer applies its own direction, edge-type list, edge predicate, and reached-node
predicate. The three-target and real Node standard Host fixture distinguishes
the first `owns` hop from the following `blocks` hop and observes only the exact
depth-two result through two consumers and final cleanup. Empty intermediate
frontiers remain successful empty results. Path output remains open, so
`traverse` remains partial.

At `5d95e21e`, traversal output admission applies the authored row ceiling to
emitted rows rather than to the input Graph node count. Portable regressions
cover a four-node Graph that emits one row, the same Graph with no reached row,
and repeated starts whose combined output exceeds the ceiling. The excess case
fails atomically without exposing a partial Relation. The tests pass on JS,
Wasm, and native.

At `0cd04f72`, start, edge, and reached-node predicates retain independent
binding widths. Only their maximum contributes to shared workspace admission;
each evaluation phase enumerates its own exact bindings. A standard Host
fixture combines all three predicates with a wider edge domain. A direct
managed fixture covers structural rejection, expression workspace one-short,
and exact success. The relevant suites pass on JS, Wasm, and native.

At `2f924a7d`, literal identity selection has a bounded induced-subgraph
kernel. It compares one authored identity per work unit, copies every selected
node once, retains only edges whose two endpoints were selected, and keeps
partial output private under cancellation. Duplicate selector identities do
not duplicate nodes. At `87909cdf`, the registered provider carries this
Graph result through the formal node-rows Bridge, two overlapping downstream
Relation consumers, Named Result publication and retrieval, and final
reclamation on JS, Wasm, and native. At `0c359fda`, that selected generation
also remains live across a same-Carrier normalization consumer and the formal
Bridge consumer; the derived Graph is reclaimed independently. Relation and
predicate selectors remained open at that revision, so `subgraph` remained
partial. At
`0a769228`, explicit literal true and false edge predicates are distinguished;
the false branch preserves selected nodes while publishing an empty formal
edge Relation on all three portable targets. At `bf716212`, the real Node
standard Host delivers timer cancellation after Graph construction enters the
bounded subgraph kernel, observes stop independently from cleanup, and returns
all ledger holdings and reservations to zero. The generated Workers fixture is
current and all 24 Workers tests pass.

At `53cc2e95`, node and edge predicates use the same typed Graph bindings and
resumable expression evaluator as the standalone match operations. Predicate
input construction, expression evaluation, output construction, and cleanup
remain bounded phases. At `2cbc57bf`, both predicate forms run from the
standard Host through the registered provider, formal Bridge, two downstream
Relation consumers, Named Result publication and retrieval, and final
reclamation on JS, Wasm, and native. At `e48f65f6`, the same kernel admits the
exact Relation selector edge, deduplicates repeated identities, and rejects
any selected identity absent from the graph. At `d80944d1`, that form reaches
the standard Host, formal Bridge, two downstream consumers, publication, and
final reclamation on all three targets. At `38923228`, the real Node standard
Host delivers timer cancellation while the node predicate, edge predicate,
and Relation selector paths are active. Each path confirms stop separately
from retryable cleanup and returns all holdings and reservations to zero. The
regenerated Workers fixture passes all 24 Workers tests. This closes every
classified `subgraph` layer.

Graph projection already defines evidence laws; execution must consume rather
than recreate them.

### VecA

Normalization now executes as a portable bounded-step kernel over exact managed
Vectors input and reaches the standard Host through the registered Vectors
provider. It applies binary32 input and output quantization, preserves the
specified dimension-order binary64 norm fold, rejects zero vectors, admits
record workspace before temporary construction, and publishes a distinct
managed generation. Its tests cover cancellation observation and two exact
downstream producer reads on JS, Wasm, and native. An independent fixed-bit
corpus covers binary32 ties, subnormals, overflow, signed zero, binary64 fold
order, square-root boundaries, and nonfinite rejection on all three targets.
Environment cancellation delivery, independent Carrier consumption, and
formal publication are connected as recorded below. Checked typed lowering
also emits
`VEC.score_sort`, including bound query values, without reading frontend syntax
again. Scoring now executes the pinned dot, cosine, and negative-L2 folds,
orders finite results by descending score and typed semantic identity, and
constructs a distinct managed Vectors generation through bounded work units.
It admits query, ordering, temporary, and retained-output workspace before
execution. Portable tests cover empty-input query validation, score ties,
cancellation observation, two exact downstream reads, and JS, Wasm, and native.
The independent fixed-bit corpus exercises every score metric and its specified
rounding and failure boundaries. Scoring now reaches the standard Host through
the same registered Vectors provider. Environment cancellation delivery,
independent Carrier consumption, and formal publication are connected as
recorded below. Pooling now lowers both Vectors and Relation source forms.
The Relation form admits its finite identity-completion expansion before
emission. The Vectors form executes mean, sum, and max as bounded deterministic
folds after global semantic-identity validation and orders output groups by
their typed keys. It admits sort, key, vector, and output workspace before
construction and reaches the standard Host through the registered Vectors
provider. Portable tests cover exact input binding, all three reductions,
renamed output identity, exact/short workspace, cancellation observation, and
two exact downstream reads on JS, Wasm, and native. The standard provider also
executes pooling followed by normalization before the Relation Bridge, cleans
each intermediate generation before advancing, and verifies the normalized
value on all three targets. The author-visible Relation form now executes its
canonical identity completion and rows-to-Vectors expansion inside the bounded
Local occurrence. It binds the exact external input edge, preserves singleton
and composite member identities, verifies the pooled value, and reaches two
downstream Relation computations with final ledger reclamation on all three
targets. One pooled generation now remains available to a same-Carrier
normalization consumer and the formal Relation Bridge. The standard Host
publishes and retrieves that Relation and covers timer cancellation, stop
observation, and cleanup. Pooling is complete. Exact nearest now has a bounded
Relation-by-Relation kernel and a
registered provider path. It validates both complete inputs and globally unique
typed identities, quantizes components through the shared VecA numeric profile,
orders queries and tied candidates by typed identity, and emits the fixed
ranking Relation schema. The standard Host fixture exercises explicit roles,
dot scoring, `k=2`, a candidate-score tie, two overlapping downstream Relation
computations, independent release, and final ledger reclamation on JS, Wasm,
and native. The same path now also covers cosine, negative L2, inferred
Relation roles, `k=1`, `k` greater than corpus size, and empty candidate or
query sides. The registered provider now consumes every formal Relation and
Vectors input combination without erasing Carrier authority, rejects reversed
use-site bindings, and preserves source storage after output cleanup on all
three targets. The real Node Host now delivers timer cancellation after exact
nearest work begins, observes kernel stop, publishes no partial result, and
reclaims all reservations at `456c2f27`. Commit `396da45da` connects the three
remaining direct-Carrier combinations to standard Host selection. One or two
bounded rows-to-Vectors bridges feed the exact nearest occurrence while final
completion retains the two external Relation bindings. Each combination
reaches two overlapping consumers, publication identity, independent release,
and zero final ledger usage on JS, Wasm, and native. Duplicate identity and
foreign use-site rejection remain covered by direct provider fixtures, so
nearest is complete. Ranking merge now has typed canonical
lowering for maximum, weighted-sum, and finite-list RRF policies. It retains
score contracts, omitted versus explicit empty tie-breaks,
and ordered repeated RRF inputs as one operation occurrence. RRF now executes
through a bounded stable-merge kernel and the registered standard Host
provider. It validates complete inputs and contiguous ranks before applying
the rank window, folds contributions in occurrence order, and emits fresh
contiguous ranks. The standard Host fixture covers two distinct inputs and one
material repeated at two authored positions. Both reach two downstream
Relation computations, independent release, and final ledger reclamation on
JS, Wasm, and native. Maximum and weighted-sum authenticate owner-bound score
declarations through the registered provider and cover stable candidate ties
on all three targets. Both policies reach the product standard Host, two
overlapping downstream computations, Named Result publication, timer
cancellation, stop confirmation, and final reclamation. The registered
provider rejects duplicate candidates and noncontiguous RRF ranks while
preserving both completed inputs through cleanup. Nullable query-group keys
use canonical NULLS FIRST grouping independently from nullable business tie
keys, which use the authored NULLS FIRST or NULLS LAST order. These fixtures
pass on JS, Wasm, and native, so ranking merge is complete.
`vector_score` now requires explicit selected-profile admission, retains both
structured operand paths in canonical lowering, and evaluates each operand
once. Its metric fold advances one component per resumable step and preserves
temporary root and workspace custody through success or failure. The lowering,
canonical reference, exact numeric, eager NULL, and bounded-step regressions
pass on JS, Wasm, and native. The checked Program carries its selected VecA
expression profile into every generated owner, so the standard Host executes
the expression and two downstream Compute consumers release independently.
Formal publication is connected. The registered VecA provider runs the outer
`OrderedBindings` Relation task through the bounded row evaluator, so an
environment timer can be delivered between rows and expression steps. Stop is
observed before cleanup, partial output remains private, and final cleanup
returns retained and execution reservations to zero. Vector score is complete.
`vector_concat` now preserves authored operand and component order, evaluates
every operand eagerly once, and builds one output component per resumable step.
It admits work and workspace before builder construction and cancels private
output before releasing reservations. Two- and three-operand, NULL, missing
operand, cancellation, and exact/short resource cases pass on JS, Wasm, and
native. The same checked-profile path reaches the standard Host, two downstream
Compute consumers, independent release, final ledger reclamation, and the
Effect-free Named Result publication and retrieval path. Its bounded kernel
also has direct cancellation coverage on all three targets, so concat is
complete.
Common immutable record storage preserves composite vector identities,
admitted dimensions, exact UTF-8 value usage, work, and workspace bounds.

### TEA

All eight TEA operations now have portable Local kernels. Checked typed
lowering emits `TEA.watermark.label`, `TEA.dedupe`, and
`TEA.window.session_assign`, while time series has both checked lowering and
portable execution. Dedupe retains repeated partition positions,
stable order terms, null placement, and the mandatory tie failure. Session
retains its exact roles, grouping positions, clock encoding, and resolved
literal or bound gap. Its bounded merge kernel orders by partition, time, and
event identity, applies the strict closed-open gap boundary, and preserves the
original event identity while adding stable session labels. Relation rows pass
through the registered Events bridges and standard Host to two downstream
computations with overlapping holdings, independent release, and final ledger
reclamation on JS, Wasm, and native. Global partitions and parameterized gaps
now traverse the same standard Host path on all three targets. The ordinary
session path also establishes its formal Named Result identity before
publication. The compiled Node Host delivers timer cancellation during the
session kernel, observes stop, retries cleanup, and releases all held and
reserved bytes. At `90e18aff`, exact owner-bound Events material feeds two
bounded managed session consumers with overlapping lifetimes. Each returns
retained Events material, one consumer can clean up and reclaim independently,
and the other consumer and source remain available until their own final
reclamation. The same provider path passes on JS, Wasm, and native. At
`1a9e0e42`, the author-visible Relation form reaches the bounded session kernel
through the standard Host, publishes its Named Result, feeds two downstream
computations, and reclaims its managed record storage on all three targets.
At `dfff01b2e`, the standard Host carries the retained Events completion
across the physical task boundary into the exact session input. At
`4ef9c6be`, equal-time events reach the standard Host on
all three targets and are ordered by their typed semantic identity before
closed-open session assignment. Session identity construction now advances
one scalar part per bounded phase, checks complete UTF-8 prefixes and
separators before retention, and reclaims partial buffers after cancellation.
Interval join has typed canonical lowering for all
four join kinds, both temporal modes and time domains, repeated equality keys,
projections, and resolved output guards. Interval and as-of joins execute
through resource-bounded evaluators and the standard Host, reach two
downstream consumers, and reclaim their retained output on all three targets.
Their publication is established. Each join now loads temporal values,
searches candidates, constructs rows, and completes output through one bounded
managed session. As-of identity validation and both stable sorts are resumable
as well. The Node Host delivers timer cancellation during each search, observes
stop, keeps partial output private, and completes cleanup. This closes interval
and as-of joins.
Sequence matching now has typed lowering and a portable bounded Relation
kernel. It validates semantic event
identity, orders by grouping keys and `(time,id)`, evaluates each demanded
row-pattern predicate once, and supports both overlap and contiguity policies.
Author match guards fail atomically, and output storage is admitted before
publication. The focused lowering and runtime suites pass on JS, Wasm, and
native. A Relation input now reaches the standard Host under exact temporal
limits, feeds two downstream computations with overlapping lifetimes, releases
them independently, and reclaims the final ledger on all three targets. At
`a93ea126`, the same path establishes the exact Logical Relation identity for
its Named Result before publication on JS, Wasm, and native. At `1e2c48f6`,
sequence matching runs through a bounded managed provider. Its identity checks,
stable sorts, predicate evaluation, match construction, and output admission
resume in finite work quanta. Empty input, global and grouped partitions, and
all overlap and contiguity policy combinations pass on JS, Wasm, and native.
The Node standard Host delivers timer cancellation during matching, observes
kernel stop, publishes no partial result, completes cleanup, and returns held
and reserved bytes to zero. At `d4fb3d6da`, the Events input crosses a
physical standard Host task boundary into bounded sequence matching. Its
Relation output reaches publication and two independently released consumers.
Event
windows now preserve the Events
Carrier in typed lowering and emit the registered fixed-label or
sliding-assignment operation. Their bounded kernel validates the complete
membership bound before output allocation, retains input occurrence order,
and emits memberships in ascending start order. Sliding storage distinguishes
physical membership records by event identity plus window start without
changing the Carrier's semantic event identity. Fixed, sliding, and
parameterized fixed variants run through the standard Host, reach two Relation
consumers, establish stable publication identities, and reclaim the final
ledger on JS, Wasm, and native. The Node Host delivers timer cancellation
during both window kernels, confirms stop, completes cleanup, and returns the
ledger to zero. A real acquisition now runs the same bounded observation with
one-row and whole-observation transport pages. Both executions preserve the
capture observation, fixed-window result identities, two downstream consumers,
and final reclamation. This closes event windows. Checkpoint advancement remains
bound to the existing successful commit boundary; page receipt and kernel steps
do not advance it. No long-lived streaming state is required by TEA 0.1. Common
immutable record storage preserves typed event roles, open payload
evidence, semantic identity uniqueness, and bounded allocation. Watermarking
now executes as a bounded-step kernel for numeric and canonical UTC clocks. It
implements both policies, preserves the exact late boundary and retained order,
admits record workspace before construction, and publishes a distinct managed
Events generation. Its portable tests cover kernel cancellation observation and
two exact downstream reads on JS, Wasm, and native. One registered standard
Host sequence now converts Relation rows to Events, runs watermarking, converts
back to Relation, feeds two downstream computations, releases them
independently, and reclaims the final ledger. The retained consumers, formal
publication identity, and complete environment cancellation artifact path now
pass. This closes watermarking. Dedupe now executes as a bounded stable merge
over the authored partition and order terms. It preserves repeated partition
references, emits representatives in canonical partition-key order, and fails
an unresolved top tie before publication. Scratch dimensions are admitted
before allocation. Its portable tests cover grouped and global selection,
empty input, exact and insufficient workspace, cancellation, and tie failure
on JS, Wasm, and native. The registered Events provider now selects either
watermark or dedupe from the checked occurrence. Dedupe reaches two downstream
Relation computations through the standard Host, establishes its formal
publication identity, and releases the final ledger. The Node Host delivers
cancellation during dedupe work and observes stop and cleanup before returning
the ledger to zero. This closes dedupe. At `fa716474`, the affected TEA,
provider, and query-integration suites pass 414 tests on JS, Wasm, and native,
and the real Node standard Host passes. Time series now lowers
literal and exact bound endpoints to a zero-input canonical
occurrence, validates its complete finite cardinality before execution, and
emits canonical UTC timestamp rows through a bounded-step Relation kernel. A
registered provider runs it through the standard Host, keeps two real
downstream consumers live together, releases them independently, and reclaims
the final ledger. The same affected suites pass on JS, Wasm, and native.
Environment cancellation delivery and Named Result publication remain open,
so time series is not complete. Session has a portable bounded kernel and a
registered Relation-to-Events-to-Relation standard-Host path. Its global,
grouped, literal-gap, and parameter-gap variants now have standard-Host
evidence, and the grouped literal path has formal publication evidence. Its
compiled environment cancellation path is also closed. Its exact Events-input
managed provider path is closed at `90e18aff`; the standard Host task boundary
remains tracked above.

### Bridges

`to_events` and `to_vectors` lower their checked semantic roles to
`BRIDGE.rows.to_events` and `BRIDGE.rows.to_vectors`. Rows-to-Events and
Events-to-rows execute inside the first registered provider. Rows-to-Vectors
and Vectors-to-rows now execute as a bridge-only sequence and with intervening
vector kernels inside the second registered provider. The vector paths cover
an exact same-Carrier consumer, a formal Bridge consumer, two downstream
Relation computations, publication, and final ledger reclamation. The
Graph-to-node and Graph-to-edge projections now also
publish and retrieve their exact Relation values, feed two downstream
computations, and release the retained output independently. A real
environment timer reaches each Bridge boundary, stop is observed, and final
cleanup returns all holdings and reservations. Both Graph projection
operations are complete. Standalone Bridge selection, overlapping direct
Carrier consumer lifetime, and Graph construction are closed. The bounded
Relation-to-Events-to-Relation path now has page-split evidence, but a
Relation-shaped buffer alone is not evidence of a completed conversion.
The Events-to-rows and Vectors-to-rows operations feed two overlapping
Relation consumers and establish the exact Named Result identity on all three
portable targets. Rows-to-Vectors now has the required direct Carrier consumer
and formal Bridge consumer evidence. At `dfff01b2e`, the standard Host
schedules the retained Events generation across its same-Carrier session
consumer and its formal Relation Bridge consumer. Relation publication remains
separate evidence.
At `fb4a149b9`, the product Node Host establishes and retrieves the exact
Named Result after rows-to-Events construction, a bounded watermark transform,
and the formal Events-to-Relation Bridge. Two downstream Relation consumers
retain independent projections, and final cleanup returns held and reserved
bytes to zero. This closes the required Relation publication layer for
`to_events`.
At `15af5df1`, the compiled Node Host separately delivers cancellation during
the rows-to-Events copy and during the Events-to-rows copy after the bounded
watermark transform. Both paths observe stop and reclaim the ledger without
publishing a partial Relation or Carrier generation.
At `eb01dc6f`, the same environment boundary separately delivers cancellation
during rows-to-Vectors construction and Vectors-to-rows projection. The
bridge-only sequence also distinguishes itself from two-step relation pooling
and reaches two consumers and Named Result publication on all three targets.
At `5b83cf99`, an exact retained Events generation crosses managed task
boundaries to one session consumer and one formal Bridge consumer. Their
lifetimes overlap; independent release leaves the producer live until the last
view is done, and a cancelled projection stops and cleans up before final
reclamation on JS, Wasm, and native. The same Carrier handoff is scheduled by
the standard Host at `dfff01b2e`.

Commits `8bdc0f73c`, `58fcfbf17`, and `c41194698` establish the next shared
physical-segmentation boundary without closing that gap. Lowering now exposes
an ordered typed inventory of every non-Relation operation edge, including
repeated material positions. A generated execution view can select one
original checked step while retaining its global coordinate, and managed
Graph and record material can issue a fresh view for one exact internal
operation edge. The Events provider executes selected rows-to-Events, session,
and Events-to-rows steps through those views. JS, Wasm, and native regressions
cover exact step and input binding, foreign-owner rejection, independent
views, and final reclamation. Commits `757bc77dc`, `438c87d0c`, and
`dfff01b2e` turn this inventory into scheduled Events construction, session,
and projection tasks.

At `c5f7dd45`, an owner-bound Events view preserves canonical timestamp values
through the formal Events-to-Relation Bridge on JS, Wasm, and native. A separate
negative fixture rejects duplicate semantic identities before Carrier
completion and preserves the completed Relation input through cleanup. These
fixtures close clock preservation and identity transfer; the existing standard
Host page-split, two-consumer, publication, and environment-cancellation
evidence closes `events`; `dfff01b2e` closes the corresponding `to_events`
scheduling boundary.

## Current verification boundary

The baseline passed Linux CI run `35414883771`. That proves the accepted RelA
baseline only. It is not evidence for any missing family execution path.

At `e34840d4`, the affected Local, Bridge, TEA, VecA, provider, and query
integration packages pass 366 tests on each of JS, Wasm, and native. The
focused Carrier suites pass six tests on every target, while the Node Local
adapter passes eleven,
and the retained boundary passes 231. Portable dependency and dependency-free
Node subset checks pass. This is local evidence, not a replacement for final
same-SHA Linux CI.

At `78064895`, the bounded time-series path additionally establishes the fixed
Logical Relation identity required by its Named Result and retains two
independent consumers on JS, Wasm, and native. The Node standard Host delivers
a real timer cancellation between bounded steps, observes the kernel stop, and
retries cleanup to zero retained and execution bytes. `time_series` is
complete. Final same-SHA Linux CI and the remaining operations are still open.

At `b42ad703`, the lowering and Relation execution packages pass 868 tests on
each of JS, Wasm, and native. JS checking, formatting, and the tracked portable
API gate also pass. This is focused evidence for `vector_score`; it does not
establish its standard Host profile propagation or any remaining completion
layer.

At `78ec134f`, the same packages pass 871 tests on each target, with focused
concat cancellation coverage passing on all three. JS checking, formatting,
and the tracked portable API gate pass. This remains expression-layer evidence,
not standard Host completion evidence.

At `d2540a9c`, the checked Program retains its exact expression profiles and
the query integration boundary supplies them to every generated owner. The
standard Host fixture executes `vector_score` and `vector_concat`, feeds the
result into two downstream Compute consumers, releases them independently, and
returns the ledger to zero. The complete program-check and query-integration
suites pass 677 tests on each target; the portable API and family coverage
gates pass. This is not cancellation-delivery or publication evidence.

At `8ffcbb75`, the common managed request, physical task, Local managed
provider, and Node dispatch paths retain an ordered mixture of Relation and
Carrier bindings. A standalone TEA provider can return a retained Events
Carrier, and the Node adapter accepts and stores a Carrier completion without
erasing it to Relation rows. The affected suites pass 1,128 tests on each of
JS, Wasm, and native; query integration passes 395 tests, the Node Local
adapter passes 13, the retained boundary passes 233, and the publication
runtime passes 16. The product standard Host still lacks a fixture that
dispatches this retained output across a physical task boundary into an exact
checked Carrier consumer, so no operation gains a completed layer from this
plumbing alone.

At `f59e17eb`, the same expression pipeline reaches the Effect-free Named
Result path. The standard Host publishes and retrieves the ordered rows with
both the numeric score and concatenated vector intact, while retaining the two
downstream Compute consumers and final ledger reclamation. This closes the
publication layer for both expressions. `vector_score` still lacks its own
environment-cancellation evidence. `vector_concat` has a resumable expression
frame, but its outer OrderedBindings row evaluator is still drained
synchronously by the common managed Relation fallback. Neither expression is
complete until the Node Host can deliver cancellation during that outer
execution and observe stop before cleanup.

At `842825f8`, bounded event deduplication preserves the checked partition
and order terms, fails unresolved top ties before output publication, and
admits its scratch dimensions before allocation. The registered Events
provider selects the operation from the typed occurrence. Its standard Host
fixture reaches two downstream Relation computations, independent release,
and final ledger reclamation. The affected TEA, provider, and query integration
suites pass 361 tests on each of JS, Wasm, and native. The portable API,
format, and family coverage gates pass. This does not prove standalone Events
consumer lifetime, environment cancellation delivery, or publication.

At `cf7b9326`, direct Vectors pooling runs through the registered provider and
the standard Host, then returns through the Vectors-to-Relation Bridge to two
downstream computations. The affected Local VecA and query-integration suites
pass 373 tests on each of JS, Wasm, and native. The same SHA covers mean, sum,
max, output identity aliases, exact input binding, resource admission, and
kernel cancellation observation. This is not evidence for author-visible
Relation pooling, an actual same-Carrier consumer, environment cancellation
delivery, or publication.

At `c097f5b5`, the registered provider accepts a finite typed VecA kernel chain,
admits storage for every intermediate generation, and reclaims each predecessor
before starting the next kernel. The standard Host executes pooling followed by
normalization and verifies the exact normalized vector. Provider and query-
integration suites pass 358 tests on each target. This proves an actual
same-Carrier computation after pooling, but not two overlapping consumers of
the same Carrier generation.

At `72f65404`, author-visible Relation pooling binds the exact checked input
edge and executes the admitted canonical identity and Bridge expansion without
publishing an intermediate completion. Both singleton and composite identities
reach the expected sum, two downstream Relation computations, independent
release, and final ledger reclamation. The affected execution, VecA, provider,
and query-integration suites pass 1,064 tests on each of JS, Wasm, and native.
The tracked public interfaces agree across targets. Commit `f26b44d1` also
corrects computed text admission to measure real UTF-8 bytes and passes all 109
value-admission tests on each target. Commit `688c910c` refreshes the generated
Workers fixture; fixture freshness and all 24 Workers tests pass. These results
do not establish overlapping direct Carrier consumers, environment
cancellation delivery, publication, or final same-SHA Linux CI.

At `0fd16e6d`, exact Relation-by-Relation nearest executes through the
registered VecA provider and the standard Host. Its fixed fixture proves query
identity ordering, score-descending and candidate-identity tie ordering,
contiguous rank, two live downstream Relation consumers, independent release,
and final ledger reclamation. The affected VecA and query-integration suites
pass 23 tests on each of JS, Wasm, and native. The Workers fixture is generated
from the same source and is fresh. This is one classified nearest slice, not
evidence for the remaining Carrier combinations, all formal metric and boundary
variants, publication, cancellation delivery, or final same-SHA Linux CI.

At `611a7969`, the nearest standard Host fixture additionally covers cosine,
negative L2, checked completion of sole string primary-key and vector roles, a
one-result prefix, and an empty candidate side. The affected VecA and query
integration suites pass 28 tests on each portable target. The empty side still
passes through normal two-consumer lifetime and final reclamation. This does
not close direct Vectors inputs, duplicate identity failures, every `k`
boundary, publication, cancellation delivery, or final Linux CI.

At `e8f06d62`, the same standard Host path covers a requested prefix larger
than the candidate corpus and an empty query side. Both cases retain the two
downstream computations and final reclamation checks. The affected VecA and
query-integration suites pass 30 tests on each portable target. This does not
close direct Vectors inputs, duplicate identity failures, publication,
cancellation delivery, or final Linux CI.

At `6b723dd9`, every currently connected Relation-by-Relation nearest variant
establishes and verifies its exact LogicalRelation identity through the formal
Named Result publication contract. Independent expected rows, two overlapping
downstream consumers, individual release, and final reclamation remain part of
the same standard Host fixture. Query integration passes 403 tests on each of
JS, Wasm, and native, and all 24 Workers tests pass with a fresh generated
fixture. Direct Vectors inputs, duplicate identity failures, environment
cancellation delivery, and final same-SHA Linux CI remain open.

At `ab818437`, the registered VecA provider accepts all four formal nearest
input combinations: Relation/Relation, Relation/Vectors, Vectors/Relation,
and Vectors/Vectors. Direct Carrier reads retain their exact producer, input
position, generation, and availability authority through Relation output
completion. A reversed pair is rejected without consuming either material,
and output cleanup leaves both inputs available for their owners to reclaim.
The focused VecA and query-integration suites pass on JS, Wasm, and native.
This does not yet establish standard Host selection, two downstream consumers,
publication, environment cancellation delivery, or final same-SHA Linux CI
for the three direct Carrier forms.

At `b954085a`, all three ranking-fusion policy families reach canonical
`VEC.merge_rankings` lowering from checked typed decisions. The RRF fixture
retains three repeated positions in authored order, while scored policies keep
their score contract and tie-break presence. Exact and one-short preparation
budgets cover nodes, references, work, and identifier bytes. The lowering,
ranking evidence, and vector typing suites pass 256 tests on each portable
target. This does not establish the Local kernel, managed execution,
publication, cancellation delivery, or final Linux CI.

At `ad1e25fe`, weighted-sum and RRF arithmetic use explicit binary64 product,
addition, and division boundaries from the shared VecA numeric profile. Fixed-
bit and invalid-operand fixtures pass 34 tests on each portable target.

At `47660253`, the portable ranking kernel validates complete RRF inputs,
detects per-input duplicates and noncontiguous ranks, applies rank-window only
after validation, and uses bounded stable merge passes for validation, fusion,
and output order. The standard Host executes ordinary and repeated-material
RRF occurrences, preserves each authored contribution, feeds two downstream
Relation computations, releases them independently, and returns the ledger to
zero. The complete Local VecA, provider, and query-integration selection passes
386 tests on each of JS, Wasm, and native. This does not establish maximum or
weighted-sum runtime authentication, their tie rules, negative RRF execution
fixtures, publication, environment cancellation delivery, or final Linux CI.

At `4ed328ba`, ordinary and repeated-input RRF establish the exact
LogicalRelation identity required by Named Result publication on JS, Wasm,
and native. The real Node standard Host also cancels the third managed task
during bounded RRF work, preserves the two completed input tasks, confirms
stop, performs cleanup, and returns every ledger to zero. Generated Workers
and dependency-free Node Host fixtures remain current, and their portable
gates pass. This evidence does not cover maximum or weighted-sum runtime
authentication, their tie rules, negative RRF execution, or final Linux CI.

Maximum and weighted-sum cannot use ordinary `values` score columns as an
execution shortcut. Their inputs require matching captured score declarations;
the author-visible Program boundary rejects otherwise identical numeric columns
before planning. It must not infer score authority from a field name or weaken
the checker to reach the kernel.

At `25aff2fd`, owner-bound producer pipelines carry matching declared score
evidence into maximum and weighted-sum fusion. Exact retained Relation outputs
bind to those producers and execute through the registered VecA provider. The
fixtures check grouped scores, fresh ranks, and stable candidate ordering for
score ties. The query-integration suite passes 428 tests on each of JS, Wasm,
and native.

At `467537d6`, both scored policies use the product supplied-input standard
Host path. Maximum and weighted-sum results establish the required Named
Result identity, feed two overlapping downstream Relation computations,
release each consumer independently, and return the execution ledger to zero.
Query integration passes 433 tests on each of JS, Wasm, and native. Generated
Workers and Node Host fixtures are current; all 24 Workers tests, the
dependency-free Node Host check, and all 236 retained-boundary tests pass.
Final same-SHA Linux CI remains open.

At `580993ac`, maximum and weighted-sum ranking use owner-bound supplied score
inputs in the real Node standard Host. Cancellation is delivered through the
event loop during bounded policy work, the kernel observes it, the Host
confirms stop, cleanup reclaims the exact inputs, and every ledger returns to
zero. The same revision passes all 433 query-integration tests on JS, Wasm,
and native, and the complete Node standard-Host test. With the existing RRF,
tie, repeated-input, negative, numeric, and resource fixtures, all classified
`merge_rankings` variants and required Local layers are closed.

At `06974f71`, business tie ordering is separated from strict candidate and
group identity. Nullable AuthorOrderable ties preserve equality for two NULLs
and order NULL after a present value without weakening nonnullable candidate
identity. Registered managed-provider regressions cover maximum and
weighted-sum inputs with present and NULL ties on JS, Wasm, and native.

At `5a8badc2`, query-group ordering has its own nullable KeyComparable path.
It applies canonical ascending order with NULLS FIRST while candidate identity
continues to use the strict non-null comparator. Registered provider fixtures
cover nullable composite groups for maximum and weighted sum and nullable
groups for reciprocal-rank fusion on JS, Wasm, and native. Existing reference
key comparison remains on the same exact-domain, availability-checked path.

At `bf85b1b4`, duplicate candidates and noncontiguous positions are exercised
through the registered RRF provider rather than only through checker or helper
tests. Both failures preserve the completed inputs, stop the provider, and
finish cleanup on JS, Wasm, and native. Negative RRF execution is closed; this
does not add product standard Host lifecycle evidence for the scored policies.

At `a9174bee`, interval join reaches one typed canonical
`TEA.join.interval` occurrence without rediscovering frontend syntax. The
lowering retains point and overlap operands, timestamp and safe-integer clock
domains, all four admitted join kinds, repeated equality keys, projections,
and resolved output guards. Exact and one-short preparation budgets are
covered. The lowering, Relation execution, and Local connector packages pass
887 tests on each of JS, Wasm, and native. Runtime selection remains closed;
this is not kernel, managed execution, publication, or cancellation evidence.

At `5d0e1a97`, the checked interval-search product reaches the captured DAG
and constrains Local selection before execution. The portable kernel validates
every temporal endpoint before matching, preserves repeated equality keys and
left-major order, implements both temporal modes and all four admitted join
kinds, and applies independent search, output, value, work, and workspace
limits. The standard managed Host consumes the exact selected 12-pair bound,
executes the result through two downstream computations, releases them
independently, and returns the ledger to zero. The affected execution,
physical-strategy, Local connector, and query-integration suites pass 1,079
tests on each of JS, Wasm, and native. Publication and bounded-step
cancellation remain open, so interval join remains partial.

At `c59c3352`, interval clock loading, key comparison, pair search, row
construction, and completion run through one resumable managed session. Exact
input bindings remain attached to the completed output. The registered TEA
provider reaches the existing standard Host two-consumer, publication, and
final-reclamation path. Focused and full affected suites pass 1,173 tests on
each of JS, Wasm, and native. The compiled Node Host also delivers a real timer
cancellation during a 40-by-40 pair search, observes stop before cleanup, keeps
partial output unpublished, and returns all reservations. This closes interval
join; it does not claim the separate as-of or sequence paths are resumable.

At `47ea7883`, as-of join reaches one typed canonical `TEA.join.asof`
occurrence without rediscovering frontend syntax. The prepared step retains
both admitted join kinds, all three directions, number and timestamp domains,
repeated equality keys, exact left identity, completed right tie-break fields,
resolved tolerance, and canonical projection metadata. Local selection remains
closed until the selected as-of search product and bounded evaluator are
connected. The lowering suite passes 202 tests on each of JS, Wasm, and native.
This is not kernel, managed execution, publication, or cancellation evidence.

At `b2c7034d`, the exact selected as-of search limit reaches Local admission
and execution. The portable evaluator validates every clock and left identity,
preserves null-key nonmatching and stable left time/identity order, implements
both kinds and all three directions, and rejects unresolved top ties. Authored
tie fields use ascending null-last order. Search, output, value, work, and
workspace limits remain independent. The standard Host consumes the selected
12-pair limit, runs two downstream computations with overlapping holdings,
releases them independently, and returns the ledger to zero. The affected
execution, physical-strategy, Local connector, and query-integration suites
pass 1,084 tests on each of JS, Wasm, and native. Events-left execution,
publication, and bounded-step cancellation remain open, so as-of join remains
partial.

At `8a204939`, normalization preserves one immutable Vectors generation across
an actual `score_vectors` consumer and the formal Vectors-to-Relation Bridge.
The portable standard Host fixture verifies exact normalized values, retained
Named Result identity, two downstream Relation computations, independent
release, and final reclamation on JS, Wasm, and native. The Node standard Host
additionally publishes and retrieves the bridged Relation, delivers a timer
cancellation after normalization starts, confirms stop, retries cleanup, and
returns held and reserved bytes to zero. A family-specific conformance entry
installs VecA without adding its kernel package to the ordinary module subset.
The affected portable suites pass 397 tests per target; the real Node Host,
Workers, package-composition, format, and generated-fixture checks also pass.
This closes `normalize_vectors`; the remaining VecA operations retain their
separate variant and lifecycle gaps.

At `ca6abe4f`, score queries resolve from both literal and bound parameter
forms through the portable standard Host. The independent numeric and kernel
fixtures retain dot, cosine, negative L2, binary32 query admission, score and
typed-identity tie order, workspace limits, and bounded cancellation checks.
One scored Vectors generation is shared with a real normalization consumer and
the formal Relation Bridge on all three targets. The Node standard Host
publishes and retrieves the scored Relation, delivers cancellation after score
work starts, confirms stop, completes retryable cleanup, and returns the ledger
to zero. Workers generation and all 24 Workers tests pass from the same source.
This closes `score_vectors` without treating the remaining VecA operations as
complete.

At `9c751e9c`, one pooled Vectors generation is shared with a real
normalization consumer and the formal Relation Bridge on JS, Wasm, and native.
The Node standard Host publishes and retrieves the pooled Relation, delivers
timer cancellation after pool work starts, confirms stop, completes retryable
cleanup, and returns the ledger to zero. The portable affected suites pass 418
tests per target, all 24 Workers tests pass, and package composition and format
checks pass. This closes `pool_vectors` without treating the remaining VecA
operations as complete.

At `c000f109`, the standard Host admits the exact Acquisition Relation binding
only for a registered Carrier family provider. The same bounded Events
observation executes with one-row and whole-observation transport pages,
preserves the capture evidence and both downstream result identities, and
reclaims all held and reserved capacity. Ordinary RelA execution remains on
its established dispatcher. The affected MoonBit suites pass 1,122 tests on
each of JS, Wasm, and native; the real Node Host, Local adapter, Workers
generation, and all 24 Workers tests also pass.

At `b636f29c`, the family artifact gate builds the RelA-only Node artifact and
the SGA, TEA, and VecA provider artifacts with the pinned MoonBit toolchain. It
derives each transitive package closure from `moon.pkg`, rejects unselected
family kernel or provider packages, and inspects the final RelA link response.
The generated artifacts are nonempty and independently identified by SHA-256.
This closes the shared packaging gap without removing complete-language
checker or contract metadata from the RelA-only artifact. It does not change
the 18/39 operation completion count.

At `4606d221`, `reach` executes through a resumable indexed graph walk. The
kernel admits its adjacency, traversal, sort, and output workspace before
allocation; preserves incoming, outgoing, and bidirectional minimum depths;
and emits canonical node identity order. The registered provider carries the
exact Graph binding through managed Relation completion, two downstream
computations, independent release, and Effect-free Named Result publication.
The direct kernel and standard Host fixtures pass on JS, Wasm, and native.

At `f96153c8`, all three direction branches run through the real Node standard
Host and the Effect-free publication store, where the named result is retrieved
and checked independently. The environment event loop delivers cancellation
to an active bounded reach walk; the kernel observes it, confirms stop, and
releases its private state through retryable cleanup. Three-target fixtures
also cover a self loop and the maximum authored depth without overflowing the
runtime depth representation. This closes the classified `reach` variants and
raises the completed operation count to 19/39.

The Graph Bridge now lowers explicit node and edge sources through one finite
typed expansion without collapsing repeated input positions. The expansion
projects the selected branch fields, closes both edge endpoints against the
declared node universe with deterministic semi-joins, and then reaches one
`BRIDGE.rows.to_graph` occurrence. The same expansion descriptor controls
preparation budgets, canonical occurrence enumeration, and wire emission.
Exact metadata and expansion limits succeed, while one-short entry, name,
work, node, reference, and identifier limits fail before emission. The fused
Local path applies the same endpoint-closure law instead of hiding different
Graph semantics inside the Bridge. Its bounded runtime constructs immutable
Graph storage, projects both node and edge rows, and revalidates values against
the exact Relation output contracts.
The registered provider runs construction and projection through the standard
Host. Its fixtures cover quantum-one progress, pre-allocation workspace
rejection, cancellation observation and cleanup, two overlapping downstream
computations, independent release, Graph reclamation before Relation use, and
a zeroed final ledger. All five Graph fixtures pass on JS, Wasm, and native.
The explicit construction fixture excludes an edge whose target is absent,
retains present endpoints and repeated logical roles, and agrees across JS,
Wasm, and native.

Commits `245a147d`, `d8928e40`, and `088770c3` close the concise construction
branch. One typed Relation input now lowers to a finite expansion that derives
the node set from source and target endpoints before the canonical Graph
Bridge occurrence. The bounded Local runtime preserves implicit edge
properties, exact input binding, workspace admission, and cleanup. Standard
Host fixtures cover concise input, distinct explicit node and edge inputs,
the pre-existing repeated-input form, two downstream Relation consumers, and
final ledger reclamation on JS, Wasm, and native. A Node timer also delivers
cancellation during endpoint derivation and verifies stop before cleanup.

Commit `9940712f` establishes the formal Relation publication identity for
the explicit, split-input, and concise construction projections on JS, Wasm,
and native. The product Node Host additionally publishes the concise
construction projection, retrieves it from the publication store, and checks
the independent value. This closes publication for the Graph-producing Bridge
without defining a non-Relation Graph artifact format.

At `16bae24a5`, a completed Graph is scheduled through the standard Host
across a physical task boundary into its formal node-Relation projection.
Commits `5d1163dd` and `da4ec645` close the underlying managed
provider boundary: standalone construction returns an owner-bound Graph
material, exact views feed overlapping graft and Graph-to-Relation consumers,
one consumer can finish or cancel without revoking the other, and final
reclamation occurs once. The physical path retains repeated exact input edges,
publishes the Relation projection, releases two consumers independently, and
reclaims the Graph after its last view. Graph publication is not invented
while the formal publication contract remains Relation-valued.

Commits `ceaf836d`, `e965f84b`, and `05f70065` close the two VecA row
expression entries. A shared bounded row evaluator retains exact input roots,
advances snapshot or ordered bindings in admitted phases, and publishes no
partial output on cancellation. The standard managed provider boundary now
receives the selected execution limits instead of reconstructing them, and
the VecA provider selects only binding kernels whose lowered roots contain a
VecA expression. Compatibility starts retain zero ceilings and therefore
cannot silently run a provider that requires the selected limits.

Independent fixtures cover `vector_score` and `vector_concat` through
quantum-one provider advances, exact output, cancellation, stop confirmation,
and cleanup on JS, Wasm, and native. The portable standard Host runs values,
score, and concatenation as separate physical tasks before two overlapping
downstream computations and final reclamation. The Node standard Host
publishes and retrieves the Relation result. A timer cancellation reaches the
active expression provider through an environment yield, stops without a
completion, and returns held and reserved bytes to zero. This closes both
VecA expression entries without treating vector filters or assertions as
supported by the binding-only provider.

Each entry moves from missing to partial to complete only when its manifest
evidence names existing fixtures, suites, targets, and recorded results. A
passing inventory count alone cannot complete a layer.

At `c009251f`, homogeneous node traversal accepts the full nonempty literal
start set instead of only a singleton. The bounded kernel resolves each typed
identity through the admitted Graph index, rejects any missing identity before
walking, deduplicates repeated selectors, and sorts unique starts by canonical
identity before producing per-start minimum depths. Selector, ordering, and
per-start traversal phases remain resumable, while output stays private and
atomic until the complete set succeeds.

Exact workspace admission accounts for the identity selection bitmap and both
start-order arrays before allocation. An exact boundary succeeds and a
one-short boundary rejects before execution. Direct fixtures also cover a
missing member and repeated out-of-order starts. The portable standard Host
runs the repeated selector through two downstream computations. The affected
Local SGA, provider, and query integration suites pass 461 tests on JS, Wasm,
and native. Traverse remains partial for Relation and predicate selectors,
patterned hops, path emission, and their classified lifecycle evidence.

At `c3059ed0`, homogeneous traversal with a nonempty literal start set can
emit bounded simple paths. The dedicated resumable kernel preserves the
original directed edge identity records, orders rows by hop count and the
canonical node and edge sequences, rejects repeated nodes, and admits both
the output ceiling and path workspace before copying an expansion. Portable
fixtures cover zero-hop and multi-hop output plus exact output and workspace
failures on JS, Wasm, and native. The registered provider now admits this
variant.

At `e9cab711`, the same path variant reaches the portable standard Host on
JS, Wasm, and native. It runs two overlapping downstream computations,
publishes and retrieves the Effect-free Named Result, releases each consumer
independently, and reclaims the producer after the final release. Admission
uses the Host path ceiling and the authored output guard; it does not attach
the node-output proof to path rows. Traverse remains partial until Relation
and predicate path starts and patterned path predicates reach the same Host
lifecycle.

At `7e0bd409`, a real Node standard Host timer delivers cancellation while
the homogeneous path kernel is active. Stop confirmation precedes cleanup,
no partial path completion is published, retryable cleanup finishes, and the
final ledger is empty. Direct JS, Wasm, and native fixtures cover the same
kernel stop and cleanup boundary. Cancellation remains open only for the
unimplemented path selector and patterned-predicate variants.

At `6ee11a18`, path traversal also resolves a checked Relation-backed start
selector through its exact ordered input edge. The resumable selection phase
retains repeated input positions until semantic identity deduplication and
checks cancellation before continuing expansion. The portable standard Host
runs the variant through two downstream computations, Effect-free Named
Result publication and retrieval, independent release, and final reclaim on
JS, Wasm, and native.

At `09b723e4`, path traversal evaluates a checked start predicate through the
same bounded typed-expression state machine used by node-emitting traversal.
Predicate bindings are admitted before allocation, evaluation is resumable,
and cancellation stops the private session before cleanup. Exact and
one-short structural workspace fixtures plus the portable standard Host cover
the kernel, two downstream computations, Effect-free publication and
retrieval, independent release, and final reclaim on JS, Wasm, and native.

At `46ba53ff`, path traversal selects every authored hop direction and edge
type at its exact depth. Edge and reached-node predicates use the shared
bounded expression state, with incremental edge-type matching and
pre-allocation admission for the maximum live binding width. A two-hop
fixture distinguishes `owns` from `blocks`, checks both predicates, publishes
and retrieves the resulting Relation, and runs two downstream computations.
Its false-predicate counterpart completes atomically with no rows. Exact and
one-short workspace fixtures, cancellation cleanup, and the affected suites
pass on JS, Wasm, and native.

At `0ae4b508`, standard Host fixtures cover path output with inbound and
bidirectional traversal, a minimum-zero bound, and an explicit empty edge-type
set. Together with the literal, Relation-backed, predicate-selected, and
patterned lifecycle evidence above, every classified `traverse` layer and
formal branch is connected. `traverse` is complete.
