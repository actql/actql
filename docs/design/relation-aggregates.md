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

`ValidateResultContract` requires the exact call's output contract before
publishing any group: finite non-negative-zero binary64 values, decimal
precision/scale, nullability and any inherited value constraints remain
enforced. It does not coerce, truncate or repair a result. First/last retain the
selected value's contract, including structured or reference types; the check
does not claim new reference evidence. Its call enumeration is exhaustive.
Array and string aggregation require independently selected item/byte limits
and are not resolved by this generic result-contract rule.

These records do not resolve per-call order, bound guards,
numeric observation capture or statistical-law obligations. Those requirements
still need their own exact bindings before full closure. Window groups, pivot
and analytic operations have different surrounding requirements and do not
inherit ordinary-group execution support through their shared call grammar.
The formal Program entry remains separate from this operation-level closure.

`select_group_array_limit` selects an ordinary `array_agg` envelope from an
owned operation-resolution index. It retains the exact call, selected Host
aggregate-array ceiling, authored guard and any matching bound-Parameter
resolution. It scans every applicable Program input-row proof, retaining its
producer/claim membership. Input rows bound per-group array items under
`actql.bound.array-aggregate-input`: filtering, null exclusion and distinct
cannot increase the number of contributed items. This does not reinterpret a
row witness itself as an array-item witness.

Selection takes the minimum of all available candidates and preserves their
origins even when the Host ceiling is already smaller. Sparse claim slots do
not terminate traversal or renumber proof references. All slot visits, rejected
proof checks and Parameter-name comparisons consume work; candidate admission
is bounded before retention. Guard binding uses the exact Stage and producer
visit, not a similarly named Parameter from another context.

The result is static selection material, not a serialized resolved-limit claim
or a discharged `AggregateEnvelope`. Persistent scope references, reconstructed
witnesses and execution enforcement must be connected separately. String-byte
aggregation and nested result-value envelopes are distinct scopes, not aliases
for this array-item limit.

`link_program_group_array_limits` attaches the selection to each ordinary
`array_agg` envelope as `GroupExecution.EnforceArrayItems`. The execution check
retains the exact requirement, input, call and original resolution owner. It
counts items after null exclusion and distinct, and requires failure without
publishing a partial Relation or truncating the array. Selection is not evidence
that this check has run. The retained call's item contract and recursive value
construction constraints must also hold before publication. Work, links and candidate storage are cumulative across
calls; failure does not expose a partially linked index. Other aggregate
envelopes and numeric observations remain unresolved. This process-owned binding
does not replace persistent resolved-limit emission. The formal Program entry
admits a group only when its complete requirement inventory and publication
boundaries close; collection limits and observations cannot be skipped merely
because another group with only exact scalar calls succeeds.

## String output ceiling selection

`select_group_string_limit` selects the exact optional Host
`max_aggregate_string_bytes` ceiling and the ordinary `string_agg` call's
`max_bytes` guard. A Parameter guard uses the existing scalar resolution for
that exact stage, producer visit, pipeline, step and aggregate occurrence;
an equal name or value elsewhere cannot supply it. The opaque selection retains
the original resolution owner, call, both ceilings and Parameter resolution,
including a guard that does not lower the minimum. Its readers do not copy
arrays or rebuild ownership.

Either applicable ceiling can supply a finite maximum; absence of the optional
Host field does not invalidate a guarded call. Absence of both reports
`MissingFiniteBound`, not a language prohibition on string aggregation. The
selector does not reinterpret input row-count proofs, nested JSON bytes or
whole-artifact bytes as raw aggregate-output bytes. Derived input extent proofs
are a separate law application, not an implicit numeric conversion here.
Work includes the prior resolution index and all inspected scalar entries;
candidate capacity counts both Host and guard even when their values coincide.

`link_program_group_string_limits` binds these selections to
`EnforceStringBytes` execution checks for their exact ordinary group input and
aggregate occurrence. Enforcement precedes operation output and rejects output
on failure rather than truncating the string. It preserves the selection owner
and Parameter resolution. The immutable resolution index is returned only after
every matching occurrence succeeds; inventory copying, unrelated slots and all
selected candidates consume cumulative budgets. Linking an already resolved
occurrence is rejected. This execution obligation does not itself construct a
persistent Unit limit or certify backend enforcement.

The selector alone only selects the Host/author ceiling scope. It leaves the original
envelope unresolved and neither emits a persistent Unit limit nor installs
runtime enforcement. Those connections are required before the formal Program
constructor can admit the aggregate; a selected number alone cannot close it.

## Reference compatibility

Persistent ordinary-group limits use the Unit/step/aggregate-name/scoped
references defined in [resolved limits](../spec/language.md#resolved-limits).
This fixes a formerly unspecified subscope, distinct from an operation's whole
output. Sketch at `87dc7144` uses `array_agg:<Program path>.<name>` for limits
and the containing Program path for input-bound proofs. Those strings are not
portable Unit identities and cannot be copied into the persistent representation.
The scoped form distinguishes sibling aggregates and item/byte quantities even
when their numeric limits coincide. Generic witness schemas remain unchanged;
semantic admission must verify the referenced call and its dependencies.

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
