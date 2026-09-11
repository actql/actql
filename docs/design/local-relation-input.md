# Local Relation input declarations

`local_relation_input.read` reads an already source-normalized, owned input
declaration. It covers the `relation` shorthand and the local Relation object
form from [Local typed inputs](../spec/language.md#local-inputs), including
`expected_columns`, inline `schema`, `primary_key`, `duplicates` and `meta`.
It requires explicit `carrier` in the object form and rejects unknown fields.
Other Carriers, SourceView and receipt inputs need their own admission boundaries;
this entry is not a general Input dispatcher or a completed CheckedProgram.

## Evidence retained

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

Sketch `87dc7144:moonbit/src/syntax_decode/decode.mbt` supplies reusable structure,
but defaults an input with only expected columns to Relation and rejects an empty
expected-column list. Current language requirements instead require `carrier`
and do not require that list to be nonempty. The reader follows current prose.
Some embedded protocol input schemas still expose legacy `schema_ref`; the
language explicitly excludes it. This reader does not revive that field, and
the broader source-schema alignment remains necessary before claiming a complete
Program input contract. No registry, backend or execution support is implied.

Subsequent integration must associate declarations with actual stage input slots,
reconcile admitted Host evidence against explicit assertions, close duplicate
policy checking and assemble the complete static Program result. It must not
substitute arbitrary caller Carrier contracts for this source correspondence.
