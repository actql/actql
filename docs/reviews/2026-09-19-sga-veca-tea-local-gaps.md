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
| Completion | Carrier-aware lifecycle is shared; 30/39 entries have kernels and managed completion, 29/39 reach the standard Host, and 25/39 have operation-specific consumer lifetime evidence | Extend the registered boundary and independent lifetime evidence to every principal variant |
| Runtime material | Bounded immutable Graph and finite-record storage preserve Carrier laws; 30/39 entries have resource and three-target kernel evidence | Implement and register the remaining nine entries without forced Carrier-erasing copies |
| Progress | Bounded sessions, retryable cleanup, and the environment yield adapter are present; long work in completed kernels is split into admitted phases | Audit every remaining long loop and foreign call, then verify each compiled environment path |
| Cancellation | Common cancellation, stop confirmation, and cleanup retry are connected; 22/39 entries record operation-specific cancellation evidence | Prove request delivery, bounded observation, stop, and cleanup for every remaining long-running principal path |
| Packaging | Closed: the RelA-only artifact and each family provider have verified transitive imports and generated artifacts | Preserve the artifact gate whenever runtime or provider imports change |
| Publication | The Effect-free path publishes and retrieves managed vector expressions, Graph projections, equality, reach, bounded homogeneous traversal, bounded Events transforms, normalized, grafted, scored, pooled, or nearest Vectors projections, and RRF output; 26/39 entries record publication evidence | Connect every remaining applicable Relation result and Carrier projection through the formal path |

Manifest snapshot at this revision: contract/checker/lowering 39/39,
kernel/managed/resources/three-target evidence 30/39, standard Host 29/39,
consumer lifetime 25/39, cancellation 22/39, and publication 26/39. These are
layer counts, not operation completion: 19 entries are `complete` and 20 remain
`partial` until their classified variants and required layers close on one
verified SHA.

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
and the generated Workers fixture is current. This closes `graft_graph`. Node
Graph equality now compares two exact positioned immutable Graph inputs by
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

At `4a72ee83`, the real Node standard Host delivers cancellation while the
bounded homogeneous traversal is active. The fixture supplies the authored
traversal proof instead of reusing reach evidence, observes kernel stop, and
verifies retryable cleanup and a zero final ledger. The direct JS, Wasm, and
native tests continue to cover the same kernel boundary. This closes the
environment-cancellation layer for the implemented variant; the classified
selector, patterned-hop, and path-output variants remain open.

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
three targets. Standard Host selection for the direct Carrier forms, their
two-consumer lifetime, duplicate identity failures, environment cancellation
delivery, and publication remain open. Ranking merge now has typed canonical
lowering for maximum, weighted-sum, and finite-list RRF policies. It retains
score contracts, omitted versus explicit empty tie-breaks,
and ordered repeated RRF inputs as one operation occurrence. RRF now executes
through a bounded stable-merge kernel and the registered standard Host
provider. It validates complete inputs and contiguous ranks before applying
the rank window, folds contributions in occurrence order, and emits fresh
contiguous ranks. The standard Host fixture covers two distinct inputs and one
material repeated at two authored positions. Both reach two downstream
Relation computations, independent release, and final ledger reclamation on
JS, Wasm, and native. Maximum and weighted-sum still need runtime score-
declaration authentication, tie-conflict fixtures, and standard Host evidence.
Negative RRF boundaries remain open. Maximum and weighted-sum also lack the
same runtime evidence, so ranking merge remains partial.
`vector_score` now requires explicit selected-profile admission, retains both
structured operand paths in canonical lowering, and evaluates each operand
once. Its metric fold advances one component per resumable step and preserves
temporary root and workspace custody through success or failure. The lowering,
canonical reference, exact numeric, eager NULL, and bounded-step regressions
pass on JS, Wasm, and native. The checked Program carries its selected VecA
expression profile into every generated owner, so the standard Host executes
the expression and two downstream Compute consumers release independently.
Formal publication is connected. Environment cancellation remains open because
the generic Local fallback drains the outer `OrderedBindings` Relation task in
one synchronous advance even though the expression frame itself is resumable.
Closing this layer requires a bounded outer row evaluator, not a test-only
quantum change or a second VecA expression implementation.
`vector_concat` now preserves authored operand and component order, evaluates
every operand eagerly once, and builds one output component per resumable step.
It admits work and workspace before builder construction and cancels private
output before releasing reservations. Two- and three-operand, NULL, missing
operand, cancellation, and exact/short resource cases pass on JS, Wasm, and
native. The same checked-profile path reaches the standard Host, two downstream
Compute consumers, independent release, and final ledger reclamation.
Publication remains open, so concat is partial.
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
The Node standard Host still needs to carry an Events completion across a
physical task boundary into the exact session input, so session assignment
remains partial. At `4ef9c6be`, equal-time events reach the standard Host on
all three targets and are ordered by their typed semantic identity before
closed-open session assignment. Session identity construction now advances
one scalar part per bounded phase, checks complete UTF-8 prefixes and
separators before retention, and reclaims partial buffers after cancellation.
Interval join now
has typed canonical lowering for all
four join kinds, both temporal modes and time domains, repeated equality keys,
projections, and resolved output guards. Interval and as-of joins execute
through bounded kernels and the standard Host, reach two downstream
consumers, and reclaim their retained output on all three targets. Their
publication and environment cancellation delivery remain open. Sequence
matching now has typed
lowering and a portable bounded Relation kernel. It validates semantic event
identity, orders by grouping keys and `(time,id)`, evaluates each demanded
row-pattern predicate once, and supports both overlap and contiguity policies.
Author match guards fail atomically, and output storage is admitted before
publication. The focused lowering and runtime suites pass on JS, Wasm, and
native. A Relation input now reaches the standard Host under exact temporal
limits, feeds two downstream computations with overlapping lifetimes, releases
them independently, and reclaims the final ledger on all three targets. The
Events input path, publication, and environment cancellation delivery remain
open, so sequence matching is partial. Event windows now preserve the Events
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
and Vectors-to-rows now execute inside a second registered provider, with
normalization between them. Both paths preserve independently managed Carrier
generations and reach two real downstream Relation computations before final
ledger reclamation. The Graph-to-node and Graph-to-edge projections now also
publish and retrieve their exact Relation values, feed two downstream
computations, and release the retained output independently. A real
environment timer reaches each Bridge boundary, stop is observed, and final
cleanup returns all holdings and reservations. Both Graph projection
operations are complete. Standalone Bridge selection, overlapping direct
Carrier consumer lifetime and Graph construction remain open. The bounded
Relation-to-Events-to-Relation path now has page-split evidence, but a
Relation-shaped buffer alone is not evidence of a completed conversion.

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
environment-cancellation evidence, so only `vector_concat` reaches complete
status.

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
Wasm, and native. Concise endpoint-derived construction, collision failures,
formal publication, and environment cancellation delivery remain open, so all
three Graph Bridge entries remain partial.

Each entry moves from missing to partial to complete only when its manifest
evidence names existing fixtures, suites, targets, and recorded results. A
passing inventory count alone cannot complete a layer.
