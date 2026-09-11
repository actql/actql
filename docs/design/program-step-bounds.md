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
`proven_upper_bound` and its unit is `rows`.

| Actual checked operation | Required proof application |
| --- | --- |
| Global Group with empty grouping keys | `actql.bound.global-group`, source derivation, value one. This holds independently of the input row count, including empty input. Other internal `OneRow` rules do not inherit this law. |
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
| `merge_rankings` | `actql.bound.merge-rankings`, sum all ordered input upper bounds; with empty `by`, clamp that sum to `k`, or use an input-independent `k` upper bound. |

`check_with_inputs` also accepts one input application for selection,
clamping its bound to the exact checked count. Offset does not weaken this upper
bound and remains an independent checked-operation obligation. `check` is the
input-free convenience entry.

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
uniqueness-based candidates still require their own evidence application; this
two-count form does not manufacture or discharge that evidence.

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
witness. Supported transports are unary `Preserve`, `Reduce` and
`OneExistingRow` rules, including window-group reduction; Events bridge,
session, watermark and deduplication; Vectors bridge, normalization and scoring;
and the explicit Events/Vectors-to-Relation projections. Graph projections do
not reinterpret row bounds as node or edge bounds. Global aggregation, expansion,
generators, and other unsupported transfers stop the walk rather than guessing
a path. Selection clamps retain their own application boundary.

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
