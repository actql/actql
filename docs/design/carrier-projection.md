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
