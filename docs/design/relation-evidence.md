# Relation key declarations and evidence

The normative owner is [local inputs](../spec/language.md#local-inputs).
`relation_evidence.declare_primary_key` admits an explicit primary-key assertion
against a particular immutable Relation contract. The result owns the ordered
key components and retains the same row knowledge and source location. It is
opaque: consumers cannot pair its key with an unrelated row contract or create
one with a public `unique: true` flag.

The assertion list is nonempty and duplicate-free, with authored field names.
Known absent columns, nullable types and non-KeyComparable domains fail at the
offending component. Unknown columns/types stay unknown and retain admission
requirements. A columns-only input is not promoted to a complete typed schema.
Field count and aggregate UTF-8 name bytes are bounded; component access is
indexed without copying the whole tuple.

This is conditional static evidence from an input contract, not a report that
runtime data has been inspected. Every consumer must retain requirements to admit
present non-null comparable components, validate complete-tuple uniqueness after
the explicitly allowed input duplicate normalization, and revalidate reference
components. Physical arrival order establishes nothing. Validation of types
alone does not discharge these requirements.

`transfer_unary` preserves the input assertion through row-subsetting and
order-only operations. Derive invalidates overwritten key aliases, while
select/rename/drop and keyed distinct transfer explicit aliases. Whole-row
distinct preserves the key. Every original component must retain at least one
alias; aliases are alternatives, not extra tuple components. This representation
avoids expanding their Cartesian product and does not lose a key merely because
an earlier alias is removed. Other operations currently return no inherited key.

The transfer consumes a checked operation on the exact retained schema handle,
not a structurally equal but unrelated schema. This is an evidence API ownership
boundary, not a restriction on authored Relation schemas. It also avoids an
unbounded structural equality scan. Output contracts come from that operation;
input-admission obligations, original input row contract, original tuple names
and declaration location remain attached. Admission validators use
`declared_records` and `declared_key_field_at`, not the renamed output tuple.
Transfer work and name bytes are bounded and charged to the pipeline budget.

## Candidate collections and completion selection

`collect_keys` owns independent conditional witnesses on the same immutable row
knowledge (or exact complete schema handle), not a structurally equal but unrelated
contract. An empty collection establishes no key. Counts refer to witnesses, not
distinct canonical tuples; repeated declarations retain their provenance.

`select_key` follows [deterministic completion](../spec/language.md#completion):
eligible fields only, each tuple in UTF-16 code-unit order, shortest tuple first,
then lexicographic field sequence. Identical tuples are equivalent for selection;
the original collection is not rewritten. This is not the sole-candidate check
required by omitted `infer.key`.

`CanonicalOrder` allows known non-null reference types as well as scalar types;
`ScalarIdentity` selects primitive scalar domains supported by scalar identity
encoding. It does not prohibit reference identities elsewhere in the language.
Unknown types cannot become known merely because a key was declared. Neither
mode establishes runtime uniqueness or actual sorted rows.

Alias alternatives are retained per component. Selecting the smallest eligible
alias for each component yields the smallest sorted tuple without expanding the
Cartesian product: valid key components have disjoint output aliases. Selection
reorders only the current tuple and alias groups. Original admission fields,
row contract, source and obligations stay attached unchanged. Collection and
selection charge witness/component/alias visits and UTF-8 name bytes; selection
also charges selected tuple elements. Sorting is O(k log k) for a k-component
tuple; work units are logical visits, not CPU-time measurements.

`transfer_keys` applies the unary transfer rules to every independent witness.
It prepares overwritten-name or projection lookup tables once per operation and
builds one shared output row contract. Each witness then visits its own components
and aliases, retaining all explicit output aliases or dropping only that witness
when a component has no surviving alias. Projection work is proportional to the
prepared mapping plus visited and emitted aliases, not witnesses times the whole
projection. Name lookup distinguishes qualified provenance from a literal dotted
name. `transfer_unary` delegates to the same implementation with one witness.
An empty result collection still retains the operation's output row knowledge.

The pipeline accepts `CandidateKeysInput` and carries collections through these
unary transfers. `KeyedInput` wraps one existing declaration without rescanning
it before the normal input budget check. All witnesses and aliases are charged
at that boundary, including unused inputs. `candidate_keys` returns the retained
collection. Legacy `candidate_key` and `input_key` return a witness only when
exactly one witness remains; they do not perform preferred-key selection or
implement the language's distinct-tuple sole-candidate inference rule.

Relation pooling selects an eligible scalar member key at the consumer boundary
and charges selection to the same pipeline budget. Join cardinality propagation,
new keys established by grouping, and other completion consumers remain shared
evidence work. This integration does not establish runtime uniqueness or ordering.
