# Relation schema representation

`relation_schema.Schema` is an opaque, complete set of Relation field contracts.
It separates Relation field references from ordinary object value contracts.
It carries no rows, keys, ordering witnesses, authority or execution evidence.

## Field references and adapters

`FieldName` distinguishes `Unqualified(name)` from `Qualified(Left, name)` and
`Qualified(Right, name)`. These are explicit field references, not nested object
paths. A qualified `id` renders as `left.id` or `right.id`; an unqualified name
containing a dot remains invalid. This follows the distinction between authored
names and qualified join references in the
[field-name rules](../spec/language.md#ordering).

`from_object` accepts an already checked, non-null object row contract in O(1),
sharing its immutable fields and child contracts. Empty rows are supported;
nullable objects and non-object roots fail with `InvalidRowContract`.
`as_object` returns that flat representation only when all columns are required,
or `None` for conditional columns or qualified fields. It never drops presence
or provenance or manufactures an object contract
with dotted names. Field nullability remains independent of root row validity.

`from_fields` validates and copies the supplied field list. Each unqualified
name or qualified leaf obeys the existing authored field-name rules, including
well-formed UTF-16, NFC/LF canonical form and reserved-name rejection. It does
not normalize or repair names. Duplicate references fail; `id`, `left.id` and
`right.id` are distinct. Supplied child contracts are already opaque and checked
and are shared without traversing their contents.

Fields are indexed in UTF-16 order of their complete reference spelling. This
order is not an authored projection order, row order or identity rule. `fields`
returns a detached array, `field_at` is bounds checked, and `lookup` uses binary
search with exact typed-reference equality. A raw
`Unqualified("left.id")` lookup cannot alias `Qualified(Left, "id")`.
`reference_name` renders a reference; it is not a validator or parser.
`lookup_reference` resolves an exact spelling against admitted entries and
returns the typed field. It does not parse nested access or invent provenance.

## Construction limits and scope

`from_fields` requires nonnegative `max_fields` and `max_name_bytes`. The latter
counts the full UTF-8 reference spelling, including `left.` or `right.`.
Limits equal to consumption are accepted. Prefix and leaf size are checked
before allocating their concatenation. Sorting uses cached reference spellings;
construction requires O(n log n) name comparisons and O(n) field storage.
Name validation and comparisons also consume work proportional to their text.
The budgets cover this construction, not the recursively shared child contracts
or total physical heap usage.

Constructing a qualified schema does not validate a join, establish provenance
evidence, extend nullability or prove cardinality. It is representation only.
The [pipeline checker](pipeline-typing.md), unary operation checker and Result
checker retain qualified fields. Local join requires flat operand schemas;
explicit projection must remove qualification before rejoining.
No general Carrier union, Graph/Vectors/Events checking or lowering is provided.

## Row presence

Each field has an independent `Required` or `Conditional` existence contract.
`from_object` and `from_fields` make all fields required. `from_presence_fields`
admits the same bounded finite column set with explicit row presence. Nullable
permits a present NULL; Conditional permits key omission, including for a
non-nullable value type. Closed column knowledge therefore does not imply that
every declared column occurs in every row. Ordinary object value contracts keep
their exact required-field rules.

The execution profile permits projection, Required-only filter/derive expressions,
Required-key sort, proven-order take, Required-key DISTINCT and complete-row
DISTINCT on conditional inputs. Every syntactic
expression reference and authored sort key must be Required,
including references in lazy/dead branches; runtime samples and `IS NOT NULL`
do not provide a presence proof. Graph definition/label selection derives its
schema from declarations through its existing Bridge contract, not row predicates.
Filter preserves the input schema, occurrence order and cell presence. All input
rows are admitted and charged before predicate evaluation, including rows that
will be rejected. The existing bounded evaluator copies admitted surviving cells,
charges presence containers, and retains them until output handoff or cleanup.
Logical wire retention omits absent keys without inventing NULL values; physical
presence slots remain charged by the common row owner. Derive retains unchanged
fields' presence and adds present computed bindings with their checked value
types/nullability. Ordered replacement refers to its exact prior binding version:
replacing an optional input field with a computed binding makes the new field
Required without reading or proving the old optional field. Both synchronous
and resumable evaluation use the existing expression, row and completion owners.
Physical Store save/reload preserves derived rows before guaranteed projection.
Sort moves each complete
typed row, including absent cells, according to its existing admitted order
completion; take applies offset/count to that proven order. Neither operation
promotes Conditional columns or discards them. Keyed DISTINCT instead projects
only its specified Required columns, then deduplicates the complete projected
rows in first-occurrence order. Omitted, NULL and present values of unselected
columns do not participate in equality; the entire sparse input and its presence
slots still undergo admission and resource accounting. Its projected output is
dense and uses the existing completion, Store export/import and cleanup owners.
Complete-row DISTINCT instead includes every column's presence and value in
equality and retains each survivor's complete admitted row. Omission is unequal
to a present NULL. Its private index comparison places omission before present
cells solely to group equal rows, discards that index order and emits survivors
in first-occurrence order. Typed presence failure remains a failure rather than
omission; no scalar represents missingness. This does not permit an authored
Conditional reference or prove stable order. Selection and retained presence
slots use the existing bounded row workspace and cleanup path. Other row consumers reject conditional inputs rather than rebuilding
their schema as dense or filling absent cells with NULL. Public Results require
required selected and ordering columns.

`execution_relation` keeps absence in its immutable row representation, not in
the scalar Value domain. Typed access distinguishes absence from a present
admitted value and invalid coordinates; ordinary value readers require a schema
guarantee. Copy, input buffers, physical Store leases and retained wire reload
use the same owners, cumulative budgets and cancellation paths as dense rows.
Presence slots consume resources even when their values are absent. Their
physical layout does not contribute to content identity.

Canonical rows omit absent keys and emit explicit NULL unchanged. Required
schema entries retain the checked value-contract preimage (required presence is
implicit); conditional entries use `{contract: <checked type>, presence:
"conditional"}`. This cannot alias a checked value contract, whose discriminator
is `type`. Presence therefore changes schema identity, independently of row
contents. Equal fully present rows retain their existing content identity.
