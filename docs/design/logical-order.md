# Conditional logical order

`pipeline_typing.logical_order` retains a deterministic sequence established by a
checked time-series or Calendar-series generator. Language explicitly orders
these outputs by ascending time/start. The opaque summary retains the originating
step and the immediate preserving input edge; callers cannot construct one from
a `total: true` flag. Inspect it in its originating pipeline, which retains all
intermediate steps, bindings, profiles and validation/resource obligations.

This is a conditional successful-execution law, not an observed order, a runnable
Plan certificate or a proof that a Connector returned complete data. A generator
with unbound Parameters still requires successful binding and validation. An
empty generated sequence retains the same law and does not waive those checks.

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
types. The current selector requires complete non-null portable components;
nullable-key completion remains unimplemented rather than silently reinterpreted.

`order_sort_completion` exposes the selected witness and indexed appended fields.
The retained origin operation supplies the unchanged authored terms. This is
information for later Plan construction and journaling, not a claim that a
journal or executable sort has already been emitted. A sort with no selected
key is not resolved merely because its keys type-check. Other unimplemented
transfer rules return no summary rather than an
invented unordered value or an unconditional success. Results still retain their
publication-order obligation. Connecting other completed orders and their
consumer checks, other ordered operations, validated external witnesses and Results
publication remains shared-evidence work.

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
