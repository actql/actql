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
Candidate-key evidence for disallow matching remains conditional on validated
identity and matching semantics; the shared proof boundary must establish it
before consumers rely on it. Checking a predicate also does not discharge its
profile or Host-envelope obligations.
