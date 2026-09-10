# Structural Carrier contracts

`carrier_contract` represents the structural type information used by
[pure operation checking](pure-operation-checking.md). Its four Carrier kinds
are Relation, Graph, Events and Vectors. It does not implement bridge evaluation,
acquisition, identity issuance, candidate-key proof, order proof, policy admission
or publication authorization.

## Relation knowledge

`Knowledge` separates an open/closed field set from each known field's optional
value contract. Names use the existing provenance-aware Relation schema names.
Lookup returns one of:

| Result | Meaning |
| --- | --- |
| Unknown | The open field set does not establish whether the name exists. |
| Absent | The closed field set excludes the name. |
| Present with no contract | The field exists, but its value type is not known. |
| Present with a contract | The field exists with that admitted recursive type. |

`complete_schema` succeeds only for a closed field set with every type known.
An empty closed set therefore has a valid empty row schema, whereas an empty
open set is unknown. Neither unknown fields nor unknown types become `json`.
The name-validation implementation uses a private placeholder solely to reuse
the existing schema name gate; that placeholder cannot be observed as evidence.

`rows` validates field count and full UTF-8 reference-name budgets, canonical
names, duplicates and provenance. It copies arrays and shares already admitted
child contracts. `typed_rows` adapts an existing complete schema in linear
field-count time without recursively traversing child types. Lookups use binary
search in canonical UTF-16 reference order. Whole input/Parameter preflight and
cumulative pipeline budgets remain the consuming checker's responsibility.

## Other Carriers

A Graph structural contract retains a non-null comparable identity domain,
node/edge property knowledge and an optional closed label domain. Its property
names are flat; raw join qualification needs explicit projection first. Label
collections are canonical, duplicate-free, byte/count bounded and detached.
Absent label-domain evidence is not proof that a semantic label role exists.
The constructor never validates graph records, endpoints or actual uniqueness.

Events retain record knowledge and known identity/time roles. Event-stream time
must already have non-null numeric millisecond type; Relation timestamps use the
specified conversion when constructing an event bridge, not implicit conversion
in this type constructor. Additional payload fields may remain unknown.

Vectors retain record knowledge, an ordered nonempty tuple of non-null comparable
identity fields, and a non-null vector field with its checked dimensions. Tuple
order is preserved; fields cannot repeat. This supports composite semantic
identity without inventing a scalar field or uniqueness proof. It performs no
quantization, metric evaluation or embedding-model equivalence check.

An opaque non-Relation Carrier retains its kind without inventing structural
roles. An opaque Relation is represented by unknown row knowledge. Returning
Relation knowledge is an explicit kind test; there is no catch-all conversion
from Graph/Events/Vectors to a row schema.

These constructors validate supplied structural constraints. They do not turn
supplied constraints into evidence that runtime data meets them. Checked-role,
law-identity and evidence-propagation boundaries must be connected by the
pipeline implementation; this package alone is not a complete pipeline checker.

## Verification

Tests distinguish unknown/absent/untyped fields, complete/open field sets,
empty schemas, provenance, exact constructor limits, canonical name ordering,
collection ownership, Carrier mismatch, event clocks and composite vector IDs.
Child contracts remain opaque and are shared rather than recursively copied.
