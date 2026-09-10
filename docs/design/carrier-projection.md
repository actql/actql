# Explicit Carrier projections

`carrier_projection` checks `events: true` and `vectors: true`. The selected
Carrier must match the operation; these are explicit conversions to Relation,
not permission for consumers to reinterpret another Carrier as rows.

The result retains the semantic record field names and recursive contracts,
including original event IDs, composite vector identity fields and vector
dimensions. Partially typed or open fields remain partial or open. An opaque
Events/Vectors input yields unknown Relation knowledge, not a complete empty
schema or invented `id`/clock/component columns. Missing static evidence remains
missing for downstream operations and Result publication.

Checked inputs and their recursive contracts are immutable and shared. The
standalone budget counts the boolean body and each inspected field/name;
children are not copied or recursively traversed. Pipeline admission separately
preflights those children and shares work, node and text budgets across steps.
Invalid body diagnostics retain source path and span.

Event projection preserves existing window roles because it neither renames nor
changes record fields. This permits `window_events -> events -> window_group`.
It creates no window roles from names, no candidate keys, no ordering witness
and no proof that external records have already passed runtime admission.

Reference bridges expose physical `id`, `event_time_ms` or `vector` fields.
ActQL's semantic contracts preserve authored roles instead; backend lowering
must restore those names according to Language's Carrier bridge rule. These
checkers do not implement that adapter, event identity uniqueness, vector f32
admission, data evaluation or publication checks.

## Vector identity evidence

The pipeline's `relation_evidence.vector_projection_keys` boundary retains the
ordered intrinsic vector identity as a conditional Relation candidate-key
witness. `VectorProjectionResult` and `key_vector_projection_producer` retain
the exact checked bridge and its input Carrier, including composite domains;
opaque Vectors contribute an empty witness set, never a guessed `id` key.
This is separate from the structural projection checker above. Whole-tuple
uniqueness, component admission and reference revalidation remain explicit
obligations alongside `ValidateKeyProducer`; structural types do not discharge
them. No input duplicate repair or data validation is performed here.

Exact projection aliases and later row-preserving/subsetting operations retain
that origin using the existing shared key rules. Losing any tuple component
loses the key, while removing one of several exact-copy aliases need not do so.
Consumers retain their own selection rules: canonical completion can use a
whole comparable tuple, but Relation nearest's implicit-ID rule still requires
a sole non-null string key. Vector-to-Relation conversion does not broaden it.
Field traversal and UTF-8 name costs are charged to the shared pipeline budget.

Event window assignments may repeat original event IDs. The vector identity
rule is not applied to Event bridges or Graph projections; their distinct
identity/multiplicity transfer remains separate work. Neither this witness nor
the bridge supplies general logical-order or publication proof.
