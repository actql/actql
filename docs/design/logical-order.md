# Conditional logical order

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

## Take consumption

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
