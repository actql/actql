# Sequence checking

The normative owner is [sequence](../spec/language.md#sequence).
`relation_typing.check_sequence` reuses the existing bounded predicate admission
and expression checker, with a known-field lookup table built once across all
pattern elements. The result is a Relation contract even for Events input.

Relation clocks can be non-null numeric UTC milliseconds or timestamps requiring
conversion. An explicit Events clock remains numeric-only under the existing
closed clock rule; the fact that Events can retain a timestamp intrinsic role
does not relax that rule. The explicit ID must preserve intrinsic Events identity.
Decimal and Ref identity types are retained rather than replaced by strings.
Actual clock values, unique identity, ascending event order and bounded matching
remain execution obligations, not conclusions from type checking.

Each pattern predicate retains its typed expression, including source locations,
profile requirements and unresolved validations. Nullable Boolean is admitted
as for a relation filter; only true matches. Labels do not create predicate scopes
for subsequent slots. Pattern nodes, text tokens and expression work share the
operation budget. Unknown unreferenced payload is not widened to JSON and does
not require a complete record schema.

Output retains each distinct group field once, numeric match boundaries and the
label-specific typed ID/numeric clock columns. Generated output names are checked
with the ordinary field-name rules. Collision checks concern actual output, not
payload fields that are not retained. Repeated key occurrences remain in the
checked source; they neither duplicate output columns nor prove uniqueness.

Empty grouping is explicitly one global partition, consistent with the established
partition decision criterion. It is not an identity operation. The reference
decoder's fixed match-limit fallbacks are not imported: absent guards stay absent
and resolved Host limits remain mandatory. Source guards and within Parameters
are not read from defaults or treated as concrete bounds.

The predicate checker is reused within `relation_typing` rather than duplicating
its syntax, scope and diagnostic machinery in a second package. Detached pattern
and key arrays cannot mutate the checked result. Pipeline input occurrence and
Result output types are connected, but no match rows or automaton are evaluated.
Checking a predicate does not discharge its profile or Host-envelope obligations.

The Program operation index binds event-value admission, global event-identity
validation and preparation of ascending `(time,id)` matcher input to the exact
`SequenceSemantics` occurrence and its primary input edge. The readonly binding
retains the original checked sequence, including identity/clock contracts,
timestamp conversion requirements and partition selectors. No predicate, key or
pattern array is copied when building these checks.

These three duties precede use of the input by the matcher. Sorting its input
does not attest that the source had a logical total order, and selecting an
identity field does not attest uniqueness. Empty input and known duplicate-ID
fixtures retain the same duties; they are not already executed observations.
Bounded matching, within binding, predicate checks and both atomic match-limit
scopes remain separate. Input-duty binding alone cannot close those requirements
or enable the formal sequence Program entry.

## Nonoverlapping match identity

`relation_evidence.sequence_keys` establishes one conditional singleton key per
pattern label when `overlap: disallow`. Each key retains the complete checked
sequence as its producer, its original generated field and that field's actual
identity contract. Keys are independent, not one composite key requiring all
labels to survive. `overlap: allow` supplies an empty key set, never a guessed
match-boundary key or a uniqueness claim from the grouping fields.

The pipeline now transfers these keys through ordinary exact-copy aliases and
subsequent preserving operations. Losing one alias does not lose other copies;
losing one label's key does not remove another surviving label's key. Sort/take
and Result publication can retain this evidence through their existing
completion boundaries. `SequenceResult`, `key_sequence_producer` and
`ValidateKeyProducer` keep event-value admission, global event identity,
ascending order, matching, profile, binding and atomic capacity obligations
attached. None is discharged merely because a candidate key was inferred.

This closes an implementation omission: the normative sequence rule and fixed
Sketch `87dc7144138edfcba108cdc59dc485ac976ba976` compiler both establish the
individual label keys for disallowed overlap. No source acceptance, identity
domain or machine contract changes. Original identity types remain intact;
the reference's string-only output typing is not imported.

Indexed pattern access avoids copying the predicate array. Work and generated
field-name bytes are charged before each witness is constructed. Tests cover
Relation and Events, both overlap and contiguity modes, independent label keys,
alias survival, retained validation debts, exact budgets, contextual order
consumers and Result publication.
