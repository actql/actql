# Conditional logical order

Graph equality and graph diff establish the trivial sequence of their specified
single result row. The origin retains the exact two-input operation and all
admission/identity/Delta/resource obligations. A structured Delta need not be
sorted as a value to publish this single-row sequence. Filtering that row can
produce the empty sequence without losing order. This is an operation-specific
law, not a generic rule deriving order from an output count: in particular,
take-one cannot use its own cardinality to justify selection from unordered
input. Graph array enumeration or plain Graph projection supplies no order.

Whole-row and keyed distinct retain first-occurrence order, with keyed distinct
applying equality only after its declared projection. This explicitly follows
the fixed AoA first-encounter implementation and the existing set-operation
occurrence rules; it does not select unprojected representatives or sort output
by row CID. The pass transfers existing input sequence evidence but creates none
on unordered input. Candidate keys and any later permitted take/Result key
completion remain separate from this preserving transfer.

Pool establishes canonical grouping-key tuple order for both Relation and
Vectors inputs. Its internal member-identity fold order and input-uniqueness,
numeric/profile and resource obligations remain attached to the producer;
the output sequence is not a substitute for those validations. The vectors
bridge preserves the sequence even when a Result projects only vector payloads.

Nest preserves the parent sequence independently of child enumeration. Its
separate effective child-array order must still be resolved before execution;
retaining parent row order neither resolves that nested order nor permits an
unordered array to be published. The retained pipeline keeps both input edges
and the checked nest's obligations. An ordered child cannot repair an unordered
parent, and projecting the nested payload does not require sorting that array.

Vector bridges and normalization retain an existing occurrence sequence; scoring
establishes score-descending, semantic-ID-ascending order independently of input
enumeration. The explicit vectors bridge can carry that sequence to Relation
consumers. Normalizing already-scored components retains the old sequence and
stored score, not a claim that the score was recomputed for the new components.
ResolveVecaProfile, ScoreArithmetic, ScoreOrder, identity uniqueness, query
binding and resource obligations remain on the producer. A typed external score
field is not an operation-order witness.

The score tie rule is now explicit in Language, aligning single-query scoring
with nearest and semantic identity preservation. Fixed AoA `dbab4fe8` instead
uses a synthesized `{id, vector}` CID for score_sort ties. A future lowerer must
implement the selected semantic-ID rule rather than silently adopt that backend
behavior; this pass does not claim executable compatibility.

Values establishes authored list occurrence order, including empty lists and
repeated equal rows. The implicit ordinal is not a candidate key of the exposed
field values, and the generator retains binding and admission obligations.
Event dedupe establishes canonical partition order under the shared dedupe rules,
independently of arrival order. Its retained producer still requires valid event
identities, complete top-tie resolution and successful resource checks; business
deduplication does not repair duplicate event IDs. The explicit events bridge
and subsequent projections retain that conditional sequence even for opaque
payloads that cannot themselves provide a projected-field sort.

`pipeline_typing.logical_order` retains a deterministic sequence established by a
checked generator, exact ranking, ordered Graph query or partition/event operation.
Language explicitly orders time grids by ascending time/start and ranking
outputs by canonical query group, score and semantic identity. The opaque summary retains the originating
step and the immediate preserving input edge; callers cannot construct one from
a `total: true` flag. Inspect it in its originating pipeline, which retains all
intermediate steps, bindings, profiles and validation/resource obligations.

This is a conditional successful-execution law, not an observed order, a runnable
Plan certificate or a proof that a Connector returned complete data. A generator
with unbound Parameters still requires successful binding and validation. An
empty generated sequence retains the same law and does not waive those checks.

Nearest, text_rank and every checked merge_rankings policy establish their
specified final sequence. The producer retains both resolved operand edges and
the complete ranking contract, including identity uniqueness, numeric evaluation,
profile selection and resource obligations. RRF uses fused-score descending and
semantic candidate identity for ties; its query groups use canonical key order.
These rules do not infer order from arbitrary Relation fields named score/rank,
nor from a Vector carrier merely having a score field. Projection can hide query
and candidate identities while preserving this sequence through take and Result
publication. A lexical producer with an unresolved profile still cannot execute:
the sequence summary is conditional on successful discharge of that obligation,
not a replacement for profile admission or correctly rounded scoring.

Graph matching establishes the specified semantic node/edge ordering. Traverse
uses its emit-specific node or path sequence order; concise reach inherits the
node form's rule. Shortest-path output uses source then target identity (not
global cost order), while components uses component then node identity. Their
checked producers retain the exact mode and all graph, path-selection and
resource obligations. This permits path-array Results to retain an established
sequence even though those array fields cannot supply a projected-field sort.
The Graph carrier itself, degree, and node_rows/edge_rows projection are not
treated as ordered by this pass: the graph-rows contract explicitly says that
projection alone does not establish row order. Additional ordering evidence or
Result completion may still establish order for those outputs.

Group (including window_group), pivot and dedupe_rows establish the canonical
partition/index sequence specified by the evidence-propagation table. Their
aggregate, partitioning, top-tie and resource checks remain prerequisites; this
does not sort arbitrary aggregate payloads or use them as synthetic identities.
The explicit empty-values pivot exception follows first index occurrence instead:
with a nonempty index it requires ordered input and retains that dependency,
never fabricating canonical index order. Empty index is a single global group,
even on empty input, and needs no input-order dependency. Aggregate `first`
still retains its independent input-order obligation in either case. The
evidence table now records the existing reshaping exception explicitly; this
does not change empty-axis acceptance.
Session and sequence establish the specified canonical event/match sequence,
retaining their TEA producers. Session keeps its input Carrier, so Events can
carry this order before explicit Relation exposure. ToEvents, watermark labeling
or filtering, and the Events-to-Relation bridge preserve an existing sequence
without establishing one on unordered inputs. In particular, a watermark never
turns provider arrival order into a publication witness.

Filter, derive, select, rename, drop, take, assertions, lag, watermark_rows and
Calendar bucket preserve an existing sequence. Empty sort preserves it without
candidate-key completion. Transfer follows the resolved input edge, including
branches, rather than whichever step happened to precede it in source order.
Projection may remove the original ordering field without changing occurrence
order: this does not make a remaining constant field a candidate key. Logical
order and candidate keys are deliberately separate evidence.

External inputs have no implicit order. Nonempty sort establishes conditional
order when its actual input retains an eligible canonical-order candidate key.
The existing key selector chooses the canonical whole tuple (arity, then UTF-16
field order); its producer and admission obligations remain attached. Authored
terms retain their order, direction and null placement. Missing components are
recorded separately as ascending, nulls-last internal identity terms; any retained
alias of a component already present in the authored terms covers that component.
This can produce an empty completion for an already-covered key, but it does not
deduplicate or rewrite authored terms. Empty sort never invokes this completion.
Reference identity ordering is internal and does not expand authored OrderKey
types. Candidate keys require complete non-null components by Language's
definition. A nullable Graph label tuple can retain a conditional identity/
uniqueness witness for other consumers, but is not an eligible candidate key
for this ordering completion. This is not a missing nullable-key feature.

Append establishes left-then-right order only when both resolved operands retain
logical order. Its origin exposes the required operand occurrences through
`order_dependency_count` and `order_dependency_at`, in left/right order, retaining
two occurrences even when both name the same target. Preserving operations keep
these origin dependencies as well as their immediate predecessor. This is a
bounded dependency graph within the originating pipeline, not a copied history.
One ordered operand cannot establish order for the unordered operand; neither
concatenation nor take's output cardinality supplies that missing proof. The
append summary does not establish global key uniqueness or completeness.

Cross join similarly requires both input sequences and records both operand
occurrences, using left-major, right-minor product order. Its own checked
projection may hide either identity without losing occurrence order. The
singleton-right assertion and product resource checks remain required; neither
typed fields nor a right-side bound substitutes for missing input order.

Unnest and unpivot establish expansion order conditional on their selected
input's order, with that input retained as an origin dependency. Unnest uses
source occurrence then element index, including the synthetic outer occurrence
for empty/null arrays; no exposed index is required for this internal sequence.
Unpivot uses source occurrence then authored column occurrence, including
repeated columns. Removing the parent or index columns can lose field-key
evidence without losing this sequence. None of these operations fabricates order
from an unordered source. These are the existing Language expansion laws, not
new acceptance rules or execution conformance claims.

Equijoins follow the kind-specific Language row-order contract. Inner, left and
full joins require both operand sequences and retain ordered left/right
dependencies. Semi and anti joins require only the left sequence, since right
enumeration does not choose among or multiply matching left occurrences. The
producer still retains the right input and all match, null-key, identity and
resource obligations. In particular, full-join stable-identity requirements are
not discharged by this order summary. Join projection may hide keys without
erasing the conditional output sequence.

Except/intersect preserve the selected left sequence under both ALL and DISTINCT
policies: the specified earliest/first surviving left occurrences remain in
left order. Right-side ordering is irrelevant to their multiplicity calculation,
but right-side admission, equality and completeness obligations are not waived.
An ordered right input cannot repair an unordered left input. Source branches
use their resolved targets rather than the last syntactically preceding step.

Interval join requires both operand orders for its left-major/right-minor rule,
retaining both dependencies just like the ordinary product enumeration. As-of
join instead establishes ascending left `(time, identity)` order independently
of input enumeration, using the checked producer's exact semantic identity and
clock contracts. It retains all time, uniqueness, tie-selection and resource
obligations; this does not choose an unresolved right-time tie or execute a sort.

Analytic and typed json_pick preserve an existing sequence. Analytic's authored
calculation order is not publication order and cannot establish a sequence on
unordered input. Its peer, position and frame obligations remain separate.
Object projection adds a field without changing row positions. Neither operation
manufactures order from its output names or field contracts.

Row and Event windows also retain a source-order dependency. The Language
occurrence-order rule clarifies input-major enumeration followed by ascending
membership starts, not a global window-start sort. This agrees with the fixed
AoA Relation/Event adapters' per-input expansion and Sketch's retained source
ordering. Both fixed labeling and sliding expansion require existing input
order for this summary. Their exact options and unresolved binding/arithmetic/
resource obligations remain on the origin. Events can expose the sequence via
the explicit events bridge. Projection can discard boundary roles while
retaining sequence order; repeated sliding memberships do not establish event
ID uniqueness. No evaluator is implemented or certified by this pass.

`order_sort_completion` exposes the selected witness and indexed appended fields.
The retained origin operation supplies the unchanged authored terms. This is
information for later Plan construction and journaling, not a claim that a
journal or executable sort has already been emitted. A sort with no selected
key is not resolved merely because its keys type-check. Other unimplemented
transfer rules return no summary rather than an
invented unordered value or an unconditional success. Results still retain their
publication-order obligation until the separate publication strategy is resolved.
Connecting other completed orders and their consumer checks, other ordered
operations and validated external witnesses remains shared-evidence work.

## Existing input-order consumers

Lag has a separate `lag_order_completion` entry, computed under the shared
pipeline budget from the actual input's eligible whole candidate key. Its
authored partition order uses the same alias-aware missing-component completion
as sort, while output rows retain the original input sequence. Even when the
calculation order resolves, it cannot establish publication order on unordered
input. Conversely, an existing input sequence without a retained candidate key
does not satisfy lag's required key-based partition order. The lag source,
offset/binding and runtime obligations remain on its checked step; no physical
sort or offset evaluation is performed here.

`resolve_existing_input_order` resolves prefix watermark and pivot(first) against
their actual input edge, never their output order. Its opaque result retains
the consumer, obligation kind, target and conditional input witness. In
particular, pivot's canonical output partition order cannot justify selecting
the first input value. The resolver performs constant-time indexed lookups and
does not copy a source tree or history, infer provider order or insert a sort.
None leaves the requirement unresolved (or indicates a non-applicable/index
case); producer and consumer runtime obligations remain intact. Fixed watermark
thresholds require no prefix-order witness. Take's allowed key completion and
lag/aggregate-local calculation orders use different rules, not this resolver.

## Take and selection consumption

Top-k and partitioned top-k share sort's bounded candidate-key completion over
their authored `by` terms. The resulting origin retains the selection operation,
count, partition references and unresolved execution bounds. Top-k-by first
orders partitions by their keys, then uses the completed authored ranking inside
each partition. Input ordering alone cannot settle a tied authored ranking;
without an eligible retained whole key this pass leaves the order unresolved.
The shared `order_sort_completion` accessor supplies the missing ascending,
nulls-last identity terms for these selection origins as well as sort. Aliases
of an already-covered component avoid unnecessary appended fields. Neither
authored terms nor partition occurrences are rewritten or deduplicated.

`take_order` reports the conditional order available before a checked take's
offset/count selection. It first retains existing generator or completed-sort
order, including descending authored terms. Only when no such order exists does
it select the actual input's eligible whole candidate key and record ascending,
nulls-last internal identity order. `order_key_completion` retains that selected
witness with its original declaration and validation requirements; it is not a
replacement of the authored take body and does not emit a journal itself.
The same canonical whole-key selector and shared budgets serve sort and take.

An empty preceding sort still establishes nothing, but does not prevent take
from applying its own permitted completion. A second take preserves the first
take's established sequence instead of choosing another ordering. Plain Carrier
input has neither admitted order nor a declared key: `take_order` then returns
None, so downstream checking must retain the unresolved StableInputOrder
obligation. The generic operation's pending list remains context-independent;
this pipeline result supplies the contextual resolution, conditional on all
retained key/producer checks. No provider-return order is assumed.

The pass is nonrecursive and charges one work unit per checked step plus bounded
candidate selection, authored-term and key-alias scans for completion. Field text
is charged to the shared text budget. It shares
the generator and records immediate edges without copying an ever-growing path.
The Relation transfer classifier reads private checked metadata in constant time,
including empty-sort detection, without copying order arrays. Fixed Sketch
`87dc7144` uses the same operation-origin versus preserved-order distinction
(`operationOrdering` / `preservedOrdering`); its public booleans are not adopted
as an admission API here. The normative generator and empty-sort rules, not a
backend's observed row order, justify these summaries.
