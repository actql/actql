# Aggregate type checking

`relation_typing.check(Group, ...)` checks the sixteen aggregate signatures in
[group](../spec/language.md#group) and
[ordered/statistical aggregates](../spec/language.md#additional-aggregates).
It produces field contracts and retained checked calls, not executable groups.

The common call checker separates field references, expression bindings and
row-count arguments. Each aggregate has its own optional filter binding,
argument binding, authored distinct member, order and guards. Calls are checked
in canonical output-name order. No argument is hoisted, merged with a sibling
or evaluated during checking. Expression profile and validation obligations
remain available through each retained typed binding.

Only a fixed immediate argument domain supplies type evidence to root literal
NULL. `expression_typing.check_argument` does not cast values or repair
unresolved descendants. Filters use the ordinary predicate checking boundary,
not an expected result type that could repair `coalesce(NULL, NULL)`.

The input and output schemas, entire source and declared Parameter contracts
are preflighted. Expression usage is debited cumulatively across filters and
arguments. The owned cursors preserve source locations; new collections exposed
by accessors are copies. Schema enumeration is canonical reference order, not
publication order. The retained `group_keys` sequence records authored key
order and duplicates, from which first-occurrence output keys can be recovered.

Empty aggregate maps are accepted, including empty input schemas. An empty
global aggregate denotes one empty row, not an identity operation. Static
checking does not execute that rule or claim a cardinality proof. Repeated
keys remain in the checked source without strengthening key or order evidence.

Capacity and demand validation, per-call total-order completion, bound numeric
guards/fractions, binary64 sum/avg observations and statistical arithmetic laws
remain explicit obligations. Literal guards are not proven output bounds.
Execution, capture, Host admission and AoA lowering are outside this checker.

## Program execution bindings

The operation-resolution index binds `GroupPartitioning` and `AggregateDemand`
to typed `GroupExecutionCheck` records for ordinary group operations. Each
record retains the precise requirement, checked step, input edge and checked
group. Aggregate demand additionally retains the exact call through its
operation-local validation index, without searching names or source paths.

`PartitionGroups` requires typed key equality, first-occurrence output keys,
canonical ascending group order and the specified empty global group. It is
not evidence of observed groups or a static cardinality proof.
`EvaluateAggregate` applies the normative per-call sequence: filter, argument
only for true rows, null exclusion, applicable canonical distinct, then fold
in that call's resolved order. Calls retain their own filter and argument
binding indices and canonical name order; no sibling's demand or order is
substituted. A false filter does not cause static deletion of its argument.
Failure rejects the operation output rather than publishing partial groups.

These records do not resolve aggregate envelopes, per-call order, bound guards,
numeric observation capture or statistical-law obligations. Those requirements
still need their own exact bindings before full closure. Window groups, pivot
and analytic operations have different surrounding requirements and do not
inherit ordinary-group execution support through their shared call grammar.
The formal Program entry remains separate from this operation-level closure.

## Reference compatibility

The fixed Sketch implementation supplies the original seven signatures but
not the complete ordered/statistical vocabulary. Its shorthand aggregate forms
are not the closed authored grammar. Some reference paths impose a shared
array-aggregate order or reject empty aggregate maps and repeated grouping keys;
the current specification permits independent orders, empty maps and repetition.
The existing AoA empty-aggregate path keeps the first complete input row and
does not synthesize a global empty-input row. Lowering must implement the
specified key-only/global behavior before claiming execution compatibility.

`pivot` and `analytic` reuse the applicable signature rules, but selection,
fill, frames and their distinct demand boundaries are separate consumers.
