# Staged local source references

The normative owner is [local input source references](../spec/protocols/contracts.md#local-input-source-reference).
`spec/contracts/actql-local-source-reference.json` pins the selector syntax and
semantic requirements. `local_source_ref` implements only its bounded canonical
codec; possession of a `Reference` is not resolved or authenticated evidence.

Sketch `87dc7144:src/actql-collection-integration.ts` emits flat
`source:local.<name>` snapshot selectors. Its portability checker requires unique
string selectors but cannot distinguish same-named inputs in different stages.
The staged format is a new explicit decision, not an assertion that the old
reference already implements it. Stage IDs avoid positional instability, and
escaping both names avoids separator ambiguity without restricting authored names.
No backward-compatible guessing, percent decoding or implicit normalization is used.

The codec checks nonempty canonical Unicode names and an encoded UTF-8 byte cap.
Names are bounded before normalization and escape expansion. The cap is not a
heap limit; bounded temporary normalized and escaped strings may coexist. A decoded
reference retains its canonical text and both exact names without mutable arrays.
The JSON Schema checks syntax only; the codec additionally rejects noncanonical
text. Fixed independent cases cover stage distinction, slash/tilde ambiguity,
Unicode, newlines, percent-like data, malformed syntax and exact byte boundaries.

`stage_source_refs.prepare` indexes actual stage/input locations from one
`stage_parameters.Source`. `resolve` resolves a batch of parsed selectors against
that exact index, rejecting unknown stages/inputs, Connector declarations and
source-admitted Result/receipt imports. Repeated selectors fail even when the
reference handles or spelling are identical; no snapshot deduplication is inferred.
Local Graph, Events and Vectors slots are not rejected merely because the current
local schema reader supports only Relation. Resolution does not validate their
declaration bodies, infer a Carrier or admit a malformed local declaration.

The opaque batch and entries retain the exact index and Program source, the stage
position as an internal navigation coordinate, and the original input cursor.
Reference spelling still uses stage IDs, not those positions. Entries expose
their original path/span without copying or reconstructing source locations.
Caller reference arrays are not retained, and a late error exposes no partial
batch. Two equivalent-looking Programs produce distinct ownership boundaries.

Indexing charges stage/input enumeration, import indexing and scanned declaration
member names before allocating their corresponding maps. UTF-8 names and work
have shared bounds. Resolution includes the original index cost once plus every
selector occurrence and encoded text. It performs two indexed lookups per
selector rather than rescanning the Program per snapshot. These costs cover this
source-location pass, not preceding source/Parameter admission or the full
snapshot body. Later assembly can subtract shared index work only after verifying
the exact shared index owner.

Next, snapshot admission must reconcile Carrier/schema, verify Check Environment
membership and retain the resolved ownership through pipeline registration.
Neither this resolver nor `stage_local_inputs.reconcile_schemas` checks those links.
The selector has no standalone Program identity or authorization meaning.
Materialization/provenance claims require their own validation and must not be
fabricated from a static schema snapshot. This change does not define a full
snapshot envelope, introduce Host I/O or implement lowering.
