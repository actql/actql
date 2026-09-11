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

Next, snapshot admission must resolve the selector against the exact selected
Program and local slot, reconcile Carrier/schema, verify Check Environment
membership and retain that ownership through pipeline registration. Neither
the codec nor `stage_local_inputs.reconcile_schemas` performs those checks.
The selector has no standalone Program identity or authorization meaning.
Materialization/provenance claims require their own validation and must not be
fabricated from a static schema snapshot. This change does not define a full
snapshot envelope, introduce Host I/O or implement lowering.
