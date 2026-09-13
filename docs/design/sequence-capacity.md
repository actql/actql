# Sequence capacity consumer binding

`capacity_sequence_limit.check_host_limits` associates both sequence limit
scopes with one actual checked pipeline step. It handles Host candidates and
separately owned authored restrictions;
it is not complete source admission, whole-pipeline checking, an observed match
count, runtime enforcement, or permission to execute.

The normative owners are [Sequence](../spec/language.md#sequence),
[resolved limits](../spec/language.md#resolved-limits), and the pinned
[Host witness contract](../spec/protocols/contracts.md#capacity-host-policy).
The fixed Sketch `87dc7144` compiler uses the same two field/unit associations
and binds them independently to `TEA.sequence.match` parameters. The current
checker does not copy its older source restrictions or implement lowering.

| Scope | Required selected-policy field | Unit | Enforcement |
| --- | --- | --- | --- |
| Matches per key | `max_temporal_matches_per_key` | `matches_per_key` | engine atomic |
| Total output matches | `max_temporal_output_rows` | `rows` | engine atomic |

## Application and ownership

Both limits are selected by index from the same retained mixed witness/limit
collection. Their candidates have already passed arithmetic, canonical body,
identity and collection-wide Host-source checks. This entry additionally
requires every candidate occurrence to use the exact selected policy CID and
the applicable field/unit. Equal values do not permit substituting the Relation
output field for the temporal output field. Candidate lists are nonempty;
their exact minima are checked by wire admission. Repeated identical Host
candidates are retained and charged separately.

The local subjects are `sequence:checked-step:<index>:matches-per-key` and
`sequence:checked-step:<index>:output`. These are owner-relative application
references, not Program/Invocation identities or an imported compiler-reference
resolver. The opaque result retains the exact pipeline, step, source collection,
selected policy and both original limit handles and indices. Swapped subjects,
wrong enforcement, missing limits and non-sequence operations fail atomically.

`max_work` charges one visit per scope and one per candidate occurrence,
cumulatively across both scopes. It is checked before candidate iteration;
only a constant-size pair of handles is allocated. Limits and sources retain
their separately admitted body/reference budgets. Successful binding does not
mutate the checked sequence or remove `AtomicMatchLimits`, identity, time,
predicate or binding obligations. No output row count is inferred.

## Collection coverage

`check_applications` requires one opaque application per local sequence step,
including unused branches. It scans every step rather than trusting the supplied
application list as the scope. Registration requires the exact pipeline and
Host-source collection owners and the selected policy CID. Re-admitting the
same bytes does not make a foreign collection handle interchangeable.
Applications may arrive in any order; duplicates are rejected. The result owns
its per-step index and limit-consumption bitmap independently of caller arrays.

Each application consumes both of its original mixed-collection limit indices.
`consumes_limit` reports exact index membership, and `unconsumed_limit_count`
keeps unrelated limits visible. `check_complete` additionally requires every
limit in this dedicated collection to be consumed by a sequence. Use the partial
entry when other consumer families must account for the remainder. Neither
entry claims that those other operations, upstream producer owners or all source
claims have been checked.

Collection work is `2 * steps + limits + 3 * applications`: owned step slots
and the all-step coverage scan, limit slots, registration and two consumptions.
This cumulative limit is checked with overflow-safe subtraction before allocating
the index arrays. Individual application checks retain their own candidate-work
budgets; coverage does not rerun or reset them. Tests cover both missing branches,
out-of-order registration, foreign owners/policy, duplicate applications, exact
and one-short budgets, detached results and unconsumed limits.

The [Graph/sequence consumer coverage check](graph-input-preflight.md) combines
this ledger with Graph input bindings from the same pipeline, policy and source
owner. It rejects any mixed limit left unconsumed across those two families;
it does not make other consumer families or upstream checks optional.

## Explicit remaining boundaries

`check_bound_limits` additionally accepts the same pipeline's owned
`BoundAuthorGuards`. It retains the exact occurrence index and effective binding
for each authored scope and computes `effective_maximum` independently as the
minimum of its Host candidates and authored restriction. Equal or looser guards
remain present; omission does not synthesize a guard. `host_limit` (and the
compatibility reader `limit`) returns the original Host-only input claim, not
the final guard-inclusive minimum. Enforcement consumers use `effective_maximum`.

The collection requires one consistent immutable Parameter binding among its
guarded selections. The application closure checks that binding against the
same producer visit's bound guards; independently collected occurrences from
the same pipeline and same bound-values owner are valid, while re-binding equal
values does not establish ownership. Selection work includes every inspected
guard occurrence, including other steps, before both candidate scopes.

Combined capacity preparation accepts these already collected and bound guards
through `prepare_application_coverage(..., guards=Some(...))`. It checks the
pipeline owner before preparing coverage and, when count bindings are also
provided, requires the same immutable Parameter values. Sequence selection and
all other preparation work share the existing cumulative work cap. Guard
collection and binding are prior charged preparation, not repeated here.

Selection alone does not construct an authored wire witness or assert its Unit
identity. Formal Program construction binds the producer's guards during capacity
preparation and converts them after the Unit Definition is known. Each scope's
final claim retains Host occurrences and inserts its Unit-owned guard in CID order;
the minimum and binding status include both, including equal or looser guards.
The wire-candidate output-proof resolver still rejects guarded selections until
those authored candidate dependencies can be connected to the proof. It must
not substitute the Host-only minimum or omit the authored source.

The [atomic Program application resolver](program-step-bounds.md#atomic-output-bound-construction)
can bind `actql.bound.sequence-output` to this result's output-row minimum and
use that conditional upper bound in later steps. It retains both enforcement
scopes but uses only output-row candidate CIDs as proof operands. In particular,
a same-valued per-key ceiling is not a total-row bound. The resolver and combined
coverage retain source/policy ownership and cumulative budgets; they do not
execute either enforcement or the sequence's other pending checks.

An authored `max_matches_per_key` or `max_output_rows` fails the Host-only
output-proof resolver entry with
`UnresolvedAuthorSource` for that scope. This applies whether the guard is
looser, equal or tighter than the Host ceiling. It is a supported-implementation
boundary, not a language restriction: the guard cannot be omitted until its
Program Definition identity, exact occurrence and resolved value are bound.
An unrequested author candidate or any other unsupported candidate source also
fails instead of being trusted based on its self-CID.

Host policy selection remains a Check Environment responsibility. The caller
must still validate every step/producer, applicable source, available candidate
and limit consumer in the combined boundary. This local result accounts for
two selected limits only; other limits in its collection are not consumed by
implication. Physical pipeline ownership does not establish Invocation binding
consistency. Engine-atomic enforcement must happen before publication and is
not executed by this static checker.

Fixed wire fixtures were independently serialized and SHA-256 hashed with Node.
Tests cover Relation/Events and overlap modes, independent maxima, repeated
candidates, exact/short budgets, policy/field substitution, incorrect subjects,
enforcement, missing scopes, unsupported sources, and preservation of guards
and pending obligations.
