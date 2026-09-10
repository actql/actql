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

Multiple independent candidate-key witnesses, join cardinality propagation and
new keys established by grouping remain part of the shared evidence work, not
implemented by this single input assertion. The pooling checker and pipeline
retain these dependencies when they use the declared identity. Unknown key types
cannot be treated as known scalar member types merely because a declaration exists.
