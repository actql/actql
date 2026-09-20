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
| Completion | Carrier-aware lifecycle is shared; 27/39 entries have kernels and managed completion, 25/39 reach the standard Host, and 15/39 have operation-specific consumer lifetime evidence | Extend the registered boundary and independent lifetime evidence to every principal variant |
| Runtime material | Bounded immutable Graph and finite-record storage preserve Carrier laws; 27/39 entries have resource and three-target kernel evidence | Implement and register the remaining 12 entries without forced Carrier-erasing copies |
| Progress | Bounded sessions, retryable cleanup, and the environment yield adapter are present; long work in completed kernels is split into admitted phases | Audit every remaining long loop and foreign call, then verify each compiled environment path |
| Cancellation | Common cancellation, stop confirmation, and cleanup retry are connected; 10/39 entries record complete operation-specific cancellation evidence | Prove request delivery, bounded observation, stop, and cleanup for every remaining long-running principal path |
| Packaging | Local execution kernels are assembled together | Produce and inspect family-selective artifacts |
| Publication | The Effect-free path publishes and retrieves managed vector expressions and Graph projections; 10/39 entries record publication evidence | Connect every remaining applicable Relation result and Carrier projection through the formal path |

Manifest snapshot at this revision: contract/checker/lowering 39/39,
kernel/managed/resources/three-target evidence 27/39, standard Host 25/39,
consumer lifetime 15/39, cancellation 10/39, and publication 10/39. These are
layer counts, not operation completion: eight entries are `complete` and 31 remain
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

Commit `a786e1b0` regenerates the Workers conformance package from its current
query-integration sources. The freshness check and all 24 Workers tests pass,
including the workerd execution cases.

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
cleanup without exposing a partial generation. A same-Carrier SGA consumer of
the normalized generation remains open, so `normalize_graph` is still partial.
Graft consumes two exact positioned inputs, preserves a
repeated material occurrence, collapses an equal declaration, and rejects a
conflicting payload atomically. Their portable tests cover pre-allocation
limits, kernel cancellation observation, and managed Graph generations on JS,
Wasm, and native. Node identity-list matching now resolves every checked
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
is complete. The remaining SGA operations still lack portable Local kernels.
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
Environment cancellation delivery and independent Carrier consumer release
remain open, so normalization is not complete. Checked typed
lowering also emits
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
independent Carrier consumer release, and publication remain open, so scoring
is not complete. Pooling now lowers both Vectors and Relation source forms.
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
targets. Overlapping independent consumers of one Vectors generation,
environment cancellation delivery, and publication remain open, so pooling is
partial. Exact nearest now has a bounded Relation-by-Relation kernel and a
registered provider path. It validates both complete inputs and globally unique
typed identities, quantizes components through the shared VecA numeric profile,
orders queries and tied candidates by typed identity, and emits the fixed
ranking Relation schema. The standard Host fixture exercises explicit roles,
dot scoring, `k=2`, a candidate-score tie, two overlapping downstream Relation
computations, independent release, and final ledger reclamation on JS, Wasm,
and native. The same path now also covers cosine, negative L2, inferred
Relation roles, `k=1`, `k` greater than corpus size, and empty candidate or
query sides. The other three Carrier combinations, duplicate identity failures,
environment cancellation delivery, and publication remain open. Ranking merge
now has typed canonical lowering for maximum, weighted-sum, and finite-list RRF
policies. It retains score contracts, omitted versus explicit empty tie-breaks,
and ordered repeated RRF inputs as one operation occurrence. RRF now executes
through a bounded stable-merge kernel and the registered standard Host
provider. It validates complete inputs and contiguous ranks before applying
the rank window, folds contributions in occurrence order, and emits fresh
contiguous ranks. The standard Host fixture covers two distinct inputs and one
material repeated at two authored positions. Both reach two downstream
Relation computations, independent release, and final ledger reclamation on
JS, Wasm, and native. Maximum and weighted-sum still need runtime score-
declaration authentication, tie-conflict fixtures, and standard Host evidence.
Negative RRF boundaries, publication, and environment cancellation delivery
also remain open, so ranking merge is partial.
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
reserved bytes. The exact Events-input and same-Carrier downstream path still
remain open, so session assignment is partial. Session identity construction
now advances one scalar
part per bounded phase, checks complete UTF-8 prefixes and separators before
retention, and reclaims partial buffers after cancellation. Interval join now
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
changing the Carrier's semantic event identity. Fixed and sliding variants run
through the standard Host, reach two Relation consumers, and reclaim the final
ledger on JS, Wasm, and native. Parameterized boundary conformance, page-split
equivalence, formal publication, and environment cancellation delivery remain
open, so event windows are not complete. Runtime work must preserve finite
event-time observation semantics
across transport page splits and bind checkpoint advancement to the existing
successful commit boundary. No long-lived streaming state is required by TEA
0.1. Common immutable record storage preserves typed event roles, open payload
evidence, semantic identity uniqueness, and bounded allocation. Watermarking
now executes as a bounded-step kernel for numeric and canonical UTC clocks. It
implements both policies, preserves the exact late boundary and retained order,
admits record workspace before construction, and publishes a distinct managed
Events generation. Its portable tests cover kernel cancellation observation and
two exact downstream reads on JS, Wasm, and native. One registered standard
Host sequence now converts Relation rows to Events, runs watermarking, converts
back to Relation, feeds two downstream computations, releases them
independently, and reclaims the final ledger. Standalone Events output lifetime,
the complete cancellation artifact path, and publication remain open, so
watermarking is not complete. Dedupe now executes as a bounded stable merge
over the authored partition and order terms. It preserves repeated partition
references, emits representatives in canonical partition-key order, and fails
an unresolved top tie before publication. Scratch dimensions are admitted
before allocation. Its portable tests cover grouped and global selection,
empty input, exact and insufficient workspace, cancellation, and tie failure
on JS, Wasm, and native. The registered Events provider now selects either
watermark or dedupe from the checked occurrence. Dedupe reaches two downstream
Relation computations through the standard Host and releases the final ledger.
Standalone Events output lifetime, environment cancellation delivery, and
publication remain open, so dedupe is not complete. Time series now lowers
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
compiled environment cancellation path is also closed. The exact Events-input
and same-Carrier downstream path remains tracked above.

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
Carrier consumer lifetime, page-split coverage, and Graph construction remain
open. A Relation-shaped buffer alone is not evidence of a completed
conversion.

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

At `efb1b6de`, value admission, lowering, Local TEA, its registered provider,
and query integration pass 656 tests on each of JS, Wasm, and native. That
fixed SHA includes the bounded time-series standard Host path and its two
retained consumers. Public interfaces agree across the three targets. This is
focused local evidence; final same-SHA Linux CI and the remaining required
layers are still open.

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
