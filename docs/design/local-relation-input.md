# Local Relation input declarations

`local_relation_input.read` reads an already source-normalized, owned input
declaration. It covers the `relation` shorthand and the local Relation object
form from [Local typed inputs](../spec/language.md#local-inputs), including
`expected_columns`, inline `schema`, `primary_key`, `duplicates` and `meta`.
It requires explicit `carrier` in the object form and rejects unknown fields.
Other Carriers, SourceView and receipt inputs need their own admission boundaries;
this entry is not a general Input dispatcher or a completed CheckedProgram.

## Evidence retained

Optional `minimum_classification` admits exactly `public`, `internal`,
`confidential`, or `restricted`, as pinned by the Program input schema. The
reader retains it as an authored lower bound, with absence preserved as None.
It does not assign an observed classification, default to public, lower a
Host/Connector classification, or authorize model/provider egress. The language's
[inference boundary](../spec/language.md#infer) requires effective classification
and current data-handling checks separately. Unknown source classification still
cannot be repaired merely by supplying this authored floor. This closes an earlier
reader acceptance omission; it does not change the schema or language.
Sketch `87dc7144:src/actql.ts` also admits this field; its legacy `schema_ref`
spelling is not imported. Ordinary source preflight charges the classification
key and value, and invalid vocabulary retains the original field cursor.

Absent schema yields open field knowledge. `expected_columns` is duplicate-free
and may be empty; listed fields are known present without inferred value types.
Additional fields remain unknown, not absent. Inline schema uses the common
author value-contract reader and yields a closed typed field set, including an
empty map. Every expected column must occur in that closed schema. Nullability,
recursive types and decimal precision/scale retain the common reader's rules.
No `json` placeholder or implicit carrier/schema completion is introduced.

Primary-key declarations use the existing conditional key evidence constructor.
Known fields must exist, be non-null and KeyComparable. Unknown static types do
not by themselves reject: raw input value/type/non-null and tuple uniqueness
checks remain required. A returned key is not evidence that any rows have passed
those checks. This declaration reader does not attach Host-supplied type, source,
ordering, acquisition or policy evidence to the input.

Duplicate policy defaults to reject. `first_by_order` retains its nonempty
authored order terms, including repetition, through the common OrderKey reader;
known non-orderable or absent fields reject. This is **not** resolution of its
mandatory independent total order. Before using normalized key evidence, the
enclosing input checker must establish the declared primary-key tuple, resolve
raw-field types and a sufficient total order, bind the policy and raw/normalized
limits, and retain raw admission before row selection. It cannot hide a malformed
discarded row or assume provider arrival order. No normalization is executed here.

## Ownership and limits

The result retains the input cursor, Carrier and optional conditional key.
Expected-name and order accessors return detached arrays. Metadata is nonempty
and rejects reserved top-level `actql_` keys while preserving nested business
keys. The whole input tree is checked for finite non-negative-zero numbers and
NFC/LF scalar strings; manually assembled noncanonical cursors are rejected, not
repaired. Source parsing remains responsible for normalization and key collisions.

One nonrecursive preflight bounds all source nodes, depth and UTF-8 text bytes
(keys included) together before field/type readers run. Root containers have
depth one. Child readers reuse these source bounds, not independent allowances
that could admit an oversized aggregate source. These caps bound source size and
depth; they are not a CPU-operation counter, heap cap or a bound on runtime rows.
The enclosing compiler must account for this pass within its Program budget.

`usage` exposes the consumed source node and text counts. The
[source-bound local input pass](stage-local-inputs.md) uses them to share the
allowance across actual stage declarations and attach exact declaration owners
to pipeline input registrations. This source-only attachment does not reconcile
Host evidence or discharge duplicate-policy requirements.

## Reference differences and remaining integration

`check_schema` checks a supplied complete, flat checked field schema against an
already read declaration. If the source has a complete schema, recursive
assignability is checked from supplied to authored, including exact object field
sets and nullability/extents. With only expected columns, all listed names must
be present, but extra supplied fields are permitted. Qualified join-output field
provenance cannot be reinterpreted as a local authored field map.

The opaque SchemaAgreement retains the exact declaration and supplied schema;
the returned Carrier uses that stronger schema without rewriting source. A
declared primary key is rechecked against newly known fields/types and remains
conditional on raw/normalized runtime admission and uniqueness. Supplied types
also recheck first-by-order fields for existence and AuthorOrderable domains;
they do not establish its independent total-order proof.

This is assertion agreement, **not Host evidence admission**. The enclosing
checker still must bind the snapshot's input source ref, Carrier, checked schema,
materialization/provenance and admitted Check Environment. There is deliberately
no registration of SchemaAgreement as a source-only stage input: an arbitrary
matching schema is not a validated Host snapshot. No snapshot wire shape, CID
preimage, signature or authority is invented by this helper.

The comparison's Limits apply to this type phase, independently of prior source
admission: max_nodes charges both type trees plus expected-column/key/order
checks; max_text_bytes charges their names and reference-domain text; max_depth
uses type-root depth zero. `schema_usage` reports these type-phase counters, not
source-tree usage. Iterative preflight bounds both trees before common recursive
assignability checking, and a depth-3,000 supplied type is tested. Exact/short
caps and incompatible/qualified schemas reject without exposing partial results.

This follows the existing [reference Host design](reference-host.md#collection-integration-admission)
and Sketch `87dc7144:src/actql.ts`'s supplied-to-authored assignability direction.
The reference's flat `source:local.<name>` snapshot mapping is not copied into a
staged Program source-identity contract. Its actual schema is checked-form data,
so checked-only text extents are retained; author defaulting is not rerun on it.

Sketch `87dc7144:moonbit/src/syntax_decode/decode.mbt` supplies reusable structure,
but defaults an input with only expected columns to Relation and rejects an empty
expected-column list. Current language requirements instead require `carrier`
and do not require that list to be nonempty. The reader follows current prose.
The embedded protocol input schemas and this reader both exclude legacy
`schema_ref`, as required by the language. `scripts/local-input-schema.mjs`
checks both embedded Program input definitions and their closed field sets;
inline `schema` remains available. This alignment does not define a Host
snapshot reference or imply registry, backend or execution support.

Subsequent integration must associate declarations with actual stage input slots,
reconcile admitted Host evidence against explicit assertions, close duplicate
policy checking and assemble the complete static Program result. It must not
substitute arbitrary caller Carrier contracts for this source correspondence.
