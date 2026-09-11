# Relation key declarations and evidence

`transfer_set_keys` preserves left candidate-key witnesses through except and
intersect, for both ALL and DISTINCT. Language's row-set multiplicity rule
returns unchanged left occurrences; right keys and full-row deduplication do not
establish a missing left field key. The transfer requires the exact checked left
schema, retains declaration/producer/alias/validation metadata, and binds the
witnesses to the output contract under a bounded witness-copy budget. The aligned
output schema may widen nullability or extents, while retained left key evidence
still proves the stronger property of the surviving occurrences. This does not
narrow the ordinary output type or validate input uniqueness at checking time.
The fixed Sketch compiler has no matching set-operation transfer implementation;
the current normative occurrence law is the basis of this transfer.

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
order-only operations. Derive transfers exact whole-field copies and invalidates
computed overwrites of key aliases, while
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
and origin location remain attached. For input declarations, admission validators use
`declared_records` and `declared_key_field_at`, not the renamed output tuple.
Transfer work and name bytes are bounded and charged to the pipeline budget.

## Independent input evidence

`pipeline_typing.combine_relation_evidence` binds a candidate-key collection and
ranking annotations into an opaque `RelationEvidence`. Pass it using
`RelationEvidenceInput` to retain both axes on one pipeline input; the existing
key-only and ranking-only variants remain available. Combining never chooses a
preferred key or changes the score domain, producer, original declaration or
validation obligations. Uniqueness does not authenticate a score declaration,
and a captured score contract does not establish a candidate key.

The constructor checks the same row-knowledge or complete-schema handle in
constant time, matching the key-collection ownership boundary. Merely equal
independently constructed schemas are rejected, as are non-Relation rankings.
An empty collection and unannotated ranking can accompany shared partial
knowledge without inventing facts. The checker still preflights the input
contract and all key witnesses against the pipeline's shared budget. Annotation
transfers and consumers retain their own existing budget checks.

This is an implementation-boundary extension, not new authored syntax or
permission to reuse evidence for unrelated captured data. The independent axes
then follow their own transfer laws through branches and exact aliases; merging
their container does not discharge the source-admission, score-authentication or
producer-execution requirements. Other shared evidence axes remain separate work.

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

`select_sole_string_key` is the separate nearest role-inference rule: admit only
singleton non-null string components and require exactly one distinct field.
It scans and charges all witnesses and aliases, deduplicates identical fields
for this decision, and returns no key for zero or multiple candidates. It must
not be replaced by canonical preferred selection, which could hide ambiguity.

Alias alternatives are retained per component. Selecting the smallest eligible
alias for each component yields the smallest sorted tuple without expanding the
Cartesian product: valid key components have disjoint output aliases. Selection
reorders only the current tuple and alias groups. Original admission fields,
row contract, source and obligations stay attached unchanged. Collection and
selection charge witness/component/alias visits and UTF-8 name bytes; selection
also charges selected tuple elements. Sorting is O(k log k) for a k-component
tuple; work units are logical visits, not CPU-time measurements.

`transfer_keys` applies the unary transfer rules to every independent witness.
It prepares derive-lineage or projection lookup tables once per operation and
builds one shared output row contract. Each witness then visits its own components
and aliases, retaining all explicit output aliases or dropping only that witness
when a component has no surviving alias. Projection work is proportional to the
prepared mapping plus visited and emitted aliases, not witnesses times the whole
projection. Name lookup distinguishes qualified provenance from a literal dotted
name. `transfer_unary` delegates to the same implementation with one witness.
An empty result collection still retains the operation's output row knowledge.

For derive, `relation_typing.binding_copy_at` reports only normalized whole-field
or join-field expressions. It uses the already checked reference target, without
copying the expression's reference array. Map references resolve against the input
snapshot; array references may resolve to a prior slot. Transfer resolves each
slot's original input lineage once and constructs an original-field to final-alias
map. This preserves a saved copy when a later slot shadows the original field,
but not a copy of a computed replacement. Self-copies preserve evidence; arithmetic,
casts, templates and property extraction do not establish whole-field equality.
No constant folding, algebraic simplification or type equality alone proves a copy.
This implements the existing exact-copy rule in
[derive](../spec/language.md#derive); it does not add a new identity inference rule.

The pipeline accepts `CandidateKeysInput` and carries collections through these
unary transfers. `KeyedInput` wraps one existing declaration without rescanning
it before the normal input budget check. All witnesses and aliases are charged
at that boundary, including unused inputs. `candidate_keys` returns the retained
collection. Legacy `candidate_key` and `input_key` return a witness only when
exactly one witness remains; they do not perform preferred-key selection or
implement the language's distinct-tuple sole-candidate inference rule.

Relation pooling selects an eligible scalar member key at the consumer boundary
and charges selection to the same pipeline budget. Join cardinality propagation,
zero-column cardinality facts, cross-family produced keys and other completion
consumers remain shared evidence work. This integration does not establish actual
runtime uniqueness or ordering.

## Operation-established keys

`advance_keys` combines unary transfer with keys established by a checked group,
keyed/whole-row distinct, dedupe, unique assertion or pivot. The input operation
is opaque and already checked; callers cannot invent these witnesses using a
public uniqueness flag. Group fields, dedupe fields, assertion fields, distinct
output fields and pivot index fields provide the corresponding tuple. Repeated
partition references count once in the derived uniqueness tuple; their authored
operation still retains the original repetitions and order.

`key_origin` distinguishes input declarations from these producer results, and
`key_producer` retains the checked operation through later alias transfers.
Calendar-series keys use `CalendarSeriesResult` and `key_calendar_producer`
instead; the internal producer is a tagged alternative, never two competing
origins. `advance_calendar_keys` creates the series start key or transfers bucket
input witnesses. `transfer_calendar_keys` is the bucket-only entry and refuses
generators or unrelated inputs. Both retain the original producer through later
transfers and keep `ValidateKeyProducer` pending.
Fixed-duration grids similarly use `TimeSeriesResult`, `time_series_keys` and
`key_time_series_producer`; their `time` field is the conditional candidate key.
The retained checked series also exposes its statically known row count when
available, without claiming downstream cardinality or source coverage.
For a produced key, `declared_records` and `declared_key_field_at` describe its
original producer output, not an upstream input primary-key declaration.
For these operation-derived keys, `key_pending` returns `ValidateKeyProducer`:
consumers must retain that producer's
execution and validation obligations, including atomic assertion and top-tie
failure where applicable. They must not apply local-input duplicate normalization
to an operation result or treat successful type checking as observed uniqueness.

The [explicit Carrier bridges](carrier-projection.md) also retain conditional
identity witnesses. Graph node/edge tuples use `GraphProjectionResult` and
`key_graph_projection_producer`, preserving graph-record admission and source-role
aliases. Vectors use `VectorProjectionResult` and `key_vector_projection_producer`;
their pending set additionally makes component, whole-tuple uniqueness and
reference validation explicit. Neither bridge is a public proof boolean, and
neither changes a downstream consumer's admissible key domains.

The pipeline advances this evidence even when no input key was supplied. It
preserves independent inherited keys where the operation allows them and appends
the new witness without rewriting provenance. Nullable grouping keys and
whole-row keys containing structured values retain their actual contracts;
non-null scalar/reference completion eligibility is still checked by each use.
An empty tuple does not create a fabricated field ID or imply sorted rows:
global group/dedupe cardinality facts require the separate cardinality boundary.

`window_group` uses the same producer-key boundary as ordinary grouping. Its
checked group includes the proven window boundary fields followed by authored
group fields, even when the authored `by` array is empty. The entire tuple is
retained, including through later exact projections; dropping any required
component loses the witness. The checked producer preserves repeated authored
keys, while its derived uniqueness tuple counts each field once. Window-role
evidence and candidate-key evidence remain distinct: neither boundary names
alone nor successful type checking establish runtime uniqueness. This follows
the existing `window_group` group-key law rather than adding a new source rule.

## Field coverage for uniqueness consumers

`select_covered_key` selects a conditional witness whose entire component tuple
is covered by supplied field occurrences. One surviving alias per original
component suffices; repeated occurrences do not cover a missing component.
Among covered witnesses it uses the same arity then UTF-16 tuple ordering as
canonical selection, without expanding the Cartesian product of aliases.
Tagged field provenance is compared exactly: a displayed `left.id` name is not
by itself evidence of a qualified left-side reference.

Coverage differs from scalar identity/order completion eligibility. A nullable
grouping key can still prove uniqueness of matching non-null join keys under
the join's own rules. Coverage therefore retains the key's actual contracts
rather than imposing a non-null scalar restriction. Consumers must independently
check operation-specific comparability, bind the witness's record contract to
the actual operand, and retain its original producer/admission obligations.
This API does not accept an arbitrary boolean proof or rebind a key to another
Relation. Pipeline join inference uses this boundary against each checked
operand's own immutable schema, never a structurally similar foreign schema.

The field set is copied into a provenance-tagged lookup under work/text budgets;
all witnesses and alias candidates share the remaining budget. Returned selected
fields are detached from caller arrays, while immutable declaration and producer
provenance remain attached. Selection does not consume or mutate alternative keys.

`pipeline_typing.join_evidence` exposes the selected left/right witnesses,
authored assertion and combined conditional cardinality for an ordinary join.
Each side is unique if its full join-key tuple covers a candidate key or the
authored assertion requires that side's uniqueness. Repeated equality pairs
remain in the checked operation but cannot cover a missing key component.
One proven side combines with an asserted opposite side as one-to-one; unknown
on both sides remains unknown, never an inferred many-to-many assertion.

The derivation charges pair preparation and candidate selection to the pipeline's
shared work/text budgets and keeps both sources of evidence. Conditional count
transfer uses these combined facts without evaluating rows or discharging
`ValidateCardinality` or producer/input admission obligations. Join-output key
transfer and dependency-closed Plan serialization remain separate unfinished
connections; this pass does not grant downstream output uniqueness by a flag.
