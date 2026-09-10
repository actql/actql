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
`as_object` returns that flat representation, or `None` for a schema containing
qualified fields. It never drops provenance or manufactures an object contract
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
