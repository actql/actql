# Checked Program step bound applications

`capacity_program_step` binds supported Program bound claims
to an actual immutable checked pipeline and step. It is an operation-law
application boundary, not Program identity admission, source authorization or a
runnable Plan.

## Local subject convention

`subject_ref` returns `checked-step:<zero-based index>` only for an existing step.
This is an internal owner-relative subject convention, not an authored `as`
name, source pointer, semantic CID or external compiler reference. The checked
result retains the exact pipeline and index as well as its proof. A naked
reference string is not the resulting evidence and cannot replace that owner.
Two owners may use the same local spelling without being the same Program.

The fixed Sketch compiler also uses generated references, but does not promise
this spelling. Existing proof bytes cannot be relabeled without changing their
preimage identity. General semantic-graph import/mapping and Program Definition
identity remain separate work; this entry does not guess that mapping from
authored names. No language syntax or existing canonical Program identity changes.

## Supported laws

The proof must use the existing `DerivedInputs` form. Its role is
`proven_upper_bound`. Relation applications use `rows`; Graph construction and
row bridges explicitly validate both the output and dependency units below.

| Actual checked operation | Required proof application |
| --- | --- |
| Global Group with empty grouping keys | `actql.bound.global-group`, source derivation, value one. This holds independently of the input row count, including empty input. Other internal `OneRow` rules do not inherit this law. |
| `values` | `actql.bound.values`, input-free source derivation with the exact authored row occurrence count. Cells and their binding obligations remain intact. |
| `time_series` | `actql.bound.time-series`, input-free source derivation with exact `ceil((end-start)/step)` after endpoint and step resolution. |
| `calendar_series` | `actql.bound.calendar-series`, input-free source derivation with the admitted Calendar unit's conservative domain upper bound (zero for equal literal endpoints). |
| `take` with a literal or bound count | `actql.bound.take`, input-free clamp with the exact resolved count as maximum and value. Offset and order obligations remain on the checked operation. |
| `top_k`, or `top_k_by` with no partition keys, with a literal or bound count | `actql.bound.top-k`, the same exact input-free clamp. Nonempty partition keys cannot use this global bound. |
| `append` | `actql.bound.append`, checked addition of both input upper bounds, with the actual left/right witness IDs in the derivation. Repeated inputs count twice. |
| `join`, `cross_join`, `interval_join` | `actql.bound.join-output`, source derivation retaining both ordered input applications. Recompute the successful-output bound for the actual join kind, including unmatched outer-join occurrences. |
| `asof_join` | `actql.bound.asof-left`, preserve the exact left input upper bound for either kind and every direction. The right data input is not an operand of this row-count proof. |
| `unpivot` | `actql.bound.unpivot`, multiplication by the authored column occurrence count, including repetitions. |
| Array `unnest` with known `max_items` | `actql.bound.unnest-array-items`, multiplication by the checked expansion factor. Outer expansion of a zero-length array uses one, not zero. Unknown bounds remain unresolved. |
| `row_window` | `actql.bound.row-window`, multiply by one for fixed windows or exact `ceil(size / step)` for sliding windows. |
| `window_events` | `actql.bound.window-events`, the same membership factor applied to the Events input occurrence bound, with Carrier-preserving output. |
| `nearest` | `actql.bound.nearest`, query bound times the checked `k`, or query bound times `min(candidate bound, k)` with both input applications retained. |
| `text_rank` | `actql.bound.text-rank`, query bound times `k`, or query bound times `min(corpus bound, k)` with both actual input applications retained. Zero-score filtering does not establish an exact count. |
| `merge_rankings` | `actql.bound.merge-rankings`, sum all ordered input upper bounds; with empty `by`, clamp that sum to `k`, or use an input-independent `k` upper bound. |
| Explicit `graph` construction | `actql.bound.graph-nodes` converts the actual node branch's row upper bound to `nodes`; `actql.bound.graph-edges` converts the actual edge branch's row upper bound to `edges`. Each uses a source derivation with its exact input application. |
| Concise edge-list `graph` | The same Graph laws use the actual edge input: at most two endpoint nodes per row and at most one edge per row. Checked multiplication fails on overflow. |
| `node_rows`, `edge_rows` | `actql.bound.graph-node-rows` and `actql.bound.graph-edge-rows` convert an actual producer's respective `nodes` or `edges` bound into `rows`, using a source derivation. |
| `degree` | `actql.bound.graph-degree` converts the original node upper bound into an output-row upper bound, independently of edge degree or direction. |
| `components` | `actql.bound.components-input-nodes` retains the input node bound; `actql.bound.components-nodes` converts it to an output-row bound. These are candidates, not the separately enforced `components-output` limit. |
| `match_nodes`, `match_edges` | `actql.bound.match-nodes` / `actql.bound.match-edges` convert the respective original entity upper bound into a conservative row upper bound. Predicate evaluation and identity membership remain required. |
| `graft_graph`, `union_graphs` | `actql.bound.graph-nodes` / `actql.bound.graph-edges` sum the same-unit bounds from every actual operand occurrence. Union lists include the current input first, then every listed reference, including repetitions. |
| `subtract_graphs` | The same measure-specific laws retain the left input bound; subtraction cannot add entities. The right data dependency and all property/endpoint validation obligations remain on the checked operation. |

Graph measure conversion is a source-law application, not a same-unit preserve
or multiply derivation. The fixed Sketch compiler separately materializes the
concise endpoint union (`actql.bound.graph-endpoints`) before Graph construction;
the local checked source step retains the authored Graph operation and validates
its composed two-endpoint upper bound without inventing lowered step identities.
Explicit construction retains both data branches even though each measure's
proof uses only its respective branch. Endpoint closure, graph identity and
property admission still require their existing validations; upper bounds do
not assert that every input occurrence survives or becomes a distinct entity.

The match bound does not evaluate predicates or deduplicate authored identity
selectors. It uses the original entity upper bound even for repeated IDs and
constant predicates. The fixed reference compiler can tighten an ID-list match
to the number of distinct IDs; that additional `match-node-ids` calculation is
not implemented here. This conservative candidate neither changes authored
selectors nor permits skipping their runtime validation. Components guards also
do not replace the node-derived candidate; their resolved minimum and enforced
output application remain separate from these source-law checks.

All dependency applications now require the expected measure: a Graph edge
bound cannot act as a Relation row bound merely because its value matches.
Row bridges require a checked Graph measure application or a validated external
Graph input bound, not the pipeline's conditional numeric summary.
`check_with_sources` retains ordered `StepInput` / `GraphInput` dependencies;
`source_at` exposes either kind, while the existing `input_at` returns only a
step dependency (and `None` for an external input). `input_count` counts both.
The original `check_with_inputs` remains the step-only convenience entry.
Arity and operand budgets are checked before allocating the retained array.
Cross-pipeline forwarding retains exact producer
owners and charges the existing traversal budget. Node/edge measures may also
cross checked `normalize_graph` and `subgraph` steps: neither can increase the
respective input entity count. They retain the original upper-bound owner,
not an exact output count or evidence that selector/Graph validation has run.
Every traversed step is charged. Other Graph operations, including expanding
unions, still require their own checked capacity applications and cannot be
skipped by this forwarding path.
Graph preflight linkage retains the admitted input owner, selected policy,
source collection and pending enforcement obligation. Application collection
closure rejects roots from a separately admitted collection, even when their
witness CIDs match. Enclosing source identity and complete consumer enforcement
remain unfinished.

Structural composition validates each operand's measure and exact data-edge
owner before summing; the proof's sorted input references retain multiplicity.
Its bounded operand passes use `max_operand_work`, including before allocation
of the owned dependency array. A source derivation retains all participating
applications; binary additions may also use the exact left/right add derivation,
and subtraction may use preserve of the exact left witness. Overflow rejects
rather than truncating or claiming a saturated bound. Sum arithmetic does not
authorize reassociation of graph property strategies such as pairwise mean.
The fixed Sketch compiler copied the left graph shape after structural union;
that implementation detail is not used as a sound output bound here.

`check_with_inputs` also accepts one input application for selection,
clamping its bound to the exact checked count. Offset does not weaken this upper
bound and remains an independent checked-operation obligation. `check` is the
input-free convenience entry.

Generator count claims do not invent data-input dependencies. Values retains
every authored row occurrence, including repetitions and Parameter cells; a
known row count is not proof that those cells are bound. Time series resolves
literal endpoints directly and Parameter endpoints from `CountBindings` owned
by the exact pipeline/declarations. Typed timestamp values have already passed
fixed-width UTC/calendar admission; arbitrary strings cannot substitute for
them. Numeric or duration steps use the existing positive safe-integer resolver.
`time_series.resolve_row_count` shares the literal counting core, rejects missing
or invalid supplied values, reversed ranges and overrides of literals, and
validates step even for an empty interval. This fixed-width arithmetic does not
generate rows, read the Host timezone or claim whole-Invocation consistency.

Calendar series uses its retained `AtMost` value, not a new interpretation of
`max_steps` or a guessed exact boundary count. The chosen Calendar profile is
retained; bound range and actual boundary/resource validation remain obligations.
The existing conservative maxima include the civil-domain edge allowance:
3,652,061 days, 521,725 weeks, 119,990 months, 39,998 quarters or 10,001 years.
Their use as source proofs changes no Calendar boundary or profile law.
The dedicated generator law names extend the registry and its CID; they do
not reuse global-group's fixed-one identity or a Host-ceiling source.

Join applications with operand upper bounds `L` and `R` use `L*R` for inner
and cross joins, `L*max(1,R)` for left joins, `max(L*R,L+R)` for full joins,
`R == 0 ? 0 : L` for semi joins, and `L` for anti joins. Interval joins use
their admitted kind with the same occurrence semantics. The source proof lists
both witness IDs, including repeated operands; neither operand can be hidden
inside a literal multiplication factor. Both owner-relative data edges must
match, even when only one numerical bound determines the result.

Arithmetic is checked in the safe-integer domain. Full joins return the other
bound when one side is empty, add when either nonempty side is one, and multiply
otherwise. This computes the maximum without overflowing an unused alternative.
These are upper bounds, not exact counts or proof of successful execution.
Author cardinality/singleton assertions, endpoint validation, stable identities,
search-work ceilings and output guards remain separate obligations. Stronger
uniqueness-based candidates use the separate application below; this generic
two-count form does not manufacture or discharge that evidence.

### Conditional join uniqueness

`check_join_with_uniqueness` uses the actual ordinary join's retained
`pipeline_typing.JoinEvidence`, not a caller-provided cardinality flag or
detached key. The application retains that exact evidence, exposed through
`checked_join_evidence`, alongside both verified input count applications.
It fails if the checked join has neither a covered candidate key nor an authored
uniqueness assertion. Cross/interval joins do not reuse equality-key cardinality
merely because they also have two inputs.

For nonempty upper bounds, inner joins use `min(L,R)` when both sides are
unique, `L` when only the right is unique, and `R` when only the left is unique.
Left joins use `L` with a unique right side, otherwise `L+R-1` with a unique
left side. Full joins use `L+R` with either unique side. Semi/anti remain bounded
by `L`. Empty-side laws take precedence over these refinements. All arithmetic
remains checked; a unique-side bound can succeed when the unrestricted product
would overflow. The source proof retains both count dependencies, even where
one count does not change the numerical result.

Covered left/right key handles and the authored assertion remain distinct.
`ValidateKeyProducer`, declared-input admission, asserted cardinality and other
pending validations are not discharged by computing this conditional bound.
The ordinary counts-only entry remains available and never silently acquires
uniqueness assumptions. Application collection coverage preserves the retained
evidence; it is not source authorization or execution readiness. General key
source identity admission and complete consumer enforcement remain required.

This follows the existing pipeline row-count rules and the normative per-side
combination of candidate-key evidence with author assertions. Compared with
Sketch at `87dc7144`, the unique-left outer bound is `L+R-1` rather than `L+R`
when both sides are nonempty: a matched right occurrence necessarily replaces
at least one unmatched left occurrence. Tests cover all assertion/kind pairs,
generated keys on either or both sides, mixed static/asserted evidence, preserved
key-owner handles and pending validations, empty sides and overflow.

Sketch at `87dc7144` uses a `source` proof under `actql.bound.join-output`, but
its unrestricted outer-join estimates add unmatched-row bounds to the entire
pair product. The local application uses the tighter safe formulas already
implemented by pipeline row-count transfer: a matched occurrence cannot also
be an unmatched occurrence. This changes neither authored semantics nor the
wire vocabulary and does not imply imported proof bytes are interchangeable.
Regression cases cover all admitted kinds, empty and singleton sides, ordered
owners, repeated operands, traversal limits, false values and overflow.

For `nearest`, one input application addresses the query edge, not the primary
candidate edge. Its derivation must be multiplication by the exact checked `k`.
With two applications, they follow data-input order (candidates, queries), the
proof lists both witness IDs in canonical sorted order, and the derivation is
`source`. Source-law application recomputes the product from both verified
operands rather than trusting that source assertion. Zero candidates give a
zero upper bound. Both forms use checked multiplication and fail on overflow.
The query-only bound remains an upper bound rather than proof that candidates
are plentiful; tighter available bounds still belong in complete resolution.

Sketch at `87dc7144` uses the same `actql.bound.nearest` law and
`min(candidate bound, k)` rule, but passes only the query witness to
`boundMultiply`, leaving the candidate dependency implicit in its scalar factor.
This local application boundary does not accept that missing dependency as
evidence for a reduced factor. The existing two-input source-proof form retains
both owners without changing the wire schema or law identifier. It also passes
Program closure, which rejects extra undeclared arithmetic operands. Imported
proofs need their own semantic-subject and dependency reconstruction.

Nearest regression cases cover below/equal/above-k candidate bounds, both proof
forms, swapped inputs, insufficient traversal budgets, false source assertions,
missing factor dependencies, empty candidates imported from another checked
producer, complete application collection coverage, and overflow after Parameter
binding. Candidate/query value, identity, profile, score, search-work and
publication obligations remain on their checked operations; an output bound is
not a search-work or memory admission certificate.

Lexical ranking shares the per-query top-k arithmetic, not nearest's law ID or
score semantics. The one-input proof addresses the query edge and multiplies
by the exact checked k; the two-input `source` proof retains corpus then query
applications and recomputes `query_count * min(k, corpus_count)`. Corpus-dependent
factors cannot omit the corpus proof, even when both edges refer to the same
producer. Full safe-integer checks include zero factors and reject overflow.
The tokenizer/profile, corpus statistics, text/identity admission, scores and
work/byte ceilings remain on the retained lexical operation. No exact result
count is inferred: zero-score documents may be absent even with nonempty inputs.

The existing Language text-rank rule is authoritative. Fixed Sketch `87dc7144`
does not provide this compiler law; its nearest arithmetic supplies implementation
material only. The new registered `actql.bound.text-rank` name identifies that
existing lexical rule explicitly instead of reusing a nearest proof. Adding it
changes the law-registry CID and its metadata/identity pins, not the lexical
profile bytes or the semantics of authored text_rank. Tests cover both tokenizers,
empty corpus/query producers, k boundaries, hidden factor dependencies, wrong
law/owner, repeated inputs, complete application coverage and overflow.

Ranking fusion's full source proof lists every input witness, including repeated
RRF occurrences, and uses `source` derivation. The application checks the actual
input edges and recomputes the bound. Grouped binary addition also admits the
existing ordered `add` derivation used by Sketch at `87dc7144`. Current Language
extends RRF to a finite input list; the source-proof form covers that full list
without inventing unnamed intermediate operations or dropping dependencies.
For empty `by`, an input-independent `clamp` with maximum `k` remains valid;
it does not mean that the ranking operation has no data inputs. Nonempty `by`
cannot use a global `k` bound. Full global proofs compute `min(k, sum)` directly,
avoiding an unnecessary overflowing sum; grouped sums fail on overflow.

Ranking checks require `max_operand_work` (default zero), charging five units
per supplied input before allocating operand tables: input-edge selection,
identity multiset construction, proof comparison, arithmetic and the retained
input copy. A bounded frequency map compares the already-canonical proof's
sorted IDs to actual input IDs without losing repetition or sorting the data
edges. Indexed pipeline connection access avoids copying an entire connection
array before checking its budget. `operand_work` reports this additional cost;
producer/step traversal remains separately cumulative in `input_work`. Both costs
must be included by a combined caller. Existing at-most-two-operand rules keep
their constant local work and do not add this ranking-specific charge.

Tests cover max, weighted sum, and RRF; 2/3/16/32 repeated inputs; exact and
insufficient work limits; unknown or reversed dependencies; detached retained
input lists; grouped overflow; and global clamping of large bound inputs.
Neither `k` nor `rank_window` bypasses complete input validation, identity,
rank continuity, score or resource obligations. Output bounds do not certify
ranking input admission or whole-pipeline capacity completeness.

Input applications must retain the exact physical producer pipeline owner and
match the actual bound-producing step reached from each data edge. For a local
step this is the current pipeline; for a `ProducedInput`, the check follows its
retained owner and target through forwarding inputs. A checked non-expanding
step may transport the original upper bound without inventing a new source
witness. Supported transports are unary `Preserve`, `Reduce`, `OneExistingRow`
and `Slice` rules, including window-group reduction; known repeat/array expansion
factors at most one; Events bridge, session, watermark and deduplication;
Vectors bridge, normalization, scoring and pooling; fixed windows on either
Carrier; calendar buckets; and explicit Events/Vectors-to-Relation projections.
Set operations, nest, as-of joins, semi/anti equality or interval joins and
cross joins with `right_rows: one` transport the actual left bound.
Graph projections do not reinterpret row bounds as node or edge bounds.
Global aggregation, expanding operations, generators, and other unsupported
transfers stop the walk rather than guessing a path. General sliding-window
factor applications remain explicit. A selection may transport its input upper
bound without resolving the authored clamp count; a tighter clamp claim still
requires its own validated application and any necessary binding.

The singleton cross-join path is conditional on its retained exactly-one-right
assertion, not proof that the right data passed. Nest child-array sizes and
right-input scan/hash/search resources are not bounded by the parent row count.
Pool retains its candidate-key, component-admission and deterministic-fold
obligations across both Relation and Vectors inputs. Calendar transport keeps
the selected profile and boundary obligations and cannot cross a generator.
The checked intermediate steps and their ordered data inputs remain available
to complete validation; transport neither prunes unused proofs from collection
coverage nor marks those operations ready to execute.

This follows Language's resolved-limit transfer rules and the same conditional
count laws as `pipeline_typing.row_counts`. Reduction keeps a valid upper bound,
not an exact count; it does not discard tighter available candidates. Every
intermediate operation and both data/validation dependencies remain retained by
the original checked pipeline. No order, uniqueness, value, profile, binding or
runtime capacity obligation is discharged by transport. Equal source text,
names or counts never
substitute for that owner. Ordinary external input facts cannot be substituted
for these owners. Proof input IDs are sorted with repetitions;
derivation operands must additionally preserve their actual left/right roles.
Checked arithmetic rejects overflow rather than rounding or saturating. The
result retains immutable child applications without rewalking their ancestors.

The traversal allowance is consumed before each traversable edge. Consequently,
a wrong input application can exhaust that allowance before reaching the missing
producer or mismatched owner: permitting transport through selection does not
permit unbudgeted traversal merely to obtain a more specific diagnostic. With
sufficient work, a sibling/right input still cannot substitute for the actual
left dependency.

Parameterized counts stay unresolved unless `check_with_inputs` receives a
`CountBindings` from `bind_parameters`. This opaque lookup retains the exact
checked pipeline and a complete `BoundValues` from its original declaration
owner. One entry and its admitted ASCII name bytes are charged per bound
Parameter before building the reusable lookup; unrelated nonnumeric Parameters
remain valid. Defaults are applied only by the ordinary Parameter binder, never
by the capacity checker. The referenced count must be a positive safe integer,
even if its declaration merely admits a number. The result retains the bindings
and their supplied/default provenance; it does not substitute the smaller
computed bound for the derivation's actual count maximum.

Window size, explicit step and offset all resolve before applying a membership
factor. Fixed step and every offset remain validated even though they do not
affect that factor. Size/step require positive safe integers; numeric offsets
admit signed safe integers. Duration Parameters use their retained declaration
rule, not a guess from a string's spelling. `bind_parameters` charges the ASCII
duration token bytes before parsing and caches each root duration once, including
unused entries; plain strings and nested value trees are not scanned. Repeated
window references use the cache without reparsing. Defaults remain the Parameter
binder's responsibility. Missing bindings, invalid numeric options and arithmetic
overflow reject the application; no rounded, saturated or invented bound escapes.
Ceiling division uses integer quotient and remainder, not binary64 division or
an overflowing `size + step - 1`. Time-value, endpoint arithmetic, profile and
publication-resource obligations remain on the checked window.

These are the existing `event-windows` laws and the two window bound laws used
by Sketch at `87dc7144`; no source spelling or identity changes. Tests exercise
both Carriers, fixed-step retention, negative offsets, exact and fractional
ratios, step larger than size, safe-integer endpoints, bound multiplication
overflow, duration spelling equivalence, repeated option references and exact
lookup text budgets. Invalid fixed step and offset bindings fail even though
the expected membership multiplier is one.

Binding checks are local application evidence, not whole-Invocation consistency.
Applications and their ancestors retain their respective binding owners; the
combined boundary must still establish compatible invocation contexts rather
than treating equal local subjects or independently bound values as one Run.
External input proofs and Program-Definition-bound proof forms still
need their respective source application owners. Successful application
retains rather than discharges order, type/data admission and runtime failures.
Tighter available input bounds and other applicable capacity candidates must
still participate in final resolution. This entry never creates a ceiling or
converts a guard into a measured bound.

The local rule check inspects one already-admitted step. Non-ranking rules
accept at most two child applications in bounded constant work; ranking uses
the explicit linear operand allowance above. Wrong-sized input arrays are
rejected before traversal or copying. A Parameter count adds one lookup in the bounded
name table; the name is already admitted by that table's declaration owner.
Following producer inputs is optional and uses
`max_input_work` (default zero): one work unit per visited producer-input link
or transported non-expanding step, shared across both operands, including
repetitions. `input_work` reports consumed work
on success. Negative limits fail; exhaustion fails without exposing a partial
application. Forwarding walks are iterative, do not copy input trees, and succeed
only at the supplied application's exact owner and producer step. A plain
external input without a retained
producer is explicitly rejected rather than inventing source evidence.
Existing source/claim admission owns recursive byte/node limits;
there is no new unbounded collection traversal. Collection-wide application and
completeness remain required at the combined boundary.

Tests construct integrity-valid claims, including intentionally false claims,
and verify subject, operation, law, unit, value and derivation independently of
hash correctness. SHA and wire identity correctness remain covered by their
separate fixed-oracle suites. Owner retention, invalid indices, offset, global
versus partitioned selection and unresolved Parameter defaults are also tested.
Input-dependent tests cover foreign owners, swapped data roles, repeated edges,
false arithmetic claims, overflow, repeated unpivot columns and outer unnest
of empty arrays. These are operation-application tests, not evaluator tests.
Producer tests additionally cover repeated cross-owner operands, a wrong owner
on the second operand, ordinary external inputs, exact work boundaries and a
2,000-owner forwarding chain. Retaining a producer does not discharge its
runtime obligations or establish whole-Program/Invocation identity.
Transport tests also cover filtering to no rows without claiming an exact count,
Relation projection/deduplication, complete Events and Vectors bridge chains,
and rejected expanding/global-group/unrelated-input paths. The 2,000-owner walk
is tested both with forwarding inputs alone and with a non-expanding step in
each owner, including exact/insufficient budgets and a same-content foreign
proof owner at the end. Repeated paths are charged independently.
Bound-count tests cover supplied/default values, unrelated string Parameters,
same-text foreign declaration/pipeline owners, exact lookup budgets, positive
safe-integer boundaries, all three selection forms and a tighter input bound
whose derivation must still retain the larger resolved maximum.

As-of application follows the normative `asof-join` rule of at most one output
per left occurrence. Sketch at `87dc7144` also uses `actql.bound.asof-left`
with only the left row-bound witness. Both actual data edges remain on the
checked pipeline: excluding the right bound from this arithmetic derivation
does not discharge right-side admission, matching/tie validation, search-work
or allocation ceilings. Tests cover both kinds, all directions, safe-integer
upper bounds, a separately bounded right input, swapped operands, false values,
the wrong law and an arithmetically equivalent but incorrect derivation.
Collection coverage still requires any right-side Program proof present in the
claim collection, even though this particular output proof does not use it.

## Application collection coverage

`check_applications` connects the already checked `ProgramClaims` collection to
one `StepBound` for every ordinary Program proof, including unused claims and
all dependency applications. Input order is arbitrary; returned entries use
the arithmetic collection's stable indices. Duplicate or foreign applications
are rejected. Every child must be the exact application handle registered for
its witness, so a matching CID cannot substitute a different pipeline or
binding context. Callers must reuse the child's checked handle, not reconstruct
an equivalent-looking replacement. Repeated dependency edges still count twice.

The check is iterative over the flat application table; it does not recursively
walk each root's ancestors. `max_work` charges one unit per claim allocation,
one per supplied application, one per claim coverage check and one per child
occurrence. Exhaustion exposes no partial table. A complete set of retained
child edges plus the wire layer's acyclic dependency checks closes ordinary
Program proof application coverage without rechecking each ancestor repeatedly.

`remaining_source_count` counts claims without an ordinary Program proof,
including mixed preflight claims. Their source/consumer boundaries are not
discharged here. Zero does not prove candidate completeness, whole-Invocation
consistency, enclosing Program identity or execution permission. The result
retains the original collection for those remaining checks.

## Join output limit consumers

`check_join_limit` binds an engine-atomic output limit to an actual ordinary
join, cross join or interval join. Its local subject is
`join:checked-step:<index>:output`; this is an owner-relative reference, not a
Program Definition identity or imported compiler-reference resolver. The fixed
Sketch `87dc7144` join compiler combines available Program output proofs,
authored guards and `max_relation_output_rows` into this kind of limit.
The governing requirements remain Language's join and resolved-limit sections.

Host sources and the complete ordinary Program application table must retain
the exact same ProgramClaims owner. Each candidate must either be the selected
policy's `max_relation_output_rows` Host witness, or a registered Program
application for this exact pipeline and step. The latter preserves operand
owners and any conditional uniqueness/assertion obligations from its checked
application. Other steps' same-unit bounds and same-valued temporal Host fields
cannot substitute. The selected Host candidate is required, as is every
available registered Program application for this step, even when a tighter
Host limit makes that proof numerically redundant. A Host-only limit is valid
when no local output proof is available. Wire admission already checks the
exact minimum and complete candidate bodies; this entry checks applicability
and completeness within these supplied source owners.

The result retains the pipeline, step, Host and Program owners, selected policy
and original mixed-limit handle/index. `max_work` charges every candidate and
every entry in the Program application table, before allocating the candidate
membership map. Repeated candidates remain intact. Authored output guards fail
with `UnresolvedAuthorSource`; neither equal nor tighter Host ceilings allow
dropping them. Binding their source identity remains implementation work, not
a language prohibition. Complete source authority, Invocation consistency,
all-step/all-consumer coverage and runtime enforcement remain separate.

Tests exercise all three join families, Host-only and Host/Program candidates,
redundant-proof retention, omitted candidates, wrong owners/fields/subjects,
enforcement, authored guards and exact/short work budgets. Dynamic wire helpers
construct integrity-valid claims, including intentionally wrong applications;
they do not compute the expected consumer acceptance from product output.

`check_join_applications` requires every local join, cross join and interval join
to have one application, including unused branches. All entries retain the same
pipeline, Host-source collection, Program application table and selected policy.
Using another otherwise valid proof table for one step is rejected rather than
letting candidate availability vary across the collection. The result owns its
per-step index and exact mixed-limit consumption bitmap; input-array mutation
does not change it. Duplicate entries fail, and unrelated limits remain visible.
`check_join_complete` additionally rejects any unconsumed limit in a dedicated
join collection. It is not completeness for other operation families.

Collection work is `2 * steps + limits + 2 * applications`, checked before index
allocation with overflow-safe subtraction. It includes all-step coverage and
one limit consumption per registration. Tests cover the three families on
independent branches, out-of-order applications, every omitted branch, detached
results, foreign source/proof owners, duplicate entries and exact/short budgets.
The [mixed consumer checker](graph-input-preflight.md) accepts this join ledger
alongside Graph and sequence ledgers under exact shared ownership. It does not
discard extra limits or certify upstream/source/runtime obligations.

## Bound guard context agreement

`check_guard_bindings` checks an admitted application table against one
`pipeline_typing.BoundAuthorGuards` context. For every proof application owned
by that exact checked pipeline, any retained `CountBindings` must hold the
same complete `BoundValues` owner as the guard context. This prevents a count
proof from a different binding run being combined with those bound guards.
Equal values or equal declarations alone are not owner identity; independently
bound equal-value collections need a separate semantic identity boundary before
they can be interchanged. Binding-independent proofs remain valid without a
value collection. No Parameter defaults are reapplied.

The scan charges one unit for every application-table slot, including absent
entries and foreign producer applications. Foreign producers are not certified
by this local context: `guard_application_count` reports only matching local
applications. The opaque result retains both original owners. Exact/short
budgets, different values, independently bound equal values, binding-independent
proofs and same-content foreign pipelines have regression coverage.

The producer capacity closure now requires these comparisons at every visit,
using its corresponding bound context and the remaining shared scan budget.
Local agreement is not whole-Invocation consistency, enclosing semantic identity,
author-witness source validation or execution permission.
